# ID42: an exact breadth-first product frontier with certified suffix pruning.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random, SHA

function wf42_candidates(directions,::Type{K}) where K
    bits=K[one(K)<<(i-1) for i in directions]
    pairs=K[bits[i]|bits[i+1] for i in 1:length(bits)-1]
    unique(vcat(K[zero(K)],bits,pairs))
end

function wf42_terms(rng,candidates::Vector{K},t,j,mutation) where K
    width=mutation=="stable" ? min(5,length(candidates)) :
        min(4,max(1,length(candidates)-1))
    offset=mutation=="stable" ? j : t+j
    selected=K[candidates[mod1(offset+k-1,length(candidates))] for k in 1:width]
    Dict{K,Int64}(mask=>rand(rng,(-2,-1,1,2)) for mask in selected)
end

function wf42_word_oracle(factors,target,diagonal,directions)
    K=typeof(target)
    result=Int64(0)
    choices=[collect(terms) for terms in factors]
    for selected in Iterators.product(choices...)
        current=zero(K)
        value=Int64(1)
        for (right,coefficient) in selected
            left_indices=[i for i in directions
                          if !iszero(current & (one(K)<<(i-1)))]
            right_indices=[i for i in directions
                           if !iszero(right & (one(K)<<(i-1)))]
            inversions=sum((a>b for a in left_indices for b in right_indices);init=0)
            factor=isodd(inversions) ? Int64(-1) : Int64(1)
            for direction in intersect(left_indices,right_indices)
                factor*=diagonal[direction]
            end
            value*=factor*coefficient
            current=xor(current,right)
        end
        current==target && (result+=value)
    end
    result
end

function wf42_generate(case,directory,rng)
    n=case["dimension"]
    n in (2,3,4,5,6,8,12,16,32,64,65,96,128,129) || error("dimension")
    signature=case["signature"]
    signature in ("positive","mixed","degenerate") || error("signature")
    shape=case["support_shape"]
    shape in ("clustered","spread") || error("support shape")
    width=case["active_directions"]
    width in ("narrow","wide") || error("active direction width")
    mutation=case["mutation"]
    mutation in ("stable","changing") || error("mutation")
    policy=case["preparation"]
    policy in ("prebuilt","rebuild") || error("preparation")
    target_kind=case["target_kind"]
    target_kind in ("reachable","absent") || error("target kind")
    chain=case["chain_length"]
    chain in (3,4) || error("chain length")
    horizon=case["horizon"]
    horizon in (1,32,256) || error("horizon")
    K=n<=64 ? UInt64 : n<=128 ? UInt128 : BigInt
    count=min(width=="narrow" ? 5 : 12,n-1)
    directions=shape=="clustered" ? collect(1:count) :
        unique(round.(Int,range(1,n;length=count+1)))[1:count]
    missing=first(setdiff(1:n,directions))
    diagonal=ones(Int64,n)
    signature=="mixed" && (diagonal[2:2:end].=-1)
    signature=="degenerate" && (diagonal[last(directions)]=0)
    candidates=wf42_candidates(directions,K)
    episodes=Vector{Vector{Dict{K,Int64}}}(undef,horizon)
    targets=Vector{K}(undef,horizon)
    expected=Vector{Int64}(undef,horizon)
    for t in 1:horizon
        factors=[wf42_terms(rng,candidates,t,j,mutation) for j in 1:chain]
        target=target_kind=="absent" ? one(K)<<(missing-1) :
            foldl(xor,(last(sort!(collect(keys(terms)))) for terms in factors);
                  init=zero(K))
        episodes[t]=factors
        targets[t]=target
        expected[t]=wf42_word_oracle(factors,target,diagonal,directions)
    end
    (;n,signature,shape,width,mutation,policy,target_kind,chain,horizon,
      diagonal,directions,episodes,targets,expected)
end

function wf42_prepare(f,case,directory)
    gram=zeros(Int64,f.n,f.n)
    for i in 1:f.n
        gram[i,i]=f.diagonal[i]
    end
    ga=algebra(gram)
    episodes=[[multivector(ga,terms;storage=:sparse) for terms in factors]
              for factors in f.episodes]
    plans=f.policy=="prebuilt" ?
        f.mutation=="stable" ? [prepare_wavefront(episodes[1],f.targets[1])] :
            [prepare_wavefront(episodes[t],f.targets[t]) for t in 1:f.horizon] :
        nothing
    (;fixture=f,episodes,plans)
end

function wf42_execute(state)
    f=state.fixture
    [begin
        plan=isnothing(state.plans) ? prepare_wavefront(state.episodes[t],f.targets[t]) :
            state.plans[f.mutation=="stable" ? 1 : t]
        run_wavefront(plan,state.episodes[t])
    end for t in 1:f.horizon]
end

wf42_baseline(state)=[coefficient_mask(reduce(geometric_product,factors),
                                       state.fixture.targets[t])
                       for (t,factors) in enumerate(state.episodes)]

function wf42_scenario(state,case)
    f=state.fixture
    Dict{String,Any}("family"=>"exact_diagonal_sparse_product_chain_target",
        "dimension"=>f.n,"diagonal"=>f.diagonal,
        "episodes"=>[join((join((string(mask)*":"*string(value)
            for (mask,value) in sort!(collect(terms);by=first)),",")
            for terms in factors),"|")*"=>"*string(f.targets[t])
            for (t,factors) in enumerate(f.episodes)])
end

wf42_output_identity(result)=bytes2hex(sha256(join(string.(result),",")))

register_adapter!(BenchmarkAdapter(name="garamon_wavefront",
    generate=wf42_generate,prepare=wf42_prepare,execute=wf42_execute,
    baseline_execute=wf42_baseline,
    baseline_name="garamon_julia_direct_sparse_chain_coefficient",
    baseline_scenario=wf42_scenario,
    baseline_output_identity=wf42_output_identity,
    oracle=(state,result)->result==state.fixture.expected,
    preflight_evidence=(state,result)->begin
        f=state.fixture
        plan=isnothing(state.plans) ?
            prepare_wavefront(state.episodes[1],f.targets[1]) : state.plans[1]
        stats=wavefront_stats(plan)
        Dict("contract"=>"exact_diagonal_target_coefficient",
            "chain_length"=>f.chain,"horizon"=>f.horizon,
            "active_directions"=>f.width,
            "mutation"=>f.mutation,"preparation"=>f.policy,
            "target_kind"=>f.target_kind,
            "suffix_widths"=>stats.suffix_widths,
            "max_suffix_width"=>stats.max_suffix_width,
            "max_frontier"=>stats.max_frontier,
            "max_pairs"=>stats.max_pairs)
    end,
    contract="owned exact Int64 target coefficients for a diagonal sparse product chain",
    capabilities=Dict("exact_oracle"=>"independent Int64 Clifford-word inversion enumeration",
        "pruning"=>"only states with certified suffix XOR reachability are retained",
        "resource_bound"=>"suffix masks, frontier masks and visited pairs",
        "gpu_kernel"=>false));replace=true)
