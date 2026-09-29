using Test, GaramonBench, TOML
include(joinpath(@__DIR__, "..", "adapters", "garamon_dense_global.jl"))
using Garamon

@testset "dense-global and sparse all-mask preflight" begin
    config = load_config(joinpath(@__DIR__, "..", "config",
        "dense_global_oracle_preflight.toml"))
    @test length(expand_cases(config)) == 264
    config["grid"]["dimension"] = [2, 6, 12]
    config["grid"]["signature"] = ["mixed"]
    config["limits"]["max_cases"] = 24
    cases = expand_cases(config)
    @test length(cases) == 24
    mktempdir() do temporary
        output = joinpath(temporary, "dense-global")
        @test run_resumable_campaign(config; output) == output
        @test resumable_status(config, output)["status"] == "complete"
        for case in cases
            verdict = TOML.parsefile(joinpath(output, "cases", case_id(case),
                "verdict.toml"))
            @test verdict["oracle_passed"]
            @test verdict["benchmark_backend"] == "oracle_preflight"
            @test !ispath(joinpath(output, "cases", case_id(case), "samples.csv"))
        end
        @test run_resumable_campaign(config; output) == output
        audit = audit_resumable_archive(config, output)
        @test audit["archive_integrity"] == "validated"
        @test length(audit["completed_ids"]) == 24
    end
    ga = algebra(12, :ega)
    @test_throws ArgumentError dense(scalar(ga, 1; storage=:sparse);
        max_coefficients=1000)
    @test_throws ArgumentError multivector(algebra(21, :ega),
        Dict(UInt64(0)=>1.0); storage=:dense)
end
