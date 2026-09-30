pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

function fs_factor(left,right,diagonal)
    parity=0
    remaining=left
    while !iszero(remaining)
        bit=trailing_zeros(remaining)
        lower=(one(left)<<bit)-one(left)
        parity+=count_ones(right&lower)
        remaining &= remaining-one(remaining)
    end
    factor=isodd(parity) ? BigInt(-1) : BigInt(1)
    overlap=left&right
    while !iszero(overlap)
        factor*=diagonal[trailing_zeros(overlap)+1]
        overlap &= overlap-one(overlap)
    end
    factor
end

function fs_generate(case,directory,rng)
    n=case["dimension"]
    n in (2,3,4,5,6,8,16,32,65,129) || error("dimension")
    mode=case["mode"]
    mode in ("prepared","oneshot","direct_bigint") || error("mode")
    signature=case["signature"]
    signature in ("positive","mixed","degenerate") || error("signature")
    cancellation=case["cancellation"]
    cancellation in ("ordinary","near_zero","exact_zero") || error("cancellation")
    bits=case["coefficient_bits"]
    bits in (8,64,128) || error("coefficient bits")
    horizon=case["horizon"]
    horizon in (1,64,1024) || error("horizon")
    K=n<=64 ? UInt64 : n<=128 ? UInt128 : BigInt
    hi=one(K)<<(n-1)
    lo=one(K)
    masks=K[0,lo,hi,lo|hi]
    diagonal=ones(Int64,n)
    diagonal[1]=signature=="positive" ? 1 :
        signature=="mixed" ? -2 : 0
    scale=big(1)<<(bits-4)
    values=Vector{Tuple{Vector{BigInt},Vector{BigInt}}}(undef,horizon)
    expected=Vector{Int8}(undef,horizon)
    index=Dict(mask=>i for (i,mask) in enumerate(masks))
    for t in 1:horizon
        left=BigInt[BigInt(rand(rng,1:7))*scale for _ in masks]
        right=BigInt[BigInt(rand(rng,1:7))*scale for _ in masks]
        right[1]=BigInt(1)
        if cancellation!="ordinary"
            other=BigInt(0)
            for i in eachindex(masks)
                i==3 && continue
                j=index[masks[i]⊻hi]
                other+=left[i]*right[j]*fs_factor(masks[i],masks[j],diagonal)
            end
            desired=cancellation=="near_zero" ? BigInt(1) : BigInt(0)
            if desired==other
                left[1]+=1
                other+=right[3]
            end
            left[3]=desired-other
        end
        total=BigInt(0)
        for i in eachindex(masks)
            j=index[masks[i]⊻hi]
            total+=left[i]*right[j]*fs_factor(masks[i],masks[j],diagonal)
        end
        expected[t]=Int8(sign(total))
        values[t]=(left,right)
    end
    (;n,mode,signature,cancellation,bits,horizon,masks,diagonal,values,expected)
end

function fs_prepare(f,case,directory)
    matrix=zeros(Int64,f.n,f.n)
    for i in 1:f.n
        matrix[i,i]=f.diagonal[i]
    end
    ga=algebra(matrix)
    inputs=[begin
        left,right=f.values[t]
        (multivector(ga,Dict(mask=>left[i] for (i,mask) in
            enumerate(f.masks));storage=:sparse),
         multivector(ga,Dict(mask=>right[i] for (i,mask) in
            enumerate(f.masks));storage=:sparse))
    end for t in 1:f.horizon]
    plan=f.mode=="prepared" ? prepare_filtered_sign(inputs[1]...,[f.n]) :
        nothing
    (;fixture=f,inputs,plan,fallbacks=Ref(0))
end

function fs_execute(state)
    f=state.fixture
    output=Vector{Int8}(undef,f.horizon)
    fallbacks=0
    for t in 1:f.horizon
        a,b=state.inputs[t]
        if f.mode=="direct_bigint"
            output[t]=Int8(sign(product_coefficient(a,b,[f.n])))
        else
            value,info=isnothing(state.plan) ?
                filtered_product_sign(a,b,[f.n];diagnostics=true) :
                run_filtered_sign(state.plan,a,b;diagnostics=true)
            output[t]=value
            fallbacks+=info.used_fallback
        end
    end
    state.fallbacks[]=fallbacks
    output
end

function fs_oracle(state,result)
    result==state.fixture.expected &&
        length(result)==state.fixture.horizon &&
        0<=state.fallbacks[]<=state.fixture.horizon
end

register_adapter!(BenchmarkAdapter(name="garamon_filtered_sign",
    generate=fs_generate,prepare=fs_prepare,execute=fs_execute,
    baseline_execute=state->fs_execute(merge(state,
        (fixture=merge(state.fixture,(mode="direct_bigint",)),plan=nothing,
            fallbacks=Ref(0)))),
    baseline_name="garamon_julia_direct_bigint_coefficient",
    oracle=fs_oracle,
    preflight_evidence=(state,result)->Dict{String,Any}(
        "mode"=>state.fixture.mode,
        "signature"=>state.fixture.signature,
        "cancellation"=>state.fixture.cancellation,
        "coefficient_bits"=>state.fixture.bits,
        "fallback_executions"=>state.fallbacks[]),
    contract="owned sequence of exact target-coefficient signs, checked Int128 or full BigInt recomputation",
    capabilities=Dict(
        "exact_oracle"=>"independent signed blade-pair BigInt sum",
        "domains"=>"integer coefficients and diagonal integer metric",
        "modes"=>"prepared,oneshot,direct_bigint",
        "fallback"=>"exact full BigInt recomputation after checked overflow",
        "generation_includes_oracle"=>true));replace=true)
