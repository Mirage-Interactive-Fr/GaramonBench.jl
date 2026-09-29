using Test, GaramonBench, TOML
include(joinpath(@__DIR__,"..","adapters","garamon_coordinate_subspace.jl"))
using Garamon

@testset "active coordinate subspace short exact preflight" begin
    config=load_config(joinpath(@__DIR__,"..","config",
        "coordinate_subspace_oracle_preflight.toml"))
    cases=expand_cases(config)
    @test length(cases)==4
    @test all(case["dimension"] in (4,65) for case in cases)
    @test all(case["operation"] in ("geometric","wedge") for case in cases)
    mktempdir() do temporary
        output=joinpath(temporary,"coordinate-subspace")
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
        @test length(audit["completed_ids"])==4
    end
    fixture=cs_generate(first(cases),nothing,MersenneTwister(1))
    state=cs_prepare(fixture,first(cases),nothing)
    outside=basisvector(state.ga,2;storage=:sparse)
    @test_throws ArgumentError project_subspace(state.plan,outside)
    @test_throws ArgumentError subspace_product(state.plan,outside,state.b)
end
