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
    case["dimension"] == 4 || error("factorized-versor smoke dimension")
    diagonal = FV17[2, -1, 3, 1]
    factors = FV17[1 0; 2 1; 0 -1; 1 2]
    normals = FV17[1 0; 1 1; 0 1; 0 0]
    scale = FV17(2)
    transformed = copy(factors)
    for col in axes(factors, 2), reflection in axes(normals, 2)
        transformed[:, col] = fv17_reflect(transformed[:, col], normals[:, reflection], diagonal)
    end
    masks = [[i, j] for i in 1:3 for j in i+1:4]
    expected = FV17[scale * (transformed[i, 1] * transformed[j, 2] -
                               transformed[j, 1] * transformed[i, 2]) for (i, j) in masks]
    (; diagonal, factors, normals, scale, masks, expected)
end

function fv17_prepare(fixture, case, directory)
    gram = Matrix{FV17}(undef, 4, 4)
    for j in 1:4, i in 1:4
        gram[i, j] = i == j ? fixture.diagonal[i] : zero(FV17)
    end
    ga = algebra(gram)
    blade = FactorizedBlade(ga, fixture.factors; scale=fixture.scale)
    chain = ReflectionChain(ga, fixture.normals)
    (; fixture, blade, chain)
end

function fv17_execute(state)
    transformed = versor_action(state.chain, state.blade)
    FV17[coefficient(transformed, indices) for indices in state.fixture.masks]
end

function fv17_baseline_prepare(state)
    ga=state.blade.algebra
    normal_mvs=[multivector(ga,Dict(UInt64(1)<<(i-1)=>state.fixture.normals[i,j]
        for i in 1:4 if !iszero(state.fixture.normals[i,j]));storage=:sparse)
        for j in axes(state.fixture.normals,2)]
    (;base=expand(state.blade),normal_mvs,masks=state.fixture.masks)
end

function fv17_baseline_execute(state)
    value=state.base
    for normal in state.normal_mvs
        # A grade-two blade has even reflection parity, so u*B*u^-1 is
        # the reflected blade for each non-null normal u.
        value=geometric_product(geometric_product(normal,value),inv(normal))
    end
    FV17[coefficient(value,indices) for indices in state.masks]
end

register_adapter!(BenchmarkAdapter(name="garamon_factorized_versor",
    generate=fv17_generate, prepare=fv17_prepare, execute=fv17_execute,
    baseline_prepare=fv17_baseline_prepare,
    baseline_execute=fv17_baseline_execute,
    baseline_name="garamon_julia_full_versor_product",
    oracle=(state, result)->result == state.fixture.expected,
    contract="owned exact rational coefficients of every grade-two blade",
    capabilities=Dict("exact_oracle"=>"independent rational reflection and two-by-two minors",
        "operation"=>"two-reflection factorized-blade versor action",
        "generation_includes_oracle"=>true, "gpu_kernel"=>false)); replace=true)
