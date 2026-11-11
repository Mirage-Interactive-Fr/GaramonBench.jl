const _ARTICLE_SUMMARY_GROUPS = (
    :robust => "Consistent gains",
    :windows => "Unanimous gains over dimension windows",
    :mixed => "Scenario-dependent gains",
    :isolated => "Isolated or limited evidence",
    :none => "No observed gain",
    :control => "Same-route control",
    :approximate => "Approximate output")

const _ARTICLE_SUMMARY_TITLES = Dict(
    "01"=>"Dense storage", "02"=>"Direct sparse-vector control",
    "06"=>"XOR join",
    "08"=>"Prepared vector-product plan", "09"=>"Reused workspace",
    "14"=>"Generated vector-product kernel", "17"=>"Factored bivector reflections",
    "22"=>"Clifford-matrix transform")

function _article_performance_entry(technique,rows,planned)
    by_dimension=Dict{Int,Vector{Float64}}()
    for row in rows
        push!(get!(by_dimension,row.dimension,Float64[]),row.time_ratio)
    end
    regimes=[begin
        ratios=by_dimension[n]
        (;n,cases=length(ratios),wins=count(<(1),ratios),
            low=minimum(ratios),mid=median(ratios),high=maximum(ratios))
    end for n in sort!(collect(keys(by_dimension)))]
    unanimous=[r.n for r in regimes if r.wins==r.cases]
    ratios=getproperty.(rows,:time_ratio)
    wins=count(<(1),ratios)
    cases=length(ratios)
    id=technique["id"]
    group=if id=="02"
        :control
    elseif get(technique,"contract","")=="approximate"
        :approximate
    elseif wins==0
        :none
    elseif cases<6 || length(regimes)<2
        :isolated
    elseif 20wins>=19cases && all(r->2r.wins>r.cases,regimes)
        :robust
    elseif any(i->regimes[i].n in unanimous && regimes[i+1].n in unanimous,
            1:(length(regimes)-1))
        :windows
    elseif count(r->r.wins>=2,regimes)<2
        :isolated
    else
        :mixed
    end
    title=get(_ARTICLE_SUMMARY_TITLES,id,replace(get(technique,"name",id),'-'=>' '))
    cpp_cases=count(row->!isnothing(_technique_cpp_ratio(row)),rows)
    (;id,title,group,cases,planned,wins,net=count(<=(0.90),ratios),regimes,unanimous,
        low=minimum(ratios),mid=median(ratios),high=maximum(ratios),cpp_cases)
end

function _article_visible_asset(roots,filename)
    for root in roots
        path=joinpath(root,filename)
        isfile(path) && return path
    end
    nothing
end

function _article_extension_entry(technique,report)
    id=technique["id"]
    rows,parameters=report.rows,report.parameters
    if id=="K4"
        groups=Dict{Tuple{Int,Int,String},Vector{Float64}}()
        for row in rows
            case=parameters[row.case_id]
            key=(row.dimension,case["horizon"],case["scenario"])
            push!(get!(groups,key,Float64[]),row.time_ratio)
        end
        details=[(;dimension=n,horizon,variant,ratio=median(ratios))
            for ((n,horizon,variant),ratios) in groups
            if variant!="reference" && length(ratios)==2]
    else
        details=[begin
            case=parameters[row.case_id]
            horizon=case["horizon"]
            (;horizon,precision=_cross_precision_label(case),
                route=_CROSS_LIBRARY_LABELS[case["scenario"]],
                ns=row.median_ns/horizon,ratio=row.time_ratio)
        end for row in rows]
    end
    (;id,group=:extension,cases=length(rows),planned=report.total,details)
end

function _article_visible_measurements(directory,figure_roots,processed_root;
        report_paths=nothing)
    root=dirname(@__DIR__)
    registry=TOML.parsefile(joinpath(root,"config","techniques.toml"))
    techniques=_registered_benchmark_entries(registry)
    entries=NamedTuple[]
    for technique in techniques
        id=technique["id"]
        stem="plot_technique_"*id
        isnothing(_article_visible_asset(figure_roots,stem*"_pending.tex")) || continue
        figure=_article_visible_asset(figure_roots,stem*".pdf")
        isnothing(figure) && continue
        if isnothing(report_paths)
            report_paths=_article_recovery_index(processed_root,processed_root,root).reports
        end
        digest=_resume_sha(figure)
        matches=NamedTuple[]
        for path in unique(get(report_paths,id,String[]))
            provenance=TOML.parsefile(path)
            get(provenance,"figure_sha256","")==digest &&
                get(provenance,"qualification","")==
                    "isolated_completed_cases_oracle_and_baseline_passed" || continue
            rows,parameters=_read_verified_technique_report(id,path,provenance)
            total=provenance["total_cases"]
            push!(matches,(;rows,parameters,total))
        end
        isempty(matches) && continue
        report=first(matches)
        all(==(report),matches) ||
            error("Several measurement reports match the article figure for technique "*id)
        # The compiled figure must be the same revision as its numerical
        # summary, even when another build publishes a newer plot concurrently.
        staged=joinpath(directory,stem*".pdf")
        cp(figure,staged)
        _resume_sha(staged)==digest ||
            error("Article figure changed during compilation for technique "*id)
        write(joinpath(directory,stem*"_caption.tex"),
            _technique_caption_text(report.rows,report.parameters,report.total;id))
        entry=id in ("E3","C3","K4") ? _article_extension_entry(technique,report) :
            _article_performance_entry(technique,report.rows,report.total)
        push!(entries,entry)
    end
    entries,length(techniques)
end

function _article_summary_panels(entries)
    panels=NamedTuple[]
    for group in (:robust,:windows)
        choices=filter(entry->entry.group==group,entries)
        sort!(choices;by=entry->(-length(entry.unanimous),-length(entry.regimes),entry.id))
        append!(panels,Iterators.take(choices,2))
    end
    if isempty(panels)
        # Show an example from the available coverage even before a clear
        # winning regime has emerged.
        append!(panels,Iterators.take(filter(entry->entry.group!=:extension,entries),1))
    end
    panels
end

function _render_article_summary(cairo,panels,path)
    _with_article_theme(cairo) do
        columns=min(length(panels),2)
        figure=cairo.Figure(size=(1000,228*cld(length(panels),columns)),fontsize=19)
        for (i,panel) in enumerate(panels)
            regimes=panel.regimes
            x=eachindex(regimes)
            ticks=length(x)<=10 ? collect(x) : round.(Int,range(first(x),last(x);length=10))
            lower,upper,_=_technique_ratio_limits((;
                time_ratio=ratio) for r in regimes for ratio in (r.low,r.high))
            axis=cairo.Axis(figure[cld(i,columns),mod1(i,columns)];
                title=string(Char('A'+i-1),". ",uppercasefirst(panel.title)),
                xlabel="Algebra dimension (tested values)",ylabel="Warm-time ratio",
                yscale=log10,xticks=(ticks,string.(getproperty.(regimes[ticks],:n))),
                yticks=_technique_ratio_ticks(lower,upper),xticklabelsize=15,
                xgridvisible=false,ygridcolor=(:gray,0.16))
            cairo.hlines!(axis,[1.0];color=:black,linestyle=:dash)
            colors=[r.wins==r.cases ? "#13765D" : r.wins==0 ? "#505F6D" : "#A45213"
                for r in regimes]
            cairo.rangebars!(axis,collect(x),getproperty.(regimes,:low),getproperty.(regimes,:high);
                color=colors,linewidth=2,whiskerwidth=8)
            cairo.scatter!(axis,collect(x),getproperty.(regimes,:mid);color=colors,markersize=8)
            cairo.xlims!(axis,0.5,length(x)+0.5)
            cairo.ylims!(axis,lower,upper)
        end
        cairo.save(path,figure)
    end
end

function _article_ratio_tex(value)
    # Keep the direction and magnitude of small differences from equality
    # visible even when the rounded ratio would otherwise read as exactly 1.
    rounded=round(value;sigdigits=3)
    prefix=""
    if rounded==1 && value!=1
        rounded=round(abs(value-1);sigdigits=3)
        prefix=value<1 ? "1-" : "1+"
    end
    number=split(string(rounded),'e')
    prefix*first(number)*(length(number)==2 ? "\\times 10^{"*last(number)*"}" : "")
end

_article_summary_title(entry)=replace(uppercasefirst(entry.title),
    "&"=>raw"\&","_"=>raw"\_","%"=>raw"\%")

function _article_summary_highlights(io,panels)
    candidates=collect(Iterators.take(filter(entry->entry.group in (:robust,:windows),panels),3))
    isempty(candidates) && return
    print(io,raw"\par\smallskip\noindent\textbf{Measured highlights.} Median warm-time ",
        length(candidates)==1 ? "ratio was " : "ratios were ")
    for (i,entry) in enumerate(candidates)
        # Pick a representative strong dimension from unanimous results.
        # Prefer repeated cases when a partial grid includes a singleton.
        unanimous=filter(r->r.wins==r.cases,entry.regimes)
        dimensions=isempty(unanimous) ? entry.regimes : unanimous
        regime=argmin(r->(r.cases<2,r.mid,-r.cases,r.n),dimensions)
        i>1 && print(io,i==length(candidates) ? " and " : ", ")
        print(io,raw"$",_article_ratio_tex(regime.mid),raw"$ for \textit{",
            _article_summary_title(entry),raw"} at $n=",regime.n,raw"$ (",
            regime.wins,"/",regime.cases,
            raw" measured cases faster, Figure~\ref{fig:technique-",entry.id,"})")
    end
    println(io,raw".\par")
end

function _article_extension_highlights(io,entries)
    for id in ("C3","E3","K4")
        index=findfirst(entry->entry.id==id,entries)
        isnothing(index) && continue
        entry=entries[index]
        title=id=="C3" ? "Garamon Julia/C++ by precision" :
            id=="E3" ? "3D library comparison (Float32)" : "Four-technique combinations"
        print(io,raw"\par\smallskip\noindent\textbf{",title,raw".} Figure~\ref{fig:technique-",
            id,"} has ",entry.cases,"/",entry.planned," qualified cases. ")
        if id=="K4"
            if isempty(entry.details)
                println(io,"No variant has both seeds measured at one dimension and batch size yet.")
            else
                best=argmin(d->(d.ratio,d.dimension,d.horizon,d.variant),entry.details)
                println(io,"The lowest measured two-seed median ratio is ",
                    raw"$",_article_ratio_tex(best.ratio),raw"$ for \code{",best.variant,
                    raw"} at $n=",best.dimension,raw"$ with ",best.horizon," request(s) per batch.")
            end
        else
            println(io,"Lowest measured warm time per precision across the available batch sizes. ")
            for precision in sort!(unique(d.precision for d in entry.details))
                best=argmin(d->(d.ns,d.horizon,d.route),
                    filter(d->d.precision==precision,entry.details))
                count_routes=count(d->d.precision==precision && d.horizon==best.horizon,entry.details)
                print(io,precision,", ",best.horizon," request(s), ",best.route,raw" at $",
                    _article_ratio_tex(best.ns),raw"$ ns/product (",
                    count_routes," routes measured in that batch size). ")
            end
        end
        println(io,raw"\par")
    end
end

function _article_summary_tex(io,entries,total,panels)
    for entry in entries
        println(io,raw"\expandafter\def\csname verifiedarticleplot",entry.id,raw"\endcsname{}")
    end
    println(io,raw"\begingroup\small")
    println(io,"Verified paired timings are available for ",length(entries)," of ",total,
        " result slots. Each ratio \$R\$ is the median warm time divided by the ",
        "median warm time of the reference on the same input.")
    if isempty(entries)
        println(io,raw" No verified technique timings are available for this build.\par\endgroup")
        return
    end
    _article_summary_highlights(io,panels)
    _article_extension_highlights(io,entries)
    cpp_entries=filter(entry->get(entry,:cpp_cases,0)>0,entries)
    if !isempty(cpp_entries)
        ids=join([raw"\ref{fig:technique-"*entry.id*"}" for entry in cpp_entries],", ")
        println(io,raw"\par\smallskip\noindent\textbf{Garamon C++ reference.} ",
            sum(entry.cpp_cases for entry in cpp_entries),
            " cases also have a same-input C++ comparison in the lower panels of Figures ",
            ids,raw". The summary tables use the Garamon.jl reference.\par")
    end
    println(io,raw"\par\endgroup")
    if !isempty(panels)
        println(io,raw"\medskip\noindent\begin{minipage}{\linewidth}\centering")
        println(io,raw"\includegraphics[width=.96\linewidth]{article_performance_summary.pdf}\par\smallskip")
        println(io,raw"\small Points show the median case ratio at each tested dimension and bars show the observed minimum and maximum. Green indicates that every measured case is faster, orange that only some are faster, and gray that none are faster. The dashed line marks equality.\par")
        for (i,panel) in enumerate(panels)
            println(io,Char('A'+i-1),raw". Figure~\ref{fig:technique-",panel.id,raw"}.\quad")
        end
        println(io,raw"\end{minipage}\par\medskip")
    end
    for (ids,description) in (
            (("08","09","14"),"Complete products of two vectors"),
            (("10","11","12","13"),"Plan-cache policies"))
        related=[id for id in ids if any(entry->entry.id==id,entries)]
        length(related)>=2 || continue
        links=join([raw"Figure~\ref{fig:technique-"*id*"}" for id in related],", ")
        println(io,raw"\par\noindent\textbf{",description,".} ",links,
            ". Compare the variants on their shared scenarios.\\par")
    end
    any(entry->entry.group!=:extension,entries) || return
    println(io,raw"""
Measured/planned counts retain incomplete coverage. Each comparison retains
its own workload and reference. A consistent gain requires at least six
measured cases spanning at least two
dimensions, at least 95\% of ratios below one, and a majority below one at
every measured dimension. A dimension window requires unanimity at two
adjacent measured dimensions. Dimensions are listed individually and only
describe the cases already measured. Among the other gains, limited evidence
means fewer than six measured cases, a single measured dimension, or fewer
than two dimensions with at least two faster cases.
The 10\% column counts cases saving at least 10\% of warm time in mixed or
limited grids. It does not determine whether a unanimous window is shown.
Small differences near equality are descriptive. Preparation, retained memory
and full-episode timing require separate measurements.

\begingroup\small
\setlength{\tabcolsep}{3pt}
\begin{longtable}{@{}>{\raggedright\arraybackslash}p{.255\textwidth}rrrr>{\raggedright\arraybackslash}p{.245\textwidth}@{}}
\toprule
Technique & Measured & $R<1$ & $R\le 0.90$ & Median & Observed range and dimensions\\
\midrule
\endhead
\bottomrule
\endfoot
""")
    for (group,label) in _ARTICLE_SUMMARY_GROUPS
        group_entries=filter(entry->entry.group==group,entries)
        isempty(group_entries) && continue
        println(io,raw"\multicolumn{6}{@{}l}{\textbf{",label,raw"}}\\*")
        for entry in group_entries
            title=_article_summary_title(entry)
            dims=isempty(entry.unanimous) ? "--" : join(entry.unanimous,", ")
            net=group in (:mixed,:isolated) ? string(entry.net) : "--"
            print(io,title,raw" (Fig.~\ref{fig:technique-",entry.id,
                "}) & ",entry.cases,"/",entry.planned," & ",entry.wins,
                " & ",net," & \$",_article_ratio_tex(entry.mid),"\$ & \$",
                _article_ratio_tex(entry.low),"\$--\$",_article_ratio_tex(entry.high),
                raw"$\newline All faster: ",dims)
            if 0<length(entry.unanimous)<length(entry.regimes)
                unanimous=filter(r->r.wins==r.cases,entry.regimes)
                print(io,raw"\newline At those dimensions: $",
                    _article_ratio_tex(minimum(r.low for r in unanimous)),raw"$--$",
                    _article_ratio_tex(maximum(r.high for r in unanimous)),raw"$")
            end
            println(io,raw" \\ ")
        end
        println(io,raw"\addlinespace")
    end
    println(io,raw"\end{longtable}\endgroup")
end

function _stage_article_performance_summary(directory,figure_roots,processed_root;
        report_paths=nothing)
    entries,total=_article_visible_measurements(directory,figure_roots,processed_root;report_paths)
    panels=_article_summary_panels(entries)
    if !isempty(panels)
        @eval import CairoMakie
        cairo=Base.invokelatest(getfield,@__MODULE__,:CairoMakie)
        Base.invokelatest(_render_article_summary,cairo,panels,
            joinpath(directory,"article_performance_summary.pdf"))
    end
    open(joinpath(directory,"article_performance_summary.tex"),"w") do io
        _article_summary_tex(io,entries,total,panels)
    end
end
