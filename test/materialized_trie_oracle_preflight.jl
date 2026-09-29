using Test, GaramonBench, TOML
include(joinpath(@__DIR__, "..", "adapters", "garamon_materialized_trie.jl"))
using Garamon

@testset "materialized trie one-case exact preflight" begin
    config = load_config(joinpath(@__DIR__, "..", "config",
        "materialized_trie_oracle_preflight.toml"))
    cases = expand_cases(config)
    @test length(cases) == 1
    @test only(cases)["dimension"] == 6
    @test only(cases)["operation"] == "wedge"
    mktempdir() do temporary
        output = joinpath(temporary, "materialized-trie")
        @test run_resumable_campaign(config; output) == output
        @test resumable_status(config, output)["status"] == "complete"
        directory = joinpath(output, "cases", case_id(only(cases)))
        verdict = TOML.parsefile(joinpath(directory, "verdict.toml"))
        @test verdict["oracle_passed"]
        @test verdict["benchmark_backend"] == "oracle_preflight"
        @test !ispath(joinpath(directory, "samples.csv"))
        @test audit_resumable_archive(config, output)["archive_integrity"] == "validated"
    end
    fixture = mt21_generate(only(cases), nothing, nothing)
    state = mt21_prepare(fixture, only(cases), nothing)
    @test mt21_execute(state) == fixture.expected
    @test count_nodes(state.left_trie) > length(fixture.left)
    @test last(wedge_visits(state.left_trie, state.right_trie, 0, fixture.n)) > 0
end
