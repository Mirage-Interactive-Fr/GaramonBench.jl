using Test, GaramonBench, Random
include(joinpath(@__DIR__, "..", "adapters", "garamon_binary_rank.jl"))

@testset "binary-rank bounded routes and independent ambient oracle" begin
    config = load_config(joinpath(@__DIR__, "..", "config",
        "binary_rank_oracle_preflight.toml"))
    cases = expand_cases(config)
    @test length(cases)==2
    adapter = GaramonBench.ADAPTERS["garamon_binary_rank"]
    for case in cases
        fixture = adapter.generate(case,"",Random.Xoshiro(case["seed"]))
        state = adapter.prepare(fixture,case,"")
        @test adapter.oracle(state,adapter.execute(state))
        @test !adapter.oracle(state,zeros(size(fixture.expected)))
        @test GaramonBench.run_case_preflight(adapter,case,config["limits"])["oracle_passed"]
    end
    case = only(filter(c->c["strategy"]=="rank",cases))
    fixture = adapter.generate(case,"",Random.Xoshiro(case["seed"]))
    state = adapter.prepare(fixture,case,"")
    @test length(only(state.plans).basis)==2
    @test -1 in fixture.diagonal
    a,b = only(state.inputs)
    for query in ((:grade,1),(:coefficient,fixture.targets[1]))
        projected = BinaryRankPrototype.rank_product(
            BinaryRankPrototype.prepare_rank(a,b;query),a,b)
        for (i,mask) in enumerate(fixture.targets)
            selected = query[1]==:grade ? count_ones(mask)==query[2] : mask==query[2]
            @test Garamon.coefficient_mask(projected,mask)==
                (selected ? fixture.expected[i,1] : 0)
        end
    end
    @test_throws ArgumentError BinaryRankPrototype.prepare_rank(a,b;max_rank=1)
    changed = Garamon.multivector(a.algebra,Dict(UInt128(1)=>1.0);storage=:sparse)
    @test_throws ArgumentError BinaryRankPrototype.rank_product(only(state.plans),changed,b)
end
