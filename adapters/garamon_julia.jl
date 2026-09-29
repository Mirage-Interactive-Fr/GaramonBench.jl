# Loaded explicitly into Main. Garamon remains a benchmark target, not a pinned
# dependency of the harness, so two checkouts can be compared independently.
push!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random


include("julia_products_kernels.jl")

register_adapter!(BenchmarkAdapter(name="garamon_julia",generate=gb_generate_vectors,
    prepare=gb_prepare_vectors,execute=gb_execute_vectors,
    oracle=(state,result)->size(result)==size(state.fixture.expected) && result==state.fixture.expected,
    contract="owned Float64 matrix of all structural product coefficients in ascending mask order",
    capabilities=Dict("exact_oracle"=>"Int64 explicit vector basis inversions",
        "metrics"=>"euclidean diagonal only","generation_includes_oracle"=>true,
        "native_child_memory_measured"=>false,"gpu_kernel"=>false));replace=true)
