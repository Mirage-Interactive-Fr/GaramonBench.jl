using Test, GaramonBench, Random

Base.include(Main,joinpath(@__DIR__,"..","adapters","garamon_k3_shared_workspace.jl"))

@testset "K3 shared-workspace exact minimal oracle" begin
    config=load_config(joinpath(@__DIR__,"..","config",
        "k3_shared_workspace_oracle_preflight.toml"))
    case=only(expand_cases(config))
    fixture=GaramonBenchK3.generate(case,"",Random.Xoshiro(case["seed"]))
    state=GaramonBenchK3.prepare(fixture,case,"")
    first=GaramonBenchK3.execute(state)
    @test first==fixture.expected
    @test state.workspace.contraction_builds==2
    saved=copy(first)
    @test GaramonBenchK3.execute(state)==fixture.expected
    @test state.workspace.contraction_builds==4
    @test first==saved
    @test first !== GaramonBenchK3.execute(state)
    @test GaramonBench.ADAPTERS["garamon_k3_shared_workspace"].oracle(state,first)
    damaged=copy(first);damaged[1,1]+=1
    @test !GaramonBench.ADAPTERS["garamon_k3_shared_workspace"].oracle(state,damaged)
    @test GaramonBench.run_case_preflight(GaramonBench.ADAPTERS["garamon_k3_shared_workspace"],case,
        config["limits"])["oracle_passed"]
end
