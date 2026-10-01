# Resolve article artifacts against the package's DrWatson layout, even when
# the CUDA environment is active. Keep CPU and GPU figures in one manuscript.
_article_plotsdir(parts...) = DrWatson.plotsdir(
    joinpath(dirname(@__DIR__),"plots",parts...))
_article_papersdir(parts...) = DrWatson.papersdir(
    joinpath(dirname(@__DIR__),"papers",parts...))

function _bench_phase_times(sample_file,selected_phase)
    lines=readlines(sample_file)
    isempty(lines) && error("empty sample file: "*sample_file)
    header=split(first(lines),',')
    phase=findfirst(==("phase"),header)
    time=findfirst(==("time_ns"),header)
    (isnothing(phase) || isnothing(time)) && error("sample schema changed")
    values=Float64[]
    for line in lines[2:end]
        fields=split(line,',')
        length(fields)==length(header) || error("sample width changed")
        fields[phase]==selected_phase && push!(values,parse(Float64,fields[time]))
    end
    values
end

_bench_warm_times(sample_file)=_bench_phase_times(sample_file,"warm")

"""Read only oracle-validated case outputs; preserve each parameter tuple.
Ratios always use the standard baseline on that exact case, including cached
baseline measurements. They never compare different scenario inputs.
"""
function _technique_report_rows(row,config,archive)
    manifest=TOML.parsefile(joinpath(archive,"campaign.toml"))
    manifest["condition"]=="isolated" ||
        error("article technique plots require an isolated campaign")
    config["campaign"]["condition"]=="isolated" || error("unqualified report configuration")
    samples=config["limits"]["samples"]
    rows=NamedTuple[]
    parameters=Dict{String,Any}()
    for case in expand_cases(config)
        id=case_id(case)
        directory=joinpath(archive,"cases",id)
        isfile(joinpath(directory,"completion.toml")) || continue
        marker=_resume_verify_case(directory,case,manifest["run_signature"],samples;
            backend="benchmarktools")
        get(case,"baseline_required",false)===true || error("article case has no standard baseline")
        verdict=TOML.parsefile(joinpath(directory,"verdict.toml"))
        sample_file=joinpath(directory,"samples.csv")
        warm=_bench_warm_times(sample_file)
        baseline=_bench_phase_times(sample_file,"baseline_warm")
        if isempty(baseline)
            baseline=TOML.parsefile(normpath(joinpath(directory,
                verdict["baseline_cache_file"])))["time_ns"]
        end
        length(warm)==length(baseline)==samples || error("incomplete paired timing samples")
        all(isfinite,warm) && all(isfinite,baseline) &&
            all(>=(0),warm) && all(>=(0),baseline) || error("invalid timing samples")
        value=median(warm)
        reference=median(baseline)
        ratio=reference>0 ? value/reference : NaN
        push!(rows,(technique=row["id"],case_id=id,
            execution_signature=get(marker,"execution_signature",manifest["run_signature"]),
            dimension=get(case,"dimension",0),
            family=string(get(case,"family",get(case,"signature","scenario"))),
            seed=case["seed"],samples=samples,median_ns=value,
            q25_ns=quantile(warm,0.25),q75_ns=quantile(warm,0.75),
            baseline_name=verdict["baseline_name"],baseline_median_ns=reference,
            time_ratio=ratio,over_baseline_budget=isfinite(ratio) && ratio>10,
            condition="isolated"))
        parameters[id]=case
    end
    rows,parameters
end

function _render_technique_plot_loaded(xkcd,row,rows,total,destination)
    isempty(rows) && error("no qualified technique cases to plot")
    xkcd.with_theme(xkcd.theme_xkcd()) do
        figure=xkcd.Figure(size=(960,520),backgroundcolor=:white)
        axis=xkcd.Axis(figure[1,1],
            title=row["id"]*" "*row["name"]*" — "*string(length(rows))*"/"*string(total)*" qualified cases",
            xlabel="Algebra dimension",ylabel="Warm time / same-input Garamon.jl baseline",
            yscale=log10)
        colors=[:steelblue3,:darkorange2,:seagreen3,:purple3,:goldenrod3,:slategray3]
        for (index,family) in enumerate(sort!(unique(r.family for r in rows)))
            points=filter(r->r.family==family && isfinite(r.time_ratio),rows)
            isempty(points) && continue
            ordinary=filter(r->!r.over_baseline_budget,points)
            outside=filter(r->r.over_baseline_budget,points)
            color=colors[mod1(index,length(colors))]
            isempty(ordinary) || xkcd.scatter!(axis,[r.dimension for r in ordinary],
                [clamp(r.time_ratio,1e-4,10) for r in ordinary];
                color=(color,0.65),markersize=9,label=family)
            isempty(outside) || xkcd.scatter!(axis,[r.dimension for r in outside],
                fill(10.0,length(outside));color=color,marker=:utriangle,
                markersize=13,label=family*" >10× baseline")
        end
        xkcd.hlines!(axis,[1.0];color=:black,linestyle=:dash)
        xkcd.hlines!(axis,[10.0];color=:firebrick,linestyle=:dot)
        xkcd.ylims!(axis,1e-4,16)
        xkcd.axislegend(axis;position=:rb)
        xkcd.Label(figure[2,1],
            "Each point retains its full scenario in the CSV + parameter table. Triangles: >10× baseline.\nRatios below 10⁻⁴ are clipped; zero-resolution baselines are omitted.",fontsize=14)
        xkcd.save(destination,figure)
    end
    destination
end

function _refresh_technique_benchmark_article(row,config,archive;
        processed_root=DrWatson.datadir(joinpath(dirname(@__DIR__),"data","processed","garamonbench","techniques")),
        figure_root=_article_plotsdir("garamonbench","techniques","qualified"),
        compile_article::Bool=true)
    rows,parameters=_technique_report_rows(row,config,archive)
    isempty(rows) && return nothing
    manifest=TOML.parsefile(joinpath(archive,"campaign.toml"))
    signature=manifest["run_signature"]
    archive_id=first(bytes2hex(sha256(abspath(archive))),12)
    directory=joinpath(processed_root,row["id"],first(signature,12),archive_id)
    mkpath(directory)
    summary=joinpath(directory,"summary.csv")
    temporary,io=mktemp(directory);close(io)
    try
        write_csv(temporary,rows)
        Base.Filesystem.rename(temporary,summary)
    finally
        isfile(temporary) && rm(temporary)
    end
    _resume_write(joinpath(directory,"case_parameters.toml"),parameters)
    mkpath(figure_root)
    figure=joinpath(figure_root,"plot_technique_"*row["id"]*".pdf")
    @eval import CairoMakie
    cairo=Base.invokelatest(getfield,@__MODULE__,:CairoMakie)
    previous=Base.invokelatest(cairo.Makie.current_default_theme)
    @eval import XKCDMakie
    xkcd=Base.invokelatest(getfield,@__MODULE__,:XKCDMakie)
    try
        mktempdir() do temporary
            built=joinpath(temporary,"plot.pdf")
            Base.invokelatest(_render_technique_plot_loaded,xkcd,row,rows,
                length(expand_cases(config)),built)
            _publish_article_pdf(built,figure)
        end
    finally
        Base.invokelatest(cairo.Makie.set_theme!,previous)
    end
    _resume_write(joinpath(directory,"provenance.toml"),Dict(
        "schema_version"=>1,"qualification"=>"isolated_completed_cases_oracle_and_baseline_passed",
        "technique"=>row["id"],"run_signature"=>signature,
        "mixed_source_revisions"=>get(manifest,"mixed_source_revisions",false),
        "execution_signatures"=>sort!(unique(r.execution_signature for r in rows)),
        "campaign_status"=>manifest["status"],"completed_cases"=>length(rows),
        "total_cases"=>length(expand_cases(config)),"summary_sha256"=>_resume_sha(summary),
        "parameters_sha256"=>_resume_sha(joinpath(directory,"case_parameters.toml")),
        "figure_sha256"=>_resume_sha(figure),
        "baseline_budget_ratio"=>10,"archive"=>abspath(archive)))
    if compile_article
        source=joinpath(dirname(@__DIR__),"papers","Garamon_research_article_2026-09-27_en.tex")
        _compile_bench_article(source,figure_root,
            _article_papersdir("garamonbench","techniques","qualified"))
    end
    (;summary_csv=summary,figure_pdf=figure,completed_cases=length(rows))
end

function _bench_summary(config,benchmark_output,destination)
    rows=NamedTuple[]
    for case in expand_cases(config)
        sample_file=joinpath(benchmark_output,"cases",case_id(case),"samples.csv")
        times=_bench_warm_times(sample_file)
        length(times)==config["limits"]["samples"] ||
            error("incomplete sample count for "*case["strategy"])
        push!(rows,(case_id=case_id(case),library=case["strategy"],
            dimension=case["dimension"],horizon=case["horizon"],seed=case["seed"],
            condition=config["campaign"]["condition"],samples=length(times),
            median_ns=median(times),q25_ns=quantile(times,0.25),
            q75_ns=quantile(times,0.75),min_ns=minimum(times),max_ns=maximum(times)))
    end
    path=joinpath(destination,"summary.csv")
    temporary=path*".tmp-"*string(uuid4())
    try
        write_csv(temporary,rows)
        if isfile(path)
            read(path)==read(temporary) || error("completed summary differs from raw samples")
        else
            mv(temporary,path)
        end
    finally
        isfile(temporary) && rm(temporary)
    end
    path,rows
end

function _report_rows(path)
    lines=readlines(path)
    isempty(lines) && error("empty summary CSV")
    header=split(first(lines),',')
    required=("library","dimension","horizon","median_ns","condition")
    all(in(header),required) || error("summary CSV schema changed")
    [Dict(zip(header,split(line,','))) for line in lines[2:end]]
end

function _bench_completed_rows(config,benchmark_output)
    rows=Dict{String,String}[]
    for case in expand_cases(config)
        directory=joinpath(benchmark_output,"cases",case_id(case))
        isfile(joinpath(directory,"completion.toml")) || continue
        times=_bench_warm_times(joinpath(directory,"samples.csv"))
        length(times)==config["limits"]["samples"] ||
            error("incomplete warm samples for "*case["strategy"])
        push!(rows,Dict("library"=>case["strategy"],
            "dimension"=>string(case["dimension"]),"horizon"=>string(case["horizon"]),
            "median_ns"=>string(median(times)),
            "condition"=>config["campaign"]["condition"]))
    end
    rows
end

function _render_bench_plot_loaded(xkcd,rows,plot_pdf)
    1<=length(rows)<=3 || error("EGA3 library chart requires 1–3 validated cases")
    all(row["dimension"]=="3" && row["horizon"]=="1024" for row in rows) ||
        error("EGA3 library chart received a different grid")
    names=Dict("garamon_packed"=>"Garamon.jl", "gal"=>"GAL", "versor"=>"Versor")
    all(haskey(names,row["library"]) for row in rows) || error("unknown EGA3 library")
    length(unique(row["library"] for row in rows))==length(rows) ||
        error("duplicate EGA3 library")
    labels=[names[row["library"]] for row in rows]
    medians=[parse(Float64,row["median_ns"])/1e3 for row in rows]
    noise=xkcd.scale(xkcd.opensimplex2_2d(seed=UInt64(20260929)),3e0)*0.2+
        xkcd.scale(xkcd.opensimplex2_2d(seed=UInt64(20260930)),1e1)*0.4+
        xkcd.scale(xkcd.opensimplex2_2d(seed=UInt64(20260931)),1e2)*0.8
    style=xkcd.theme_xkcd(noise_generator=noise)
    xkcd.with_theme(style) do
        figure=xkcd.Figure(size=(800,460),backgroundcolor=:white)
        axis=xkcd.Axis(figure[1,1],
            title="EGA3: 1,024 products ("*string(length(rows))*"/3 validated routes)",
            xlabel="Median time per batch (microseconds)",
            yticks=(1:length(rows),labels),ygridvisible=false,xgridvisible=true)
        xkcd.barplot!(axis,1:length(rows),medians;direction=:x,
            color=[:steelblue3,:darkorange2,:seagreen3][1:length(rows)],
            strokecolor=:black,strokewidth=1)
        xkcd.xlims!(axis,0,maximum(medians)*1.27)
        xkcd.ylims!(axis,0.5,length(rows)+0.5)
        for (index,value) in enumerate(medians)
            xkcd.text!(axis,value+maximum(medians)*0.02,index;
                text=string(round(value;digits=2)),align=(:left,:center),fontsize=20)
        end
        xkcd.save(plot_pdf,figure)
    end
    isfile(plot_pdf) && filesize(plot_pdf)>0 || error("Makie did not produce a PDF")
    plot_pdf
end

function _render_preflight_card_loaded(xkcd,row,plot_pdf)
    case=row["case"]
    style=xkcd.theme_xkcd()
    xkcd.with_theme(style) do
        figure=xkcd.Figure(size=(840,240),backgroundcolor=:white)
        axis=xkcd.Axis(figure[1,1],
            title="Preflight validation — "*row["id"]*" "*row["name"])
        xkcd.hidedecorations!(axis)
        xkcd.hidespines!(axis)
        xkcd.xlims!(axis,0,1)
        xkcd.ylims!(axis,0,1)
        details=join((string(key)*"="*string(case[key]) for key in
            ("dimension","signature","horizon","operation","mode")
            if haskey(case,key)),"   ")
        xkcd.text!(axis,0.05,0.72;
            text="Declared oracle: PASSED",fontsize=25,align=(:left,:center))
        xkcd.text!(axis,0.05,0.45;
            text=details,fontsize=18,align=(:left,:center))
        xkcd.text!(axis,0.05,0.17;
            text="One representative case. No timing or speed ranking.",
            fontsize=17,align=(:left,:center))
        xkcd.save(plot_pdf,figure)
    end
    isfile(plot_pdf) && filesize(plot_pdf)>0 || error("preflight card was not rendered")
    plot_pdf
end

"""Display oracle coverage beside the method while performance is pending."""
function _refresh_technique_preflight_article(row,preflight)
    technique_smoke_evidence(row,preflight)
    figure_dir=_article_plotsdir("garamonbench","techniques","preflight")
    paper_dir=_article_papersdir("garamonbench","techniques","preflight")
    figure=joinpath(figure_dir,"preflight_technique_"*row["id"]*".pdf")
    mkpath(figure_dir)
    @eval import CairoMakie
    cairo=Base.invokelatest(getfield,@__MODULE__,:CairoMakie)
    previous=Base.invokelatest(cairo.Makie.current_default_theme)
    @eval import XKCDMakie
    xkcd=Base.invokelatest(getfield,@__MODULE__,:XKCDMakie)
    try
        Base.invokelatest(_render_preflight_card_loaded,xkcd,row,figure)
    finally
        Base.invokelatest(cairo.Makie.set_theme!,previous)
    end
    source=joinpath(dirname(@__DIR__),"papers",
        "Garamon_research_article_2026-09-27_en.tex")
    _compile_bench_article(source,figure_dir,paper_dir)
end

function _render_bench_plot(rows::AbstractVector,plot_pdf)
    mkpath(dirname(plot_pdf))
    @eval import CairoMakie
    cairo=Base.invokelatest(getfield,@__MODULE__,:CairoMakie)
    previous=Base.invokelatest(cairo.Makie.current_default_theme)
    @eval import XKCDMakie
    xkcd=Base.invokelatest(getfield,@__MODULE__,:XKCDMakie)
    try
        Base.invokelatest(_render_bench_plot_loaded,xkcd,rows,plot_pdf)
    finally
        Base.invokelatest(cairo.Makie.set_theme!,previous)
    end
end

_render_bench_plot(summary_csv::AbstractString,plot_pdf)=
    _render_bench_plot(_report_rows(summary_csv),plot_pdf)

function _publish_article_pdf(source,destination)
    mkpath(dirname(destination))
    temporary,io=mktemp(dirname(destination))
    close(io)
    try
        cp(source,temporary;force=true)
        # libuv rename publishes the complete PDF in one filesystem operation.
        Base.Filesystem.rename(temporary,destination)
    finally
        isfile(temporary) && rm(temporary)
    end
    destination
end

function _compile_bench_article(tex_source,plot_dir,paper_dir;
    publish_canonical::Bool=true)
    compiler=Sys.which("latexmk")
    isnothing(compiler) && error("latexmk is required to compile the article after benchmarking")
    isfile(tex_source) || error("Garamon article source is missing")
    mkpath(paper_dir)
    pdf=joinpath(paper_dir,splitext(basename(tex_source))[1]*".pdf")
    mktempdir() do auxiliary
        isolated_output=joinpath(auxiliary,"pdf")
        mkpath(isolated_output)
        preflight=_article_plotsdir("garamonbench","techniques","preflight")
        qualified=_article_plotsdir("garamonbench","techniques","qualified")
        texinputs=join((plot_dir,qualified,preflight,dirname(tex_source),
            get(ENV,"TEXINPUTS","")),':')*":"
        command=`$compiler -pdf -silent -interaction=nonstopmode -halt-on-error -auxdir=$auxiliary -outdir=$isolated_output $tex_source`
        logfile=joinpath(auxiliary,"latexmk.log")
        open(logfile,"w") do io
            try
                run(pipeline(addenv(command,"TEXINPUTS"=>texinputs);
                    stdout=io,stderr=io))
            catch
                lines=readlines(logfile)
                error("LaTeX compilation failed: "*join(last(lines,min(25,length(lines))),"\n"))
            end
        end
        built=joinpath(isolated_output,basename(pdf))
        isfile(built) && filesize(built)>0 || error("LaTeX did not produce the article PDF")
        _publish_article_pdf(built,pdf)
        canonical=joinpath(dirname(tex_source),basename(pdf))
        publish_canonical && abspath(pdf)!=abspath(canonical) &&
            _publish_article_pdf(built,canonical)
    end
    pdf
end
