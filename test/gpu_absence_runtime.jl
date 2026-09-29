# Launch with CUDA_VISIBLE_DEVICES=-1 under --project=gpu. The CPU route stays
# usable and the GPU route is explicitly refused before an experiment can pass.
using Test, GaramonBench, CUDA
include(joinpath(@__DIR__,"..","adapters","garamon_gpu_packed.jl"))

@testset "GPU-unavailable contract is explicit" begin
    @test !CUDA.functional()
    config=GaramonBench.load_config(joinpath(@__DIR__,"..","config","gpu_packed_preflight_smoke.toml"))
    cases=GaramonBench.expand_cases(config)
    cpu=only(filter(c->c["dimension"]==8 && c["horizon"]==1 &&
        c["strategy"]=="cpu_packed",cases))
    gpu=only(filter(c->c["dimension"]==8 && c["horizon"]==1 &&
        c["strategy"]=="gpu_host_owned",cases))
    adapter=getfield(GaramonBench,:ADAPTERS)["gpu_packed_exact"]
    rows,verdict=GaramonBench.run_case_perfchecker(adapter,cpu,config["limits"])
    @test verdict["oracle_passed"]
    @test verdict["perfchecker_verdict"]=="validated"
    @test count(r->r.phase=="warm",rows)==config["limits"]["samples"]
    @test_throws ErrorException GaramonBench.run_case_perfchecker(adapter,gpu,config["limits"])
end
