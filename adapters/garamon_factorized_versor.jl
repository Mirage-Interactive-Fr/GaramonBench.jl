# Exact independent coordinate oracle for a factorized blade under reflections.
pushfirst!(LOAD_PATH, get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")))
using Garamon, GaramonBench, Random

const FV17 = Rational{BigInt}

function fv17_reflect(vector, normal, diagonal)
    squared = sum(diagonal[i] * normal[i]^2 for i in eachindex(diagonal))
    iszero(squared) && error("null independent-oracle normal")
    pairing = sum(diagonal[i] * normal[i] * vector[i] for i in eachindex(diagonal))
    [vector[i] - 2 * pairing * normal[i] / squared for i in eachindex(diagonal)]
end

function fv17_generate(case, directory, rng)
    n=case["dimension"]
    2<=n<=128 || error("factorized-versor dimension budget")
    reflections=get(case,"reflection_count",2)
    horizon=get(case,"horizon",1)
    1<=reflections<=8 && 1<=horizon<=32 || error("factorized episode budget")
    diagonal=FV17[[2,-1,3,1][mod1(i,4)] for i in 1:n]
    pattern=FV17[1 0;2 1;0 -1;1 2]
    factors=FV17[pattern[mod1(i,4),j] for i in 1:n,j in 1:2]
    normals=zeros(FV17,n,reflections)
    for j in 1:reflections
        if j<=2
            p=FV17[1 0;1 1;0 1;0 0]
            for i in 1:n;normals[i,j]=p[mod1(i,4),j];end
        else
            normals[mod1(j,n),j]=1
        end
    end
    if haskey(case,"reflection_count")
        factors .*= reshape(FV17.(rand(rng,(-1,1),n)),n,1)
    end
    scale = FV17(2)
    transformed = copy(factors)
    for col in axes(factors, 2), reflection in axes(normals, 2)
        transformed[:, col] = fv17_reflect(transformed[:, col], normals[:, reflection], diagonal)
    end
    masks = [[i,j] for i in 1:n-1 for j in i+1:n]
    expected = FV17[scale * (transformed[i, 1] * transformed[j, 2] -
                               transformed[j, 1] * transformed[i, 2]) for (i, j) in masks]
    (;n,diagonal,factors,normals,scale,masks,expected,horizon)
end

function fv17_prepare(fixture, case, directory)
    gram = Matrix{FV17}(undef, fixture.n, fixture.n)
    for j in 1:fixture.n, i in 1:fixture.n
        gram[i, j] = i == j ? fixture.diagonal[i] : zero(FV17)
    end
    ga = algebra(gram)
    blade = FactorizedBlade(ga, fixture.factors; scale=fixture.scale)
    chain = ReflectionChain(ga, fixture.normals)
    (; fixture, blade, chain)
end

function fv17_once(state)
    transformed = versor_action(state.chain, state.blade)
    FV17[coefficient(transformed, indices) for indices in state.fixture.masks]
end

fv17_execute(state)=state.fixture.horizon==1 ? fv17_once(state) :
    [fv17_once(state) for _ in 1:state.fixture.horizon]

function fv17_baseline_prepare(state)
    ga=state.blade.algebra
    normal_mvs=[multivector(ga,Dict(big(1)<<(i-1)=>state.fixture.normals[i,j]
        for i in 1:state.fixture.n if !iszero(state.fixture.normals[i,j]));storage=:sparse)
        for j in axes(state.fixture.normals,2)]
    (;base=expand(state.blade),normal_mvs,masks=state.fixture.masks,horizon=state.fixture.horizon)
end

function fv17_baseline_once(state)
    value=state.base
    for normal in state.normal_mvs
        # A grade-two blade has even reflection parity, so u*B*u^-1 is
        # the reflected blade for each non-null normal u.
        # Temporary grades can be larger than the final bivector. This
        # explicit budget rejects overflow; it never drops contributions.
        value=geometric_product(geometric_product(normal,value;max_terms=1<<20),
            inv(normal);max_terms=1<<20)
    end
    FV17[coefficient(value,indices) for indices in state.masks]
end

fv17_baseline_execute(state)=state.horizon==1 ? fv17_baseline_once(state) :
    [fv17_baseline_once(state) for _ in 1:state.horizon]

register_adapter!(BenchmarkAdapter(name="garamon_factorized_versor",
    generate=fv17_generate, prepare=fv17_prepare, execute=fv17_execute,
    baseline_prepare=fv17_baseline_prepare,
    baseline_execute=fv17_baseline_execute,
    baseline_name="garamon_julia_full_versor_product",
    oracle=(state,result)->state.fixture.horizon==1 ? result==state.fixture.expected :
        length(result)==state.fixture.horizon && all(==(state.fixture.expected),result),
    contract="owned exact rational coefficients of every grade-two blade",
    capabilities=Dict("exact_oracle"=>"independent rational reflection and two-by-two minors",
        "operation"=>"configurable reflection-chain factorized-blade versor action",
        "generation_includes_oracle"=>true, "gpu_kernel"=>false)); replace=true)
