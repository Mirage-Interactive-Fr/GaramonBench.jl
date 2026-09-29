@testset "DrWatson case identities and crash-safe resume" begin
    config=load_config(joinpath(@__DIR__,"..","config","smoke.toml"))
    config["case_defaults"]["adapter"]="resume_probe"
    calls=Int[]
    fail_second=Ref(true)
    register_adapter!(BenchmarkAdapter(name="resume_probe",
        contract="owned exact Int64 squares for resumable harness test",
        generate=(case,dir,rng)->begin
            push!(calls,case["length"])
            case["length"]==16 && fail_second[] && error("deliberate interruption")
            collect(Int64(1):Int64(case["length"]))
        end,
        execute=state->state.*state,
        oracle=(state,result)->result==[x*x for x in state],
        diagnostics=(state,case,directory)->begin
            write(joinpath(directory,"diagnostic.txt"),"length=$(length(state))\n")
            Dict("status"=>"captured")
        end,
        capabilities=Dict("scientific_garamon_result"=>false));replace=true)
    mktempdir() do root
        output=joinpath(root,"campaign")
        @test_throws ErrorException run_resumable_campaign(config;output)
        first=resumable_status(config,output)
        @test first["status"]=="incomplete"
        @test length(first["completed_ids"])==1
        @test length(first["pending_ids"])==1
        @test calls==[4,16]
        @test TOML.parsefile(joinpath(output,"progress.toml"))["status"]=="interrupted"

        fail_second[]=false
        @test run_resumable_campaign(config;output)==output
        @test calls==[4,16,16] # The first completed case was never reexecuted.
        @test resumable_status(config,output)["status"]=="complete"
        @test run_resumable_campaign(config;output)==output
        @test calls==[4,16,16]

        # A crash after the final completion marker but before publication
        # preserves qualified work in staging; the restart recovers it.
        second=last(case_id.(expand_cases(config)))
        mv(joinpath(output,"cases",second),joinpath(output,"staging",second))
        @test run_resumable_campaign(config;output)==output
        @test calls==[4,16,16]
        @test isdir(joinpath(output,"cases",second))

        diagnostic=joinpath(output,"cases",only(first["completed_ids"]),"diagnostic.txt")
        @test read(diagnostic,String)=="length=4\n"
        @test length(TOML.parsefile(joinpath(dirname(diagnostic),"completion.toml"))["diagnostic_artifacts"])==1
        open(diagnostic,"a") do io
            print(io,"tampered")
        end
        @test_throws ErrorException run_resumable_campaign(config;output)
        write(diagnostic,"length=4\n")

        copied=joinpath(root,"transferred-archive")
        cp(output,copied)
        audit=audit_resumable_archive(config,copied)
        @test audit["archive_integrity"]=="validated"
        @test length(audit["completed_ids"])==2
        @test audit["current_machine_matches"]
        @test audit["current_environment_matches"]
        @test all(values(audit["current_sources_match"]))
        @test audit["same_machine_resume_allowed"]
        @test !audit["cross_machine_measurements_reused"]
        source=joinpath(copied,"sources","benchmark","src","resume.jl")
        open(source,"a") do io
            print(io,"tampered")
        end
        @test_throws ErrorException audit_resumable_archive(config,copied)

        changed=deepcopy(config); changed["campaign"]["seed"]+=1
        @test_throws ErrorException run_resumable_campaign(changed;output)
        @test calls==[4,16,16]

        sample=joinpath(output,"cases",only(first["completed_ids"]),"samples.csv")
        open(sample,"a") do io
            println(io,"tampered")
        end
        @test_throws ErrorException run_resumable_campaign(config;output)
        @test calls==[4,16,16]
    end
    mktempdir() do root
        output=joinpath(root,"partial-setup")
        mkpath(joinpath(output,"sources"))
        write(joinpath(output,".run.lock"),"")
        write(joinpath(output,".garamonbench-setup.toml"),
            "status = \"setting_up\"\n")
        write(joinpath(output,"sources","partial.txt"),"incomplete snapshot")
        fail_second[]=false
        @test run_resumable_campaign(config;output)==output
        @test TOML.parsefile(joinpath(output,"campaign.toml"))["recovered_incomplete_setup"]
        @test resumable_status(config,output)["status"]=="complete"
    end
    mktempdir() do root
        output=joinpath(root,"interrupted-setup-write")
        mkpath(output)
        write(joinpath(output,".garamonbench-setup.toml.tmp-dead"),
            "status = \"setting_up\"\n")
        fail_second[]=false
        @test run_resumable_campaign(config;output)==output
        @test TOML.parsefile(joinpath(output,"campaign.toml"))["recovered_incomplete_setup"]
        @test resumable_status(config,output)["status"]=="complete"
    end
end

@testset "BenchmarkTools archive resumes without PerfChecker" begin
    config=load_config(joinpath(@__DIR__,"..","config","smoke.toml"))
    config["campaign"]["backend"]="benchmarktools"
    config["case_defaults"]["adapter"]="harness_smoke"
    config["limits"]["samples"]=1
    GaramonBench.register_smoke_adapter!()
    mktempdir() do root
        output=joinpath(root,"native")
        updates=Tuple{Int,Int}[]
        callback=(archive,ids,total)->begin
            @test archive==output
            push!(updates,(length(ids),total))
        end
        @test run_resumable_campaign(config;output,on_progress=callback)==output
        @test updates==[(0,2),(1,2),(2,2)]
        @test resumable_status(config,output)["status"]=="complete"
        cases=expand_cases(config)
        for case in cases
            directory=joinpath(output,"cases",case_id(case))
            @test TOML.parsefile(joinpath(directory,"verdict.toml"))["benchmark_backend"]=="BenchmarkTools"
            @test TOML.parsefile(joinpath(directory,"completion.toml"))["warm_samples"]==1
        end
        @test run_resumable_campaign(config;output)==output
        @test audit_resumable_archive(config,output)["archive_integrity"]=="validated"
    end
end
