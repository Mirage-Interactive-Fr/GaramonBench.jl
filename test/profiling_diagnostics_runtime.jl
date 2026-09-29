# Explicit target-dependent diagnostic preflight. Tool findings may be nonempty;
# this test checks execution and exact-case identity, not a speed verdict.
using Test, GaramonBench, TOML

@testset "PerfChecker JET and AllocCheck execute on the exact case" begin
    plan=GaramonBench.profile_plan(joinpath(@__DIR__,"..","config","profiling_diagnostics_smoke.toml"))
    @test all(c->c["status"]=="implemented_not_runtime_probed",plan["capabilities"])
    mktempdir() do temporary
        output=GaramonBench.profile_capture(
            joinpath(@__DIR__,"..","config","profiling_diagnostics_smoke.toml");
            output=joinpath(temporary,"capture"))
        metadata=TOML.parsefile(joinpath(output,"capture.toml"))
        @test metadata["case_id"]==plan["case_id"]
        @test metadata["status"]=="captured_review_native_statuses"
        @test metadata["source_unchanged"]
        records=TOML.parsefile(joinpath(output,"measurements","capture-results.toml"))["records"]
        @test Set(r["name"] for r in records)==Set(["benchmark","jet","alloccheck"])
        @test all(r->r["status"]=="complete",records)
        @test all(isfile(joinpath(output,"measurements","diagnostic-"*name,"diagnosis.json"))
                  for name in ("jet","alloccheck"))
    end
end
