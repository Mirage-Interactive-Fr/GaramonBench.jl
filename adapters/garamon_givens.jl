pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random, SparseArrays, LinearAlgebra

function givens_bench_matrix(n,rotations)
    T=Rational{BigInt}
    q=Matrix{T}(I,n,n)
    for (i,j,c,s) in rotations
        old_i=copy(q[i,:])
        old_j=copy(q[j,:])
        q[i,:]=c.*old_i.-s.*old_j
        q[j,:]=s.*old_i.+c.*old_j
    end
    q
end

function givens_bench_generate(case,directory,rng)
    n=case["dimension"]
    n in (2,3,4,5,6,8,16,32,65,129) || error("dimension budget")
    mode=case["mode"]
    mode in ("factored","materialized") || error("mode")
    steps=case["rotation_count"]
    steps in (1,2,4,8) || error("rotation count")
    support=case["support"]
    support in (1,4,16) || error("support")
    grade=case["grade"]
    grade in (1,2) || error("grade")
    angle=case["angle"]
    angle in ("3-4-5","5-12-13") || error("angle")
    horizon=case["horizon"]
    horizon in (1,64,1024) || error("horizon")
    c,s=angle=="3-4-5" ? (3//5,4//5) : (5//13,12//13)
    rotations=[(1+mod(k-1,n-1),n,c,s) for k in 1:steps]
    K=n<=64 ? UInt64 : n<=128 ? UInt128 : BigInt
    terms=Vector{Dict{K,BigInt}}(undef,horizon)
    for t in 1:horizon
        coefficients=Dict{K,BigInt}()
        for z in 1:support
            i=1+mod(z+t-2,n)
            j=1+mod(3z+t-2,n)
            if grade==2
                i==j && (j=mod(j,n)+1)
                mask=(one(K)<<(i-1)) | (one(K)<<(j-1))
            else
                mask=one(K)<<(i-1)
            end
            coefficients[mask]=get(coefficients,mask,BigInt(0))+
                BigInt(rand(rng,-9:9))
        end
        filter!(pair->!iszero(last(pair)),coefficients)
        terms[t]=coefficients
    end
    (;n,mode,steps,support,grade,angle,horizon,rotations,terms)
end

function givens_bench_prepare(fixture,case,directory)
    ga=algebra(spdiagm(0=>ones(Rational{BigInt},fixture.n)))
    plan=prepare_givens_basis_change(ga,fixture.rotations)
    matrix=givens_bench_matrix(fixture.n,fixture.rotations)
    inputs=[multivector(ga,terms;storage=:sparse) for terms in fixture.terms]
    (;fixture,ga,plan,matrix,inputs)
end

function givens_bench_execute(state)
    f=state.fixture
    if f.mode=="factored"
        return [run_givens_basis_change(state.plan,a).values for a in state.inputs]
    end
    [outermorphism(state.matrix,a,state.ga;check_metric=false).values
        for a in state.inputs]
end

function givens_bench_oracle(state,result)
    expected=state.fixture.mode=="factored" ?
        [outermorphism(state.matrix,a,state.ga;check_metric=true).values
            for a in state.inputs] :
        [run_givens_basis_change(state.plan,a).values for a in state.inputs]
    result==expected
end

register_adapter!(BenchmarkAdapter(name="garamon_givens",
    generate=givens_bench_generate,prepare=givens_bench_prepare,
    execute=givens_bench_execute,oracle=givens_bench_oracle,
    preflight_evidence=(state,result)->Dict{String,Any}(
        "mode"=>state.fixture.mode,
        "rotation_count"=>state.fixture.steps,
        "support"=>state.fixture.support,
        "grade"=>state.fixture.grade,
        "angle"=>state.fixture.angle),
    contract="owned sequence of all exact rational coefficients after a metric-preserving Euclidean outermorphism",
    capabilities=Dict(
        "exact_oracle"=>"independent materialized matrix exterior extension cross-checked with factored masked updates",
        "domains"=>"Euclidean identity metric, exact rational coefficients and rotations",
        "modes"=>"factored,materialized",
        "generation_includes_oracle"=>false));replace=true)

