using Test, GaramonBench, TOML
include(joinpath(@__DIR__, "..", "adapters", "garamon_cpu_threaded_packed.jl"))
using Garamon

@testset "four-thread packed CPU correction" begin
    @test Threads.nthreads() == 4
    config = load_config(joinpath(@__DIR__, "..", "config",
        "cpu_threaded_packed_oracle_preflight.toml"))
    @test length(expand_cases(config)) == 4
    mktempdir() do temporary
        output = joinpath(temporary, "cpu-packed")
        @test run_resumable_campaign(config; output) == output
        @test resumable_status(config, output)["status"] == "complete"
        @test run_resumable_campaign(config; output) == output
        @test audit_resumable_archive(config, output)["archive_integrity"] == "validated"
        for case in expand_cases(config)
            verdict = TOML.parsefile(joinpath(output, "cases", case_id(case),
                "verdict.toml"))
            @test verdict["oracle_passed"]
            @test verdict["samples_collected"] == 0
        end
    end
    ga = algebra(Int64[1 0; 0 1])
    a = basisvector(ga, 1; storage=:sparse)
    plan = prepare_product(a, a)
    batch = pack_product_batch(plan, [a], [a])
    resident = cpu_resident_batch(batch)
    @test cpu_run_serial!(resident)[1,1] == 1
    metric(ga)[1,1] = 2
    @test_throws ArgumentError cpu_run_serial!(resident)
    @test_throws ArgumentError cpu_run_threaded!(resident)
end
