# Explicit target-dependent integration check. Run only in an allocated CPU slot.
# No timed benchmark or profiler is run. This requires the private Garamon checkout.
using Test, GaramonBench, TOML
@testset "profiling worker project, target LOAD_PATH, exact oracle and catalog serialization" begin
    plan=profile_plan(joinpath(@__DIR__,"..","config","profiling.toml"))
    mktempdir() do temporary
        request=joinpath(temporary,"request.toml");response=joinpath(temporary,"response.toml")
        GaramonBench.write_toml(request,Dict("source"=>joinpath(@__DIR__,"..","adapters","profiling","julia_products.jl"),"case"=>plan["case"]))
        code=raw"""
        using TOML, BenchmarkTools
        data=TOML.parsefile(ARGS[1]);owner=Module(:ProfilingWorkerProbe)
        Base.include(owner,data["source"])
        scenario=Base.invokelatest(getfield(owner,:make_case),Dict("case"=>data["case"]))
        state=Base.invokelatest(scenario.prepare)
        result=Base.invokelatest(scenario.operation,state)
        valid=Base.invokelatest(scenario.verify,state,result)
        Base.invokelatest(scenario.cleanup,state)
        evidence=Dict("oracle_passed"=>valid,"target_source"=>pathof(getfield(owner,:Garamon)),
            "active_project"=>Base.active_project(),"benchmarktools_loaded"=>true,
            "controller_loaded"=>any(nameof(m) in (:GaramonBench,:PerfChecker) for m in values(Base.loaded_modules)))
        open(io->TOML.print(io,evidence),ARGS[2],"w")
        """
        command=Cmd([first(Base.julia_cmd()),"--startup-file=no","--threads=1,0","--gcthreads=1",
            "--project="*plan["worker_project"],"-e",code,request,response])
        environment=GaramonBench.profile_environment(plan)
        environment["JULIA_LOAD_PATH"]=join(("@","@stdlib"),Sys.iswindows() ? ';' : ':')
        job=GaramonBench.recipe_supervise(addenv(command,environment),joinpath(temporary,"worker.txt"),temporary,
            plan["limits"],time()+plan["limits"]["job_seconds"])
        @test job["process_success"]
        if job["process_success"]
            evidence=TOML.parsefile(response)
            @test evidence["oracle_passed"]
            @test evidence["benchmarktools_loaded"]
            @test !evidence["controller_loaded"]
            @test realpath(evidence["active_project"])==realpath(joinpath(plan["worker_project"],"Project.toml"))
            @test realpath(evidence["target_source"])==realpath(joinpath(plan["julia_root"],"src","Garamon.jl"))
        end
    end
end

@testset "B1W profiling keeps preparation, hot work and owned episode distinct" begin
    owner=Module(:B1WProfilingProbe)
    Base.include(owner,joinpath(@__DIR__,"..","adapters","profiling","bounds_b1w.jl"))
    factory=getfield(owner,:make_case)
    for phase in ("build","hot","episode"),strategy in ("workspace_native","workspace_native_singlepass")
        case=Dict{String,Any}("adapter"=>"bounds_b1w","dimension"=>8,
            "family"=>"low_grade","signature"=>"positive","strategy"=>strategy,
            "phase"=>phase,"horizon"=>32)
        scenario=Base.invokelatest(factory,Dict("case"=>case,"episode_repetitions"=>2))
        state=Base.invokelatest(scenario.prepare)
        results=Base.invokelatest(scenario.operation,state)
        @test length(results)==2
        @test Base.invokelatest(scenario.verify,state,results)
        if phase=="episode"
            @test length(results[1])==32
            @test all(results[1][i].values==state.fixture.expected[mod1(i,4)] for i in 1:32)
            @test results[1][1].values !== results[1][2].values
            results[1][1].values[zero(UInt64)]=123.0
            @test !Base.invokelatest(scenario.verify,state,results)
        end
    end
end

@testset "CPU episode owns and verifies every repeated output" begin
    plan=profile_plan(joinpath(@__DIR__,"..","config","profiling_smoke.toml"))
    owner=Module(:ProfilingEpisodeProbe)
    Base.include(owner,joinpath(@__DIR__,"..","adapters","profiling","julia_products.jl"))
    factory=getfield(owner,:make_case)
    scenario=Base.invokelatest(factory,Dict("case"=>plan["case"],"episode_repetitions"=>3))
    state=Base.invokelatest(scenario.prepare)
    results=Base.invokelatest(scenario.operation,state)
    @test length(results)==3
    @test all(result->result==state.fixture.expected,results)
    @test all(results[i] !== results[j] for i in 1:3 for j in i+1:3)
    @test Base.invokelatest(scenario.verify,state,results)
    results[2][1,1]+=1
    @test !Base.invokelatest(scenario.verify,state,results)
    @test_throws ErrorException Base.invokelatest(factory,Dict("case"=>plan["case"],"episode_repetitions"=>4097))
end

@testset "ID14 PerfChecker executes the oracle-preflight adapter callback" begin
    config=TOML.parsefile(joinpath(@__DIR__,"..","config","profiling_smoke.toml"))
    config["profiling"]["case_config"]=abspath(joinpath(@__DIR__,"..","config",
        "generated_product_oracle_preflight.toml"))
    config["profiling"]["worker_project"]=abspath(joinpath(@__DIR__,"..","worker"))
    config["select"]=Dict("dimension"=>3,"signature"=>"mixed",
        "strategy"=>"generated","horizon"=>1)
    plan=profile_plan(config)
    @test plan["case"]["adapter"]=="garamon_generated_product"
    catalog=GaramonBench.profile_catalog(plan,["benchmark"])
    spec=only(catalog.scenarios)
    @test spec.id==plan["case_id"]
    @test basename(spec.source)=="benchmark_adapter.jl"
    @test Set(basename.(spec.fixtures))==Set(["garamon_generated_product.jl",
        "julia_products_kernels.jl"])
    owner=Module(:GeneratedProductProfilingProbe)
    Base.include(owner,spec.source)
    scenario=Base.invokelatest(getfield(owner,:make_case),spec.parameters)
    adapter=GaramonBench.ADAPTERS["garamon_generated_product"]
    @test scenario.adapter_execute===adapter.execute
    @test GaramonBench.run_case_preflight(adapter,plan["case"],Dict("case_seconds"=>30))["oracle_passed"]
    prepared=Base.invokelatest(scenario.prepare)
    try
        result=Base.invokelatest(scenario.operation,prepared)
        @test Base.invokelatest(scenario.verify,prepared,result)
        @test result==Base.invokelatest(adapter.execute,prepared.state)
    finally
        Base.invokelatest(scenario.cleanup,prepared)
    end
    @test !ispath(prepared.directory)
    withenv(GaramonBench.profile_environment(plan)...) do
        mktempdir() do reports
            bundles=GaramonBench.PerfChecker.run_scenarios(catalog;
                project=plan["worker_project"],samples=1,timeout=60,threads=1,reports)
            bundle=only(bundles)
            @test bundle.manifest["scenario"]["id"]==plan["case_id"]
            @test bundle.manifest["qualification"]["correctness"]=="passed"
            @test bundle.manifest["qualification"]["availability"]=="complete"
            @test length(bundle.manifest["scenario_evidence"]["samples"])==1
        end
    end
end
