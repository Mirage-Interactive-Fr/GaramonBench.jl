pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

function cg_oracle(diagonal,left,right)
    k=size(left,2)
    gram=[sum(BigInt(left[l,i])*BigInt(diagonal[l])*BigInt(right[l,j])
        for l in eachindex(diagonal)) for i in 1:k,j in 1:k]
    used=falses(k)
    function permutation_sum(row,sign,product)
        row>k && return BigInt(sign)*product
        total=BigInt(0)
        for col in 1:k
            used[col] && continue
            crossings=count(used[j] for j in col+1:k)
            used[col]=true
            total+=permutation_sum(row+1,isodd(crossings) ? -sign : sign,
                product*gram[row,col])
            used[col]=false
        end
        total
    end
    permutation_sum(1,1,BigInt(1))
end

function cg_generate(case,directory,rng)
    n=case["dimension"]
    n in (3,4,5,6,8,16,32,64,65,129) || error("dimension")
    mode=case["mode"]
    mode in ("prepared","direct") || error("mode")
    signature=case["signature"]
    signature in ("positive","mixed","degenerate") || error("signature")
    k=case["grade"]
    k in (2,3) || error("grade")
    regime=case["rank_regime"]
    regime in ("generic","dependent") || error("rank_regime")
    support=case["vector_support"]
    support in (1,2) || error("vector_support")
    mutation=case["mutation"]
    mutation in ("stable","vector_change","metric_change") || error("mutation")
    horizon=case["horizon"]
    horizon in (1,32,256) || error("horizon")
    diagonal=ones(Int64,n)
    diagonal[1]=signature=="positive" ? 1 :
        signature=="mixed" ? -1 : 0
    changed_diagonal=copy(diagonal)
    changed_diagonal[1]=diagonal[1]==1 ? -1 : 1
    left=zeros(Int64,n,k)
    right=zeros(Int64,n,k)
    for j in 1:k
        left[j,j]=rand(rng,1:5)
        right[j,j]=rand(rng,1:5)
        if support==2
            left[n,j]+=rand(rng,1:3)
            right[n,j]+=rand(rng,1:3)
        end
    end
    regime=="dependent" && (right[:,2]=right[:,1])
    inputs=Vector{Tuple{Matrix{Int64},Matrix{Int64},Vector{Int64},Int64,Int64}}(undef,horizon)
    expected=Vector{BigInt}(undef,horizon)
    for t in 1:horizon
        active_left=copy(left)
        if mutation=="vector_change" && t>1
            active_left[1,1]+=1
        end
        active_diagonal=mutation=="metric_change" && t>1 ?
            changed_diagonal : diagonal
        ls=rand(rng,-5:5)
        rs=rand(rng,-5:5)
        ls=iszero(ls) ? 1 : ls
        rs=iszero(rs) ? 1 : rs
        inputs[t]=(active_left,right,active_diagonal,ls,rs)
        expected[t]=BigInt(ls)*BigInt(rs)*
            cg_oracle(active_diagonal,active_left,right)
    end
    (;n,k,mode,signature,regime,support,mutation,horizon,
      diagonal,left,right,inputs,expected)
end

function cg_prepare(f,case,directory)
    function make_ga(diagonal)
        matrix=zeros(Int64,f.n,f.n)
        for i in 1:f.n
            matrix[i,i]=diagonal[i]
        end
        algebra(matrix)
    end
    ga=make_ga(f.diagonal)
    changed_ga=f.mutation=="metric_change" && f.horizon>1 ?
        make_ga(f.inputs[2][3]) : ga
    prepared=[begin
        left,right,diagonal,ls,rs=item
        active=f.mutation=="metric_change" && t>1 ? changed_ga : ga
        (active,left,right,ls,rs)
    end for (t,item) in enumerate(f.inputs)]
    plan=f.mode=="prepared" ? prepare_cross_gram(ga,f.left,f.right) : nothing
    (;fixture=f,prepared,plan,fallbacks=Ref(0))
end

function cg_execute(state)
    f=state.fixture
    output=Vector{BigInt}(undef,f.horizon)
    fallbacks=0
    for t in 1:f.horizon
        ga,left,right,ls,rs=state.prepared[t]
        if f.mode=="prepared"
            value,info=run_cross_gram(state.plan,ga,left,right;
                left_scale=ls,right_scale=rs,on_invalid=:direct,
                diagnostics=true)
            fallbacks+=info.used_fallback
            output[t]=value
        else
            output[t]=cross_gram_scalar(ga,left,right;
                left_scale=ls,right_scale=rs)
        end
    end
    state.fallbacks[]=fallbacks
    output
end

function cg_check(state,result)
    result==state.fixture.expected &&
        length(result)==state.fixture.horizon &&
        0<=state.fallbacks[]<=state.fixture.horizon &&
        (state.fixture.mode!="prepared" ||
         state.fixture.mutation!="stable" || state.fallbacks[]==0)
end

register_adapter!(BenchmarkAdapter(name="garamon_cross_gram",
    generate=cg_generate,prepare=cg_prepare,execute=cg_execute,
    oracle=cg_check,
    contract="exact scalar pairing of two equal-grade decomposable blades; prepared cross-Gram rank or recomputation",
    capabilities=Dict(
        "exact_oracle"=>"independent Leibniz permutation determinant over BigInt",
        "domains"=>"integer vector coordinates and diagonal integer metric",
        "modes"=>"prepared,direct",
        "fallback"=>"complete direct exact cross-Gram recomputation",
        "generation_includes_oracle"=>true));replace=true)
