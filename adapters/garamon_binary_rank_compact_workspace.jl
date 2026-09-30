# K1 combination (08+09+31): reachable XOR outputs and one reusable buffer.
# The expected matrix is computed from ambient Clifford basis words, never
# from the reduced-coordinate plan or a Garamon product.
pushfirst!(LOAD_PATH, get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")))
using Garamon, GaramonBench, Random
const K1_TARGET_ROOT = get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon"))
isdefined(@__MODULE__,:BinaryRankPrototype) ||
    include(joinpath(K1_TARGET_ROOT,"perf","binary_rank.jl"))
isdefined(@__MODULE__,:BinaryRankCompactPrototype) ||
    include(joinpath(K1_TARGET_ROOT,"perf","binary_rank_compact.jl"))
using .BinaryRankCompactPrototype

function k1_word(a::BigInt,b::BigInt,diagonal::Vector{Int64})
    ai = [i for i in eachindex(diagonal) if !iszero(a & (big(1) << (i-1)))]
    bi = [i for i in eachindex(diagonal) if !iszero(b & (big(1) << (i-1)))]
    inversions = count(i>j for i in ai for j in bi)
    factor = isodd(inversions) ? Int64(-1) : Int64(1)
    for i in intersect(ai,bi)
        factor *= diagonal[i]
    end
    xor(a,b),factor
end

function k1_generate(case,directory,rng)
    n = case["dimension"]
    3<=n<=129 || error("K1 dimension budget")
    case["strategy"]=="compact_workspace" || error("K1 minimal strategy")
    horizon=case["horizon"]
    2<=horizon<=32 || error("K1 workspace reuse horizon")
    diagonal = Int64[iseven(i) ? -1 : 1 for i in 1:n]
    low = big(1)
    second = big(1) << 1
    high = big(1) << (n-1)
    left = BigInt[0,low|high,second|high]
    right = BigInt[0,high]
    targets = sort!(unique(BigInt[xor(a,b) for a in left for b in right]))
    positions = Dict(mask=>i for (i,mask) in enumerate(targets))
    coefficients = [(rand(rng,Int64(1):Int64(3),length(left)),
                     rand(rng,Int64(1):Int64(3),length(right))) for _ in 1:horizon]
    coefficients[2] == coefficients[1] &&
        (coefficients[2][1][1] += 1)
    expected = zeros(Int64,length(targets),horizon)
    for t in 1:horizon
        av,bv = coefficients[t]
        for (i,a) in enumerate(left), (j,b) in enumerate(right)
            mask,factor = k1_word(a,b,diagonal)
            expected[positions[mask],t] += factor*av[i]*bv[j]
        end
    end
    (;n,diagonal,left,right,targets,coefficients,expected,horizon)
end

function k1_prepare(fixture,case,directory)
    metric_values = zeros(Int64,fixture.n,fixture.n)
    for i in 1:fixture.n
        metric_values[i,i] = fixture.diagonal[i]
    end
    ga = algebra(metric_values)
    inputs = [(
        multivector(ga,Dict(mask=>Float64(av[i]) for (i,mask) in enumerate(fixture.left));
            storage=:sparse),
        multivector(ga,Dict(mask=>Float64(bv[i]) for (i,mask) in enumerate(fixture.right));
            storage=:sparse)) for (av,bv) in fixture.coefficients]
    plan = prepare_compact_rank(inputs[1]...;query=(:all,0),max_rank=4,
        max_pairs=16,max_outputs=16,max_bytes=1<<20)
    workspace = CompactRankWorkspace(plan,Float64;max_bytes=1<<20)
    length(plan.phi)<(1<<length(plan.basis)) || error("fixture does not exercise compact outputs")
    sort!(BigInt.(plan.phi))==fixture.targets || error("compact plan output coverage")
    (;fixture,inputs,plan,workspace)
end

function k1_execute(state)
    outputs = Matrix{Float64}(undef,length(state.fixture.targets),state.fixture.horizon)
    first_owned = nothing
    saved = nothing
    for t in 1:state.fixture.horizon
        result = compact_rank_product!(state.workspace,state.inputs[t]...)
        if t==1
            first_owned = result
            saved = copy(result.values)
        else
            first_owned.values==saved || error("first result was overwritten by workspace reuse")
            first_owned.values !== result.values || error("results share mutable dictionary")
        end
        for (i,mask) in enumerate(state.fixture.targets)
            outputs[i,t] = coefficient_mask(result,mask)
        end
    end
    outputs
end

register_adapter!(BenchmarkAdapter(name="garamon_binary_rank_compact_workspace",
    generate=k1_generate,prepare=k1_prepare,execute=k1_execute,
    baseline_execute=state->begin
        f=state.fixture
        output=Matrix{Float64}(undef,length(f.targets),length(state.inputs))
        for (t,(a,b)) in enumerate(state.inputs)
            product=geometric_product(a,b)
            for (i,mask) in enumerate(f.targets)
                output[i,t]=coefficient_mask(product,mask)
            end
        end
        output
    end,
    baseline_name="garamon_julia_direct_product",
    oracle=(state,result)->size(result)==size(state.fixture.expected) &&
        result==state.fixture.expected,
    contract="owned Float64 matrix of every reachable ambient coefficient across a workspace-reuse episode",
    capabilities=Dict("exact_oracle"=>"independent Int64 ambient Clifford-word inversions",
        "combination"=>"K1: 08+09+31", "route"=>"compact_rank_product! with reused workspace",
        "output_ownership"=>"first SparseMultiVector remains intact after second product",
        "compactness"=>"6 reachable XOR outputs in rank-3 span of 8",
        "generation_includes_oracle"=>true,"gpu_kernel"=>false));replace=true)
