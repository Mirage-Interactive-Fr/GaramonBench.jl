using Test,GaramonBench,TOML,PerfChecker

# Functional integration only: no BenchmarkTools observation or benchmark worker
# entrypoint is executed. The temporary probe exists solely for the subprocess
# command contract and is deleted by mktempdir.
@testset "B1 real Julia option propagation, eight configurations" begin
    raw=TOML.parsefile(joinpath(@__DIR__,"..","config","bounds_b1.toml"))
    raw["compiler"]=Dict("check_bounds"=>["yes","auto"],"opt_levels"=>[2,3],"cpu_targets"=>["generic","native"])
    plan=b1_plan(raw)
    mktempdir() do temporary
        probe=joinpath(temporary,"options.jl")
        write(probe,"using TOML\no=Base.JLOptions()\nTOML.print(stdout,Dict(\"bounds\"=>Int(o.check_bounds),\"optimization\"=>Int(o.opt_level),\"cpu\"=>unsafe_string(o.cpu_target),\"pkgimages\"=>Int(o.use_pkgimages),\"threads\"=>Threads.nthreads(),\"version\"=>string(VERSION),\"condition\"=>ENV[\"GARAMONBENCH_CONDITION\"],\"label\"=>ENV[\"GARAMONBENCH_INTERFERENCE_LABEL\"]))\n")
        for job in plan["jobs"]
            original=GaramonBench.b1_command(plan,job,"/unused-request","/unused-output")
            argv=collect(original);argv[end-2]=probe
            command=Cmd(Cmd(argv);env=original.env)
            effective=TOML.parse(read(command,String))
            @test effective["bounds"]==(job["check_bounds"]=="yes" ? 1 : 0)
            @test effective["optimization"]==job["opt_level"]
            @test effective["cpu"]==job["cpu_target"]
            @test effective["pkgimages"]==0
            @test effective["threads"]==1
            @test startswith(effective["version"],"1.13.")
            @test effective["condition"]=="exploratory_interference"
            @test effective["label"]=="Etendue3D"
        end
    end
end

@testset "B1 native fixture ownership and PerfChecker custom-executor wiring" begin
    root=abspath(expanduser(get(ENV,"GARAMON_JULIA_ROOT","~/.julia/dev/Garamon")))
    isfile(joinpath(root,"perf","bounds_b1.jl")) || error("runtime integration test requires exact private B1 target")
    raw=TOML.parsefile(joinpath(@__DIR__,"..","config","bounds_b1.toml"));plan=b1_plan(raw)
    request=merge(plan,Dict("job"=>first(plan["jobs"]),"julia_root"=>root));delete!(request,"jobs")
    mktempdir() do temporary
        path=joinpath(temporary,"request.toml");GaramonBench.write_toml(path,request)
        sandbox=Module(gensym(:B1FunctionalTests))
        Core.eval(sandbox,:(const ARGS=[$path]))
        before=copy(LOAD_PATH)
        try
            Base.include(sandbox,joinpath(@__DIR__,"..","adapters","bounds_b1","worker.jl"))
        finally
            empty!(LOAD_PATH);append!(LOAD_PATH,before)
        end
        fixturefn=Base.invokelatest(getfield,sandbox,:b1_fixture);build=Base.invokelatest(getfield,sandbox,:b1_build)
        buildexecution=Base.invokelatest(getfield,sandbox,:b1_build_execution)
        batch=Base.invokelatest(getfield,sandbox,:b1_batch);episode=Base.invokelatest(getfield,sandbox,:b1_episode)
        oracle=Base.invokelatest(getfield,sandbox,:b1_exact_owned)
        for n in (2,64,65,128),family in ("low_grade","high_grade"),signature in ("positive","mixed","degenerate")
            fixture=Base.invokelatest(fixturefn,n,family,signature)
            prepared=Base.invokelatest(build,fixture)
            for route in (:checked,:inbounds,:workspace,:workspace_native,:workspace_native_singlepass),horizon in (1,32,1024)
                execution=route in (:workspace,:workspace_native,:workspace_native_singlepass) ?
                    Base.invokelatest(buildexecution,fixture,route) : prepared
                outputs=Base.invokelatest(batch,fixture,execution,route,horizon)
                @test Base.invokelatest(oracle,fixture,outputs,horizon)
                second=Base.invokelatest(episode,fixture,route,horizon)
                @test Base.invokelatest(oracle,fixture,second,horizon)
                @test outputs[1].values!==second[1].values
                old=copy(second[end].values);empty!(outputs[1].values)
                @test second[end].values==old
            end
        end
        suite=Base.invokelatest(Base.invokelatest(getfield,sandbox,:b1_suite),request)
        catalogue=plan_suite(suite;profile=:quick)
        @test length(catalogue.runs)==4
        @test all(r->r.planned_status!=:unavailable,catalogue.runs)
        executed=String[]
        function executor(planned,config,setup,workload)
            c=planned.feature.options[:b1_case];push!(executed,c["id"])
            fixture=Base.invokelatest(fixturefn,c["dimension"],c["family"],c["signature"])
            values=Base.invokelatest(episode,fixture,Symbol(c["route"]),c["horizon"])
            @test Base.invokelatest(oracle,fixture,values,c["horizon"])
            # No result tables, no timings, no performance qualification fabricated.
            nothing
        end
        result=run_suite(catalogue;executor)
        @test executed==[c["id"] for c in request["job"]["cases"]]
        @test all(r->r.status==:pass,result.runs)
        @test all(r->r.result===nothing,result.runs)
    end
end
