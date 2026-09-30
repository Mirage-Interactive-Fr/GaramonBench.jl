# Independent combinatorial identity for Garamon's homogeneous blade ordering.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

bi_indices(mask,n)=[i for i in 1:n if !iszero(mask & (big(1) << (i-1)))]

function bi_lex_rank(mask,n)
    indices=bi_indices(mask,n)
    k=length(indices)
    # Complementary combinadic identity, distinct from the target's
    # skipped-prefix loop.
    binomial(big(n),k)-1-
        sum(binomial(big(n-i),k-j+1) for (j,i) in enumerate(indices);init=big(0))
end

function bi_generate(case,directory,rng)
    n=case["dimension"]
    2<=n<=129 || error("blade index dimension budget")
    horizon=case["horizon"]
    1<=horizon<=1024 || error("blade index horizon budget")
    strategy=case["strategy"]
    strategy in ("mask","indices") || error("blade index strategy")
    full=(big(1) << n)-1
    middle=cld(n,2)
    masks=BigInt[0,full,big(1),big(1) << (middle-1),big(1) << (n-1),
        full⊻big(1),full⊻(big(1) << (middle-1)),full⊻(big(1) << (n-1))]
    for grade in unique([2,3,div(n,2),n-2])
        0<=grade<=n || continue
        selected=sort!(randperm(rng,n)[1:grade])
        push!(masks,sum((big(1) << (i-1) for i in selected);init=big(0)))
    end
    sort!(unique!(masks))
    sequence=[circshift(masks,t-1) for t in 1:horizon]
    expected=Matrix{BigInt}(undef,3length(masks),horizon)
    for t in 1:horizon,(j,mask) in enumerate(sequence[t])
        expected[3j-2,t]=length(bi_indices(mask,n))
        expected[3j-1,t]=bi_lex_rank(mask,n)
        expected[3j,t]=mask
    end
    (;n,horizon,strategy,sequence,expected)
end

function bi_prepare(fixture,case,directory)
    (;fixture,ga=algebra(fixture.n,:ega))
end

function bi_execute(state)
    fixture=state.fixture
    output=Matrix{BigInt}(undef,size(fixture.expected)...)
    for t in 1:fixture.horizon,(j,mask) in enumerate(fixture.sequence[t])
        grade,rank=fixture.strategy=="mask" ? blade_rank(state.ga,mask) :
            blade_rank(state.ga,bi_indices(mask,fixture.n))
        unranked=blade_unrank(state.ga,grade,rank)
        output[3j-2,t]=grade
        output[3j-1,t]=rank
        output[3j,t]=BigInt(unranked)
    end
    output
end

register_adapter!(BenchmarkAdapter(name="garamon_blade_index",
    generate=bi_generate,prepare=bi_prepare,execute=bi_execute,
    baseline_execute=state->bi_execute(merge(state,
        (fixture=merge(state.fixture,(strategy="mask",)),))),
    baseline_name="garamon_julia_mask_index",
    oracle=(state,result)->result==state.fixture.expected,
    contract="owned BigInt matrix of grade, lexicographic rank and unranked mask",
    capabilities=Dict("exact_oracle"=>"complementary combinadic rank identity plus roundtrip",
        "strategies"=>"mask,indices","boundaries"=>"64/65 and 128/129",
        "generation_includes_oracle"=>true));replace=true)
