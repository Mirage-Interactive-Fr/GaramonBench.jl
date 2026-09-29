module GaramonBench

using Dates, DrWatson, SHA, TOML, UUIDs, Random, Pkg, BenchmarkTools, JSON, Statistics

# Correctness-only preflight must not initialize PerfChecker. Measurement paths
# load it explicitly when selected.
function require_perfchecker()
    isdefined(@__MODULE__,:PerfChecker) || (@eval import PerfChecker)
    nothing
end

export BenchmarkAdapter, register_adapter!, load_config, expand_cases, case_id,
       repository_identity, machine_snapshot, run_campaign, with_build_directory,
       archive_file!, cli, register_smoke_adapter!, run_cpp_matched, recipe_plan, run_recipe, audit_k1,
       profile_plan, profile_preflight, profile_capture, b1_plan, run_b1,
       run_resumable_campaign, resumable_status, audit_resumable_archive,
       technique_inventory, technique_smoke_plan, run_technique_smoke,
       technique_bench_plan, run_technique_bench,
       technique_profile_request, run_technique_profiles,
       compatibility_matrix, ensure_cpp_source, cpp_source_root, cpp_source_revision,
       cpp_toolchain, cpp_toolchain_environment,
       external_ga_candidates, ensure_external_ga_source, bench
export render_exploratory_figures

include("cpp_install.jl")
include("external_ga.jl")
include("configuration.jl")
include("provenance.jl")
include("runner.jl")
include("resume.jl")
include("techniques.jl")
include("quickcheck.jl")
include("cpp_matched.jl")
include("recipes.jl")
include("recipe_k1.jl")
include("profiling.jl")
include("bounds_b1.jl")
include("cli.jl")
include(joinpath(@__DIR__, "..", "adapters", "external_ga_vector_product.jl"))
include("report.jl")
include("article_figures.jl")
include("bench.jl")

function __init__()
    if haskey(ENV, "GARAMON_CPP_ROOT")
        root=cpp_source_root()
        isfile(joinpath(root,"CMakeLists.txt")) || error("Garamon C++ source missing")
        if haskey(ENV,"GARAMON_CPP_REVISION")
            ENV["GARAMON_CPP_REVISION"]==CPP_SOURCE_REVISION ||
                error("Garamon C++ mirror revision differs from pinned source")
        else
            cpp_source_revision(root)
        end
    else
        ensure_cpp_source()
    end
end

end
