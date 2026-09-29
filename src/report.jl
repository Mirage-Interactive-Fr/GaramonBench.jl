function _bench_warm_times(sample_file)
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
        fields[phase]=="warm" && push!(values,parse(Float64,fields[time]))
    end
    values
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

function _compile_bench_article(tex_source,plot_dir,paper_dir)
    compiler=Sys.which("latexmk")
    isnothing(compiler) && error("latexmk is required to compile the article after benchmarking")
    isfile(tex_source) || error("Garamon article source is missing")
    mkpath(paper_dir)
    mktempdir() do auxiliary
        texinputs=join((plot_dir,dirname(tex_source),get(ENV,"TEXINPUTS","")),':')*":"
        command=`$compiler -pdf -silent -interaction=nonstopmode -halt-on-error -auxdir=$auxiliary -outdir=$paper_dir $tex_source`
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
    end
    pdf=joinpath(paper_dir,splitext(basename(tex_source))[1]*".pdf")
    isfile(pdf) && filesize(pdf)>0 || error("LaTeX did not produce the article PDF")
    pdf
end
