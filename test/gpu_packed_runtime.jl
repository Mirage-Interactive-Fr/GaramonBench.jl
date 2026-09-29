# Target-dependent GPU preflight. This is intentionally separate from Pkg.test.
using Test, GaramonBench, CUDA, TOML
include(joinpath(@__DIR__,"..","adapters","garamon_gpu_packed.jl"))

@testset "same exact CPU/GPU cases and resumable CUPTI evidence" begin
    @test CUDA.functional()
    config=GaramonBench.load_config(
        joinpath(@__DIR__,"..","config","gpu_packed_preflight_smoke.toml"))
    config["grid"]["dimension"]=[8]
    config["grid"]["horizon"]=[1]
    config["limits"]["max_cases"]=2
    cases=GaramonBench.expand_cases(config)
    @test length(cases)==2
    mktempdir() do temporary
        output=joinpath(temporary,"campaign")
        @test GaramonBench.run_resumable_campaign(config;output)==output
        @test GaramonBench.resumable_status(config,output)["status"]=="complete"
        gpu=only(filter(c->c["strategy"]=="gpu_host_owned",cases))
        directory=joinpath(output,"cases",GaramonBench.case_id(gpu))
        verdict=TOML.parsefile(joinpath(directory,"verdict.toml"))
        @test verdict["oracle_passed"]
        @test verdict["diagnostics"]["status"]=="captured_and_oracle_checked"
        @test length(verdict["diagnostics"]["phases"])==3
        marker=TOML.parsefile(joinpath(directory,"completion.toml"))
        @test length(marker["diagnostic_artifacts"])==3
        traces=[joinpath(directory,item["path"]) for item in marker["diagnostic_artifacts"]]
        @test all(path->occursin("Device-side activity",read(path,String)),traces)
        before=mtime(joinpath(directory,"completion.toml"))
        @test GaramonBench.run_resumable_campaign(config;output)==output
        @test mtime(joinpath(directory,"completion.toml"))==before
        open(first(traces),"a") do io
            print(io,"tampered")
        end
        @test_throws ErrorException GaramonBench.run_resumable_campaign(config;output)
    end
end
