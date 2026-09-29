using Test, GaramonBench, TOML
include(joinpath(@__DIR__, "..", "adapters", "garamon_blade_index.jl"))
using Garamon

@testset "combinatorial blade index preflight" begin
    config = load_config(joinpath(@__DIR__, "..", "config",
        "blade_index_oracle_preflight.toml"))
    @test length(expand_cases(config)) == 56
    config["grid"]["dimension"] = [2, 64, 65, 128, 129]
    config["grid"]["horizon"] = [1, 32]
    config["limits"]["max_cases"] = 20
    cases = expand_cases(config)
    @test length(cases) == 20
    mktempdir() do temporary
        output = joinpath(temporary, "blade-index")
        @test run_resumable_campaign(config; output) == output
        @test resumable_status(config, output)["status"] == "complete"
        for case in cases
            verdict = TOML.parsefile(joinpath(output, "cases", case_id(case),
                "verdict.toml"))
            @test verdict["oracle_passed"]
            @test verdict["samples_collected"] == 0
        end
        @test run_resumable_campaign(config; output) == output
        audit = audit_resumable_archive(config, output)
        @test audit["archive_integrity"] == "validated"
        @test length(audit["completed_ids"]) == 20
    end
    for n in (64, 65, 128, 129)
        ga = algebra(n, :ega)
        @test blade_rank(ga, big(1) << (n-1)) == (1, big(n-1))
        @test BigInt(blade_unrank(ga, 1, n-1)) == big(1) << (n-1)
        @test_throws BoundsError blade_rank(ga, big(1) << n)
        @test_throws BoundsError blade_unrank(ga, 1, n)
    end
end
