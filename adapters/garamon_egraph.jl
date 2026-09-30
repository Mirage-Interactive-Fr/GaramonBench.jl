# ID23: bounded equality saturation of associative exact product chains.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random, SHA

function eg23_terms(rng,n,support_count)
    available=min(1<<n,support_count)
    masks=Set{UInt64}()
    while length(masks)<available
        push!(masks,UInt64(rand(rng,0:(1<<n)-1)))
    end
    Dict{UInt64,BigInt}(mask=>BigInt(rand(rng,(-2,-1,1,2)))
        for mask in masks)
end

function eg23_word_factor(left::UInt64,right::UInt64,diagonal)
    factor=BigInt(1)
    for i in eachindex(diagonal)
        !iszero(left & (UInt64(1)<<(i-1))) || continue
        isodd(count_ones(right & ((UInt64(1)<<(i-1))-1))) &&
            (factor=-factor)
        !iszero(right & (UInt64(1)<<(i-1))) &&
            (factor*=diagonal[i])
    end
    factor
end

function eg23_oracle!(aggregate,factors,diagonal)
    choices=[collect(factor) for factor in factors]
    for picked in Iterators.product(choices...)
        mask=UInt64(0)
        value=BigInt(1)
        for (right,coefficient) in picked
            value*=coefficient*eg23_word_factor(mask,right,diagonal)
            mask=xor(mask,right)
        end
        aggregate[mask]=get(aggregate,mask,BigInt(0))+value
    end
    filter!(entry->!iszero(last(entry)),aggregate)
    aggregate
end

function eg23_generate(case,directory,rng)
    n=case["dimension"]
    n in (2,4,6,8,10,12,14,16,18,20) || error("e-graph dimension")
    support_count=case["support_count"]
    support_count in (2,4,8) || error("e-graph support")
    factor_count=case["factor_count"]
    factor_count in (3,4) || error("e-graph factor count")
    pattern=case["support_pattern"]
    pattern in ("fixed","alternating") || error("e-graph pattern")
    preparation=case["preparation"]
    preparation in ("prebuilt","rebuild") || error("e-graph preparation")
    horizon=case["horizon"]
    horizon in (1,16,128) || error("e-graph horizon")
    diagonal=Int64[mod(i,7)==0 ? 0 : iseven(i) ? -1 : 1 for i in 1:n]
    episode=Vector{Vector{Dict{UInt64,BigInt}}}(undef,horizon)
    support_pool=[[sort!(collect(keys(eg23_terms(rng,n,support_count))))
        for _ in 1:factor_count] for _ in 1:(pattern=="fixed" ? 1 : 2)]
    expected=Dict{UInt64,BigInt}()
    for t in 1:horizon
        supports=support_pool[mod1(t,length(support_pool))]
        episode[t]=[Dict{UInt64,BigInt}(mask=>BigInt(rand(rng,(-2,-1,1,2)))
                     for mask in support) for support in supports]
        eg23_oracle!(expected,episode[t],diagonal)
    end
    (;n,support_count,factor_count,pattern,preparation,horizon,diagonal,
      episode,expected)
end

function eg23_prepare(f,case,directory)
    gram=zeros(Int64,f.n,f.n)
    for i in 1:f.n
        gram[i,i]=f.diagonal[i]
    end
    ga=algebra(gram)
    inputs=[[multivector(ga,terms;storage=:sparse) for terms in factors]
        for factors in f.episode]
    plans=f.preparation=="prebuilt" ?
        [prepare_product_egraph(inputs[t];max_support=1<<16)
         for t in 1:(f.pattern=="fixed" ? 1 : min(2,f.horizon))] : nothing
    (;fixture=f,ga,inputs,plans)
end

function eg23_execute(state)
    f=state.fixture
    aggregate=Dict{UInt64,BigInt}()
    for t in 1:f.horizon
        plan=isnothing(state.plans) ?
            prepare_product_egraph(state.inputs[t];max_support=1<<16) :
            state.plans[mod1(t,length(state.plans))]
        result=run_product_egraph(plan,state.inputs[t])
        for (mask,value) in result.values
            aggregate[mask]=get(aggregate,mask,BigInt(0))+value
        end
    end
    filter!(entry->!iszero(last(entry)),aggregate)
    aggregate
end

eg23_baseline_prepare(state)=state
function eg23_baseline(state)
    aggregate=Dict{UInt64,BigInt}()
    for factors in state.inputs
        product=reduce(geometric_product,factors)
        for (mask,value) in product.values
            aggregate[mask]=get(aggregate,mask,BigInt(0))+value
        end
    end
    filter!(entry->!iszero(last(entry)),aggregate)
    aggregate
end

eg23_serial(terms)=join((string(mask)*":"*string(value)
    for (mask,value) in sort!(collect(terms);by=first)),",")
function eg23_scenario(state,case)
    f=state.fixture
    Dict{String,Any}("family"=>"exact_associative_chain_aggregate",
        "dimension"=>f.n,"diagonal"=>f.diagonal,
        "episodes"=>[join((eg23_serial(terms) for terms in factors),"|")
            for factors in f.episode])
end
eg23_output_identity(result)=bytes2hex(sha256(join(
    (string(mask)*":"*string(value) for (mask,value)
     in sort!(collect(result);by=first)),",")))

register_adapter!(BenchmarkAdapter(name="garamon_egraph",
    generate=eg23_generate,prepare=eg23_prepare,execute=eg23_execute,
    baseline_prepare=eg23_baseline_prepare,baseline_execute=eg23_baseline,
    baseline_name="garamon_julia_left_associative_sparse_full_aggregate",
    baseline_scenario=eg23_scenario,
    baseline_output_identity=eg23_output_identity,
    oracle=(state,result)->result==state.fixture.expected,
    preflight_evidence=(state,result)->begin
        f=state.fixture
        plan=isnothing(state.plans) ?
            prepare_product_egraph(state.inputs[1]) : state.plans[1]
        stats=product_egraph_stats(plan)
        Dict("contract"=>"full_exact_bigint_aggregate_fixed_supports",
            "candidate_splits"=>stats.candidates,
            "estimated_pair_products"=>stats.estimated_pairs,
            "root_split"=>stats.root_split,
            "horizon"=>f.horizon,"preparation"=>f.preparation)
    end,
    contract="owned exact BigInt coefficient aggregate; diagonal integral metric",
    capabilities=Dict("oracle"=>"independent BigInt Clifford word enumeration",
        "rewrites"=>"associativity only, contiguous factor intervals",
        "extraction"=>"support-pair upper bound, no numeric pruning",
        "gpu_kernel"=>false));replace=true)
