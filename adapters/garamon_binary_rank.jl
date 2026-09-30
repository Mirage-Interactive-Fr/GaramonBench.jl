# Bounded N01 support-rank prototype. Expected values use ambient Clifford
# word arithmetic, independent of the reduced-coordinate cocycle and plan.
pushfirst!(LOAD_PATH, get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")))
using Garamon, GaramonBench, LinearAlgebra, Random
include(joinpath(get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")), "perf", "binary_rank.jl"))
using .BinaryRankPrototype

function br31_word(a::BigInt, b::BigInt, diagonal::Vector{Int64})
    left = [i for i in eachindex(diagonal) if !iszero(a & (big(1) << (i-1)))]
    right = [i for i in eachindex(diagonal) if !iszero(b & (big(1) << (i-1)))]
    inversions = sum(count(j -> j<i, right) for i in left; init=0)
    factor = isodd(inversions) ? Int64(-1) : Int64(1)
    for i in intersect(left, right)
        factor *= diagonal[i]
    end
    xor(a,b), factor
end

function br31_generate(case, directory, rng)
    n = case["dimension"]
    2 <= n <= 129 || error("binary-rank fixture dimension budget")
    strategy = case["strategy"]
    strategy in ("rank", "direct") || error("binary-rank strategy")
    signature = case["signature"]
    signature in ("mixed", "degenerate") || error("binary-rank signature")
    horizon = case["horizon"]
    1 <= horizon <= 32 || error("binary-rank horizon budget")
    diagonal = Int64[signature=="degenerate" && i==n ? 0 : iseven(i) ? -1 : 1
                     for i in 1:n]
    low = big(1)
    high = big(1) << (n-1)
    blade = low | high
    left = BigInt[0, blade]
    # Include the ambient grade-2 generator on both sides: its square has a
    # nontrivial sign even though the reduced support rank is only two.
    right = BigInt[0, high, blade]
    targets = sort!(unique(BigInt[xor(a,b) for a in left for b in right]))
    positions = Dict(mask=>i for (i,mask) in enumerate(targets))
    coefficients = [(rand(rng, Int64(1):Int64(3), length(left)),
                     rand(rng, Int64(1):Int64(3), length(right)))
                    for _ in 1:horizon]
    expected = zeros(Int64, length(targets), horizon)
    for t in 1:horizon
        av,bv = coefficients[t]
        for (i,a) in enumerate(left), (j,b) in enumerate(right)
            mask,factor = br31_word(a,b,diagonal)
            expected[positions[mask],t] += factor*av[i]*bv[j]
        end
    end
    (;n,signature,strategy,horizon,diagonal,left,right,targets,coefficients,expected)
end

function br31_prepare(fixture, case, directory)
    metric_matrix = zeros(Int64,fixture.n,fixture.n)
    for i in 1:fixture.n
        metric_matrix[i,i] = fixture.diagonal[i]
    end
    ga = algebra(metric_matrix)
    inputs = [(
        multivector(ga, Dict(mask=>Float64(av[i]) for (i,mask) in enumerate(fixture.left));
            storage=:sparse),
        multivector(ga, Dict(mask=>Float64(bv[i]) for (i,mask) in enumerate(fixture.right));
            storage=:sparse)) for (av,bv) in fixture.coefficients]
    plans = fixture.strategy=="rank" ?
        [prepare_rank(a,b;max_rank=4,max_pairs=16,max_bytes=1<<20)
         for (a,b) in inputs] : nothing
    (;fixture,inputs,plans)
end

function br31_execute(state)
    f = state.fixture
    out = Matrix{Float64}(undef,length(f.targets),f.horizon)
    for t in 1:f.horizon
        a,b = state.inputs[t]
        result = isnothing(state.plans) ? a*b : rank_product(state.plans[t],a,b)
        for (i,mask) in enumerate(f.targets)
            out[i,t] = coefficient_mask(result,mask)
        end
    end
    out
end

register_adapter!(BenchmarkAdapter(name="garamon_binary_rank",
    generate=br31_generate, prepare=br31_prepare, execute=br31_execute,
    baseline_execute=state->br31_execute(merge(state,(plans=nothing,))),
    baseline_name="garamon_julia_direct_product",
    oracle=(state,result)->size(result)==size(state.fixture.expected) &&
        result==state.fixture.expected,
    contract="owned Float64 matrix of every structural coefficient of fixed-support diagonal product",
    capabilities=Dict("exact_oracle"=>"independent Int64 ambient Clifford-word inversions",
        "strategies"=>"rank,direct", "support"=>"two and three terms, rank at most 2",
        "metric"=>"diagonal mixed or degenerate", "gpu_kernel"=>false,
        "generation_includes_oracle"=>true)); replace=true)
