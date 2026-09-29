# Explicit integration preflight: runs the exact Garamon operation through
# PerfChecker FeatureSpec, archives the wall profile, and checks its oracle.
using Test, GaramonBench, TOML

config=TOML.parsefile(joinpath(@__DIR__,"..","config","profiling.toml"))
config["profiling"]["case_config"]=abspath(joinpath(@__DIR__,"..","config","julia_products.toml"))
config["profiling"]["worker_project"]=abspath(joinpath(@__DIR__,"..","worker"))
config["profiling"]["collectors"]=["wall_profile"]
config["profiling"]["diagnostics"]=String[]
config["profiling"]["type_stability"]=false

@testset "wall profile of the same exact case survives archive" begin
    mktempdir() do temporary
        output=GaramonBench.profile_capture(config;output=joinpath(temporary,"capture"))
        metadata=TOML.parsefile(joinpath(output,"capture.toml"))
        @test metadata["status"]=="captured_review_native_statuses"
        @test metadata["source_unchanged"]
        records=TOML.parsefile(joinpath(output,"measurements","capture-results.toml"))["records"]
        @test length(records)==1
        @test only(records)["name"]=="wall_profile"
        @test only(records)["status"]=="complete"
        @test only(records)["verdict"]=="validated"
        @test only(records)["stack_samples"]>0
        directory=joinpath(output,"measurements","collector-wall_profile")
        @test isfile(joinpath(directory,"wall-suite.json"))
        @test isfile(joinpath(directory,"wall-case.toml"))
        @test isfile(joinpath(directory,"wall-feature.txt"))
        @test !isempty(read(joinpath(directory,"stacks.folded"),String))
    end
end
