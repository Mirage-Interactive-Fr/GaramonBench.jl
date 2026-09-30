# Exact repeated products under direct execution, LRU, or roulette plan
# retention. Roulette may evict a plan but never discard product terms.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

pc_indices(mask,n)=[i for i in 1:n if !iszero(mask & (one(mask) << (i-1)))]

function pc_factor(amask,bmask,diagonal)
    ai=pc_indices(amask,length(diagonal))
    bi=pc_indices(bmask,length(diagonal))
    parity=0
    for i in ai
        parity+=searchsortedfirst(bi,i)-1
    end
    factor=isodd(parity) ? Int64(-1) : Int64(1)
    for i in intersect(ai,bi)
        factor*=diagonal[i]
    end
    xor(amask,bmask),factor
end

function pc_trace_index(trace,t,horizon)
    trace=="hot" && return 1
    trace=="scan" && return mod1(t,4)
    trace=="phase" && return mod1(div(t-1,max(1,div(horizon,4)))+1,4)
    trace=="shift" && return mod1(div(t-1,2)+1,4)
    error("unknown cache trace")
end

function pc_generate(case,directory,rng)
    n=case["dimension"]
    2<=n<=129 || error("cache dimension budget")
    horizon=case["horizon"]
    1<=horizon<=1024 || error("cache horizon budget")
    signature=case["signature"]
    signature in ("positive","mixed","degenerate") || error("cache signature")
    strategy=case["strategy"]
    strategy in ("direct","lru","roulette","tinylfu","sieve") ||
        error("cache strategy")
    capacity_plans=get(case,"capacity_plans",1)
    capacity_plans in (1,2) || error("cache capacity fixture")
    eviction_exponent=Float64(get(case,"eviction_exponent",1.0))
    isfinite(eviction_exponent) && 0<=eviction_exponent<=8 ||
        error("cache eviction exponent fixture")
    frequency_slots=get(case,"frequency_slots",256)
    frequency_slots in (16,256,4096) || error("cache sketch width fixture")
    trace=case["trace"]
    trace in ("hot","scan","phase","shift") || error("cache trace")
    diagonal=signature=="positive" ? ones(Int64,n) :
        signature=="mixed" ? Int64[iseven(i) ? -1 : 1 for i in 1:n] :
        Int64[i%3==0 ? 0 : iseven(i) ? -1 : 2 for i in 1:n]
    K=n<=64 ? UInt64 : n<=128 ? UInt128 : BigInt
    low=one(K);high=one(K) << (n-1)
    full=K==BigInt ? (big(1) << n)-1 :
        n==8*sizeof(K) ? typemax(K) : (one(K) << n)-one(K)
    supports=[(K[0,low],K[0,high]),
              (K[0,high],K[0,low]),
              (K[low,high],K[0,full]),
              (K[0,full],K[low,high])]
    targets=sort!(unique(K[xor(a,b) for (left,right) in supports
        for a in left for b in right]))
    positions=Dict(mask=>i for (i,mask) in enumerate(targets))
    selected=[pc_trace_index(trace,t,horizon) for t in 1:horizon]
    coefficients=[(rand(rng,Int64(1):Int64(3),length(supports[k][1])),
                   rand(rng,Int64(1):Int64(3),length(supports[k][2])))
                  for k in selected]
    expected=zeros(Int64,length(targets),horizon)
    for t in 1:horizon
        left,right=supports[selected[t]]
        av,bv=coefficients[t]
        for (ia,amask) in enumerate(left),(ib,bmask) in enumerate(right)
            output,factor=pc_factor(amask,bmask,diagonal)
            expected[positions[output],t]+=factor*av[ia]*bv[ib]
        end
    end
    (;n,horizon,signature,strategy,trace,capacity_plans,eviction_exponent,
      frequency_slots,
      diagonal,supports,targets,
      selected,coefficients,expected)
end

function pc_prepare(fixture,case,directory)
    ga=if fixture.signature=="positive"
        algebra(fixture.n,:ega)
    else
        metric=zeros(Int64,fixture.n,fixture.n)
        for i in 1:fixture.n
            metric[i,i]=fixture.diagonal[i]
        end
        algebra(metric)
    end
    make_input(t)=begin
        left,right=fixture.supports[fixture.selected[t]]
        av,bv=fixture.coefficients[t]
        a=multivector(ga,Dict(mask=>Float64(av[i]) for (i,mask) in enumerate(left));
            storage=:sparse)
        b=multivector(ga,Dict(mask=>Float64(bv[i]) for (i,mask) in enumerate(right));
            storage=:sparse)
        (a,b)
    end
    first_input=make_input(1)
    inputs=Vector{typeof(first_input)}(undef,fixture.horizon)
    inputs[1]=first_input
    for t in 2:fixture.horizon
        inputs[t]=make_input(t)
    end
    cache=nothing
    if fixture.strategy!="direct"
        single_sizes=Int[]
        for (left,right) in fixture.supports
            probe=ProductPlanCache(max_bytes=typemax(Int))
            a=multivector(ga,Dict(mask=>1.0 for mask in left);storage=:sparse)
            b=multivector(ga,Dict(mask=>1.0 for mask in right);storage=:sparse)
            cached_plan!(probe,a,b)
            push!(single_sizes,cache_stats(probe).estimated_bytes)
        end
        budget=fixture.capacity_plans==1 ? maximum(single_sizes) :
            sum(single_sizes[1:2])
        cache=ProductPlanCache(max_bytes=budget,
            policy=Symbol(fixture.strategy),
            eviction_exponent=fixture.eviction_exponent,
            frequency_slots=fixture.frequency_slots,
            seed=get(case,"draw_seed",case["seed"]))
    end
    (;fixture,inputs,cache)
end

function pc_execute(state)
    fixture=state.fixture
    output=Matrix{Float64}(undef,length(fixture.targets),fixture.horizon)
    for t in 1:fixture.horizon
        a,b=state.inputs[t]
        result=isnothing(state.cache) ? a*b : cached_product!(state.cache,a,b)
        pc_store_result!(output,result,fixture.targets,t)
    end
    output
end

function pc_store_result!(output::Matrix{Float64},result::R,
                          targets::AbstractVector{K},t::Int) where
                          {R<:AbstractMultiVector,K<:Integer}
    for (i,mask) in enumerate(targets)
        output[i,t]=coefficient_mask(result,mask)
    end
    output
end

function pc_oracle(state,result)
    result==state.fixture.expected || return false
    isnothing(state.cache) && return true
    stats=cache_stats(state.cache)
    (state.fixture.capacity_plans!=1 || stats.entries<=1) &&
        stats.estimated_bytes<=stats.max_bytes || return false
    state.fixture.horizon>=4 && state.fixture.trace!="hot" &&
        stats.evictions+stats.admissions_rejected<1 && return false
    state.fixture.horizon>=2 && state.fixture.trace=="hot" &&
        stats.hits<1 && return false
    state.fixture.capacity_plans==2 && state.fixture.horizon>=17 &&
        state.fixture.trace in ("scan","phase","shift") &&
        stats.multi_candidate_evictions+stats.admissions_rejected<1 && return false
    true
end

register_adapter!(BenchmarkAdapter(name="garamon_plan_cache",
    generate=pc_generate,prepare=pc_prepare,execute=pc_execute,oracle=pc_oracle,
    baseline_execute=state->pc_execute(merge(state,(cache=nothing,))),
    baseline_name="garamon_julia_direct_product",
    preflight_evidence=(state,result)->isnothing(state.cache) ?
        Dict{String,Any}("policy"=>"direct") : begin
            stats=cache_stats(state.cache)
            Dict{String,Any}("policy"=>string(stats.policy),
                "eviction_exponent"=>stats.eviction_exponent,
                "capacity_plans"=>state.fixture.capacity_plans,
                "frequency_slots"=>state.fixture.frequency_slots,
                "multi_candidate_evictions"=>stats.multi_candidate_evictions,
                "evictions"=>stats.evictions,"hits"=>stats.hits,
                "admissions_rejected"=>stats.admissions_rejected,
                "frequency_metadata_bytes"=>stats.frequency_metadata_bytes,
                "sieve_scans"=>stats.sieve_scans,
                "estimated_bytes"=>stats.estimated_bytes,"max_bytes"=>stats.max_bytes)
        end,
    contract="owned Float64 matrix of all structural product coefficients over a changing trace",
    capabilities=Dict("exact_oracle"=>"independent Int64 word inversion per trace step",
        "strategies"=>"direct,lru,roulette,tinylfu,sieve",
        "traces"=>"hot,scan,phase,shift",
        "retention_budget"=>"one plan, or first two plans to expose multiple eviction candidates",
        "roulette_changes"=>"plan retention only, never algebraic contributions",
        "generation_includes_oracle"=>true));replace=true)
