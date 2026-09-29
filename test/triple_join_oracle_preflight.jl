# Correctness-only target test. It does not invoke BenchmarkTools or PerfChecker.
using Test, GaramonBench, TOML
include(joinpath(@__DIR__,"..","adapters","garamon_triple_join.jl"))

@testset "independent triple-join oracle and resume" begin
    config=load_config(joinpath(@__DIR__,"..","config",
        "triple_join_oracle_preflight.toml"))
    config["grid"]["dimension"]=[2,65,129]
    config["grid"]["horizon"]=[1]
    config["limits"]["max_cases"]=45
    cases=expand_cases(config)
    @test length(cases)==45
    mktempdir() do temporary
        output=joinpath(temporary,"triple-join")
        @test run_resumable_campaign(config;output)==output
        @test resumable_status(config,output)["status"]=="complete"
        for case in cases
            directory=joinpath(output,"cases",case_id(case))
            verdict=TOML.parsefile(joinpath(directory,"verdict.toml"))
            @test verdict["oracle_passed"]
            @test verdict["benchmark_backend"]=="oracle_preflight"
            @test !ispath(joinpath(directory,"samples.csv"))
        end
        markers=Dict(case_id(case)=>mtime(joinpath(output,"cases",case_id(case),
            "completion.toml")) for case in cases)
        @test run_resumable_campaign(config;output)==output
        @test all(mtime(joinpath(output,"cases",id,"completion.toml"))==timestamp
            for (id,timestamp) in markers)
        audit=audit_resumable_archive(config,output)
        @test audit["archive_integrity"]=="validated"
        @test length(audit["completed_ids"])==45
    end
end
