using Test, GaramonBench
include(joinpath(@__DIR__, "..", "adapters", "garamon_expression_dag.jl"))

@testset "DAG sharing and leaf invalidation" begin
    config = load_config(joinpath(@__DIR__, "..", "config",
        "expression_dag_oracle_preflight.toml"))
    cases = expand_cases(config)
    @test length(cases) == 4
    adapter = GaramonBench.ADAPTERS["garamon_expression_dag"]
    for case in cases
        fixture = adapter.generate(case, "", Random.Xoshiro(case["seed"]))
        state = adapter.prepare(fixture, case, "")
        @test length(state.plan) == (case["structure"]=="shared" ? 4 : 6)
        if case["structure"] == "shared"
            @test state.plan.children[state.plan.root][1] ==
                  state.plan.children[state.plan.root][2]
        end
        result = adapter.execute(state)
        @test adapter.oracle(state, result)
        @test result[:,1] != result[:,2]
        result[1,1] += 1
        @test !adapter.oracle(state, result)
        @test_throws ArgumentError Garamon.prepare_expression(
            state.plan.nodes[state.plan.root]; max_nodes=3)
    end
    @test GaramonBench.run_case_preflight(adapter, first(cases),
        config["limits"])["oracle_passed"]
end
