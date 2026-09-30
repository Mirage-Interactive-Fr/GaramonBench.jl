pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

function ps_factor(left,right,diagonal)
    swaps=0
    remaining=left
    while !iszero(remaining)
        bit=trailing_zeros(remaining)
        swaps+=count_ones(right&((one(left)<<bit)-one(left)))
        remaining &= remaining-one(remaining)
    end
    factor=isodd(swaps) ? BigInt(-1) : BigInt(1)
    overlap=left&right
    while !iszero(overlap)
        factor*=diagonal[trailing_zeros(overlap)+1]
        overlap &= overlap-one(overlap)
    end
    factor
end

function ps_oracle(a,b,diagonal,parity)
    K=keytype(a)
    output=Dict{K,BigInt}()
    for (am,av) in a,(bm,bv) in b
        mask=am⊻bm
        parity=="all" || (iseven(count_ones(mask))==(parity=="even")) || continue
        term=av*bv*ps_factor(am,bm,diagonal)
        output[mask]=get(output,mask,BigInt(0))+term
    end
    filter!(pair->!iszero(last(pair)),output)
    output
end

function ps_generate(case,directory,rng)
    n=case["dimension"]
    n in (2,3,4,5,6,8,16,32,65,129) || error("dimension")
    mode=case["mode"]
    mode in ("prepared","direct") || error("mode")
    parity=case["output_parity"]
    parity in ("all","even","odd") || error("output_parity")
    regime=case["regime"]
    regime in ("stable","support_change","metric_change") || error("regime")
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
    terms=Vector{NTuple{2,Dict{K,BigInt}}}(undef,horizon)
    expected=Vector{Dict{K,BigInt}}(undef,horizon)
    for t in 1:horizon
        values=ntuple(2) do _
            Dict{K,BigInt}(mask=>BigInt(rand(rng,1:7))*
                (rand(rng,Bool) ? 1 : -1) for mask in masks)
        end
        if regime=="support_change" && t>1
            values[1][low|high]=BigInt(3)
        end
        terms[t]=values
        active=regime=="metric_change" && t>1 ?
            changed_diagonal : diagonal
        expected[t]=ps_oracle(values...,active,parity)
    end
    (;n,mode,parity,regime,signature,support,horizon,diagonal,
      changed_diagonal,terms,expected)
end

function ps_prepare(f,case,directory)
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
        ntuple(i->multivector(active,f.terms[t][i];storage=:sparse),2)
    end for t in 1:f.horizon]
    plan=f.mode=="prepared" ?
        prepare_invariant_sectors(inputs[1]...;
            output_parity=Symbol(f.parity)) : nothing
    (;fixture=f,inputs,plan,fallbacks=Ref(0))
end

function ps_execute(state)
    f=state.fixture
    K=keytype(first(f.terms[1]))
    output=Vector{Dict{K,BigInt}}(undef,f.horizon)
    fallbacks=0
    for t in 1:f.horizon
        a,b=state.inputs[t]
        if f.mode=="prepared"
            value,info=run_invariant_sectors(state.plan,a,b;
                on_invalid=:direct,diagnostics=true)
            fallbacks+=info.used_fallback
            output[t]=copy(value.values)
        else
            value=geometric_product(a,b)
            output[t]=Dict{K,BigInt}(mask=>BigInt(coefficient)
                for (mask,coefficient) in Garamon._terms(value)
                if f.parity=="all" ||
                    iseven(count_ones(mask))==(f.parity=="even"))
        end
    end
    state.fallbacks[]=fallbacks
    output
end

function ps_check(state,result)
    result==state.fixture.expected &&
        length(result)==state.fixture.horizon &&
        0<=state.fallbacks[]<=state.fixture.horizon &&
        (state.fixture.mode!="prepared" ||
         state.fixture.regime in ("support_change","metric_change") ||
         state.fallbacks[]==0)
end

register_adapter!(BenchmarkAdapter(name="garamon_invariant_sectors",
    generate=ps_generate,prepare=ps_prepare,execute=ps_execute,
    baseline_execute=state->ps_execute(merge(state,
        (fixture=merge(state.fixture,(mode="direct",)),
            plan=nothing,fallbacks=Ref(0)))),
    baseline_name="garamon_julia_direct_product",
    oracle=ps_check,
    contract="exact requested parity of a geometric product via grade-involution sectors or full direct fallback",
    capabilities=Dict(
        "exact_oracle"=>"independent signed blade BigInt accumulation",
        "domains"=>"integer coefficients and diagonal metric entries -1,0,1",
        "modes"=>"prepared,direct",
        "fallback"=>"complete direct exact product after support or metric invalidation",
        "generation_includes_oracle"=>true));replace=true)
