# N05: exact scalar projection of an even ordered vector chain. The oracle
# applies Chevalley wedge and contraction to a full exterior-state dictionary;
# it never calls the Pfaffian or a Garamon product.
pushfirst!(LOAD_PATH, get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")))
using Garamon, GaramonBench, LinearAlgebra, Random
include(joinpath(get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")), "perf", "n05_pfaffian.jl"))

function pf35_exterior_oracle(G::Matrix{Int64}, V::Matrix{Int64})
    n,k = size(V)
    Q = Rational{BigInt}
    state = Dict{UInt64,Q}(0=>one(Q))
    # Left multiplication: apply the rightmost vector first. A metric
    # contraction against each occupied blade axis lowers grade by one.
    for col in k:-1:1
        next = Dict{UInt64,Q}()
        for (mask,value) in state
            occupied = [i for i in 1:n if !iszero(mask & (UInt64(1) << (i-1)))]
            for i in 1:n
                bit = UInt64(1) << (i-1)
                if iszero(mask & bit)
                    sign = isodd(count(j->j<i,occupied)) ? -1 : 1
                    next[mask|bit] = get(next,mask|bit,zero(Q)) +
                        sign*Q(V[i,col])*value
                end
            end
            for (place,i) in enumerate(occupied)
                contraction = sum((Q(V[j,col])*Q(G[j,i]) for j in 1:n);init=zero(Q))
                reduced = mask ⊻ (UInt64(1) << (i-1))
                next[reduced] = get(next,reduced,zero(Q)) +
                    (isodd(place) ? 1 : -1)*contraction*value
            end
        end
        filter!(entry->!iszero(last(entry)),next)
        state = next
    end
    get(state,UInt64(0),zero(Q))
end

function pf35_generate(case,directory,rng)
    n = case["dimension"]
    2<=n<=64 || error("Pfaffian oracle mask budget")
    k = case["chain_length"]
    k in (2,4,6,8,12,16) || error("even chain budget")
    strategy = case["strategy"]
    strategy in ("pfaffian","precontracted","full","recursive") ||
        error("Pfaffian strategy")
    horizon = case["horizon"]
    1<=horizon<=16 || error("Pfaffian horizon budget")
    G = zeros(Int64,n,n)
    for i in 1:n
        G[i,i] = iseven(i) ? -1 : 1
    end
    V = zeros(Int64,n,k)
    # Repeated e1,e2 pairs make the scalar nonzero and exercise signs.
    for j in 1:k
        V[iseven(j) ? 2 : 1,j] = 1
    end
    expected = pf35_exterior_oracle(G,V)
    (;n,k,strategy,horizon,G,V,expected)
end

function pf35_prepare(fixture,case,directory)
    G = Float64.(fixture.G)
    V = Float64.(fixture.V)
    ga = algebra(G)
    contractions = fixture.strategy=="precontracted" ? n05_contractions(G,V) : nothing
    (;fixture,G,V,ga,contractions)
end

function pf35_execute(state)
    strategy = state.fixture.strategy
    values = Vector{Float64}(undef,state.fixture.horizon)
    for t in eachindex(values)
        values[t] = strategy=="pfaffian" ? n05_scalar(state.G,state.V) :
            strategy=="precontracted" ? n05_pfaffian!(copy(state.contractions)) :
            strategy=="full" ? n05_garamon(state.ga,state.V,:full) :
            n05_garamon(state.ga,state.V,:recursive)
    end
    values
end

function pf35_oracle(state,result)
    length(result)==state.fixture.horizon || return false
    exact = state.fixture.expected
    # All configured inputs are small integers and exactly representable.
    all(value->isfinite(value) && Rational{BigInt}(value)==exact,result)
end

register_adapter!(BenchmarkAdapter(name="garamon_pfaffian_scalar",
    generate=pf35_generate,prepare=pf35_prepare,execute=pf35_execute,
    baseline_execute=state->pf35_execute(merge(state,
        (fixture=merge(state.fixture,(strategy="full",)),))),
    baseline_name="garamon_julia_full_vector_chain",
    oracle=pf35_oracle,
    contract="owned Float64 vector of scalar projections of an ordered even vector chain",
    capabilities=Dict("exact_oracle"=>"independent Rational{BigInt} Chevalley exterior action",
        "strategies"=>"pfaffian,precontracted,full,recursive",
        "output"=>"scalar only; no full multivector equivalence implied",
        "chain"=>"even vector chain", "gpu_kernel"=>false,
        "generation_includes_oracle"=>true));replace=true)
