# Targeted configuration/archival tests. No Garamon target load or scientific run.
using Test, GaramonBench, TOML
@testset "profiling exact identity, explicit availability and budgets" begin
    path=joinpath(@__DIR__,"..","config","profiling.toml")
    plan=profile_plan(path)
    cases=expand_cases(load_config(plan["case_configuration"]))
    @test plan["case_id"] in case_id.(cases)
    @test plan["case"]["dimension"]==3 && plan["case"]["strategy"]=="workspace" && plan["case"]["horizon"]==32
    @test plan["status"]=="static_plan_not_runtime_qualification"
    @test !plan["isolation_certified"]
    @test only(filter(c->c["name"]=="wall_profile",plan["capabilities"]))["status"]=="implemented_not_runtime_probed"
    @test only(filter(c->c["name"]=="wall_profile",plan["capabilities"]))["interface"]=="FeatureSpec/run_suite"
    @test haskey(plan["perfchecker_api_sources"],"scenarios.jl")
    @test Set(keys(GaramonBench.profile_environment(plan)))==Set(["GARAMON_JULIA_ROOT","GARAMONBENCH_CONDITION",
        "GARAMONBENCH_INTERFERENCE_LABEL","JULIA_PKG_OFFLINE","JULIA_PKG_PRECOMPILE_AUTO","OPENBLAS_NUM_THREADS","OMP_NUM_THREADS"])
    catalog=GaramonBench.profile_catalog(plan,["benchmark","profile","profile_alloc"])
    @test only(catalog.scenarios).id==plan["case_id"]
    @test only(catalog.scenarios).parameters["case"]==plan["case"]
    @test only(catalog.scenarios).parameters["episode_repetitions"]==1
    grouped=GaramonBench.profile_catalog(plan,["profile"];episode_repetitions=256)
    @test only(grouped.scenarios).parameters["episode_repetitions"]==256
    @test isfile(only(only(catalog.scenarios).fixtures))
    serialized=TOML.parse(GaramonBench.canonical_toml(GaramonBench.PerfChecker.scenario_catalog_dict(catalog)))
    @test only(serialized["scenarios"])["parameters"]["case"]==plan["case"]
    @test TOML.parse(GaramonBench.canonical_toml(plan))["case_id"]==plan["case_id"]
    @test plan["worker_project"]==abspath(joinpath(@__DIR__,"..","worker"))
    for name in ("jet","alloccheck")
        @test only(filter(c->c["name"]==name,plan["capabilities"]))["status"]=="implemented_not_runtime_probed"
    end
    @test GaramonBench.profile_environment(plan)["GARAMON_JULIA_ROOT"]==plan["julia_root"]
    @test_throws ArgumentError GaramonBench.profile_catalog(plan,["wall_profile"])
    config=TOML.parsefile(path)
    config["profiling"]["case_config"]=plan["case_configuration"]
    config["profiling"]["worker_project"]=plan["worker_project"]
    exact=deepcopy(config);delete!(exact,"select");exact["profiling"]["case_id"]=plan["case_id"]
    @test profile_plan(exact)["case_id"]==plan["case_id"]
    for modify in (
        c->(c["select"]["dimension"]=999),
        c->delete!(c["select"],"horizon"),
        c->(c["profiling"]["case_id"]=plan["case_id"]),
        c->(c["profiling"]["collectors"]=["made_up"]),
        c->(c["profiling"]["diagnostics"]=["snoopcompile"]),
        c->(c["limits"]["threads"]=5),
        c->(c["limits"]["samples"]=true),
        c->(c["limits"]["profile_episode_repetitions"]=4097),
        c->(c["limits"]["total_seconds"]=1),
        c->(c["limits"]["unknown"]=1))
        changed=deepcopy(config);modify(changed)
        @test_throws ErrorException profile_plan(changed)
    end
    mktempdir() do temporary
        cp(plan["case_configuration"],joinpath(temporary,"cases.toml"))
        native=TOML.parsefile(joinpath(temporary,"cases.toml"))
        native["campaign"]["condition"]="isolated";native["campaign"]["interference_label"]="Etendue3D"
        open(io->TOML.print(io,native),joinpath(temporary,"cases.toml"),"w")
        changed=deepcopy(config);changed["profiling"]["case_config"]=joinpath(temporary,"cases.toml")
        isolated=profile_plan(changed)
        @test isolated["interference_label"]==""
        @test GaramonBench.profile_environment(isolated)["GARAMONBENCH_INTERFERENCE_LABEL"]==""
        # A cached source outside this worker's declared environment is insufficient.
        worker=joinpath(temporary,"worker");mkpath(worker)
        write(joinpath(worker,"Project.toml"),"[deps]\n")
        write(joinpath(worker,"Manifest.toml"),"[deps]\n")
        changed["profiling"]["worker_project"]=worker
        unavailable=profile_plan(changed)
        for name in ("jet","alloccheck","benchmark")
            @test only(filter(c->c["name"]==name,unavailable["capabilities"]))["status"]=="blocked_worker_manifest_dependency"
        end
    end
end
@testset "B1W profiling selects an exact fixture and its native source" begin
    plan=profile_plan(joinpath(@__DIR__,"..","config","profiling_b1w_episode_8d.toml"))
    @test plan["case"]["adapter"]=="bounds_b1w"
    @test plan["case"]["phase"]=="episode"
    @test plan["case"]["dimension"]==8
    @test plan["case"]["horizon"]==1024
    @test !plan["isolation_certified"]
    catalog=GaramonBench.profile_catalog(plan,["benchmark","profile_alloc"])
    scenario=only(catalog.scenarios)
    @test scenario.id==plan["case_id"]
    @test basename(scenario.source)=="bounds_b1w.jl"
    @test isempty(scenario.fixtures)
    @test only(filter(c->c["name"]=="profile_alloc",plan["capabilities"]))["status"]=="implemented_not_runtime_probed"
    @test TOML.parse(GaramonBench.canonical_toml(plan))["case"]["adapter"]=="bounds_b1w"
end
@testset "native RunBundle text formats survive archival with integrity" begin
    mktempdir() do root
        source=joinpath(root,"source");mkpath(source)
        bundle=GaramonBench.PerfChecker.RunBundle(
            Dict{String,Any}("schema_version"=>"perfchecker-run-bundle/1","run_id"=>"synthetic-archive-test"),
            Dict{String,Any}[],[Dict{String,Any}("metric"=>"synthetic","value"=>1)],
            [Dict{String,Any}("message"=>"synthetic diagnostic, no measurement")],Dict{String,Any}[])
        GaramonBench.PerfChecker.write_run_bundle(bundle,joinpath(source,"bundle"))
        archived=joinpath(root,"archived")
        records=GaramonBench.profile_archive_results(source,archived,1<<20)
        @test Set(basename(r["path"]) for r in records)==Set(["manifest.json","measurement-definitions.json",
            "observations.jsonl","diagnostics.jsonl","artifacts.json","integrity.json"])
        @test isdir(joinpath(archived,"bundle","artifacts"))
        restored=GaramonBench.PerfChecker.read_run_bundle(joinpath(archived,"bundle");require_integrity=true)
        @test restored.observations==bundle.observations
        @test restored.diagnostics==bundle.diagnostics
    end
end
@testset "profiling archive accepts stacks and refuses unsafe artifacts" begin
    mktempdir() do root
        source=joinpath(root,"source");mkpath(source)
        write(joinpath(source,"stacks.folded"),"root;operation 3\n")
        files=GaramonBench.profile_archive_results(source,joinpath(root,"ok"),1024)
        @test only(files)["path"]=="stacks.folded"
        @test_throws ErrorException GaramonBench.profile_archive_results(source,joinpath(root,"small"),1)
        heap=joinpath(source,"diagnostic-heap","artifacts","snapshot")
        mkpath(heap)
        write(joinpath(heap,"after-operation.heapsnapshot"),UInt8[0x00,0x01])
        write(joinpath(heap,"after-operation.heapsnapshot.edges"),UInt8[0x02,0x00])
        archived=GaramonBench.profile_archive_results(source,joinpath(root,"heap-ok"),1024)
        @test length(archived)==3
        @test read(joinpath(root,"heap-ok","diagnostic-heap","artifacts","snapshot",
            "after-operation.heapsnapshot.edges"))==UInt8[0x02,0x00]
        write(joinpath(source,"binary.so"),UInt8[0,1])
        @test_throws ErrorException GaramonBench.profile_archive_results(source,joinpath(root,"bad"),1024)
        rm(joinpath(source,"binary.so"))
        write(joinpath(source,"failure.txt"),"setenv(secret_environment)")
        @test_throws ErrorException GaramonBench.profile_archive_results(source,joinpath(root,"secret"),1024)
        rm(joinpath(source,"failure.txt"))
        write(joinpath(source,"diagnostics.jsonl"),"{\"message\":\"setenv(secret_environment)\"}\n")
        @test_throws ErrorException GaramonBench.profile_archive_results(source,joinpath(root,"secret-jsonl"),1024)
        write(joinpath(source,"diagnostics.jsonl"),UInt8[0xff,0xfe])
        @test_throws ErrorException GaramonBench.profile_archive_results(source,joinpath(root,"nontext"),1024)
    end
end
