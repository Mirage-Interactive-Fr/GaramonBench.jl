using Test, GaramonBench, TOML

@testset "paired budgets admit the declared samples of a slow standard reference" begin
    rows=[(phase="first_execution",time_ns=1e6),
        (phase="baseline_first_execution",time_ns=40e9)]
    limits=Dict("case_seconds"=>60,"samples"=>11)
    @test GaramonBench.paired_case_budget(limits,rows,45;baseline_required=true)>880
    @test GaramonBench.paired_case_budget(limits,rows,45)==60
    @test limits["case_seconds"]==60
    @test GaramonBench.paired_case_budget(merge(limits,Dict("paired_case_min_seconds"=>60,"paired_case_max_seconds"=>120)),
        rows,45;baseline_required=true)==120
    @test GaramonBench.paired_case_budget(limits,NamedTuple[],0;baseline_required=true)==3600
    @test GaramonBench.paired_case_budget(limits,
        [(phase="baseline_first_execution",time_ns=1e15)],0;baseline_required=true)==21600
    observed=vcat(rows,[(phase="baseline_warm",time_ns=80e9)])
    @test GaramonBench.paired_case_budget(limits,observed,140;
        baseline_required=true,verification_only=true)>300
    adapter=BenchmarkAdapter(name="slow_standard_reference",
        generate=(case,dir,rng)->Int[1,2,3],execute=copy,
        baseline_execute=state->begin sleep(0.1); copy(state); end,
        baseline_name="exact_slow_reference",
        oracle=(state,result)->state==result,contract="exact owned fixture")
    rows,verdict=GaramonBench.run_case(adapter,
        Dict{String,Any}("adapter"=>adapter.name,"seed"=>1,"baseline_required"=>true),
        Dict{String,Any}("case_seconds"=>0.8,"paired_case_min_seconds"=>0.8,
            "samples"=>11,"controller_rss_bytes"=>4<<30))
    @test count(r->r.phase=="baseline_warm",rows)==11
    @test verdict["effective_case_seconds"]>verdict["declared_case_seconds"]
    @test verdict["oracle_passed"] && verdict["baseline_oracle_passed"]
end

@testset "native failures retain child output without dumping the environment" begin
    mktempdir() do output
        julia=joinpath(Sys.BINDIR,Base.julia_exename())
        command=addenv(`$julia --startup-file=no --threads=1 -e 'println("child stdout"); println(stderr,"independent oracle rejected fixture"); exit(3)'`,
            "GARAMON_TEST_PRIVATE_ENV"=>"must-not-be-dumped")
        terminal=IOBuffer()
        result=GaramonBench._run_native_stage(command,output,:benchmark,"17";terminal)
        @test result.exitcode==3
        @test isfile(result.logfile)
        @test occursin("child stdout",String(take!(terminal)))
        @test occursin("independent oracle rejected fixture",read(result.logfile,String))
        message=GaramonBench._native_stage_failure(result,:benchmark,"17")
        @test occursin("technique 17",message)
        @test occursin("independent oracle rejected fixture",message)
        @test !occursin("must-not-be-dumped",message)
        @test !occursin("setenv(",message)
        command=`$julia --startup-file=no --threads=1 -e 'print(repeat("x",100000)); println("final error")'`
        result=GaramonBench._run_native_stage(command,output,:preflight,"17";
            terminal=devnull,log_limit=1024)
        @test result.exitcode==0
        @test filesize(result.logfile)<=1024
        @test endswith(result.tail,"final error\n")
    end
end

@testset "explicit source-change resume preserves and identifies completed cases" begin
    mktempdir() do root
        fixture=joinpath(root,"source")
        mkpath(fixture)
        source=joinpath(fixture,"kernel.jl")
        write(source,"# revision one\n")
        config=load_config(joinpath(@__DIR__,"..","config","smoke.toml"))
        config["campaign"]["backend"]="benchmarktools"
        config["campaign"]["condition"]="isolated"
        config["campaign"]["interference_label"]=""
        config["case_defaults"]["adapter"]="source_override_fixture"
        config["case_defaults"]["baseline_required"]=true
        config["repositories"]=Dict("fixture"=>fixture)
        config["limits"]["samples"]=1
        config["limits"]["sample_seconds"]=0.001
        calls=Int[]
        fail_second=Ref(true)
        register_adapter!(BenchmarkAdapter(name="source_override_fixture",
            contract="exact owned vector for source override regression",
            generate=(case,dir,rng)->begin
                push!(calls,case["length"])
                case["length"]==16 && fail_second[] && error("test stop")
                collect(1:case["length"])
            end,execute=copy,baseline_execute=copy,baseline_name="standard_fixture",
            oracle=(state,result)->state==result);replace=true)
        output=joinpath(root,"campaign")
        @test_throws ErrorException run_resumable_campaign(config;output)
        first_id=first(case_id.(expand_cases(config)))
        first_marker=joinpath(output,"cases",first_id,"completion.toml")
        # Match the completion schema written before this feature existed.
        legacy=TOML.parsefile(first_marker)
        delete!(legacy,"execution_signature")
        GaramonBench.write_toml(first_marker,legacy)
        first_bytes=read(first_marker)
        original=TOML.parsefile(joinpath(output,"campaign.toml"))["run_signature"]
        write(source,"# revision two\n")
        fail_second[]=false
        @test_throws ErrorException run_resumable_campaign(config;output)
        @test calls==[4,16]
        @test run_resumable_campaign(config;output,allow_source_changes=true)==output
        @test calls==[4,16,16]
        @test read(first_marker)==first_bytes
        manifest=TOML.parsefile(joinpath(output,"campaign.toml"))
        @test manifest["run_signature"]==original
        @test manifest["mixed_source_revisions"]
        @test length(manifest["source_revisions"])==1
        revision=only(manifest["source_revisions"])["run_signature"]
        second_id=last(case_id.(expand_cases(config)))
        second=TOML.parsefile(joinpath(output,"cases",second_id,"completion.toml"))
        @test second["execution_signature"]==revision!=original
        @test run_resumable_campaign(config;output)==output
        @test calls==[4,16,16]
        audit=audit_resumable_archive(config,output)
        @test audit["archive_integrity"]=="validated"
        @test audit["mixed_source_revisions"]
        @test audit["same_machine_resume_allowed"]
        @test length(audit["source_revision_signatures"])==2
        report_rows,_=GaramonBench._technique_report_rows(Dict("id"=>"fixture"),config,output)
        @test Set(r.execution_signature for r in report_rows)==Set([original,revision])
        changed=deepcopy(config)
        changed["campaign"]["seed"]+=1
        @test_throws ErrorException run_resumable_campaign(changed;output,allow_source_changes=true)
        manifest["machine"]["sha256"]="different-machine"
        GaramonBench.write_toml(joinpath(output,"campaign.toml"),manifest)
        @test_throws ErrorException run_resumable_campaign(config;output,allow_source_changes=true)
        manifest["machine"]["sha256"]=GaramonBench._resume_machine()["sha256"]
        GaramonBench.write_toml(joinpath(output,"campaign.toml"),manifest)
        # An override never authorizes modifying a validated artifact.
        sample=joinpath(output,"cases",first_id,"samples.csv")
        saved=read(sample)
        write(sample,"tampered")
        @test_throws ErrorException run_resumable_campaign(config;output,allow_source_changes=true)
        write(sample,saved)
        snapshot=joinpath(output,"revisions",revision,"sources","fixture","kernel.jl")
        @test read(snapshot,String)=="# revision two\n"
        write(snapshot,"tampered")
        @test_throws ErrorException audit_resumable_archive(config,output)
    end
end

@testset "current RSS admission does not inherit historical peaks" begin
    if Sys.islinux()
        live=GaramonBench.resident_rss_bytes()
        peak=Sys.maxrss()
        @test live>0
        if peak-live>64<<20
            ceiling=(peak+live)÷2
            @test peak>ceiling
            limits=Dict("controller_rss_bytes"=>ceiling,"case_seconds"=>30)
            @test GaramonBench.case_guard(
                [(disk_checkpoint_bytes=0,)],time(),limits)===true
            adapter=BenchmarkAdapter(name="released_peak_fixture",
                generate=(case,dir,rng)->Int64[1,2,3],execute=copy,
                oracle=(state,result)->result==state,contract="owned exact fixture")
            case=Dict{String,Any}("adapter"=>adapter.name,"seed"=>1)
            @test GaramonBench.run_case_preflight(adapter,case,limits)["oracle_passed"]
        end
        @test_throws GaramonBench.ControllerMemoryBudget GaramonBench.controller_memory_guard(
            Dict("controller_rss_bytes"=>1))
    end
end

@testset "memory exclusions resume at the next case without accepting partial samples" begin
    mktempdir() do root
        config=load_config(joinpath(pkgdir(GaramonBench),"config","smoke.toml"))
        config["campaign"]["backend"]="benchmarktools"
        config["campaign"]["condition"]="isolated"
        config["case_defaults"]["adapter"]="memory_skip_fixture"
        config["case_defaults"]["baseline_required"]=true
        config["limits"]["samples"]=1
        calls=Int[]
        register_adapter!(BenchmarkAdapter(name="memory_skip_fixture",
            generate=(case,dir,rng)->begin
                push!(calls,case["length"])
                case["length"]==4 && GaramonBench.controller_memory_guard(
                    Dict("controller_rss_bytes"=>1))
                collect(1:case["length"])
            end,execute=copy,baseline_execute=copy,baseline_name="fixture_standard",
            oracle=(state,result)->state==result,
            contract="exact memory exclusion fixture");replace=true)
        output=joinpath(root,"campaign")
        @test_throws GaramonBench.MemoryBudgetRestart run_resumable_campaign(config;
            output,skip_memory_budget=true)
        status=resumable_status(config,output)
        skipped=only(status["budget_skipped_ids"])
        @test isempty(status["completed_ids"])
        @test length(status["pending_ids"])==1
        @test !isfile(joinpath(output,"staging",skipped,"completion.toml"))
        @test TOML.parsefile(joinpath(output,"progress.toml"))["status"]=="restart_required"
        @test run_resumable_campaign(config;output,skip_memory_budget=true)==output
        @test calls==[4,16]
        @test run_resumable_campaign(config;output,skip_memory_budget=true)==output
        @test calls==[4,16]
        status=resumable_status(config,output)
        @test status["status"]=="complete_with_budget_skips"
        @test isempty(status["pending_ids"])
        @test length(status["completed_ids"])==1
        audit=audit_resumable_archive(config,output)
        @test audit["budget_skipped_ids"]==[skipped]
        @test isempty(audit["pending_ids"])
        rows,_=GaramonBench._technique_report_rows(Dict("id"=>"fixture"),config,output)
        @test length(rows)==1
        @test only(rows).case_id!=skipped
        recordpath=joinpath(output,"budget-skips",skipped*".toml")
        record=TOML.parsefile(recordpath)
        record["case"]["seed"]+=1
        GaramonBench.write_toml(recordpath,record)
        @test_throws ErrorException resumable_status(config,output)
        register_adapter!(BenchmarkAdapter(name="memory_skip_fixture",
            generate=(case,dir,rng)->Int[1],execute=copy,baseline_execute=copy,
            baseline_name="fixture_standard",oracle=(state,result)->false,
            contract="oracle failure must not be excluded");replace=true)
        failed=joinpath(root,"oracle-failure")
        @test_throws ErrorException run_resumable_campaign(config;
            output=failed,skip_memory_budget=true)
        @test !isdir(joinpath(failed,"budget-skips"))
    end
end

@testset "memory worker restarts are fresh and must make forward progress" begin
    mktempdir() do output
        mkpath(joinpath(output,"benchmark"))
        code="""
        using TOML
        output=ARGS[1]
        state=joinpath(output,"attempts.toml")
        pids=isfile(state) ? TOML.parsefile(state)["pids"] : Int[]
        push!(pids,getpid())
        open(state,"w") do io; TOML.print(io,Dict("pids"=>pids)); end
        if length(pids)==1
            open(joinpath(output,"benchmark","bench-progress.toml"),"w") do io
                TOML.print(io,Dict("technique"=>[Dict("id"=>"17",
                    "status"=>"restart_required","budget_skipped_ids"=>["case-a"])]))
            end
            exit(75)
        end
        println("next case completed")
        """
        julia=joinpath(Sys.BINDIR,Base.julia_exename())
        command=Cmd([julia,"--startup-file=no","--threads=1","-e",code,output])
        restarts=Int[]
        result=GaramonBench._run_native_stage_resumable(command,output,:benchmark,"17";
            terminal=devnull,on_restart=(r,n)->push!(restarts,n))
        @test result.exitcode==0
        @test restarts==[1]
        pids=TOML.parsefile(joinpath(output,"attempts.toml"))["pids"]
        @test length(unique(pids))==2
        stuck=`$julia --startup-file=no -e 'exit(75)'`
        @test_throws ErrorException GaramonBench._run_native_stage_resumable(stuck,output,:benchmark,"17";terminal=devnull)
    end
end

@testset "ordinary failures retain their cause in terminal and stage reports" begin
    io=IOBuffer()
    meter=GaramonBench._campaign_meter("Technique 12";output=io)
    GaramonBench._campaign_meter_update!(meter,"fixture",String[],1)
    GaramonBench._campaign_meter_close!(meter;complete=false,
        failure=ErrorException("controller RSS budget"))
    text=String(take!(io))
    @test occursin("failed:",text)
    @test occursin("controller RSS budget",text)
    @test !occursin("interrupted",text)
    mktempdir() do root
        report=joinpath(root,"bench-progress.toml")
        records=[Dict("id"=>"12","status"=>"failed","reason"=>"controller RSS budget"),
            Dict("id"=>"13","status"=>"complete","article_status"=>"updated")]
        GaramonBench.write_toml(report,Dict("technique"=>records))
        exception=try
            GaramonBench._check_native_stage_report(report,["12","13"],"benchmark")
            nothing
        catch e
            e
        end
        @test exception isa ErrorException
        @test occursin("Technique 12: failed; controller RSS budget",sprint(showerror,exception))
        @test isnothing(GaramonBench._check_native_stage_report(report,["13"],"benchmark"))
        @test_throws ErrorException GaramonBench._check_native_stage_report(report,["14"],"benchmark")
        records=[Dict("id"=>"17","status"=>"complete_with_budget_skips",
            "validated_cases"=>0,"budget_skipped_ids"=>["case-a"],
            "article_status"=>"budget_skipped_no_measurements")]
        GaramonBench.write_toml(report,Dict("technique"=>records))
        @test isnothing(GaramonBench._check_native_stage_report(report,["17"],"benchmark"))
        records[1]["validated_cases"]=1
        GaramonBench.write_toml(report,Dict("technique"=>records))
        @test_throws ErrorException GaramonBench._check_native_stage_report(report,["17"],"benchmark")
        records[1]["article_status"]="updated"
        GaramonBench.write_toml(report,Dict("technique"=>records))
        @test isnothing(GaramonBench._check_native_stage_report(report,["17"],"benchmark"))
    end
end

@testset "launcher separates techniques into fresh native processes" begin
    command=GaramonBench._technique_launch_command(
        only(technique_launch_plan(ids=["12"],gpu=:off)),"/tmp/campaign",
        :benchmark,false,0,true)
    @test occursin("allow_source_changes",join(command.exec," "))
        @test command.exec[end-1]=="true"
    mktempdir() do output
        report=run_technique_campaign(output;ids=["12","13"],gpu=:off,
            phase=:preflight,show_progress=false,allow_source_changes=true)
        progress=TOML.parsefile(report)
        @test progress["status"]=="complete"
        @test length(progress["groups"])==2
        @test getindex.(progress["groups"],"ids")==[["12"],["13"]]
        for id in ("12","13")
            @test TOML.parsefile(joinpath(output,"preflight","quickcheck.toml"))["oracle_passed_count"]==2
            @test isfile(joinpath(output,"preflight",id,"campaign.toml"))
        end
    end
end
