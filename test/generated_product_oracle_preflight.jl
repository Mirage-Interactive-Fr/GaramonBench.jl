using Test, GaramonBench, TOML
include(joinpath(@__DIR__, "..", "adapters", "garamon_generated_product.jl"))
using Garamon

@testset "bounded generated product preflight" begin
    config = load_config(joinpath(@__DIR__, "..", "config",
        "generated_product_oracle_preflight.toml"))
    @test length(expand_cases(config)) == 120
    config["grid"]["dimension"] = [2, 8, 16]
    config["grid"]["signature"] = ["mixed", "degenerate"]
    config["limits"]["max_cases"] = 24
    cases = expand_cases(config)
    @test length(cases) == 24
    mktempdir() do temporary
        output = joinpath(temporary, "generated")
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
        @test length(audit["completed_ids"]) == 24
    end
    ga = algebra(17, :ega)
    terms = Dict(UInt64(1) << (i-1) => Float64(i) for i in 1:17)
    vector = multivector(ga, terms; storage=:sparse)
    plan = prepare_product(vector, vector; max_paths=300)
    @test length(plan.paths) == 289
    @test_throws ArgumentError generate_product(plan; max_paths=256)
end
