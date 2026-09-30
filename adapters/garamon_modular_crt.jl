pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

function mc_factor(left,right,diagonal)
    parity=0
    remaining=left
    while !iszero(remaining)
        bit=trailing_zeros(remaining)
        lower=(one(left) << bit)-one(left)
        parity+=count_ones(right & lower)
        remaining &= remaining-one(remaining)
    end
    factor=isodd(parity) ? BigInt(-1) : BigInt(1)
    overlap=left & right
    while !iszero(overlap)
        factor*=diagonal[trailing_zeros(overlap)+1]
        overlap &= overlap-one(overlap)
    end
    factor
end

function mc_generate(case,directory,rng)
    n=case["dimension"]
    2<=n<=129 || error("modular dimension budget")
    signature=case["signature"]
    signature in ("positive","mixed","degenerate") || error("modular signature")
    mode=case["mode"]
    mode in ("prepared","oneshot","direct_bigint") || error("modular mode")
    bits=case["coefficient_bits"]
    bits in (8,64,128) || error("modular coefficient bits")
    prime_bits=case["prime_bits"]
    prime_bits in (17,31) || error("modular prime bits")
    max_primes=case["max_primes"]
    max_primes in (1,4,8,16) || error("modular prime count")
    horizon=case["horizon"]
    horizon in (1,64,1024) || error("modular horizon")
    diagonal=signature=="positive" ? ones(Int64,n) :
        signature=="mixed" ? Int64[iseven(i) ? -2 : 3 for i in 1:n] :
        Int64[i%5==0 ? 0 : iseven(i) ? -2 : 3 for i in 1:n]
    K=n<=64 ? UInt64 : n<=128 ? UInt128 : BigInt
    high=one(K) << (n-1)
    masks=K[0,one(K),high,one(K)|high]
    values=Vector{Tuple{Vector{BigInt},Vector{BigInt}}}(undef,horizon)
    expected=Vector{Dict{K,BigInt}}(undef,horizon)
    for t in 1:horizon
        left=BigInt[(BigInt(rand(rng,1:7)) << (bits-4))*(isodd(t+i) ? -1 : 1)
            for i in eachindex(masks)]
        right=BigInt[(BigInt(rand(rng,1:7)) << (bits-4))*(isodd(t+2i) ? -1 : 1)
            for i in eachindex(masks)]
        values[t]=(left,right)
        out=Dict{K,BigInt}()
        for (i,amask) in enumerate(masks),(j,bmask) in enumerate(masks)
            mask=amask ⊻ bmask
            term=left[i]*right[j]*mc_factor(amask,bmask,diagonal)
            out[mask]=get(out,mask,BigInt(0))+term
        end
        filter!(pair->!iszero(last(pair)),out)
        expected[t]=out
    end
    (;n,signature,mode,bits,prime_bits,max_primes,horizon,diagonal,masks,
      values,expected)
end

function mc_prepare(fixture,case,directory)
    matrix=zeros(Int64,fixture.n,fixture.n)
    for i in 1:fixture.n
        matrix[i,i]=fixture.diagonal[i]
    end
    ga=algebra(matrix)
    make_input(t)=begin
        left,right=fixture.values[t]
        a=multivector(ga,Dict(mask=>left[i] for (i,mask) in
            enumerate(fixture.masks));storage=:sparse)
        b=multivector(ga,Dict(mask=>right[i] for (i,mask) in
            enumerate(fixture.masks));storage=:sparse)
        (a,b)
    end
    first_input=make_input(1)
    inputs=Vector{typeof(first_input)}(undef,fixture.horizon)
    inputs[1]=first_input
    for t in 2:fixture.horizon
        inputs[t]=make_input(t)
    end
    plan=fixture.mode=="prepared" ?
        prepare_modular_product(first_input...;
            prime_bits=fixture.prime_bits,max_primes=fixture.max_primes) : nothing
    (;fixture,inputs,plan,prime_counts=Ref(Int[]),fallbacks=Ref(0))
end

function mc_execute(state)
    fixture=state.fixture
    K=eltype(fixture.masks)
    output=Vector{Dict{K,BigInt}}(undef,fixture.horizon)
    counts=Vector{Int}(undef,fixture.horizon)
    fallbacks=0
    for t in 1:fixture.horizon
        a,b=state.inputs[t]
        product,info=if fixture.mode=="direct_bigint"
            geometric_product(a,b),(prime_count=0,used_fallback=false)
        elseif isnothing(state.plan)
            modular_geometric_product(a,b;prime_bits=fixture.prime_bits,
                max_primes=fixture.max_primes,diagnostics=true)
        else
            run_modular_product(state.plan,a,b;diagnostics=true)
        end
        output[t]=copy(product.values)
        counts[t]=info.prime_count
        fallbacks+=info.used_fallback
    end
    state.prime_counts[]=counts
    state.fallbacks[]=fallbacks
    output
end

function mc_oracle(state,result)
    result==state.fixture.expected || return false
    length(state.prime_counts[])==state.fixture.horizon || return false
    state.fixture.mode!="direct_bigint" && state.fixture.bits==8 &&
        state.fixture.max_primes>=4 &&
        state.fixture.horizon==1 &&
        state.fallbacks[]!=0 && return false
    true
end

register_adapter!(BenchmarkAdapter(name="garamon_modular_crt",
    generate=mc_generate,prepare=mc_prepare,execute=mc_execute,
    baseline_execute=state->mc_execute(merge(state,
        (fixture=merge(state.fixture,(mode="direct_bigint",)),plan=nothing,
            prime_counts=Ref(Int[]),fallbacks=Ref(0)))),
    baseline_name="garamon_julia_direct_bigint_product",
    oracle=mc_oracle,
    preflight_evidence=(state,result)->Dict{String,Any}(
        "mode"=>state.fixture.mode,
        "prime_bits"=>state.fixture.prime_bits,
        "max_primes"=>state.fixture.max_primes,
        "used_prime_counts"=>state.prime_counts[],
        "fallback_executions"=>state.fallbacks[]),
    contract="owned sequence of every exact integer geometric-product coefficient; certified CRT or exact integer fallback",
    capabilities=Dict("exact_oracle"=>"independent signed blade-pair accumulation with BigInt",
        "domains"=>"integer coefficients and diagonal integer metric",
        "modes"=>"prepared,oneshot,direct_bigint",
        "fallback"=>"direct exact BigInt accumulation when CRT modulus is insufficient",
        "generation_includes_oracle"=>true));replace=true)
