# Exact homogeneous-grade preflight with independent mask arithmetic.
using Test, GaramonBench, TOML
include(joinpath(@__DIR__,"..","adapters","garamon_grade_product.jl"))
using Garamon

@testset "independent homogeneous-grade oracle and budgets" begin
    config=load_config(joinpath(@__DIR__,"..","config",
        "grade_product_oracle_preflight.toml"))
    config["grid"]["dimension"]=[2,65,129]
    config["grid"]["signature"]=["mixed","degenerate"]
    config["grid"]["horizon"]=[1]
    config["limits"]["max_cases"]=96
    cases=expand_cases(config)
    @test length(cases)==96
    for (n,K) in ((2,UInt64),(65,UInt128),(129,BigInt))
        case=first(filter(c->c["dimension"]==n,cases))
        fixture=gg_generate(case,"",MersenneTwister(20260928))
        @test eltype(fixture.targets)==K
        @test eltype(fixture.supports[1])==K
    end
    @test_throws ArgumentError prepare_grade_product(algebra(129,:ega),2,1;
        max_paths=1<<16)
    mktempdir() do temporary
        output=joinpath(temporary,"homogeneous-grade")
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
        @test length(audit["completed_ids"])==96
    end
end
