# Exact coefficient queries compared with a complete product and an independent
# combinatorial Clifford-word oracle. All output matrices are owned.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

tc_indices(mask,n)=[i for i in 1:n if !iszero(mask & (big(1) << (i-1)))]

function tc_word(mask_a,mask_b,diagonal,operation)
    n=length(diagonal)
    ai=tc_indices(mask_a,n)
    bi=tc_indices(mask_b,n)
    ra,rb=length(ai),length(bi)
    output=xor(mask_a,mask_b)
    grade=length(tc_indices(output,n))
    selected=operation==:geometric ? true :
        operation==:wedge ? isempty(intersect(ai,bi)) :
        operation==:left ? ra<=rb && grade==rb-ra :
        operation==:right ? rb<=ra && grade==ra-rb :
        operation==:inner ? ra>0 && rb>0 && grade==abs(ra-rb) :
        operation==:dot ? grade==abs(ra-rb) :
        operation==:scalar ? ra==rb && grade==0 : error("operation")
    selected || return output,Int64(0)
    # ai and bi are sorted. This two-pointer inversion count does not call
    # any Garamon sign, grade, or product helper.
    lower=1
    inversions=0
    for i in ai
        while lower<=length(bi) && bi[lower]<i
            lower+=1
        end
        inversions+=lower-1
    end
    factor=isodd(inversions) ? Int64(-1) : Int64(1)
    if operation!=:wedge
        for i in intersect(ai,bi)
            factor*=diagonal[i]
        end
    end
    output,factor
end

function tc_generate(case,directory,rng)
    n=case["dimension"]
    2<=n<=129 || error("target coefficient dimension budget")
    horizon=case["horizon"]
    1<=horizon<=1024 || error("target coefficient horizon budget")
    signature=case["signature"]
    signature in ("positive","mixed","degenerate") || error("target signature")
    operation=Symbol(case["operation"])
    operation in (:geometric,:wedge,:left,:right,:inner,:dot,:scalar) ||
        error("target operation")
    strategy=case["strategy"]
    strategy in ("full","targeted") || error("target strategy")
    diagonal=signature=="positive" ? ones(Int64,n) :
        signature=="mixed" ? Int64[iseven(i) ? -1 : 1 for i in 1:n] :
        Int64[i%3==0 ? 0 : iseven(i) ? -1 : 2 for i in 1:n]
    low=big(1);high=big(1) << (n-1);near=big(1) << (n-2)
    full=(big(1) << n)-1
    supports=(unique(BigInt[0,low,high,near,low|high,full]),
              unique(BigInt[0,high,near,low|near,full]))
    targets=unique(BigInt[0,low,high,near,low|high,full,full⊻low,near|high])
    positions=Dict(mask=>i for (i,mask) in enumerate(targets))
    coefficients=[ntuple(k->rand(rng,Int64(1):Int64(3),length(supports[k])),2)
                  for _ in 1:horizon]
    expected=zeros(Int64,length(targets),horizon)
    for t in 1:horizon
        values=coefficients[t]
        for (ia,amask) in enumerate(supports[1]),
            (ib,bmask) in enumerate(supports[2])
            output,factor=tc_word(amask,bmask,diagonal,operation)
            row=get(positions,output,0)
            iszero(row) && continue
            expected[row,t]+=factor*values[1][ia]*values[2][ib]
        end
    end
    (;n,horizon,signature,operation,strategy,diagonal,supports,targets,
      coefficients,expected)
end

function tc_prepare(fixture,case,directory)
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
    indices=[tc_indices(mask,fixture.n) for mask in fixture.targets]
    if fixture.strategy=="targeted"
        return (;fixture,inputs,indices,strategy=Val(:targeted))
    end
    return (;fixture,inputs,indices,strategy=Val(:full))
end

function tc_apply(operation,a,b)
    operation==:geometric && return geometric_product(a,b)
    operation==:wedge && return wedge(a,b)
    operation==:left && return left_contraction(a,b)
    operation==:right && return right_contraction(a,b)
    operation==:inner && return inner_product(a,b)
    operation==:dot && return dot_product(a,b)
    operation==:scalar && return scalar_product(a,b)
    error("operation")
end

tc_execute(state)=tc_execute_strategy(state,state.strategy)

function tc_execute_strategy(state,::Val{:full})
    fixture=state.fixture
    output=Matrix{Float64}(undef,length(fixture.targets),fixture.horizon)
    for t in 1:fixture.horizon
        operands=state.inputs[t]
        result=tc_apply(fixture.operation,operands...)
        for (i,mask) in enumerate(fixture.targets)
            output[i,t]=coefficient_mask(result,mask)
        end
    end
    output
end

function tc_execute_strategy(state,::Val{:targeted})
    fixture=state.fixture
    output=Matrix{Float64}(undef,length(fixture.targets),fixture.horizon)
    for t in 1:fixture.horizon
        operands=state.inputs[t]
        for (i,indices) in enumerate(state.indices)
            output[i,t]=product_coefficient(operands...,indices;
                operation=fixture.operation)
        end
    end
    output
end

register_adapter!(BenchmarkAdapter(name="garamon_target_coefficient",
    generate=tc_generate,prepare=tc_prepare,execute=tc_execute,
    oracle=(state,result)->size(result)==size(state.fixture.expected) &&
        result==state.fixture.expected,
    contract="owned Float64 matrix of selected coefficients for one exact binary product",
    capabilities=Dict("exact_oracle"=>"independent Int64 Clifford-word inversions and grade selection",
        "operations"=>"geometric,wedge,left,right,inner,dot,scalar",
        "signatures"=>"positive,mixed,degenerate diagonal",
        "strategies"=>"full,targeted","generation_includes_oracle"=>true,
        "gpu_kernel"=>false));replace=true)
