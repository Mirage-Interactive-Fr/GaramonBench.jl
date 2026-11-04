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
            strategy=string(get(case,"strategy","")),
            support=string(get(case,"support","")),
            grade_pair=string(get(case,"grade_pair","")),
            operation=string(get(case,"operation","")),
            trace=string(get(case,"trace","")),
            scenario=string(get(case,"scenario","")),
            structure=string(get(case,"structure","")),
            signature=string(get(case,"signature","")),
            horizon=string(get(case,"horizon","")),
            request_index=string(get(case,"request_index","")),
            capacity_plans=string(get(case,"capacity_plans","")),
            eviction_exponent=string(get(case,"eviction_exponent","")),
            frequency_slots=string(get(case,"frequency_slots","")),
            draw_seed=string(get(case,"draw_seed","")),
            seed=case["seed"],samples=samples,median_ns=value,
            q25_ns=quantile(warm,0.25),q75_ns=quantile(warm,0.75),
            baseline_name=verdict["baseline_name"],baseline_median_ns=reference,
            time_ratio=ratio,over_baseline_budget=isfinite(ratio) && ratio>10,
            condition="isolated"))
        parameters[id]=case
    end
    rows,parameters
end

const _TECHNIQUE_PLOT_AXES=("strategy","support","grade_pair","trace",
    "scenario","structure","horizon","request_index","operation","signature","family","capacity_plans",
    "eviction_exponent","frequency_slots","draw_seed")

const _TECHNIQUE_AXIS_MEANING=Dict(
    "strategy"=>"algorithmic route",
    "support"=>"pattern of nonzero input blades",
    "grade_pair"=>"grades of the two operands",
    "trace"=>"order of cache-context requests",
    "scenario"=>"workload sequence",
    "structure"=>"whether expression nodes are shared or distinct",
    "horizon"=>"number of requests in the episode",
    "request_index"=>"starting context in the catalogue request sequence",
    "operation"=>"requested product operation",
    "signature"=>"sign and degeneracy pattern of the metric",
    "family"=>"workload family",
    "capacity_plans"=>"number of plans the cache can retain",
    "eviction_exponent"=>"roulette eviction weight exponent",
    "frequency_slots"=>"frequency-table size",
    "draw_seed"=>"pseudorandom draw seed")

_technique_axis_meaning(key)=isempty(key) ? "no varying category" :
    key*" ("*get(_TECHNIQUE_AXIS_MEANING,key,"scenario parameter")*")"

function _technique_caption_text(rows,parameters,total)
    color_key,marker_key=_technique_plot_axes(rows,parameters)
    cases=[parameters[r.case_id] for r in rows]
    unencoded=[key*"="*join(sort!(unique(string(get(case,key,"")) for case in cases);
        by=value->(isnothing(tryparse(Float64,value)),
            something(tryparse(Float64,value),0.0),value)),"/")
        for key in _TECHNIQUE_PLOT_AXES if key!=color_key && key!=marker_key &&
        length(unique(string(get(case,key,"")) for case in cases))>1]
    coverage=string(length(rows))*" of "*string(total)
    grouping=isempty(color_key) ?
        "The completed cases have no varying color category. " :
        "Color distinguishes "*_technique_axis_meaning(color_key)*". "
    grouping*=isempty(marker_key) ?
        "No second category is encoded by marker shape. " :
        "Marker shape distinguishes "*_technique_axis_meaning(marker_key)*". "
    caption="The horizontal axis is algebra dimension; "*coverage*
    " planned cases have qualified timing data. Each timed point is this route's "*
    "median warm time divided by standard Garamon.jl's median warm time "*
    "on the same input; a ratio below one means a faster warm execution. "*grouping*
    (isempty(unencoded) ? "" : "Other parameters varying among the completed cases but not encoded by color or marker are "*join(unencoded,", ")*"; points may overlap. ")*
    "Preparation, memory, and complete-episode costs are not shown in this panel."
    replace(caption,"_"=>"\\_")
end

function _technique_plot_axes(rows,parameters)
    cases=[parameters[r.case_id] for r in rows]
    varying=[key for key in _TECHNIQUE_PLOT_AXES if
        2<=length(unique(string(get(case,key,"")) for case in cases))<=6]
    color_key=isempty(varying) ? "" : first(varying)
    color_count=isempty(color_key) ? 1 :
        length(unique(string(get(case,color_key,"")) for case in cases))
    marker_candidates=[key for key in varying if key!=color_key &&
        length(unique(string(get(case,key,"")) for case in cases))<=4 &&
        color_count*length(unique(string(get(case,key,"")) for case in cases))<=8]
    color_key,isempty(marker_candidates) ? "" : first(marker_candidates)
end

_technique_plot_value(parameters,id,key)=isempty(key) ? "" :
    string(get(parameters[id],key,""))

const _TECHNIQUE_PLOT_TITLES=Dict(
    "01"=>"Dense versus sparse complete product",
    "02"=>"Two direct sparse-vector entry points",
    "03"=>"Prepared versus direct wedge",
    "04"=>"Selected outputs of a three-factor product",
    "05"=>"Selected left-contraction coefficients",
    "06"=>"Selected geometric-product coefficients",
    "07"=>"Three-input selected-output join",
    "08"=>"Prepared versus direct vector product",
    "09"=>"Reused workspace versus direct vector product",
    "10"=>"LRU cache versus uncached products",
    "11"=>"Roulette cache versus uncached products",
    "12"=>"TinyLFU cache versus uncached products",
    "13"=>"SIEVE cache versus uncached products",
    "14"=>"Generated versus direct vector product",
    "15"=>"Known and untrained catalogue requests",
    "16"=>"Shared versus distinct expression graph")

function _technique_ratio_limits(rows;has_exclusions=false)
    ratios=[r.time_ratio for r in rows]
    all(ratio->isfinite(ratio) && ratio>0,ratios) ||
        error("a qualified technique ratio is not positive and finite")
    low=min(minimum(ratios),1.0)
    high=max(maximum(ratios),1.0)
    span=max(log10(high)-log10(low),0.4)
    pad=max(0.12span,0.08)
    lower=10.0^(log10(low)-pad)
    upper=10.0^(log10(high)+pad*(has_exclusions ? 1.8 : 1.0))
    exclusion_y=has_exclusions ? 10.0^(log10(high)+0.8pad) : nothing
    lower,upper,exclusion_y
end

function _technique_ratio_ticks(lower,upper)
    values=sort!([factor*10.0^exponent
        for exponent in floor(Int,log10(lower)):ceil(Int,log10(upper)),
            factor in (1.0,2.0,5.0)
        if lower<=factor*10.0^exponent<=upper])
    if length(values)>8
        values=filter(value->isapprox(log10(value),round(log10(value));atol=1e-9),
            values)
    end
    values,[string(round(value;sigdigits=3))*"×" for value in values]
end

const _ARTICLE_PLOT_RENDERER="cairo-standard-v2"

function _with_article_theme(f,cairo)
    # XKCDMakie's initialization changes Makie's global theme, including
    # its Cairo drawing hook. A reused process must explicitly disable it.
    cairo.with_theme(f,cairo.Theme(xkcd_enabled=false,
        fonts=(regular="TeX Gyre Heros",bold="TeX Gyre Heros Bold",
            italic="TeX Gyre Heros Italic",bold_italic="TeX Gyre Heros Bold Italic"),
        fontsize=18,backgroundcolor=:white))
end

function _render_technique_plot_loaded(cairo,args...;kwargs...)
    _with_article_theme(cairo) do
        _draw_technique_plot(cairo,args...;kwargs...)
    end
end

function _draw_technique_plot(cairo,row,rows,parameters,total,destination;
                                       budget_skips=NamedTuple[])
    isempty(rows) && error("no qualified technique cases to plot")
    lower,upper,exclusion_y=_technique_ratio_limits(rows;
        has_exclusions=!isempty(budget_skips))
    ratio_ticks=_technique_ratio_ticks(lower,upper)
    color_key,marker_key=_technique_plot_axes(rows,parameters)
    colored=isempty(color_key) ? [""] :
        sort!(unique(_technique_plot_value(parameters,r.case_id,color_key) for r in rows))
    marked=isempty(marker_key) ? [""] :
        sort!(unique(_technique_plot_value(parameters,r.case_id,marker_key) for r in rows))
    colors=["#0072B2","#D55E00","#009E73","#88419D","#B58900","#505F6D"]
    markers=[:circle,:rect,:diamond,:utriangle]
    figure=cairo.Figure(size=(1200,610),backgroundcolor=:white,fontsize=18)
    axis=cairo.Axis(figure[1,1],
        title=row["id"]*" "*get(_TECHNIQUE_PLOT_TITLES,row["id"],row["name"])*
            " — "*string(length(rows))*"/"*string(total)*" qualified cases",
        xlabel="Algebra dimension",ylabel="Warm time / same-input Garamon.jl baseline",
        yscale=log10,yticks=ratio_ticks,xticklabelsize=17,yticklabelsize=17,
        xlabelsize=19,ylabelsize=19,titlesize=20,
        xgridvisible=false,ygridvisible=true,
        ygridcolor=(:gray,0.16),topspinevisible=false,rightspinevisible=false)
    dimensions=sort!(unique(r.dimension for r in rows))
    length(dimensions)<=10 && (axis.xticks[]=dimensions)
    for (color_index,color_value) in enumerate(colored),
        (marker_index,marker_value) in enumerate(marked)
        points=filter(r->_technique_plot_value(parameters,r.case_id,color_key)==color_value &&
            _technique_plot_value(parameters,r.case_id,marker_key)==marker_value,rows)
        isempty(points) && continue
        color=colors[color_index]
        marker=markers[marker_index]
        label=isempty(color_key) ? "Qualified cases" :
            color_key*"="*color_value*
            (isempty(marker_key) ? "" : "; "*marker_key*"="*marker_value)
        # Small deterministic offsets expose points sharing a dimension.
        group_index=(color_index-1)*length(marked)+marker_index
        group_count=length(colored)*length(marked)
        offset=group_count==1 ? 0.0 : 0.24*((group_index-1)/(group_count-1)-0.5)
        cairo.scatter!(axis,[r.dimension+offset for r in points],
            [r.time_ratio for r in points];
            color,marker,markersize=11,strokecolor=:white,strokewidth=0.7,label)
    end
    cairo.hlines!(axis,[1.0];color=:black,linestyle=:dash,linewidth=1.5)
    if any(r->r.time_ratio>10,rows)
        cairo.hlines!(axis,[10.0];color="#B52A2A",linestyle=:dot,linewidth=1.5)
    end
    if !isempty(budget_skips)
        cairo.scatter!(axis,[r.dimension for r in budget_skips],
            fill(exclusion_y,length(budget_skips));
            color="#B52A2A",marker=:xcross,markersize=15,
            label="Resource exclusion (no timing)")
    end
    cairo.ylims!(axis,lower,upper)
    cairo.Legend(figure[1,2],axis,"Scenario categories";
        tellheight=false,labelsize=17,titlesize=18,framevisible=false)
    note="Color: "*_technique_axis_meaning(color_key)*
        "; marker: "*_technique_axis_meaning(marker_key)*".\n"*
        "Horizontal offsets separate overlapping cases. Dashed line: equal time."
    any(r->r.time_ratio>10,rows) &&
        (note*=" Red dotted line: 10× review threshold.")
    !isempty(budget_skips) &&
        (note*=" Red crosses at the chart top: resource exclusions, not ratios.")
    cairo.Label(figure[2,1:2],note;fontsize=16)
    cairo.save(destination,figure)
    destination
end

function _publish_technique_plot(row,rows,parameters,total,figure_root;
        budget_skips=NamedTuple[])
    mkpath(figure_root)
    figure=joinpath(figure_root,"plot_technique_"*row["id"]*".pdf")
    @eval import CairoMakie
    cairo=Base.invokelatest(getfield,@__MODULE__,:CairoMakie)
    mktempdir() do temporary
        built=joinpath(temporary,"plot.pdf")
        Base.invokelatest(_render_technique_plot_loaded,cairo,row,rows,parameters,
            total,built;budget_skips)
        _publish_article_pdf(built,figure)
    end
    caption=joinpath(figure_root,"plot_technique_"*row["id"]*"_caption.tex")
    _publish_article_text(_technique_caption_text(rows,parameters,total),caption)
    figure,caption
end

function _refresh_technique_benchmark_article(row,config,archive;
        processed_root=DrWatson.datadir(joinpath(dirname(@__DIR__),"data","processed","garamonbench","techniques")),
        figure_root=_article_plotsdir("garamonbench","techniques","qualified"),
        compile_article::Bool=true)
    rows,parameters=_technique_report_rows(row,config,archive)
    isempty(rows) && return nothing
    manifest=TOML.parsefile(joinpath(archive,"campaign.toml"))
    cases=expand_cases(config)
    skipped_ids=_resume_budget_ids(archive,cases,manifest)
    budget_skips=[begin
        record=TOML.parsefile(joinpath(archive,"budget-skips",case_id(case)*".toml"))
        parameters[case_id(case)]=case
        (;case_id=case_id(case),dimension=get(case,"dimension",0),
          status=record["status"],kind=get(record,"kind","controller_rss"),
          observed_rss_bytes=get(record,"observed_rss_bytes","unmeasured"),
          limit_rss_bytes=get(record,"limit_rss_bytes","unmeasured"),
          signal=get(record,"signal",0),reason=record["reason"])
    end for case in cases if case_id(case) in skipped_ids]
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
    isempty(budget_skips) || write_csv(joinpath(directory,"budget_skips.csv"),budget_skips)
    figure,caption=_publish_technique_plot(row,rows,parameters,length(cases),
        figure_root;budget_skips)
    _resume_write(joinpath(directory,"provenance.toml"),Dict(
        "schema_version"=>1,"qualification"=>"isolated_completed_cases_oracle_and_baseline_passed",
        "technique"=>row["id"],"run_signature"=>signature,
        "mixed_source_revisions"=>get(manifest,"mixed_source_revisions",false),
        "execution_signatures"=>sort!(unique(r.execution_signature for r in rows)),
        "campaign_status"=>manifest["status"],"completed_cases"=>length(rows),
        "budget_skipped_cases"=>length(budget_skips),
        "total_cases"=>length(expand_cases(config)),"summary_sha256"=>_resume_sha(summary),
        "parameters_sha256"=>_resume_sha(joinpath(directory,"case_parameters.toml")),
        "figure_sha256"=>_resume_sha(figure),
        "caption_sha256"=>_resume_sha(caption),
        "plot_renderer"=>_ARTICLE_PLOT_RENDERER,
        "figure_color_axis"=>_technique_plot_axes(rows,parameters)[1],
        "figure_marker_axis"=>_technique_plot_axes(rows,parameters)[2],
        "baseline_budget_ratio"=>10,"archive"=>abspath(archive)))
    if compile_article
        source=joinpath(dirname(@__DIR__),"papers","Garamon_research_article_2026-09-27_en.tex")
        _compile_bench_article(source,figure_root,
            _article_papersdir("garamonbench","techniques","qualified"))
    end
    (;summary_csv=summary,figure_pdf=figure,completed_cases=length(rows))
end

function _technique_csv_records(path)
    function fields(line)
        result=String[]; buffer=IOBuffer(); quoted=false
        i=firstindex(line)
        while i<=lastindex(line)
            char=line[i]
            if char=='"'
                following=nextind(line,i)
                if quoted && following<=lastindex(line) && line[following]=='"'
                    write(buffer,'"');i=following
                else
                    quoted=!quoted
                end
            elseif char==',' && !quoted
                push!(result,String(take!(buffer)))
            else
                write(buffer,char)
            end
            i=nextind(line,i)
        end
        quoted && error("incomplete quoted CSV field in "*path)
        push!(result,String(take!(buffer)))
        result
    end
    lines=readlines(path)
    isempty(lines) && error("empty retained report: "*path)
    header=fields(first(lines))
    [begin
        values=fields(line)
        length(values)==length(header) || error("retained CSV width changed: "*path)
        Dict(zip(header,values))
    end for line in lines[2:end]]
end

"""Regenerate a retained plot from its own checksum-verified measurement
summary. Never replace it with another campaign or infer numbers from a PDF.
"""
function _refresh_retained_technique_figure(row,processed_root,figure_root)
    figure=joinpath(figure_root,"plot_technique_"*row["id"]*".pdf")
    isfile(figure) || return nothing
    digest=_resume_sha(figure)
    directory=joinpath(processed_root,row["id"])
    candidates=Pair{String,Any}[]
    if isdir(directory)
        for (root,_,files) in walkdir(directory)
            "provenance.toml" in files || continue
            path=joinpath(root,"provenance.toml")
            provenance=TOML.parsefile(path)
            get(provenance,"technique","")==row["id"] &&
                get(provenance,"figure_sha256","")==digest &&
                push!(candidates,path=>provenance)
        end
    end
    isempty(candidates) && error("Technique "*row["id"]*
        ": a retained figure has no matching validated report in "*directory*
        ". Rebuild stopped; existing data and figure were kept.")
    identities=unique((p.second["summary_sha256"],p.second["parameters_sha256"],
        p.second["total_cases"]) for p in candidates)
    length(identities)==1 || error("Ambiguous measurement provenance for technique "*row["id"])
    provenance_path,provenance=first(sort!(candidates;by=first))
    provenance["qualification"]=="isolated_completed_cases_oracle_and_baseline_passed" ||
        error("unqualified retained report for technique "*row["id"])
    summary=joinpath(dirname(provenance_path),"summary.csv")
    parameter_file=joinpath(dirname(provenance_path),"case_parameters.toml")
    _resume_sha(summary)==provenance["summary_sha256"] ||
        error("retained summary changed for technique "*row["id"])
    _resume_sha(parameter_file)==provenance["parameters_sha256"] ||
        error("retained case parameters changed for technique "*row["id"])
    parameters=TOML.parsefile(parameter_file)
    rows=[begin
        id=record["case_id"]
        record["technique"]==row["id"] && record["condition"]=="isolated" ||
            error("retained case qualification differs")
        haskey(parameters,id) && case_id(parameters[id])==id ||
            error("retained case identity differs")
        dimension=parse(Int,record["dimension"])
        dimension==get(parameters[id],"dimension",0) ||
            error("retained dimension differs")
        ratio=parse(Float64,record["time_ratio"])
        candidate=parse(Float64,record["median_ns"])
        baseline=parse(Float64,record["baseline_median_ns"])
        isfinite(ratio) && ratio>0 && baseline>0 &&
            isapprox(ratio,candidate/baseline;rtol=1e-12) ||
            error("retained paired timing ratio differs")
        (;case_id=id,dimension,time_ratio=ratio,over_baseline_budget=ratio>10)
    end for record in _technique_csv_records(summary)]
    length(rows)==provenance["completed_cases"] &&
        length(unique(r.case_id for r in rows))==length(rows) ||
        error("retained completed case count differs")
    skips=NamedTuple[]
    skip_count=get(provenance,"budget_skipped_cases",0)
    if skip_count>0
        skip_file=joinpath(dirname(provenance_path),"budget_skips.csv")
        for record in _technique_csv_records(skip_file)
            id=record["case_id"]
            haskey(parameters,id) && case_id(parameters[id])==id ||
                error("retained resource exclusion has no verified case")
            push!(skips,(;case_id=id,dimension=Int(parameters[id]["dimension"])))
        end
        length(skips)==skip_count || error("retained resource exclusion count differs")
    end
    figure,caption=_publish_technique_plot(row,rows,parameters,
        provenance["total_cases"],figure_root;budget_skips=skips)
    merge!(provenance,Dict(
        "figure_sha256"=>_resume_sha(figure),"caption_sha256"=>_resume_sha(caption),
        "plot_renderer"=>_ARTICLE_PLOT_RENDERER,
        "figure_color_axis"=>_technique_plot_axes(rows,parameters)[1],
        "figure_marker_axis"=>_technique_plot_axes(rows,parameters)[2]))
    _resume_write(provenance_path,provenance)
    (;summary_csv=summary,figure_pdf=figure,completed_cases=length(rows))
end

"""Rebuild all visible article figures from validated archived cases or their
verified retained reports, without running an experiment.
"""
function refresh_technique_article(output;ids=String[],
        processed_root=DrWatson.datadir(joinpath(dirname(@__DIR__),"data","processed","garamonbench","techniques")),
        figure_root=_article_plotsdir("garamonbench","techniques","qualified"),
        paper_root=_article_papersdir("garamonbench","techniques","qualified"),
        publish_canonical::Bool=true)
    root=dirname(@__DIR__)
    rows=technique_smoke_plan(;benchmark_root=root)
    requested=Set(ids)
    isempty(requested) || issubset(requested,Set(row["id"] for row in rows)) ||
        error("unknown technique ID")
    selected=isempty(requested) ? rows : filter(row->row["id"] in requested,rows)
    refreshed=NamedTuple[]
    for row in selected
        archive=joinpath(abspath(output),"benchmark",row["id"])
        isfile(joinpath(archive,"campaign.toml")) || continue
        config=technique_bench_config(row;benchmark_root=root)
        result=_refresh_technique_benchmark_article(row,config,archive;
            processed_root,figure_root,compile_article=false)
        isnothing(result) || push!(refreshed,(;id=row["id"],result...))
    end
    updated=Set(result.id for result in refreshed)
    # Figures can outlive the campaign that generated them. LaTeX must never
    # silently include such a file without regenerating its plot and caption.
    for row in rows
        row["id"] in updated && continue
        result=_refresh_retained_technique_figure(row,processed_root,figure_root)
        isnothing(result) || push!(refreshed,(;id=row["id"],result...))
    end
    source=joinpath(root,"papers","Garamon_research_article_2026-09-27_en.tex")
    pdf=_compile_bench_article(source,figure_root,paper_root;publish_canonical)
    (;article_pdf=pdf,figures=refreshed)
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

function _render_bench_plot_loaded(cairo,args...;kwargs...)
    _with_article_theme(cairo) do
        _draw_bench_plot(cairo,args...;kwargs...)
    end
end

function _draw_bench_plot(cairo,rows,plot_pdf)
    1<=length(rows)<=3 || error("EGA3 library chart requires 1–3 validated cases")
    all(row["dimension"]=="3" && row["horizon"]=="1024" for row in rows) ||
        error("EGA3 library chart received a different grid")
    names=Dict("garamon_packed"=>"Garamon.jl", "gal"=>"GAL", "versor"=>"Versor")
    all(haskey(names,row["library"]) for row in rows) || error("unknown EGA3 library")
    length(unique(row["library"] for row in rows))==length(rows) ||
        error("duplicate EGA3 library")
    labels=[names[row["library"]] for row in rows]
    medians=[parse(Float64,row["median_ns"])/1e3 for row in rows]
    figure=cairo.Figure(size=(800,460),backgroundcolor=:white,fontsize=18)
    axis=cairo.Axis(figure[1,1],
        title="EGA3: 1,024 products ("*string(length(rows))*"/3 validated routes)",
        xlabel="Median time per batch (microseconds)",
        yticks=(1:length(rows),labels),ygridvisible=false,xgridvisible=true,
        topspinevisible=false,rightspinevisible=false)
    cairo.barplot!(axis,1:length(rows),medians;direction=:x,
        color=["#0072B2","#D55E00","#009E73"][1:length(rows)])
    cairo.xlims!(axis,0,maximum(medians)*1.27)
    cairo.ylims!(axis,0.5,length(rows)+0.5)
    for (index,value) in enumerate(medians)
        cairo.text!(axis,value+maximum(medians)*0.02,index;
            text=string(round(value;digits=2)),align=(:left,:center),fontsize=20)
    end
    cairo.save(plot_pdf,figure)
    isfile(plot_pdf) && filesize(plot_pdf)>0 || error("Makie did not produce a PDF")
    plot_pdf
end

function _render_preflight_card_loaded(cairo,args...;kwargs...)
    _with_article_theme(cairo) do
        _draw_preflight_card(cairo,args...;kwargs...)
    end
end

function _draw_preflight_card(cairo,row,plot_pdf)
    case=row["case"]
    figure=cairo.Figure(size=(840,240),backgroundcolor=:white,fontsize=18)
    axis=cairo.Axis(figure[1,1],
        title="Preflight validation — "*row["id"]*" "*row["name"])
    cairo.hidedecorations!(axis)
    cairo.hidespines!(axis)
    cairo.xlims!(axis,0,1)
    cairo.ylims!(axis,0,1)
    details=join((string(key)*"="*string(case[key]) for key in
        ("dimension","signature","horizon","operation","mode")
        if haskey(case,key)),"   ")
    cairo.text!(axis,0.05,0.72;
        text="Independent oracle: passed",fontsize=25,align=(:left,:center),
        color="#164A6E")
    cairo.text!(axis,0.05,0.45;
        text=details,fontsize=18,align=(:left,:center))
    cairo.text!(axis,0.05,0.17;
        text="One representative case. No timing or speed ranking.",
        fontsize=17,align=(:left,:center),color="#505F6D")
    cairo.save(plot_pdf,figure)
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
    Base.invokelatest(_render_preflight_card_loaded,cairo,row,figure)
    source=joinpath(dirname(@__DIR__),"papers",
        "Garamon_research_article_2026-09-27_en.tex")
    _compile_bench_article(source,figure_dir,paper_dir)
end

function _render_bench_plot(rows::AbstractVector,plot_pdf)
    mkpath(dirname(plot_pdf))
    @eval import CairoMakie
    cairo=Base.invokelatest(getfield,@__MODULE__,:CairoMakie)
    Base.invokelatest(_render_bench_plot_loaded,cairo,rows,plot_pdf)
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

function _publish_article_text(content,destination)
    mkpath(dirname(destination))
    temporary,io=mktemp(dirname(destination))
    try
        write(io,content)
        close(io)
        Base.Filesystem.rename(temporary,destination)
    finally
        isopen(io) && close(io)
        isfile(temporary) && rm(temporary)
    end
    destination
end

function _compile_bench_article(tex_source,plot_dir,paper_dir;
    publish_canonical::Bool=true)
    compiler=Sys.which("latexmk")
    isnothing(compiler) && error("latexmk is required to compile the article after benchmarking")
    tex_source=abspath(tex_source)
    plot_dir=abspath(plot_dir)
    paper_dir=abspath(paper_dir)
    isfile(tex_source) || error("Garamon article source is missing")
    mkpath(paper_dir)
    pdf=joinpath(paper_dir,splitext(basename(tex_source))[1]*".pdf")
    mktempdir() do auxiliary
        isolated_output=joinpath(auxiliary,"pdf")
        mkpath(isolated_output)
        staged_source=joinpath(auxiliary,basename(tex_source))
        cp(tex_source,staged_source)
        preflight=_article_plotsdir("garamonbench","techniques","preflight")
        qualified=_article_plotsdir("garamonbench","techniques","qualified")
        texinputs=join((plot_dir,qualified,preflight,dirname(tex_source)),':')*":"
        command=Cmd(`$compiler -pdf -silent -interaction=nonstopmode -halt-on-error -auxdir=$auxiliary -outdir=$isolated_output $staged_source`;
            dir=auxiliary)
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
        fonts_tool=Sys.which("pdffonts")
        if !isnothing(fonts_tool) &&
                occursin("xkcd",lowercase(read(`$fonts_tool $built`,String)))
            error("The rebuilt article still contains an XKCD figure. Publication stopped; the existing PDF and measurement data were kept.")
        end
        _publish_article_pdf(built,pdf)
        canonical=joinpath(dirname(tex_source),basename(pdf))
        publish_canonical && abspath(pdf)!=abspath(canonical) &&
            _publish_article_pdf(built,canonical)
    end
    pdf
end
