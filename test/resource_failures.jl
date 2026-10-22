using Test, GaramonBench, TOML

# Type fixtures exercise the optional-CUDA classifier without initializing a
# device or deliberately exhausting RAM/VRAM. Real CUDA types are also usable.
module ResourceFailureFixtures
module CUDACore
struct OutOfGPUMemoryError <: Exception end
struct CuError <: Exception
    code::Int
end
end
end

@testset "detached descendants are reclaimed without touching another launch" begin
    mktempdir() do output
        julia=joinpath(Sys.BINDIR,Base.julia_exename())
        sentinel=run(Cmd(addenv(`$julia --startup-file=no --threads=1 -e 'sleep(60)'`,
            "GARAMONBENCH_WORKER_TOKEN"=>"unrelated-test-launch");detach=true);wait=false)
        try
            code="""
            julia=joinpath(Sys.BINDIR,Base.julia_exename())
            child=run(Cmd(Cmd([julia,"--startup-file=no","--threads=1","-e","sleep(60)"]);
                detach=true);wait=false)
            println("DETACHED_PID=",getpid(child)); flush(stdout)
            ccall(:kill,Cint,(Cint,Cint),getpid(),9)
            """
            command=Cmd([julia,"--startup-file=no","--threads=1","-e",code])
            result=GaramonBench._run_native_stage_resumable(command,output,:benchmark,"28";terminal=devnull)
            @test result.stage_skipped
            matchpid=match(r"DETACHED_PID=(\d+)",result.tail)
            @test !isnothing(matchpid)
            pid=parse(Int,matchpid.captures[1])
            sleep(0.1)
            statfile=joinpath("/proc",string(pid),"stat")
            @test !isfile(statfile) || split(read(statfile,String))[3]=="Z"
            @test process_running(sentinel)
        finally
            process_running(sentinel) && kill(sentinel,9)
            wait(sentinel)
        end
    end
end

@testset "CPU and CUDA resource failures are classified by type" begin
    classify=GaramonBench.memory_failure_details
    gpu=ResourceFailureFixtures.CUDACore
    @test classify(OutOfMemoryError())["kind"]=="cpu_out_of_memory"
    @test classify(GaramonBench.AvailableMemoryBudget(1,2))["kind"]=="host_memory_admission"
    @test classify(gpu.OutOfGPUMemoryError())["kind"]=="gpu_out_of_memory"
    @test classify(gpu.CuError(2))["kind"]=="gpu_out_of_memory"
    @test classify(gpu.CuError(700))["kind"]=="gpu_memory_error"
    @test classify(gpu.CuError(701))["kind"]=="gpu_memory_error"
    @test isnothing(classify(gpu.CuError(1)))
    @test isnothing(classify(ErrorException("out of memory: oracle rejected result")))
    @test classify(LoadError("fixture",1,gpu.OutOfGPUMemoryError()))["kind"]=="gpu_out_of_memory"
    @test classify(CompositeException([OutOfMemoryError()]))["kind"]=="cpu_out_of_memory"
    @test isnothing(classify(CompositeException([OutOfMemoryError(),ErrorException("oracle failed")])))
end

@testset "CPU and GPU exceptions exclude only the failing case" begin
    for exception in (OutOfMemoryError(),GaramonBench.AvailableMemoryBudget(1,2),ResourceFailureFixtures.CUDACore.OutOfGPUMemoryError(),
                      ResourceFailureFixtures.CUDACore.CuError(700))
        mktempdir() do output
            config=load_config(joinpath(pkgdir(GaramonBench),"config","smoke.toml"))
            config["campaign"]["backend"]="benchmarktools"
            config["case_defaults"]["adapter"]="resource_exception_fixture"
            config["limits"]["samples"]=1
            calls=Int[]
            register_adapter!(BenchmarkAdapter(name="resource_exception_fixture",
                generate=(case,dir,rng)->begin
                    push!(calls,case["length"])
                    case["length"]==4 && throw(exception)
                    collect(1:case["length"])
                end,execute=copy,oracle=(state,result)->state==result,
                contract="owned exact harness fixture");replace=true)
            @test_throws GaramonBench.MemoryBudgetRestart run_resumable_campaign(config;
                output,skip_memory_budget=true)
            @test run_resumable_campaign(config;output,skip_memory_budget=true)==output
            status=resumable_status(config,output)
            @test calls==[4,16]
            @test length(status["budget_skipped_ids"])==1
            @test length(status["completed_ids"])==1
            @test isempty(status["pending_ids"])
            @test audit_resumable_archive(config,output)["archive_integrity"]=="validated"
        end
    end
end

@testset "SIGKILL recovery preserves completed cases and advances to the next case" begin
    mktempdir() do output
        code="""
        using GaramonBench, TOML
        output=ARGS[1]
        config=load_config(joinpath(pkgdir(GaramonBench),"config","smoke.toml"))
        config["campaign"]["backend"]="benchmarktools"
        config["case_defaults"]["adapter"]="killed_case_fixture"
        config["grid"]["length"]=[4,8,16]
        config["limits"]["samples"]=1
        register_adapter!(BenchmarkAdapter(name="killed_case_fixture",
            generate=(case,dir,rng)->begin
                open(joinpath(output,"attempts.txt"),"a") do io
                    println(io,case["length"])
                end
                case["length"]==8 && ccall(:kill,Cint,(Cint,Cint),getpid(),9)
                collect(1:case["length"])
            end,execute=copy,oracle=(state,result)->state==result,
            contract="exact SIGKILL recovery fixture");replace=true)
        archive=joinpath(output,"benchmark","42")
        run_resumable_campaign(config;output=archive,skip_memory_budget=true)
        """
        julia=joinpath(Sys.BINDIR,Base.julia_exename())
        command=Cmd([julia,"--startup-file=no","--threads=1,0","--gcthreads=1",
            "--project="*pkgdir(GaramonBench),"-e",code,output])
        restarts=Int[]
        result=GaramonBench._run_native_stage_resumable(command,output,:benchmark,"42";
            terminal=devnull,on_restart=(r,n)->push!(restarts,n))
        @test result.exitcode==0 && result.termsignal==0
        @test !result.stage_skipped
        @test length(restarts)==1
        @test readlines(joinpath(output,"attempts.txt"))==["4","8","16"]
        archive=joinpath(output,"benchmark","42")
        config=TOML.parsefile(joinpath(archive,"configuration.toml"))
        status=resumable_status(config,archive)
        @test length(status["completed_ids"])==2
        @test length(status["budget_skipped_ids"])==1
        @test isempty(status["pending_ids"])
        record=TOML.parsefile(joinpath(archive,"budget-skips",only(status["budget_skipped_ids"])*".toml"))
        @test record["signal"]==9
        @test record["memory_cause_confirmed"]===false
        @test record["kind"]=="worker_terminated"
        @test audit_resumable_archive(config,archive)["archive_integrity"]=="validated"
        # A further launch never repeats the validated or excluded case.
        again=GaramonBench._run_native_stage_resumable(command,output,:benchmark,"42";terminal=devnull)
        @test again.exitcode==0
        @test readlines(joinpath(output,"attempts.txt"))==["4","8","16"]
    end
end

@testset "startup kills are reported; user interruption stays an interruption" begin
    mktempdir() do output
        julia=joinpath(Sys.BINDIR,Base.julia_exename())
        for phase in (:preflight,:benchmark)
            command=`$julia --startup-file=no --threads=1 -e 'ccall(:kill,Cint,(Cint,Cint),getpid(),9)'`
            result=GaramonBench._run_native_stage_resumable(command,output,phase,"29";terminal=devnull)
            @test result.stage_skipped
            @test result.termsignal==9
            @test occursin("memory cause unconfirmed",result.resource_reason)
        end
        command=`$julia --startup-file=no --threads=1 -e 'ccall(:kill,Cint,(Cint,Cint),getpid(),15)'`
        @test_throws InterruptException GaramonBench._run_native_stage_resumable(
            command,output,:benchmark,"29";terminal=devnull)
        command=`$julia --startup-file=no --threads=1 -e 'error("independent oracle rejected fixture")'`
        result=GaramonBench._run_native_stage_resumable(command,output,:benchmark,"29";terminal=devnull)
        @test result.exitcode!=0
        @test !result.stage_skipped
    end
end

@testset "the campaign advances to other techniques after a preflight resource failure" begin
    mktempdir() do output
        # Replace only the native command factory inside this disposable test
        # process. Exercise the real campaign scheduler and report handling.
        code="""
        using GaramonBench, TOML
        @eval GaramonBench function _technique_launch_command(group,output,phase,show_progress,every,override::Bool=false)
            id=only(group.ids)
            status=phase==:preflight ? (id=="17" ? "resource_unavailable" : "oracle_passed") : "complete"
            record=Dict("id"=>id,"status"=>status,"reason"=>"injected GPU allocation failure",
                "article_status"=>"updated","validated_cases"=>1)
            report=joinpath(output,string(phase),phase==:preflight ? "quickcheck.toml" : "bench-progress.toml")
            program="using TOML; mkpath("*repr(dirname(report))*"); open("*repr(report)*","*repr("w")*") do io; TOML.print(io,"*repr(Dict("technique"=>[record]))*"); end; exit("*(status=="resource_unavailable" ? "76" : "0")*")"
            Cmd([joinpath(Sys.BINDIR,Base.julia_exename()),"--startup-file=no","--threads=1","-e",program])
        end
        probe=GaramonBench._technique_launch_command(only(technique_launch_plan(ids=["17"],gpu=:off)),ARGS[1],:preflight,false,0,false)
        @assert !occursin("quickactivate",join(probe.exec," ")) "test must use the injected command factory"
        run_technique_campaign(ARGS[1];ids=["17","18"],gpu=:off,show_progress=false)
        """
        julia=joinpath(Sys.BINDIR,Base.julia_exename())
        command=Cmd([julia,"--startup-file=no","--threads=1,0","--gcthreads=1",
            "--project="*pkgdir(GaramonBench),"-e",code,output])
        run(pipeline(command;stdout=devnull))
        report=TOML.parsefile(joinpath(output,"launch-progress.toml"))
        @test report["status"]=="complete_with_budget_skips"
        @test any(r->r["ids"]==["17"] && r["status"]=="resource_unavailable",report["groups"])
        @test any(r->r["ids"]==["18"] && r["stage"]=="benchmark" && r["status"]=="complete",report["groups"])
        @test !any(r->r["ids"]==["17"] && r["stage"]=="benchmark" && r["status"]=="complete",report["groups"])
    end
end
