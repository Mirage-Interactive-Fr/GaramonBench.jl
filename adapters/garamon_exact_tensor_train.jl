# Enumerated Clifford-word oracle independent of Garamon train/product methods.
pushfirst!(LOAD_PATH, get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")))
using Garamon, GaramonBench, Random

function tt19_input_coefficient(mask::Int, zero_weights, one_weights)
    coefficient = Int64(1)
    for i in eachindex(zero_weights)
        coefficient *= iszero(mask & (1 << (i - 1))) ? zero_weights[i] : one_weights[i]
    end
    coefficient
end

function tt19_word(left::Int, right::Int, diagonal)
    factor = Int64(1)
    inversions = 0
    for i in eachindex(diagonal)
        iszero(left & (1 << (i - 1))) && continue
        for j in 1:i-1
            inversions += !iszero(right & (1 << (j - 1)))
        end
        if !iszero(right & (1 << (i - 1)))
            factor *= diagonal[i]
        end
    end
    xor(left, right), isodd(inversions) ? -factor : factor
end

function tt19_generate(case, directory, rng)
    n = case["dimension"]
    2<=n<=8 || error("full-coefficient train oracle is bounded to dimensions 2..8")
    repeat_weights(v)=Int64[v[mod1(i,4)] for i in 1:n]
    diagonal = repeat_weights([2,-1,0,3])
    left_zero,left_one=repeat_weights([1,2,1,1]),repeat_weights([2,0,1,-1])
    right_zero,right_one=repeat_weights([1,1,2,1]),repeat_weights([1,-1,1,2])
    horizon=get(case,"horizon",1)
    1<=horizon<=32 || error("train episode horizon budget")
    # Keep the original smoke fixture; campaign seeds vary the input signs.
    if haskey(case,"horizon")
        left_one .*= rand(rng,(-1,1),n)
        right_one .*= rand(rng,(-1,1),n)
    end
    expected = zeros(Int64, 1 << n)
    for left in 0:(1 << n)-1, right in 0:(1 << n)-1
        output, factor = tt19_word(left, right, diagonal)
        expected[output + 1] += factor *
            tt19_input_coefficient(left, left_zero, left_one) *
            tt19_input_coefficient(right, right_zero, right_one)
    end
    (; n, diagonal, left_zero, left_one, right_zero, right_one, expected,horizon)
end

function tt19_prepare(fixture, case, directory)
    gram = zeros(Int64, fixture.n, fixture.n)
    for i in 1:fixture.n
        gram[i, i] = fixture.diagonal[i]
    end
    ga = algebra(gram)
    left = separable_train(ga, fixture.left_zero, fixture.left_one)
    right = separable_train(ga, fixture.right_zero, fixture.right_one)
    (; fixture, left, right)
end

function tt19_once(state)
    product = train_product(state.left, state.right; max_rank=4, max_entries=32*state.fixture.n)
    n = state.fixture.n
    Int64[coefficient(product, [i for i in 1:n if !iszero(mask & (1 << (i - 1)))])
          for mask in 0:(1 << n)-1]
end

tt19_execute(state)=state.fixture.horizon==1 ? tt19_once(state) :
    [tt19_once(state) for _ in 1:state.fixture.horizon]

function tt19_baseline_once(state)
    product=geometric_product(state.left,state.right)
    n=state.fixture.n
    Int64[coefficient_mask(product,mask) for mask in 0:(1<<n)-1]
end

register_adapter!(BenchmarkAdapter(name="garamon_exact_tensor_train",
    generate=tt19_generate, prepare=tt19_prepare, execute=tt19_execute,
    baseline_prepare=state->(;fixture=state.fixture,
        left=expand(state.left;max_terms=1<<16),
        right=expand(state.right;max_terms=1<<16)),
    baseline_execute=state->state.fixture.horizon==1 ? tt19_baseline_once(state) :
        [tt19_baseline_once(state) for _ in 1:state.fixture.horizon],
    baseline_name="garamon_julia_expanded_direct_product",
    oracle=(state,result)->state.fixture.horizon==1 ? result==state.fixture.expected :
        length(result)==state.fixture.horizon && all(==(state.fixture.expected),result),
    contract="owned exact Int64 vector of all ordered-blade coefficients",
    capabilities=Dict("exact_oracle"=>"independent full mask-pair enumeration, inversion parity and diagonal contractions",
        "operation"=>"bounded exact product of two separable trains",
        "generation_includes_oracle"=>true, "gpu_kernel"=>false)); replace=true)
