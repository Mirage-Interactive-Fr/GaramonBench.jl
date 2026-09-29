# Exact selected-output preflight for all seven binary-product operations.
using Test, GaramonBench, TOML
include(joinpath(@__DIR__,"..","adapters","garamon_target_coefficient.jl"))

@testset "independent targeted coefficient oracle and resume" begin
    config=load_config(joinpath(@__DIR__,"..","config",
        "target_coefficient_oracle_preflight.toml"))
    config["grid"]["dimension"]=[2,65,129]
    config["grid"]["signature"]=["mixed","degenerate"]
    config["grid"]["horizon"]=[1]
    config["limits"]["max_cases"]=84
    cases=expand_cases(config)
    @test length(cases)==84
    mktempdir() do temporary
        output=joinpath(temporary,"target-coefficient")
        @test run_resumable_campaign(config;output)==output
        @test resumable_status(config,output)["status"]=="complete"
        for case in cases
            directory=joinpath(output,"cases",case_id(case))
            verdict=TOML.parsefile(joinpath(directory,"verdict.toml"))
            @test verdict["oracle_passed"]
            @test verdict["benchmark_backend"]=="oracle_preflight"
            @test !ispath(joinpath(directory,"samples.csv"))
        end
        @test run_resumable_campaign(config;output)==output
        audit=audit_resumable_archive(config,output)
        @test audit["archive_integrity"]=="validated"
        @test length(audit["completed_ids"])==84
    end
end
