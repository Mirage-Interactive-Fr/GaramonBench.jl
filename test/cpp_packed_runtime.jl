# Target-dependent matched C++/Julia preflight; intentionally separate from Pkg.test.
using Test, GaramonBench, TOML
include(joinpath(@__DIR__,"..","adapters","garamon_cpp_packed.jl"))

@testset "exact matched packed C++ and Julia with resumable evidence" begin
    config=GaramonBench.load_config(
        joinpath(@__DIR__,"..","config","cpp_packed_preflight_smoke.toml"))
    config["grid"]["dimension"]=[3]
    config["grid"]["horizon"]=[1]
    config["limits"]["max_cases"]=2
    config["limits"]["samples"]=1
    cases=GaramonBench.expand_cases(config)
    @test length(cases)==2
    mktempdir() do temporary
        output=joinpath(temporary,"campaign")
        @test GaramonBench.run_resumable_campaign(config;output)==output
        @test GaramonBench.resumable_status(config,output)["status"]=="complete"
        for case in cases
            directory=joinpath(output,"cases",GaramonBench.case_id(case))
            verdict=TOML.parsefile(joinpath(directory,"verdict.toml"))
            @test verdict["oracle_passed"]
            @test verdict["perfchecker_verdict"]=="validated"
            @test verdict["adapter_capabilities"]["comparison_group"]=="matched_packed_paths_v1"
        end
        cpp=only(filter(c->c["strategy"]=="cpp_packed",cases))
        directory=joinpath(output,"cases",GaramonBench.case_id(cpp))
        verdict=TOML.parsefile(joinpath(directory,"verdict.toml"))
        @test verdict["diagnostics"]["status"]=="matched_packed_library_built_and_oracle_checked"
        marker=TOML.parsefile(joinpath(directory,"completion.toml"))
        @test length(marker["diagnostic_artifacts"])==1
        log=joinpath(directory,only(marker["diagnostic_artifacts"])["path"])
        @test occursin("garamon_packed",read(log,String))
        @test !any(endswith(name,".so") for (root,_,files) in walkdir(output) for name in files)
        before=Dict(GaramonBench.case_id(c)=>mtime(joinpath(output,"cases",
            GaramonBench.case_id(c),"completion.toml")) for c in cases)
        @test GaramonBench.run_resumable_campaign(config;output)==output
        @test all(mtime(joinpath(output,"cases",id,"completion.toml"))==timestamp
            for (id,timestamp) in before)
        audit=GaramonBench.audit_resumable_archive(config,output)
        @test audit["archive_integrity"]=="validated"
        @test length(audit["completed_ids"])==2
        open(log,"a") do io
            print(io,"altered")
        end
        @test_throws ErrorException GaramonBench.run_resumable_campaign(config;output)
    end
end
