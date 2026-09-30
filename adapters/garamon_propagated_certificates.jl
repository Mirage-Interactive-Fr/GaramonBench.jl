pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

function pc_pair_factor(left,right,diagonal)
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

function pc_independent_oracle(a,b,c,diagonal)
    K=keytype(a)
    output=Dict{K,BigInt}()
    for (am,av) in a,(bm,bv) in b,(cm,cv) in c
        mid=am⊻bm
        mask=mid⊻cm
        factor=pc_pair_factor(am,bm,diagonal)*
            pc_pair_factor(mid,cm,diagonal)
        term=av*bv*cv*factor
        output[mask]=get(output,mask,BigInt(0))+term
    end
    filter!(pair->!iszero(last(pair)),output)
    output
end

function pc_generate(case,directory,rng)
    n=case["dimension"]
    n in (2,3,4,5,6,8,16,32,65,129) || error("dimension")
    mode=case["mode"]
    mode in ("certified","direct") || error("mode")
    regime=case["regime"]
    regime in ("stable","cancellation","support_change","metric_change") ||
        error("regime")
    signature=case["signature"]
    signature in ("positive","mixed","degenerate") || error("signature")
    support=case["support"]
    support in (2,3) || error("support")
    horizon=case["horizon"]
    horizon in (1,32,256) || error("horizon")
    K=n<=64 ? UInt64 : n<=128 ? UInt128 : BigInt
    low=one(K)
    high=one(K)<<(n-1)
    masks=K[0,low,high][1:support]
    diagonal=ones(Int64,n)
    diagonal[1]=signature=="positive" ? 1 :
        signature=="mixed" ? -1 : 0
    changed_diagonal=copy(diagonal)
    changed_diagonal[1]=diagonal[1]==1 ? -1 : 1
    terms=Vector{NTuple{3,Dict{K,BigInt}}}(undef,horizon)
    expected=Vector{Dict{K,BigInt}}(undef,horizon)
    for t in 1:horizon
        values=ntuple(3) do _
            Dict{K,BigInt}(mask=>BigInt(rand(rng,1:7))*
                (rand(rng,Bool) ? 1 : -1) for mask in masks)
        end
        if regime=="cancellation"
            values[1][K(0)]=BigInt(1)
            values[1][low]=BigInt(1)
            values[2][K(0)]=BigInt(1)
            values[2][low]=BigInt(-1)
        end
        if regime=="support_change" && t>1
            values[1][low|high]=BigInt(3)
        end
        terms[t]=values
        active=regime=="metric_change" && t>1 ?
            changed_diagonal : diagonal
        expected[t]=pc_independent_oracle(values...,active)
    end
    (;n,mode,regime,signature,support,horizon,diagonal,
      changed_diagonal,terms,expected)
end

function pc_prepare(f,case,directory)
    function make_ga(diagonal)
        matrix=zeros(Int64,f.n,f.n)
        for i in 1:f.n
            matrix[i,i]=diagonal[i]
        end
        algebra(matrix)
    end
    ga=make_ga(f.diagonal)
    changed_ga=f.regime=="metric_change" ? make_ga(f.changed_diagonal) : ga
    inputs=[begin
        active=f.regime=="metric_change" && t>1 ? changed_ga : ga
        ntuple(i->multivector(active,f.terms[t][i];storage=:sparse),3)
    end for t in 1:f.horizon]
    certificate=f.mode=="certified" ?
        prepare_propagated_product(inputs[1]...) : nothing
    (;fixture=f,inputs,certificate,fallbacks=Ref(0))
end

function pc_execute(state)
    f=state.fixture
    K=keytype(first(f.terms[1]))
    output=Vector{Dict{K,BigInt}}(undef,f.horizon)
    fallbacks=0
    for t in 1:f.horizon
        a,b,c=state.inputs[t]
        if f.mode=="certified"
            value,info=run_propagated_product(state.certificate,a,b,c;
                on_invalid=:direct,diagnostics=true)
            fallbacks+=info.used_fallback
        else
            value=geometric_product(geometric_product(a,b),c)
        end
        output[t]=copy(value.values)
    end
    state.fallbacks[]=fallbacks
    output
end

function pc_oracle(state,result)
    result==state.fixture.expected &&
        length(result)==state.fixture.horizon &&
        0<=state.fallbacks[]<=state.fixture.horizon &&
        (state.fixture.mode!="certified" ||
         state.fixture.regime in ("support_change","metric_change") ||
         state.fallbacks[]==0)
end

register_adapter!(BenchmarkAdapter(name="garamon_propagated_certificates",
    generate=pc_generate,prepare=pc_prepare,execute=pc_execute,
    oracle=pc_oracle,
    preflight_evidence=(state,result)->Dict{String,Any}(
        "mode"=>state.fixture.mode,"regime"=>state.fixture.regime,
        "signature"=>state.fixture.signature,
        "support"=>state.fixture.support,
        "fallback_executions"=>state.fallbacks[]),
    contract="owned sequence of all exact coefficients of a three-input chain; propagated support certificate or direct exact fallback",
    capabilities=Dict(
        "exact_oracle"=>"independent signed triple-blade BigInt accumulation",
        "domains"=>"integer coefficients and diagonal metric entries -1,0,1",
        "modes"=>"certified,direct",
        "fallback"=>"direct exact chain after support, basis or metric invalidation",
        "generation_includes_oracle"=>true));replace=true)

