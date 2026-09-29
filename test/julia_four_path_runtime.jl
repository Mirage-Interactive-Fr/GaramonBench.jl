# Target-dependent vector-product preflight; separate from the harness-only suite.
using Test, GaramonBench, TOML, Random
include(joinpath(@__DIR__,"..","adapters","garamon_julia.jl"))

@testset "four exact Julia vector paths across the UInt64 boundary" begin
    config=GaramonBench.load_config(joinpath(@__DIR__,"..","config",
        "julia_vectors_four_path_preflight.toml"))
    config["grid"]["horizon"]=[1]
    config["limits"]["max_cases"]=8
    config["limits"]["samples"]=1
    cases=GaramonBench.expand_cases(config)
    @test length(cases)==8
    adapter=GaramonBench.ADAPTERS["garamon_julia"]
    for dimension in (3,65)
        group=filter(case->case["dimension"]==dimension,cases)
        fixtures=[adapter.generate(case,"",Xoshiro(case["seed"])) for case in group]
        first_fixture=first(fixtures)
        @test all(f->f.coefficients==first_fixture.coefficients &&
            f.diagonal==first_fixture.diagonal &&
            f.masks==first_fixture.masks &&
            f.output_masks==first_fixture.output_masks &&
            f.expected==first_fixture.expected,fixtures)
    end
    mktempdir() do temporary
        output=joinpath(temporary,"campaign")
        @test GaramonBench.run_resumable_campaign(config;output)==output
        @test GaramonBench.resumable_status(config,output)["status"]=="complete"
        @test Set(case["strategy"] for case in cases)==
            Set(["direct","prepared","workspace","packed"])
        for case in cases
            verdict=TOML.parsefile(joinpath(output,"cases",GaramonBench.case_id(case),
                "verdict.toml"))
            @test verdict["oracle_passed"]
            @test verdict["perfchecker_verdict"]=="validated"
        end
        markers=Dict(GaramonBench.case_id(case)=>mtime(joinpath(output,"cases",
            GaramonBench.case_id(case),"completion.toml")) for case in cases)
        @test GaramonBench.run_resumable_campaign(config;output)==output
        @test all(mtime(joinpath(output,"cases",id,"completion.toml"))==before
            for (id,before) in markers)
    end
end
