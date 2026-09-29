# A bounded generated kernel and the corresponding prepared plan share inputs.
pushfirst!(LOAD_PATH, get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")))
using Garamon, GaramonBench, Random
isdefined(@__MODULE__, :gb_generate_vectors) ||
    Base.include(@__MODULE__, joinpath(@__DIR__, "julia_products_kernels.jl"))

function ggen_generate(case, directory, rng)
    2 <= case["dimension"] <= 16 || error("generated vector dimension budget")
    case["strategy"] in ("prepared", "generated") || error("generated strategy")
    gb_generate_vectors(case, directory, rng)
end

function ggen_prepare(fixture, case, directory)
    base = gb_prepare_vectors(merge(fixture, (strategy="prepared",)), case, directory)
    program = case["strategy"] == "generated" ?
        generate_product(base.plan; max_paths=256) : nothing
    (; base, program, strategy=case["strategy"])
end

function ggen_execute(state)
    state.strategy == "prepared" && return gb_execute_vectors(state.base)
    fixture = state.base.fixture
    output = Matrix{Float64}(undef, length(fixture.output_masks), fixture.horizon)
    for t in 1:fixture.horizon
        result = run_generated_product(state.program, state.base.inputs[t]...)
        for (i, mask) in enumerate(fixture.output_masks)
            output[i,t] = coefficient_mask(result, mask)
        end
    end
    output
end

register_adapter!(BenchmarkAdapter(name="garamon_generated_product",
    generate=ggen_generate, prepare=ggen_prepare, execute=ggen_execute,
    oracle=(state,result)->size(result)==size(state.base.fixture.expected) &&
        result==state.base.fixture.expected,
    contract="owned Float64 matrix of all structural vector-product coefficients",
    capabilities=Dict("exact_oracle"=>"independent Int64 explicit vector basis inversions",
        "strategies"=>"prepared,generated", "max_generated_paths"=>256,
        "metric_factors_at_runtime"=>true, "generation_includes_oracle"=>true)); replace=true)
