using Test, GaramonBench, Random
include(joinpath(@__DIR__,"..","adapters",
    "garamon_binary_rank_compact_workspace.jl"))

@testset "K1 compact workspace reuse and owned outputs" begin
    config = load_config(joinpath(@__DIR__,"..","config",
        "binary_rank_compact_workspace_oracle_preflight.toml"))
    case = only(expand_cases(config))
    adapter = GaramonBench.ADAPTERS["garamon_binary_rank_compact_workspace"]
    fixture = adapter.generate(case,"",Random.Xoshiro(case["seed"]))
    state = adapter.prepare(fixture,case,"")
    @test length(state.plan.basis)==3
    @test length(state.plan.phi)==6
    @test length(state.plan.phi)<(1<<length(state.plan.basis))
    @test state.workspace.plan===state.plan
    first_result = BinaryRankCompactPrototype.compact_rank_product!(
        state.workspace,state.inputs[1]...)
    first_values = copy(first_result.values)
    second_result = BinaryRankCompactPrototype.compact_rank_product!(
        state.workspace,state.inputs[2]...)
    @test first_result.values==first_values
    @test first_result.values!==second_result.values
    @test first_result.values!=second_result.values
    observed = adapter.execute(state)
    @test adapter.oracle(state,observed)
    @test !adapter.oracle(state,observed .+ 1)
    @test GaramonBench.run_case_preflight(adapter,case,config["limits"])["oracle_passed"]
end
