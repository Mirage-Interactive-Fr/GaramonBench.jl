# Four-thread CPU packed batch with the same independent vector oracle.
pushfirst!(LOAD_PATH, get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")))
using Garamon, GaramonBench, Random
isdefined(@__MODULE__, :gb_generate_vectors) || include("julia_products_kernels.jl")
include(joinpath(get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")),
    "perf", "cpu_threaded_packed.jl"))
using .CPUThreadedPackedPrototype

function ctp_generate(case, directory, rng)
    Threads.nthreads() == case["threads_required"] || error("CPU packed thread count")
    case["strategy"] in ("serial_resident", "threaded_resident") ||
        error("CPU packed strategy")
    gb_generate_vectors(case, directory, rng)
end

function ctp_prepare(fixture, case, directory)
    base = gb_prepare_vectors(merge(fixture, (strategy="packed",)), case, directory)
    resident = cpu_resident_batch(base.batch; max_bytes=256<<20)
    (; base, resident, strategy=case["strategy"])
end

function ctp_execute(state)
    values = state.strategy == "threaded_resident" ?
        cpu_run_threaded!(state.resident) : cpu_run_serial!(state.resident)
    fixture = state.base.fixture
    output = Matrix{Float64}(undef, length(fixture.output_masks), fixture.horizon)
    for t in 1:fixture.horizon, i in eachindex(state.base.positions)
        output[i,t] = values[state.base.positions[i],t]
    end
    output
end

register_adapter!(BenchmarkAdapter(name="garamon_cpu_threaded_packed",
    generate=ctp_generate, prepare=ctp_prepare, execute=ctp_execute,
    baseline_execute=state->gb_execute_vectors_baseline(state.base),
    baseline_name="garamon_julia_direct_product",
    baseline_scenario=(state,case)->gb_baseline_scenario(state.base,case),
    baseline_output_identity=gb_baseline_output_identity,
    oracle=(state,result)->size(result)==size(state.base.fixture.expected) &&
        result==state.base.fixture.expected,
    contract="owned Float64 matrix extracted from reusable CPU packed output",
    capabilities=Dict("exact_oracle"=>"Int64 explicit vector basis inversions",
        "strategies"=>"serial_resident,threaded_resident",
        "threads_required"=>4,"generation_includes_oracle"=>true)); replace=true)
