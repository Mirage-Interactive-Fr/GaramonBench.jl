const EXPLORATORY_FIGURES = Dict(
    "cpppacked" => (kind=:bar, x=["3D mixte","3D vect.","7D mixte","7D vect."],
        names=["Julia JIT","Julia précompilée","C++ packed"], xlabel="Charge",
        ylabel="Lot de 10 000 produits (ms)"),
    "cppmovealloc" => (kind=:bar, x=["3D mixte","3D vect.","7D mixte","7D vect."],
        names=["C++ amont","C++ avec déplacements"], xlabel="Charge",
        ylabel="Appels malloc Eigen (milliers)"),
    "sorties" => (kind=:bar, x=["Une sortie","Quatre sorties"],
        names=["Récursion","join3"], xlabel="Sorties demandées",
        ylabel="Temps par lot (µs)"),
    "tripleamort" => (kind=:logline, x=["1","32","1 024"],
        names=["Égalité","Une sortie","Quatre sorties"],
        xlabel="Produits réutilisant les mêmes supports",
        ylabel="Temps plan / temps join3"),
    "workspaceamort" => (kind=:logbar,
        x=["Creux 2D H=1","Creux 2D H=32","Creux 4D H=32","Creux 12D H=1024"],
        names=["Direct total","Workspace total"], xlabel="Charge",
        ylabel="Temps de la trace (µs)"),
    "masques" => (kind=:logbar,
        x=["65D coefficient","65D entier","128D coefficient","128D entier"],
        names=["BigInt","UInt128"], xlabel="Charge",
        ylabel="Médiane du noyau (µs)"),
    "n01horizon" => (kind=:bar, x=["1","32","1 024"],
        names=["Passage 1","Ordre inverse"], xlabel="Produits par épisode H",
        ylabel="Cas favorables à N01 (sur 36)"),
    "n03screen" => (kind=:bar, x=["1/1","1/2","2/1","2/2","3/1","3/2"],
        names=["Radical","Régulier","Sensible ou égalité"],
        xlabel="Directions actives r/s", ylabel="Configurations appariées"),
    "n04smoke" => (kind=:logbar,
        x=["V2 stable","M4 stable","N65 changeant","R4 refus"],
        names=["Linéaire","Binaire","DAG","Certifier chaque fois","Certifier puis réemployer"],
        xlabel="Fixture", ylabel="Médiane de l'épisode (µs)"),
    "n05temps" => (kind=:logbar,
        x=["2D signée","65D signée","4D générale","8D dégénérée"],
        names=["Complet","Récursif scalaire","Contractions + Pfaffien"],
        xlabel="Fixture", ylabel="Médiane de l'épisode (µs)"),
    "k3partage" => (kind=:logbar,
        x=["A : changeant","B : stable","C : une chaîne","D : disjoint"],
        names=["Indépendant","Workspace partagé","Cache vérifié"],
        xlabel="Fixture", ylabel="Médiane de l'épisode (µs)"),
    "b1dimensions" => (kind=:line,
        x=["2","3","4","6","8","12","16","32","64","65","96","128"],
        names=["Calcul chaud","Épisode complet"], xlabel="Dimension ambiante n",
        ylabel="Octets alloués"),
    "b1gradealloc" => (kind=:line,
        x=["2","3","4","6","8","12","16","32","64","65","96","128"],
        names=["Bas grades","Grades n et n−1"], xlabel="Dimension ambiante n",
        ylabel="Octets alloués par épisode"),
    "b1horizons" => (kind=:bar,
        x=["2 bas","2 haut","8 bas","8 haut","65 bas","65 haut","128 bas","128 haut"],
        names=["Avantage de l'annotation"], xlabel="Dimension et grade",
        ylabel="Avantage de A sur V (%)"),
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
