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
    mktempdir() do depot
        cache=lifecycle_cache_info(depot)
        state=(code_precompiled=true,package_loaded=true,method_ready=true,
            cache_before_load=cache,cache_after_load=cache,
            environment=(;depot),expected=[1.0])
        @test pc15_oracle(state,[1.0])
        mkpath(joinpath(depot,"compiled"))
        write(joinpath(depot,"compiled","probe.ji"),"changed cache")
        @test !pc15_oracle(state,[1.0])
    end
    mktempdir() do temporary
        @test_throws ErrorException lifecycle_environment(joinpath(temporary,"incomplete"),true;
            dependency_manifest=joinpath(@__DIR__,"..","worker","Manifest.toml"))
        environment=lifecycle_environment(joinpath(temporary,"complete"),true;
            dependency_manifest=joinpath(@__DIR__,"..","Manifest.toml"))
        manifest=TOML.parsefile(joinpath(environment.package,"Manifest.toml"))
        @test length(manifest["deps"]["DelimitedFiles"])==1
        @test only(manifest["deps"]["Garamon"])["path"]==LIFECYCLE_ROOT
    end
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
