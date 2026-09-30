# IDs 40 and 41: exact split-Clifford bilinear synthesis and verified choice.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random, SHA

function bl40_terms(rng,count,support_count)
    masks=Set{UInt64}()
    while length(masks)<min(count,support_count)
        push!(masks,UInt64(rand(rng,0:count-1)))
    end
    Dict{UInt64,BigInt}(mask=>BigInt(rand(rng,(-2,-1,1,2)))
        for mask in masks)
end

function bl40_word_factor(left::UInt64,right::UInt64,negative::UInt64)
    parity=isodd(count_ones(left & right & negative))
    while !iszero(left)
        bit=trailing_zeros(left)
        parity ⊻=isodd(count_ones(right & ((UInt64(1)<<bit)-UInt64(1))))
        left &= left-UInt64(1)
    end
    parity ? BigInt(-1) : BigInt(1)
end

function bl40_oracle!(aggregate,left,right,negative)
    for (amask,avalue) in left,(bmask,bvalue) in right
        mask=xor(amask,bmask)
        aggregate[Int(mask)+1]+=bl40_word_factor(amask,bmask,negative)*
            avalue*bvalue
    end
    aggregate
end

function bl40_generate(case,directory,rng)
    n=case["dimension"]
    n in (2,4,6,8,10) || error("exact bilinear split dimension")
    support_count=case["support_count"]
    support_count in (4,16,64) || error("bilinear support")
    pattern=case["left_pattern"]
    pattern in ("fixed","pool4") || error("bilinear left pattern")
    preparation=case["preparation"]
    preparation in ("prebuilt","rebuild") || error("bilinear preparation")
    horizon=case["horizon"]
    horizon in (1,16,128) || error("bilinear horizon")
    count=1<<n
    pool_size=pattern=="fixed" ? 1 : min(4,horizon)
    left_pool=[bl40_terms(rng,count,support_count) for _ in 1:pool_size]
    right_terms=[bl40_terms(rng,count,support_count) for _ in 1:horizon]
    indices=[pattern=="fixed" ? 1 : mod1(t,pool_size) for t in 1:horizon]
    expected=zeros(BigInt,count)
    negative=foldl(|,(UInt64(1)<<(i-1) for i in 2:2:n);init=UInt64(0))
    for t in 1:horizon
        bl40_oracle!(expected,left_pool[indices[t]],right_terms[t],negative)
    end
    diagonal=Int64[isodd(i) ? 1 : -1 for i in 1:n]
    (;n,support_count,pattern,preparation,horizon,left_pool,right_terms,
      indices,expected,diagonal)
end

function bl40_dense(ga,terms,count)
    values=zeros(BigInt,count)
    for (mask,value) in terms
        values[Int(mask)+1]=value
    end
    DenseMultiVector(ga,values)
end

function bl40_prepare(f,case,directory)
    gram=zeros(Int64,f.n,f.n)
    for i in 1:f.n
        gram[i,i]=f.diagonal[i]
    end
    ga=algebra(gram)
    kind=case["kernel"]
    kind in ("strassen","verified") || error("bilinear kernel")
    cutoff=get(case,"cutoff",1)
    mul_weight=get(case,"mul_weight",10)
    add_weight=get(case,"add_weight",1)
    build=left->kind=="strassen" ?
        prepare_bilinear_split(left;cutoff) :
        prepare_verified_bilinear(left;mul_weight,add_weight)
    plans=f.preparation=="prebuilt" ?
        [build(bl40_dense(ga,terms,1<<f.n)) for terms in f.left_pool] :
        nothing
    (;fixture=f,ga,kind,cutoff,mul_weight,add_weight,plans)
end

function bl40_plan(state,terms)
    left=bl40_dense(state.ga,terms,1<<state.fixture.n)
    state.kind=="strassen" ?
        prepare_bilinear_split(left;cutoff=state.cutoff) :
        prepare_verified_bilinear(left;mul_weight=state.mul_weight,
                                  add_weight=state.add_weight)
end

function bl40_execute(state)
    f=state.fixture
    aggregate=zeros(BigInt,1<<f.n)
    for t in 1:f.horizon
        plan=isnothing(state.plans) ?
            bl40_plan(state,f.left_pool[f.indices[t]]) :
            state.plans[f.indices[t]]
        right=bl40_dense(state.ga,f.right_terms[t],1<<f.n)
        result=state.kind=="strassen" ?
            run_bilinear_split(plan,right) : run_verified_bilinear(plan,right)
        aggregate .+= result.values
    end
    aggregate
end

function bl40_baseline_prepare(state)
    f=state.fixture
    left=[multivector(state.ga,terms;storage=:sparse) for terms in f.left_pool]
    right=[multivector(state.ga,terms;storage=:sparse) for terms in f.right_terms]
    (;fixture=f,left,right)
end

function bl40_baseline(state)
    f=state.fixture
    aggregate=zeros(BigInt,1<<f.n)
    for t in 1:f.horizon
        product=geometric_product(state.left[f.indices[t]],state.right[t])
        for (mask,value) in product.values
            aggregate[Int(mask)+1]+=value
        end
    end
    aggregate
end

bl40_serial(terms)=join((string(mask)*":"*string(value)
    for (mask,value) in sort!(collect(terms);by=first)),",")
function bl40_scenario(state,case)
    f=state.fixture
    Dict{String,Any}("family"=>"split_clifford_exact_full_aggregate",
        "dimension"=>f.n,"diagonal"=>f.diagonal,
        "episodes"=>[bl40_serial(f.left_pool[f.indices[t]])*"|"*
            bl40_serial(f.right_terms[t]) for t in 1:f.horizon])
end
bl40_output_identity(result)=bytes2hex(sha256(join(string.(result),",")))

for (adapter_name,kernel) in (("garamon_bilinear_synthesis","strassen"),
                              ("garamon_verified_superopt","verified"))
    register_adapter!(BenchmarkAdapter(name=adapter_name,
        generate=bl40_generate,prepare=bl40_prepare,execute=bl40_execute,
        baseline_prepare=bl40_baseline_prepare,baseline_execute=bl40_baseline,
        baseline_name="garamon_julia_sparse_direct_full_aggregate",
        baseline_scenario=bl40_scenario,
        baseline_output_identity=bl40_output_identity,
        oracle=(state,result)->result==state.fixture.expected,
        preflight_evidence=(state,result)->begin
            f=state.fixture
            plan=isnothing(state.plans) ?
                bl40_plan(state,f.left_pool[1]) : state.plans[1]
            stats=state.kind=="strassen" ?
                bilinear_split_stats(plan) : verified_bilinear_stats(plan)
            Dict("contract"=>"exact_bigint_split_clifford_full_aggregate",
                 "kernel"=>state.kind,
                 "plan_stats"=>Dict(string(k)=>(v isa Symbol ? string(v) : v)
                                    for (k,v) in pairs(stats)),
                 "horizon"=>f.horizon,"preparation"=>f.preparation)
        end,
        contract="owned full BigInt coefficient aggregate over interleaved Cl(r,r)",
        capabilities=Dict("oracle"=>"independent BigInt Clifford word pairs",
            "kernel"=>kernel,
            "verified"=>kernel=="verified" ?
                "all sixteen elementary 2x2 bilinear tensor pairs" :
                "independent full blade-pair oracle",
            "gpu_kernel"=>false));replace=true)
end
