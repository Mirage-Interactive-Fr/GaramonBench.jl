using Test, GaramonBench, Random
include(joinpath(@__DIR__,"..","adapters","garamon_deferred_exact_replay.jl"))

@testset "N24 exact deferred correction and replay" begin
    config=load_config(joinpath(@__DIR__,"..","config",
        "deferred_exact_replay_oracle_preflight.toml"))
    cases=expand_cases(config)
    @test length(cases)==1
    case=only(cases)
    adapter=GaramonBench.ADAPTERS["garamon_deferred_exact_replay"]
    state=adapter.generate(case,"",Xoshiro(case["seed"]))
    result=adapter.execute(state)
    @test adapter.oracle(state,result)
    @test result.deferred.buffer_bytes===nothing
    @test result.replay.buffer_bytes===nothing
    @test result.deferred.value==last(state.oracle)
    @test result.replay.value==last(state.oracle)
    @test result.deferred.counts.omitted>0
    @test result.deferred.counts.correction_paths>0
    @test result.replay.counts.replay_paths>0
    damaged=deepcopy(result)
    damaged.deferred.value[1]+=1
    @test !adapter.oracle(state,damaged)
    @test GaramonBench.run_case_preflight(adapter,case,config["limits"])["oracle_passed"]
end
