# A bounded expression DAG with an independent Clifford-word oracle.
pushfirst!(LOAD_PATH, get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")))
using Garamon, GaramonBench, Random

function dag16_word(left::UInt64, right::UInt64, diagonal::Vector{Int64})
    inversions = 0
    factor = Int64(1)
    for i in eachindex(diagonal)
        iszero(left & (UInt64(1) << (i-1))) && continue
        for j in 1:i-1
            inversions += !iszero(right & (UInt64(1) << (j-1)))
        end
        if !iszero(right & (UInt64(1) << (i-1)))
            factor *= diagonal[i]
        end
    end
    xor(left, right), isodd(inversions) ? -factor : factor
end

function dag16_expected(a, b, c, diagonal, shared)
    result = zeros(Int64, 1 << length(diagonal))
    for other in (b, shared ? b : c)
        for (left, avalue) in a, (right, bvalue) in other
            mask, factor = dag16_word(left, right, diagonal)
            result[Int(mask)+1] += factor * avalue * bvalue
        end
    end
    result
end

function dag16_generate(case, directory, rng)
    n = case["dimension"]
    n in (3, 4) || error("DAG dimension budget")
    structure = case["structure"]
    structure in ("shared", "distinct") || error("DAG structure")
    diagonal = Int64[iseven(i) ? -1 : 2 for i in 1:n]
    high = UInt64(1) << (n-1)
    supports = (UInt64[0, 1, 3, high], UInt64[0, 2, high, 2|high],
                UInt64[0, 1, high, 1|high])
    coefficients = ntuple(k -> Dict(mask => rand(rng, Int64(1):Int64(3))
                                      for mask in supports[k]), 3)
    a, b, c = coefficients
    changed = copy(a)
    changed[UInt64(1)] += 2
    expected = hcat(dag16_expected(a, b, c, diagonal, structure=="shared"),
                    dag16_expected(changed, b, c, diagonal, structure=="shared"))
    (;n, structure, diagonal, coefficients, changed, expected)
end

function dag16_prepare(fixture, case, directory)
    metric = zeros(Int64, fixture.n, fixture.n)
    for i in 1:fixture.n
        metric[i,i] = fixture.diagonal[i]
    end
    ga = algebra(metric)
    a, b, c = (multivector(ga, Dict(mask => Float64(value) for (mask,value) in terms);
                            storage=:sparse) for terms in fixture.coefficients)
    expression = fixture.structure=="shared" ? @ga(a*b + a*b) : @ga(a*b + a*c)
    plan = prepare_expression(expression; max_nodes=6)
    length(plan) == (fixture.structure=="shared" ? 4 : 6) ||
        error("unexpected expression DAG sharing")
    outputs = [[i for i in 1:fixture.n if !iszero(mask & (1 << (i-1)))]
               for mask in 0:(1 << fixture.n)-1]
    (;fixture, plan, a, outputs)
end

function dag16_execute(state)
    fixture = state.fixture
    result = Matrix{Float64}(undef, size(fixture.expected))
    try
        for (column, terms) in enumerate((fixture.coefficients[1], fixture.changed))
            for (mask, value) in terms
                state.a.values[mask] = Float64(value)
            end
            result[:,column] = evaluate(state.plan; outputs=state.outputs)
        end
    finally
        for (mask, value) in fixture.coefficients[1]
            state.a.values[mask] = Float64(value)
        end
    end
    result
end

register_adapter!(BenchmarkAdapter(name="garamon_expression_dag",
    generate=dag16_generate, prepare=dag16_prepare, execute=dag16_execute,
    oracle=(state,result)->size(result)==size(state.fixture.expected) &&
        result==state.fixture.expected,
    contract="owned Float64 matrix of all coefficients before and after a leaf mutation",
    capabilities=Dict("exact_oracle"=>"independent Int64 Clifford-word inversions",
        "expression_nodes"=>"shared 4, distinct 6",
        "mutation"=>"leaf coefficients reread by one prepared DAG",
        "generation_includes_oracle"=>true, "gpu_kernel"=>false)); replace=true)
