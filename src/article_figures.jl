const EXPLORATORY_FIGURES = Dict(
    "cppreplay" => (kind=:bar, x=["1","32","1 024","10 000"],
        names=["Julia wins"], xlabel="Products per batch",
        ylabel="Paired wins for Julia (out of 8)"),
    "gpupacked" => (kind=:bar, x=["1","32","1 024","8 192"],
        names=["Warm with host output","Complete episode"], xlabel="Batch length",
        ylabel="Pairs favoring GPU (out of 48)"),
    "gpu-copy-profile" => (kind=:bar, x=["8D","65D"],
        names=["GPU kernel","Copy to host"], xlabel="Dimension",
        ylabel="CUPTI phase duration (ms)"),
    "gpu-pinned" => (kind=:bar,
        x=["Pilot 8D/65D","12D pooled","Low rank","Higher rank"],
        names=["Pinning wins"], xlabel="Workload group",
        ylabel="Complete episodes favoring pinning (%)"),
    "cpu4gpu" => (kind=:bar, x=["1 024","8 192"],
        names=["CPU4 vs sequential","GPU vs sequential","GPU vs CPU4"],
        xlabel="Batch length", ylabel="Paired complete-episode wins (out of 72)"),
    "resident-sum" => (kind=:bar, x=["32/32","1024/8","1024/32"],
        names=["GPU wins"], xlabel="H/R workload",
        ylabel="Complete episodes favoring GPU (out of 72)"),
    "resident-fusion" => (kind=:bar, x=["32/32","1024/8","1024/32"],
        names=["Versus R GPU kernels","Versus CPU4"], xlabel="H/R workload",
        ylabel="Complete episodes favoring fusion (out of 72)"),
    "resident-graph" => (kind=:bar,
        x=["32/32/32","1024/8/32","1024/32/8"],
        names=["R-kernel GPU","Fused GPU","CPU4"], xlabel="H/R/Q workload",
        ylabel="Median other-route / graph time"),
    "resident-cupti-counts" => (kind=:bar,
        x=["R-kernel GPU","Fusion","CUDA Graph"],
        names=["Accumulation kernels","Host submissions"], xlabel="Route",
        ylabel="Count per resident-sum trace (R=32)"),
    "resident-highdim" => (kind=:line,
        x=["129","192","256","384","512","768","1024","2048","4096","8192"],
        names=["H/R/Q=32/32/32","H/R/Q=1024/32/8"],
        xlabel="Ambient dimension", ylabel="Paired CPU4 / fused-GPU ratio"),
    "packonce" => (kind=:line,
        x=["129","192","256","384","512","768","1024","2048","4096","8192"],
        names=["Build","Complete episode"], xlabel="Ambient dimension",
        ylabel="Old / new median time"),
    "b4bounds" => (kind=:bar, x=["1","32","1 024"],
        names=["Concurrent load","No other user computation"],
        xlabel="Products per episode", ylabel="Pairs favoring annotation (out of 48)"),
    "b1wdirect" => (kind=:bar,
        x=["2 low","2 high","8 low","8 high","65 low","65 high","128 low","128 high"],
        names=["B1 / direct B1W"], xlabel="Dimension and grade",
        ylabel="Best B1 time / direct B1W time"),
    "b1wsinglepass" => (kind=:bar,
        x=["2 low","2 high","8 low","8 high","65 low","65 high","128 low","128 high"],
        names=["Earlier / single-pass"], xlabel="Dimension and grade",
        ylabel="Earlier B1W time / single-pass time"),
    "benchvariabilite" => (kind=:bar,
        x=["Julia JIT","Julia precompiled","C++ packed"],
        names=["Median","p95"], xlabel="Route",
        ylabel="Batch of 32 products (µs)"),
    "cpppacked" => (kind=:bar, x=["3D mixed","3D vectors","7D mixed","7D vectors"],
        names=["Julia JIT","Julia precompiled","C++ packed"], xlabel="Workload",
        ylabel="Batch of 10,000 products (ms)"),
    "cppmovealloc" => (kind=:bar, x=["3D mixed","3D vectors","7D mixed","7D vectors"],
        names=["Upstream C++","C++ with moves"], xlabel="Workload",
        ylabel="Eigen malloc calls (thousands)"),
    "sorties" => (kind=:bar, x=["One output","Four outputs"],
        names=["Recursion","join3"], xlabel="Requested outputs",
        ylabel="Batch time (µs)"),
    "tripleamort" => (kind=:logline, x=["1","32","1 024"],
        names=["Equality","One output","Four outputs"],
        xlabel="Products reusing the same supports",
        ylabel="Plan time / join3 time"),
    "workspaceamort" => (kind=:logbar,
        x=["Sparse 2D H=1","Sparse 2D H=32","Sparse 4D H=32","Sparse 12D H=1024"],
        names=["Direct total","Workspace total"], xlabel="Workload",
        ylabel="Trace time (µs)"),
    "masques" => (kind=:logbar,
        x=["65D coefficient","65D complete","128D coefficient","128D complete"],
        names=["BigInt","UInt128"], xlabel="Workload",
        ylabel="Kernel median (µs)"),
    "n01horizon" => (kind=:bar, x=["1","32","1 024"],
        names=["Forward order","Reverse order"], xlabel="Products per episode H",
        ylabel="Cases favoring N01 (out of 36)"),
    "n03screen" => (kind=:bar, x=["1/1","1/2","2/1","2/2","3/1","3/2"],
        names=["Radical","Regular","Order-sensitive or tie"],
        xlabel="Active directions r/s", ylabel="Paired configurations"),
    "n04smoke" => (kind=:logbar,
        x=["V2 stable","M4 stable","N65 changing","R4 rejected"],
        names=["Linear","Binary","DAG","Certify every time","Certify then reuse"],
        xlabel="Fixture", ylabel="Episode median (µs)"),
    "n05temps" => (kind=:logbar,
        x=["Signed 2D","Signed 65D","General 4D","Degenerate 8D"],
        names=["Complete","Recursive scalar","Contractions + Pfaffian"],
        xlabel="Fixture", ylabel="Episode median (µs)"),
    "k3partage" => (kind=:logbar,
        x=["A: changing","B: stable","C: one chain","D: disjoint"],
        names=["Independent","Shared workspace","Verified cache"],
        xlabel="Fixture", ylabel="Episode median (µs)"),
    "b1dimensions" => (kind=:line,
        x=["2","3","4","6","8","12","16","32","64","65","96","128"],
        names=["Warm kernel","Complete episode"], xlabel="Ambient dimension n",
        ylabel="Allocated bytes"),
    "b1gradealloc" => (kind=:line,
        x=["2","3","4","6","8","12","16","32","64","65","96","128"],
        names=["Low grades","Grades n and n−1"], xlabel="Ambient dimension n",
        ylabel="Allocated bytes per episode"),
    "b1horizons" => (kind=:bar,
        x=["2 low","2 high","8 low","8 high","65 low","65 high","128 low","128 high"],
        names=["Annotation advantage"], xlabel="Dimension and grade",
        ylabel="Advantage of A over V (%)"),
)

const ARTICLE_COLORS = [:steelblue3,:darkorange2,:seagreen3,:mediumpurple3,:gray60]

function _article_exploratory_series(block::AbstractString)
    series=Vector{Tuple{Vector{Float64},Vector{Float64}}}()
    plot_pattern=r"\\addplot\+\[[^\]]*\]\s*coordinates\s*\{([^}]*)\}"s
    point_pattern=r"\(\s*([+-]?(?:\d+\.?\d*|\.\d+))\s*,\s*([+-]?(?:\d+\.?\d*|\.\d+))\s*\)"
    for plot in eachmatch(plot_pattern,block)
        points=[(parse(Float64,p.captures[1]),parse(Float64,p.captures[2]))
            for p in eachmatch(point_pattern,plot.captures[1])]
        isempty(points) && error("article plot without numeric coordinates")
        push!(series,([p[1] for p in points],[p[2] for p in points]))
    end
    series
end

function _article_exploratory_blocks(source::AbstractString)
    blocks=Dict{String,Vector{Tuple{Vector{Float64},Vector{Float64}}}}()
    content=read(source,String)
    for figure in eachmatch(r"\\begin\{figure\}\[[^\]]*\](.*?)\\end\{figure\}"s,content)
        label=match(r"\\label\{fig:([^}]+)\}",figure.match)
        isnothing(label) && continue
        key=label.captures[1]
        haskey(EXPLORATORY_FIGURES,key) || continue
        series=_article_exploratory_series(figure.match)
        length(series)==length(EXPLORATORY_FIGURES[key].names) ||
            error("article series changed for "*key)
        blocks[key]=series
    end
    Set(keys(blocks))==Set(keys(EXPLORATORY_FIGURES)) ||
        error("article exploratory figure missing or renamed")
    blocks
end

function _render_exploratory_loaded(xkcd,source,plot_dir)
    blocks=_article_exploratory_blocks(source)
    noise=xkcd.scale(xkcd.opensimplex2_2d(seed=UInt64(20260929)),3e0)*0.2+
        xkcd.scale(xkcd.opensimplex2_2d(seed=UInt64(20260930)),1e1)*0.4+
        xkcd.scale(xkcd.opensimplex2_2d(seed=UInt64(20260931)),1e2)*0.8
    style=xkcd.theme_xkcd(noise_generator=noise)
    mkpath(plot_dir)
    paths=String[]
    xkcd.with_theme(style) do
        for key in sort!(collect(keys(blocks)))
            meta=EXPLORATORY_FIGURES[key]
            data=blocks[key]
            figure=xkcd.Figure(size=(1040,590),backgroundcolor=:white)
            xtickvalues=sort!(unique(vcat((xs for (xs,_) in data)...)))
            length(xtickvalues)==length(meta.x) || error("article x ticks changed: "*key)
            kwargs=Dict{Symbol,Any}(:xlabel=>meta.xlabel,:ylabel=>meta.ylabel,
                :xticks=>(xtickvalues,meta.x),:xticklabelsize=>16,
                :yticklabelsize=>16,:xlabelsize=>18,:ylabelsize=>18,
                :xticklabelrotation=>length(meta.x)>4 ? pi/6 : 0)
            if meta.kind in (:logbar,:logline)
                kwargs[:yscale]=log10
            end
            meta.kind==:logline && (kwargs[:xscale]=log10)
            axis=xkcd.Axis(figure[1,1];kwargs...)
            positive=[y for (_,values) in data for y in values if y>0]
            baseline=meta.kind==:logbar ? minimum(positive)*0.6 : 0.0
            if meta.kind in (:bar,:logbar)
                count_series=length(data)
                width=0.82/count_series
                for (index,(xs,ys)) in enumerate(data)
                    offset=(index-(count_series+1)/2)*width
                    xkcd.barplot!(axis,xs .+ offset,ys;width=width*0.9,
                        fillto=baseline,color=ARTICLE_COLORS[index],
                        strokecolor=:black,strokewidth=1,
                        label=meta.names[index])
                end
                if meta.kind==:logbar
                    xkcd.ylims!(axis,baseline,maximum(positive)*2)
                elseif minimum(y for (_,values) in data for y in values)<0
                    yvals=[y for (_,values) in data for y in values]
                    xkcd.ylims!(axis,minimum(yvals)*1.25,maximum(yvals)*1.3)
                else
                    xkcd.ylims!(axis,0,maximum(positive)*1.3)
                end
            else
                for (index,(xs,ys)) in enumerate(data)
                    xkcd.lines!(axis,xs,ys;color=ARTICLE_COLORS[index],linewidth=3,
                        label=meta.names[index])
                    xkcd.scatter!(axis,xs,ys;color=ARTICLE_COLORS[index],markersize=13)
                end
            end
            xkcd.axislegend(axis;position=:lt,nbanks=length(data)>3 ? 2 : 1,
                labelsize=15)
            path=joinpath(plot_dir,"exploratory_"*key*".pdf")
            xkcd.save(path,figure)
            isfile(path) && filesize(path)>0 || error("article figure not saved: "*key)
            push!(paths,path)
        end
    end
    paths
end

"""Render all measured exploratory plots as deterministic vector XKCDMakie PDFs.
The source coordinates are read from the article's documented PGFPlots fallback;
this function performs no benchmark and does not manufacture observations.
"""
function render_exploratory_figures(source::AbstractString,plot_dir::AbstractString)
    @eval import CairoMakie
    cairo=Base.invokelatest(getfield,@__MODULE__,:CairoMakie)
    previous=Base.invokelatest(cairo.Makie.current_default_theme)
    @eval import XKCDMakie
    xkcd=Base.invokelatest(getfield,@__MODULE__,:XKCDMakie)
    try
        Base.invokelatest(_render_exploratory_loaded,xkcd,source,plot_dir)
    finally
        Base.invokelatest(cairo.Makie.set_theme!,previous)
    end
end
