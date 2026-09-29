using Test, GaramonBench, TOML
include(joinpath(@__DIR__, "..", "adapters", "garamon_exact_tensor_train.jl"))
using Garamon

@testset "exact tensor-train one-case preflight" begin
    config = load_config(joinpath(@__DIR__, "..", "config",
        "exact_tensor_train_oracle_preflight.toml"))
    cases = expand_cases(config)
    @test length(cases) == 1
    @test cases[1]["dimension"] == 4
    mktempdir() do temporary
        output = joinpath(temporary, "tensor-train")
        @test run_resumable_campaign(config; output) == output
        @test resumable_status(config, output)["status"] == "complete"
        verdict = TOML.parsefile(joinpath(output, "cases", case_id(only(cases)), "verdict.toml"))
        @test verdict["oracle_passed"]
        @test verdict["benchmark_backend"] == "oracle_preflight"
        @test !ispath(joinpath(output, "cases", case_id(only(cases)), "samples.csv"))
        @test audit_resumable_archive(config, output)["archive_integrity"] == "validated"
    end
    fixture = tt19_generate(only(cases), nothing, nothing)
    state = tt19_prepare(fixture, only(cases), nothing)
    @test tt19_execute(state) == fixture.expected
    @test length(fixture.expected) == 16
    @test_throws ArgumentError train_product(state.left, state.right; max_rank=1)
    @test_throws ArgumentError train_product(state.left, state.right; max_entries=1)
end
