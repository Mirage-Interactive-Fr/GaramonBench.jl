# Short exact preflight for an active coordinate subspace. The expected
# coefficients come from independent Clifford-word mask arithmetic.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

cs_indices(mask,n)=[i for i in 1:n if !iszero(mask & (big(1) << (i-1)))]

function cs_word(amask,bmask,diagonal,operation)
    ai=cs_indices(amask,length(diagonal))
    bi=cs_indices(bmask,length(diagonal))
    output=xor(amask,bmask)
    operation==:wedge && !isempty(intersect(ai,bi)) && return output,Int64(0)
    operation in (:geometric,:wedge) || error("subspace operation")
    inversions=count(i>j for i in ai for j in bi)
    factor=isodd(inversions) ? Int64(-1) : Int64(1)
    if operation==:geometric
        for i in intersect(ai,bi)
            factor*=diagonal[i]
        end
    end
    output,factor
end

function cs_generate(case,directory,rng)
    n=case["dimension"]
    n in (4,65) || error("subspace preflight dimension budget")
    operation=Symbol(case["operation"])
    operation in (:geometric,:wedge) || error("subspace preflight operation")
    diagonal=Int64[i%3==0 ? 0 : iseven(i) ? -1 : 2 for i in 1:n]
    e1=big(1);e3=big(1)<<2;en=big(1)<<(n-1)
    left=BigInt[0,e1,e3,en,e1|e3,e3|en]
    right=BigInt[0,e3,en,e1|en]
    targets=sort!(unique(BigInt[xor(a,b) for a in left for b in right]))
    positions=Dict(mask=>i for (i,mask) in enumerate(targets))
    values=(rand(rng,Int64(1):Int64(3),length(left)),
            rand(rng,Int64(1):Int64(3),length(right)))
    expected=zeros(Int64,length(targets))
    for (ia,amask) in enumerate(left),(ib,bmask) in enumerate(right)
        output,factor=cs_word(amask,bmask,diagonal,operation)
        expected[positions[output]]+=factor*values[1][ia]*values[2][ib]
    end
    (;n,operation,diagonal,left,right,targets,values,expected,
      active_indices=[1,3,n])
end

function cs_prepare(fixture,case,directory)
    metric_values=zeros(Int64,fixture.n,fixture.n)
    for i in 1:fixture.n
        metric_values[i,i]=fixture.diagonal[i]
    end
    ga=algebra(metric_values)
    a=multivector(ga,Dict(mask=>Float64(fixture.values[1][i])
        for (i,mask) in enumerate(fixture.left));storage=:sparse)
    b=multivector(ga,Dict(mask=>Float64(fixture.values[2][i])
        for (i,mask) in enumerate(fixture.right));storage=:sparse)
    plan=coordinate_subspace(a,b)
    (;fixture,ga,a,b,plan)
end

function cs_execute(state)
    result=subspace_product(state.plan,state.a,state.b;
        operation=state.fixture.operation)
    Float64[coefficient_mask(result,mask) for mask in state.fixture.targets]
end

function cs_oracle(state,result)
    fixture=state.fixture
    size(result)==size(fixture.expected) && result==fixture.expected || return false
    state.plan.indices==fixture.active_indices || return false
    dimension(state.plan.algebra)==length(fixture.active_indices) || return false
    metric(state.plan.algebra)==metric(state.ga)[fixture.active_indices,
        fixture.active_indices] || return false
    lift_subspace(state.plan,project_subspace(state.plan,state.a),state.ga)==state.a &&
        lift_subspace(state.plan,project_subspace(state.plan,state.b),state.ga)==state.b
end

register_adapter!(BenchmarkAdapter(name="garamon_coordinate_subspace",
    generate=cs_generate,prepare=cs_prepare,execute=cs_execute,oracle=cs_oracle,
    baseline_execute=state->begin
        result=state.fixture.operation==:wedge ? wedge(state.a,state.b) :
            geometric_product(state.a,state.b)
        Float64[coefficient_mask(result,mask) for mask in state.fixture.targets]
    end,
    baseline_name="garamon_julia_full_direct_product",
    contract="owned Float64 vector of every structural product coefficient in mask order",
    capabilities=Dict("exact_oracle"=>"independent Int64 Clifford-word inversions and diagonal intersections",
        "active_directions"=>"1,3,n in ambient dimensions 4 and 65",
        "operations"=>"geometric,wedge",
        "metric"=>"diagonal with positive, negative and null directions",
        "generation_includes_oracle"=>true,"gpu_kernel"=>false));replace=true)
