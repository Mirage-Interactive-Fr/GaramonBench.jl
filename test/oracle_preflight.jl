# Target-dependent, correctness-only campaign. No PerfChecker measurements.
using Test, GaramonBench, TOML
include(joinpath(@__DIR__,"..","adapters","garamon_julia.jl"))

@testset "resumable exact oracle preflight" begin
    config=load_config(joinpath(@__DIR__,"..","config",
        "julia_vectors_signature_oracle_preflight.toml"))
    config["grid"]["dimension"]=[2,3]
    config["grid"]["horizon"]=[1]
    config["limits"]["max_cases"]=24
    cases=expand_cases(config)
    @test length(cases)==24
    mktempdir() do temporary
        output=joinpath(temporary,"preflight")
        @test run_resumable_campaign(config;output)==output
        @test resumable_status(config,output)["status"]=="complete"
        for case in cases
            directory=joinpath(output,"cases",case_id(case))
            verdict=TOML.parsefile(joinpath(directory,"verdict.toml"))
            @test verdict["oracle_passed"]
            @test verdict["benchmark_backend"]=="oracle_preflight"
            @test verdict["execution_count"]==2
            @test !ispath(joinpath(directory,"samples.csv"))
        end
        markers=Dict(case_id(case)=>mtime(joinpath(output,"cases",case_id(case),
            "completion.toml")) for case in cases)
        @test run_resumable_campaign(config;output)==output
        @test all(mtime(joinpath(output,"cases",id,"completion.toml"))==timestamp
            for (id,timestamp) in markers)
        audit=audit_resumable_archive(config,output)
        @test audit["archive_integrity"]=="validated"
        @test length(audit["completed_ids"])==24
        first_case=joinpath(output,"cases",case_id(first(cases)),"verdict.toml")
        open(first_case,"a") do io
            println(io,"# changed")
        end
        @test_throws ErrorException run_resumable_campaign(config;output)
    end
end
