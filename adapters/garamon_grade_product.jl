# Homogeneous-grade product: direct operation versus a bounded full-grade plan.
# The oracle enumerates only actual operand supports, independently of plans.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

gg_indices(mask,n)=[i for i in 1:n if !iszero(mask & (big(1) << (i-1)))]

function gg_factor(amask,bmask,diagonal,operation)
    ai=gg_indices(amask,length(diagonal))
    bi=gg_indices(bmask,length(diagonal))
    ra,rb=length(ai),length(bi)
    output=xor(amask,bmask)
    grade=length(gg_indices(output,length(diagonal)))
    selected=operation==:geometric ? true :
        operation==:wedge ? isempty(intersect(ai,bi)) :
        operation==:left ? ra<=rb && grade==rb-ra :
        operation==:right ? rb<=ra && grade==ra-rb : error("grade operation")
    selected || return output,Int64(0)
    inversions=0
    for i in ai
        inversions+=searchsortedfirst(bi,i)-1
    end
    factor=isodd(inversions) ? Int64(-1) : Int64(1)
    if operation!=:wedge
        for i in intersect(ai,bi)
            factor*=diagonal[i]
        end
    end
    output,factor
end

function gg_generate(case,directory,rng)
    n=case["dimension"]
    2<=n<=129 || error("grade dimension budget")
    horizon=case["horizon"]
    1<=horizon<=1024 || error("grade horizon budget")
    signature=case["signature"]
    signature in ("positive","mixed","degenerate") || error("grade signature")
    operation=Symbol(case["operation"])
    operation in (:geometric,:wedge,:left,:right) || error("grade operation")
    grade_pair=case["grade_pair"]
    grade_pair in ("one_one","top_one") || error("grade pair")
    strategy=case["strategy"]
    strategy in ("full","grade_plan") || error("grade strategy")
    grades=grade_pair=="one_one" ? (1,1) : (n-1,1)
    diagonal=signature=="positive" ? ones(Int64,n) :
        signature=="mixed" ? Int64[iseven(i) ? -1 : 1 for i in 1:n] :
        Int64[i%3==0 ? 0 : iseven(i) ? -1 : 2 for i in 1:n]
    # Match Garamon's blade representation. BigInt targets would make every
    # coefficient lookup allocate even for a four-dimensional algebra.
    K=n<=64 ? UInt64 : n<=128 ? UInt128 : BigInt
    basis=unique([1,2,n-1,n])
    full_mask=(K(1) << n)-K(1)
    left=unique(K[grades[1]==1 ? K(1) << (i-1) :
        full_mask ⊻ (K(1) << (i-1)) for i in basis])
    right=unique(K[K(1) << (i-1) for i in basis])
    supports=(left,right)
    targets=sort!(unique(K[xor(a,b) for a in left for b in right]))
    positions=Dict(mask=>i for (i,mask) in enumerate(targets))
    coefficients=[ntuple(k->rand(rng,Int64(1):Int64(3),length(supports[k])),2)
                  for _ in 1:horizon]
    expected=zeros(Int64,length(targets),horizon)
    for t in 1:horizon
        values=coefficients[t]
        for (ia,amask) in enumerate(left),(ib,bmask) in enumerate(right)
            output,factor=gg_factor(amask,bmask,diagonal,operation)
            expected[positions[output],t]+=factor*values[1][ia]*values[2][ib]
        end
    end
    (;n,horizon,signature,operation,grade_pair,strategy,grades,diagonal,
      supports,targets,coefficients,expected)
end

function gg_prepare(fixture,case,directory)
    ga=if fixture.signature=="positive"
        algebra(fixture.n,:ega)
    else
        metric=zeros(Int64,fixture.n,fixture.n)
        for i in 1:fixture.n
            metric[i,i]=fixture.diagonal[i]
        end
        algebra(metric)
    end
    inputs=[ntuple(k->multivector(ga,
        Dict(mask=>Float64(values[k][i]) for (i,mask) in enumerate(fixture.supports[k]));
        storage=:sparse),2) for values in fixture.coefficients]
    plan=fixture.strategy=="grade_plan" ?
        prepare_grade_product(ga,fixture.grades...;
            operation=fixture.operation,max_paths=1<<16,max_slots=1<<16) : nothing
    (;fixture,inputs,plan)
end

function gg_apply(operation,a,b)
    operation==:geometric && return geometric_product(a,b)
    operation==:wedge && return wedge(a,b)
    operation==:left && return left_contraction(a,b)
    operation==:right && return right_contraction(a,b)
    error("grade operation")
end

function gg_execute(state)
    fixture=state.fixture
    output=Matrix{Float64}(undef,length(fixture.targets),fixture.horizon)
    for t in 1:fixture.horizon
        operands=state.inputs[t]
        result=fixture.strategy=="grade_plan" ?
            run_grade_product(state.plan,operands...) :
            gg_apply(fixture.operation,operands...)
        for (i,mask) in enumerate(fixture.targets)
            output[i,t]=coefficient_mask(result,mask)
        end
    end
    output
end

register_adapter!(BenchmarkAdapter(name="garamon_grade_product",
    generate=gg_generate,prepare=gg_prepare,execute=gg_execute,
    baseline_execute=state->gg_execute(merge(state,
        (fixture=merge(state.fixture,(strategy="full",)),))),
    baseline_name="garamon_julia_direct_grade_product",
    oracle=(state,result)->size(result)==size(state.fixture.expected) &&
        result==state.fixture.expected,
    contract="owned Float64 matrix of all structurally possible homogeneous-grade outputs",
    capabilities=Dict("exact_oracle"=>"independent Int64 word inversions and grade selection",
        "grade_pairs"=>"1x1,(n-1)x1","operations"=>"geometric,wedge,left,right",
        "signatures"=>"positive,mixed,degenerate diagonal",
        "strategies"=>"full,grade_plan","generation_includes_oracle"=>true));replace=true)
