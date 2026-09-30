# Dense-global versus sparse storage with the same complete Clifford product.
pushfirst!(LOAD_PATH, get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")))
using Garamon, GaramonBench, Random

function dg_word(a::Integer, b::Integer, diagonal)
    ai = [i for i in eachindex(diagonal) if !iszero(a & (1 << (i-1)))]
    bi = [i for i in eachindex(diagonal) if !iszero(b & (1 << (i-1)))]
    inversions = sum(x > y for x in ai for y in bi; init=0)
    factor = isodd(inversions) ? Int64(-1) : Int64(1)
    for i in intersect(ai, bi)
        factor *= diagonal[i]
    end
    xor(a, b), factor
end

function dg_generate(case, directory, rng)
    n = case["dimension"]
    2 <= n <= 12 || error("dense-global dimension budget")
    horizon = case["horizon"]
    1 <= horizon <= 32 || error("dense-global horizon budget")
    signature = case["signature"]
    signature in ("positive", "mixed", "degenerate") || error("dense-global signature")
    storage = case["strategy"]
    storage in ("dense", "sparse") || error("dense-global storage")
    support = case["support"]
    support in ("basis", "broad") || error("dense-global support")
    diagonal = signature == "positive" ? ones(Int64, n) :
        signature == "mixed" ? Int64[iseven(i) ? -1 : 1 for i in 1:n] :
        Int64[i%3==0 ? 0 : iseven(i) ? -1 : 2 for i in 1:n]
    universe = 1 << n
    masks = support == "basis" ? unique([0; [1 << (i-1) for i in 1:n]; universe-1]) :
        sort!(randperm(rng, universe)[1:min(universe, 64)] .- 1)
    coefficients = [(rand(rng, Int64(1):Int64(3), length(masks)),
                     rand(rng, Int64(1):Int64(3), length(masks)))
                    for _ in 1:horizon]
    expected = zeros(Int64, universe, horizon)
    for t in 1:horizon, (i, a) in enumerate(masks), (j, b) in enumerate(masks)
        output, factor = dg_word(a, b, diagonal)
        expected[output+1,t] += factor*coefficients[t][1][i]*coefficients[t][2][j]
    end
    (; n, horizon, signature, storage, support, diagonal, masks, coefficients, expected)
end

function dg_prepare(fixture, case, directory)
    ga = if fixture.signature == "positive"
        algebra(fixture.n, :ega)
    else
        values = zeros(Int64, fixture.n, fixture.n)
        for i in 1:fixture.n
            values[i,i] = fixture.diagonal[i]
        end
        algebra(values)
    end
    storage = Symbol(fixture.storage)
    inputs = [ntuple(k->multivector(ga,
        Dict(UInt64(mask)=>Float64(pair[k][i]) for (i,mask) in enumerate(fixture.masks));
        storage), 2) for pair in fixture.coefficients]
    @assert all((operand isa DenseMultiVector) == (storage == :dense)
                for pair in inputs for operand in pair)
    (; fixture, inputs)
end

function dg_execute(state)
    fixture = state.fixture
    output = Matrix{Float64}(undef, 1 << fixture.n, fixture.horizon)
    for t in 1:fixture.horizon
        result = geometric_product(state.inputs[t]...)
        @assert (result isa DenseMultiVector) == (fixture.storage == "dense")
        for mask in 0:(1 << fixture.n)-1
            output[mask+1,t] = coefficient_mask(result, mask)
        end
    end
    output
end

register_adapter!(BenchmarkAdapter(name="garamon_dense_global",
    generate=dg_generate, prepare=dg_prepare, execute=dg_execute,
    baseline_prepare=state->dg_prepare(merge(state.fixture,(storage="sparse",)),
        nothing,nothing),
    baseline_execute=dg_execute,
    baseline_name="garamon_julia_sparse_direct_product",
    oracle=(state,result)->size(result)==size(state.fixture.expected) &&
        result==state.fixture.expected,
    contract="owned Float64 matrix of every mask coefficient in global order",
    capabilities=Dict("exact_oracle"=>"Int64 pairwise basis inversions and diagonal intersections",
        "storage"=>"dense,sparse", "support"=>"basis,broad capped at 64 nonzero masks",
        "signatures"=>"positive,mixed,degenerate diagonal",
        "dense_dimension_limit"=>12, "generation_includes_oracle"=>true)); replace=true)
