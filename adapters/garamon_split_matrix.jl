# ID22: recursive split-Clifford transform, matrix product, and inverse.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random, SHA

function sm22_terms(rng,coefficient_count,support_count)
    count=min(coefficient_count,support_count)
    masks=Set{UInt64}()
    while length(masks)<count
        push!(masks,UInt64(rand(rng,0:coefficient_count-1)))
    end
    Dict{UInt64,Int64}(mask=>rand(rng,(-2,-1,1,2)) for mask in sort!(collect(masks)))
end

function sm22_word_factor(left::UInt64,right::UInt64,negative::UInt64)
    parity=isodd(count_ones(left & right & negative))
    remaining=left
    while !iszero(remaining)
        bit=trailing_zeros(remaining)
        parity ⊻=isodd(count_ones(right & ((UInt64(1)<<bit)-UInt64(1))))
        remaining &= remaining-UInt64(1)
    end
    parity ? Int64(-1) : Int64(1)
end

function sm22_oracle!(aggregate,left,right,negative)
    for (amask,avalue) in left,(bmask,bvalue) in right
        mask=xor(amask,bmask)
        value=sm22_word_factor(amask,bmask,negative)*avalue*bvalue
        aggregate[Int(mask)+1]=Base.checked_add(aggregate[Int(mask)+1],value)
    end
    aggregate
end

function sm22_generate(case,directory,rng)
    n=case["dimension"]
    n in (2,4,6,8,10,12,14,16,18,20) || error("split dimension")
    support_count=case["support_count"]
    support_count in (4,16,64) || error("support count")
    pattern=case["left_pattern"]
    pattern in ("fixed","pool4") || error("left pattern")
    preparation=case["preparation"]
    preparation in ("prebuilt","rebuild") || error("preparation")
    horizon=case["horizon"]
    horizon in (1,16,128) || error("horizon")
    n==20 && horizon==128 && error("excluded by matrix episode budget")
    coefficient_count=1<<n
    pool_size=pattern=="fixed" ? 1 : min(4,horizon)
    left_pool=[sm22_terms(rng,coefficient_count,support_count)
               for _ in 1:pool_size]
    right_terms=[sm22_terms(rng,coefficient_count,support_count)
                 for _ in 1:horizon]
    indices=[pattern=="fixed" ? 1 : mod1(t,pool_size) for t in 1:horizon]
    expected=zeros(Int64,coefficient_count)
    negative=foldl(|,(UInt64(1)<<(i-1) for i in 2:2:n);init=UInt64(0))
    for t in 1:horizon
        sm22_oracle!(expected,left_pool[indices[t]],right_terms[t],negative)
    end
    diagonal=Int64[isodd(i) ? 1 : -1 for i in 1:n]
    (;n,horizon,support_count,pattern,preparation,left_pool,right_terms,
      indices,expected,diagonal)
end

function sm22_dense(ga,terms,n)
    values=zeros(Float64,1<<n)
    for (mask,value) in terms
        values[Int(mask)+1]=Float64(value)
    end
    DenseMultiVector(ga,values)
end

function sm22_prepare(f,case,directory)
    gram=zeros(Int64,f.n,f.n)
    for i in 1:f.n
        gram[i,i]=f.diagonal[i]
    end
    ga=algebra(gram)
    plans=f.preparation=="prebuilt" ?
        [prepare_split_matrix(sm22_dense(ga,terms,f.n)) for terms in f.left_pool] :
        nothing
    (;fixture=f,ga,plans)
end

function sm22_execute(state)
    f=state.fixture
    aggregate=zeros(Float64,1<<f.n)
    for t in 1:f.horizon
        left=f.left_pool[f.indices[t]]
        plan=isnothing(state.plans) ?
            prepare_split_matrix(sm22_dense(state.ga,left,f.n)) :
            state.plans[f.indices[t]]
        right=sm22_dense(state.ga,f.right_terms[t],f.n)
        result=run_split_matrix(plan,right)
        aggregate .+= result.values
    end
    aggregate
end

function sm22_baseline_prepare(state)
    f=state.fixture
    left=[multivector(state.ga,Dict(mask=>Float64(value) for (mask,value) in terms);
                      storage=:sparse) for terms in f.left_pool]
    right=[multivector(state.ga,Dict(mask=>Float64(value) for (mask,value) in terms);
                       storage=:sparse) for terms in f.right_terms]
    (;fixture=f,left,right)
end

function sm22_baseline(state)
    f=state.fixture
    aggregate=zeros(Float64,1<<f.n)
    for t in 1:f.horizon
        product=geometric_product(state.left[f.indices[t]],state.right[t])
        for (mask,value) in product.values
            aggregate[Int(mask)+1]+=value
        end
    end
    aggregate
end

sm22_serial(terms)=join((string(mask)*":"*string(value)
    for (mask,value) in sort!(collect(terms);by=first)),",")

function sm22_scenario(state,case)
    f=state.fixture
    Dict{String,Any}("family"=>"split_clifford_full_aggregate",
        "dimension"=>f.n,"diagonal"=>f.diagonal,
        "episodes"=>[sm22_serial(f.left_pool[f.indices[t]])*"|"*
            sm22_serial(f.right_terms[t]) for t in 1:f.horizon])
end

sm22_output_identity(result)=
    bytes2hex(sha256(collect(reinterpret(UInt8,result))))

register_adapter!(BenchmarkAdapter(name="garamon_split_matrix",
    generate=sm22_generate,prepare=sm22_prepare,execute=sm22_execute,
    baseline_prepare=sm22_baseline_prepare,
    baseline_execute=sm22_baseline,
    baseline_name="garamon_julia_sparse_direct_full_aggregate",
    baseline_scenario=sm22_scenario,
    baseline_output_identity=sm22_output_identity,
    oracle=(state,result)->length(result)==length(state.fixture.expected) &&
        result==Float64.(state.fixture.expected),
    preflight_evidence=(state,result)->begin
        f=state.fixture
        plan=isnothing(state.plans) ?
            prepare_split_matrix(sm22_dense(state.ga,f.left_pool[1],f.n)) :
            state.plans[1]
        stats=split_matrix_stats(plan)
        Dict("contract"=>"full_dense_aggregate_bounded_integer_inputs",
            "matrix_side"=>stats.side,
            "left_matrix_bytes"=>stats.left_matrix_bytes,
            "matrix_buffer_budget_bytes"=>stats.max_bytes,
            "left_pool_size"=>length(f.left_pool),
            "horizon"=>f.horizon,"preparation"=>f.preparation)
    end,
    contract="owned full Float64 coefficient aggregate, exact for bounded integer fixtures",
    capabilities=Dict("oracle"=>"independent checked Int64 blade-pair inversion enumeration",
        "transform"=>"recursive Cl(n,n) right-spinor matrix isomorphism and inverse",
        "basis"=>"interleaved +1,-1 diagonal split metric",
        "arithmetic"=>"fixture intermediates remain below 2^53",
        "gpu_kernel"=>false));replace=true)
