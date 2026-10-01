using Test, GaramonBench, TOML

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
        @test_throws ErrorException GaramonBench.controller_memory_guard(
            Dict("controller_rss_bytes"=>1))
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
