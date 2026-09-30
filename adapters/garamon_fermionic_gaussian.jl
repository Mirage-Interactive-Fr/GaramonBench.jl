pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

function fg_oracle(transport,occupied,target)
    gram=transpose(BigInt.(target))*(transport*BigInt.(occupied))
    k=size(gram,1)
    used=falses(k)
    function sum_permutations(row,sign,product)
        row>k && return BigInt(sign)*product
        total=BigInt(0)
        for col in 1:k
            used[col] && continue
            inversions=count(used[j] for j in col+1:k)
            used[col]=true
            total+=sum_permutations(row+1,
                isodd(inversions) ? -sign : sign,product*gram[row,col])
            used[col]=false
        end
        total
    end
    sum_permutations(1,1,BigInt(1))
end

function fg_generate(case,directory,rng)
    n=case["dimension"]
    n in (3,4,5,6,8,16,32,64,65,129) || error("dimension")
    mode=case["mode"]
    mode in ("factored","materialized") || error("mode")
    k=case["particles"]
    k in (2,3) || error("particles")
    count_shears=case["shear_count"]
    count_shears in (1,4,16) || error("shear_count")
    support=case["orbital_support"]
    support in (1,2) || error("orbital_support")
    relation=case["target_relation"]
    relation in ("same","shifted") || error("target_relation")
    horizon=case["horizon"]
    horizon in (1,32,256) || error("horizon")
    shears=Tuple{Int,Int,Int}[]
    for _ in 1:count_shears
        source=rand(rng,1:n)
        target=rand(rng,1:n-1)
        target>=source && (target+=1)
        coefficient=rand(rng,(-2,-1,1,2))
        push!(shears,(target,source,coefficient))
    end
    transport=zeros(BigInt,n,n)
    for i in 1:n
        transport[i,i]=1
    end
    for (target,source,coefficient) in shears
        for j in 1:n
            transport[target,j]+=coefficient*transport[source,j]
        end
    end
    inputs=Vector{Tuple{Matrix{Int64},Matrix{Int64}}}(undef,horizon)
    expected=Vector{BigInt}(undef,horizon)
    for t in 1:horizon
        occupied=zeros(Int64,n,k)
        target=zeros(Int64,n,k)
        for j in 1:k
            occupied[j,j]=rand(rng,1:5)
            position=relation=="same" ? j : mod1(j+1,n)
            target[position,j]=rand(rng,1:5)
            if support==2
                occupied[n,j]+=rand(rng,1:3)
                target[n,j]+=rand(rng,1:3)
            end
        end
        inputs[t]=(occupied,target)
        expected[t]=fg_oracle(transport,occupied,target)
    end
    (;n,k,mode,count_shears,support,relation,horizon,shears,inputs,expected)
end

function fg_prepare(f,case,directory)
    plan=prepare_fermionic_gaussian(f.n,f.shears;
        materialize=f.mode=="materialized")
    (;fixture=f,plan)
end

function fg_execute(state)
    f=state.fixture
    output=Vector{BigInt}(undef,f.horizon)
    for t in 1:f.horizon
        output[t]=run_fermionic_gaussian(state.plan,f.inputs[t]...)
    end
    output
end

fg_check(state,result)=result==state.fixture.expected &&
    length(result)==state.fixture.horizon

register_adapter!(BenchmarkAdapter(name="garamon_fermionic_gaussian",
    generate=fg_generate,prepare=fg_prepare,execute=fg_execute,
    oracle=fg_check,
    contract="exact Slater-state overlap after number-conserving quadratic-generator shears",
    capabilities=Dict(
        "exact_oracle"=>"independent Leibniz determinant after materialized one-body transformation",
        "domains"=>"integer one-body shears and decomposable integer-orbital states",
        "modes"=>"factored,materialized",
        "unsupported"=>"general multivectors, pairing terms and non-Gaussian operators explicitly rejected",
        "generation_includes_oracle"=>true));replace=true)
