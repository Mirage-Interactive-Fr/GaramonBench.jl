# Launch from any working directory: julia /path/to/GaramonBench/scripts/bench.jl
if "--help" in ARGS
    println("Usage: julia scripts/bench.jl [--preflight|--refresh-article] [--ids=17,18] [--output=PATH] [--allow-source-changes] [--gpu=auto|required|off] [--no-progress] [--skip-initial-article-refresh]")
    println("The default runs the dedicated-machine technique campaign. Repeat the same options to resume.")
    exit()
end

function options(args)
    ids=String[]
    output=nothing
    gpu=:auto
    phase=:benchmark
    allow_source_changes=false
    show_progress=true
    refresh_article_on_resume=true
    for arg in args
        if arg=="--preflight"
            phase=:preflight
        elseif arg=="--refresh-article"
            phase=:refresh_article
        elseif arg=="--allow-source-changes"
            allow_source_changes=true
        elseif arg=="--no-progress"
            show_progress=false
        elseif arg=="--skip-initial-article-refresh"
            refresh_article_on_resume=false
        elseif startswith(arg,"--ids=")
            ids=split(arg[7:end],',')
        elseif startswith(arg,"--output=")
            output=expanduser(arg[10:end])
        elseif startswith(arg,"--gpu=")
            gpu=Symbol(arg[7:end])
            gpu in (:auto,:required,:off) || error("Invalid GPU option")
        else
            error("Unknown option: "*arg*"; use --help")
        end
    end
    (;ids,output,gpu,phase,allow_source_changes,show_progress,refresh_article_on_resume)
end
settings=options(ARGS)

# Pkg is a standard library: bootstrap even if DrWatson is not installed in
# the caller's global environment, then import it from this project.
using Pkg
Pkg.activate(normpath(joinpath(@__DIR__,"..")))
Pkg.instantiate()
using DrWatson
@quickactivate "GaramonBench"
DrWatson.projectname()=="GaramonBench" || error("Unexpected benchmark project")
using GaramonBench
samefile(pkgdir(GaramonBench),normpath(joinpath(@__DIR__,".."))) ||
    error("This launcher loaded GaramonBench from a different checkout: "*pkgdir(GaramonBench))

destination=isnothing(settings.output) ? DrWatson.datadir("garamonbench","techniques-dedicated-001") : settings.output
println("Project: ",Base.active_project())
println("Campaign: ",abspath(destination))
if settings.phase==:refresh_article
    result=refresh_technique_article(destination;ids=settings.ids)
    println("Article: ",result.article_pdf,
        "; measured figures rebuilt: ",length(result.figures))
    println("Rebuilt technique IDs: ",join(sort!(getproperty.(result.figures,:id)),", "))
    if !isempty(result.pending_measurements)
        println("Techniques requiring validated timing measurements: ",
            join(sort!(getproperty.(result.pending_measurements,:id)),", "),
            ". Earlier unverified curves were excluded; these techniques remain in the campaign.")
    end
else
    run_technique_campaign(destination;ids=settings.ids,gpu=settings.gpu,
        phase=settings.phase,allow_source_changes=settings.allow_source_changes,
        show_progress=settings.show_progress,
        refresh_article_on_resume=settings.refresh_article_on_resume)
end
