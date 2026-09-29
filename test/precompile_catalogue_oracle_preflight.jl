using Test, GaramonBench, TOML
include(joinpath(@__DIR__, "..", "adapters", "garamon_precompile_catalogue.jl"))

@testset "precompilation catalogue one-case exact preflight" begin
    config = load_config(joinpath(@__DIR__, "..", "config",
        "precompile_catalogue_oracle_preflight.toml"))
    cases = expand_cases(config)
    @test length(cases) == 1
    @test only(cases)["dimension"] == 3
    @test only(cases)["scenario"] == "known"
    @test only(cases)["strategy"] == "generated"
    mktempdir() do temporary
        output = joinpath(temporary, "precompile-catalogue")
        @test run_resumable_campaign(config; output) == output
        @test resumable_status(config, output)["status"] == "complete"
        directory = joinpath(output, "cases", case_id(only(cases)))
        verdict = TOML.parsefile(joinpath(directory, "verdict.toml"))
        @test verdict["oracle_passed"]
        @test verdict["benchmark_backend"] == "oracle_preflight"
        @test verdict["execution_count"] == 2
        @test !ispath(joinpath(directory, "samples.csv"))
        @test audit_resumable_archive(config, output)["archive_integrity"] == "validated"
    end
end
