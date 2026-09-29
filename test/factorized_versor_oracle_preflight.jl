using Test, GaramonBench, TOML
include(joinpath(@__DIR__, "..", "adapters", "garamon_factorized_versor.jl"))
using Garamon

@testset "factorized-versor one-case exact preflight" begin
    config = load_config(joinpath(@__DIR__, "..", "config",
        "factorized_versor_oracle_preflight.toml"))
    cases = expand_cases(config)
    @test length(cases) == 1
    @test cases[1]["dimension"] == 4
    mktempdir() do temporary
        output = joinpath(temporary, "factorized-versor")
        @test run_resumable_campaign(config; output) == output
        @test resumable_status(config, output)["status"] == "complete"
        verdict = TOML.parsefile(joinpath(output, "cases", case_id(only(cases)), "verdict.toml"))
        @test verdict["oracle_passed"]
        @test verdict["benchmark_backend"] == "oracle_preflight"
        @test !ispath(joinpath(output, "cases", case_id(only(cases)), "samples.csv"))
        @test audit_resumable_archive(config, output)["archive_integrity"] == "validated"
    end
    fixture = fv17_generate(only(cases), nothing, nothing)
    state = fv17_prepare(fixture, only(cases), nothing)
    @test fv17_execute(state) == fixture.expected
    @test length(fixture.expected) == 6
end
