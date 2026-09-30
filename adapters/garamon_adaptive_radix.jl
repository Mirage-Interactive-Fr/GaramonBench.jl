# ID43: exact sparse exterior product through an adaptive byte-radix index.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random, SHA

function ar43_mask(rng,directions,::Type{K}) where K
    grade=rand(rng,0:min(2,length(directions)))
    chosen=randperm(rng,length(directions))[1:grade]
    foldl(|,(one(K)<<(directions[i]-1) for i in chosen);init=zero(K))
end

function ar43_terms(rng,directions,::Type{K}) where K
    terms=Dict{K,Int64}(zero(K)=>1,
        one(K)<<(first(directions)-1)=>2)
    for _ in 1:10
        mask=ar43_mask(rng,directions,K)
        terms[mask]=rand(rng,(-3,-2,-1,1,2,3))
    end
    terms
end

function ar43_word(left::K,right::K,n::Int) where K
    iszero(left & right) || return left|right,0
    inversions=0
    for i in 1:n
        iszero(left & (one(K)<<(i-1))) && continue
        for j in 1:i-1
            inversions+=!iszero(right & (one(K)<<(j-1)))
        end
    end
    left|right,isodd(inversions) ? -1 : 1
end

function ar43_oracle(left::Dict{K,Int64},right::Dict{K,Int64},n) where K
    output=Dict{K,Int64}()
    for (a,x) in left,(b,y) in right
        mask,sign=ar43_word(a,b,n)
        iszero(sign) && continue
        output[mask]=get(output,mask,0)+sign*x*y
    end
    filter!(pair->!iszero(last(pair)),output)
    Dict{K,Float64}(mask=>Float64(value) for (mask,value) in output)
end

function ar43_generate(case,directory,rng)
    n=case["dimension"]
    n in (2,3,4,5,6,8,12,16,32,64,65,96,128,129) || error("dimension")
    signature=case["signature"]
    signature in ("positive","mixed","degenerate") || error("signature")
    shape=case["support_shape"]
    shape in ("clustered","spread") || error("support shape")
    mutation=case["mutation"]
    mutation in ("stable","changing") || error("mutation")
    policy=case["index_policy"]
    policy in ("prebuilt","rebuild") || error("index policy")
    horizon=case["horizon"]
    horizon in (1,32,256) || error("horizon")
    K=n<=64 ? UInt64 : n<=128 ? UInt128 : BigInt
    count=min(8,n)
    directions=shape=="clustered" ? collect(1:count) :
        unique(round.(Int,range(1,n;length=count)))
    diagonal=ones(Int64,n)
    signature=="mixed" && (diagonal[2:2:end].=-1)
    signature=="degenerate" && (diagonal[last(directions)]=0)
    fixed_right=ar43_terms(rng,directions,K)
    inputs=Vector{Tuple{Dict{K,Int64},Dict{K,Int64}}}(undef,horizon)
    expected=Vector{Dict{K,Float64}}(undef,horizon)
    for t in 1:horizon
        left=ar43_terms(rng,directions,K)
        right=mutation=="stable" ? copy(fixed_right) :
            ar43_terms(rng,directions,K)
        inputs[t]=(left,right)
        expected[t]=ar43_oracle(left,right,n)
    end
    (;n,signature,shape,mutation,policy,horizon,diagonal,inputs,expected)
end

function ar43_prepare(f,case,directory)
    gram=zeros(Int64,f.n,f.n)
    for i in 1:f.n
        gram[i,i]=f.diagonal[i]
    end
    ga=algebra(gram)
    inputs=[(multivector(ga,Dict(mask=>Float64(v) for (mask,v) in left);
                         storage=:sparse),
             multivector(ga,Dict(mask=>Float64(v) for (mask,v) in right);
                         storage=:sparse)) for (left,right) in f.inputs]
    indexes=f.policy=="prebuilt" ?
        f.mutation=="stable" ? [prepare_adaptive_radix(inputs[1][2])] :
            [prepare_adaptive_radix(pair[2]) for pair in inputs] : nothing
    (;fixture=f,inputs,indexes)
end

function ar43_execute(state)
    [begin
        index=isnothing(state.indexes) ? prepare_adaptive_radix(pair[2]) :
            state.indexes[state.fixture.mutation=="stable" ? 1 : t]
        radix_wedge(pair[1],index).values
    end for (t,pair) in enumerate(state.inputs)]
end

ar43_baseline(state)=[wedge(pair...).values for pair in state.inputs]

function ar43_serial(terms)
    join((string(mask)*":"*string(value) for (mask,value) in
        sort!(collect(terms);by=first)),",")
end

ar43_scenario(state,case)=Dict{String,Any}(
    "dimension"=>state.fixture.n,"diagonal"=>state.fixture.diagonal,
    "inputs"=>[ar43_serial(left)*"|"*ar43_serial(right)
        for (left,right) in state.fixture.inputs])

ar43_output_hash(values)=bytes2hex(sha256(join(ar43_serial.(values),"|")))

register_adapter!(BenchmarkAdapter(name="garamon_adaptive_radix",
    generate=ar43_generate,prepare=ar43_prepare,execute=ar43_execute,
    baseline_execute=ar43_baseline,
    baseline_name="garamon_julia_sparse_direct_wedge",
    baseline_scenario=ar43_scenario,
    baseline_output_identity=ar43_output_hash,
    oracle=(state,result)->result==state.fixture.expected,
    preflight_evidence=(state,result)->begin
        index=isnothing(state.indexes) ? prepare_adaptive_radix(state.inputs[1][2]) :
            state.indexes[1]
        stats=radix_stats(index)
        Dict("contract"=>"exact_sparse_wedge","index_policy"=>state.fixture.policy,
            "support_shape"=>state.fixture.shape,"horizon"=>state.fixture.horizon,
            "branches"=>stats.branches,"leaves"=>stats.leaves,
            "compressed_prefix_bytes"=>stats.prefix_bytes,
            "capacity4"=>stats.capacity4,"capacity16"=>stats.capacity16,
            "capacity48"=>stats.capacity48,"capacity256"=>stats.capacity256)
    end,
    contract="owned sequence of exact sparse wedge coefficient dictionaries",
    capabilities=Dict("exact_oracle"=>"independent Int64 disjoint-mask inversion enumeration",
        "index"=>"bytewise path compression and 4/16/48/256 fanout tiers",
        "index_lifetime"=>"owned right operand snapshot; changing supports rebuilt explicitly",
        "generation_includes_oracle"=>true,"gpu_kernel"=>false));replace=true)
