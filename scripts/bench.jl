# Launch from any working directory: julia /path/to/GaramonBench/scripts/bench.jl
if "--help" in ARGS
    println("Usage: julia scripts/bench.jl [--preflight] [--ids=17,18] [--output=PATH] [--allow-source-changes] [--gpu=auto|required|off] [--no-progress]")
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
    for arg in args
        if arg=="--preflight"
            phase=:preflight
        elseif arg=="--allow-source-changes"
            allow_source_changes=true
        elseif arg=="--no-progress"
            show_progress=false
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
    (;ids,output,gpu,phase,allow_source_changes,show_progress)
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

destination=isnothing(settings.output) ? DrWatson.datadir("garamonbench","techniques-dedicated-001") : settings.output
println("Project: ",Base.active_project())
println("Campaign: ",abspath(destination))
run_technique_campaign(destination;ids=settings.ids,gpu=settings.gpu,
    phase=settings.phase,allow_source_changes=settings.allow_source_changes,
    show_progress=settings.show_progress)
