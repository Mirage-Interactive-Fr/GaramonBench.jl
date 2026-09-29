using Test, GaramonBench, Distributed, Random
include(joinpath(@__DIR__, "..", "adapters", "garamon_cpu_processes.jl"))

@testset "actual worker packed product and cleanup" begin
    config = load_config(joinpath(@__DIR__, "..", "config",
        "cpu_processes_oracle_preflight.toml"))
    case = only(expand_cases(config))
    adapter = GaramonBench.ADAPTERS["garamon_cpu_processes"]
    before = Set(workers())
    fixture = adapter.generate(case,"",Random.Xoshiro(case["seed"]))
    @test size(fixture.expected,2)==4
    @test any(!iszero,fixture.expected)
    try
        state = adapter.prepare(fixture,case,"")
        try
            @test state.pid in workers()
            result = adapter.execute(state)
            @test result.worker_id==state.pid
            @test result.os_pid!=getpid()
            @test adapter.oracle(state,result)
            damaged = merge(result,(output=copy(result.output),))
            damaged.output[1,1] += 1
            @test !adapter.oracle(state,damaged)
        finally
            adapter.cleanup(state)
        end
        @test Set(workers())==before
        @test GaramonBench.run_case_preflight(adapter,case,config["limits"])["oracle_passed"]
        @test Set(workers())==before
    finally
        for pid in setdiff(Set(workers()),before)
            rmprocs(pid)
        end
    end
end
