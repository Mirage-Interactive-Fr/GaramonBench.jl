using Test, GaramonBench, Random, SHA, TOML

@testset "paired standard baseline shares the exact generated fixture" begin
    generated=Ref(0)
    adapter=BenchmarkAdapter(name="paired_baseline_fixture",
        generate=(case,directory,rng)->begin
            generated[]+=1
            rand(rng,1:10,8)
        end,
        prepare=(values,case,directory)->values,
        execute=values->copy(values),
        baseline_execute=values->copy(values),
        baseline_name="garamon_julia_standard_fixture",
        oracle=(values,result)->result==values,
        contract="owned copy of the same eight seeded integers")
    case=Dict{String,Any}("adapter"=>adapter.name,"family"=>"fixture",
        "dimension"=>2,"strategy"=>"candidate","seed"=>17,
        "baseline_required"=>true)
    limits=Dict{String,Any}("samples"=>3,"case_seconds"=>30,
        "build_disk_bytes"=>1<<20,"controller_rss_bytes"=>8<<30)
    rows,verdict=GaramonBench.run_case(adapter,case,limits)
    @test generated[]==1
    @test verdict["oracle_passed"] && verdict["baseline_oracle_passed"]
    @test verdict["baseline_name"]=="garamon_julia_standard_fixture"
    @test count(row->row.phase=="warm",rows)==3
    @test count(row->row.phase=="baseline_warm",rows)==3
    @test any(row->row.phase=="baseline_preparation",rows)
    missing=BenchmarkAdapter(name="missing_baseline_fixture",
        generate=adapter.generate,prepare=adapter.prepare,
        execute=adapter.execute,oracle=adapter.oracle,contract=adapter.contract)
    @test_throws ErrorException GaramonBench.run_case(missing,case,limits)
end

@testset "shared baseline survives archive resume and transfer" begin
    config=load_config(joinpath(@__DIR__,"..","config","smoke.toml"))
    config["campaign"]["backend"]="benchmarktools"
    config["grid"]=Dict{String,Any}("length"=>[4],"strategy"=>["a","b"])
    config["case_defaults"]["adapter"]="shared_archive_fixture"
    config["case_defaults"]["baseline_required"]=true
    config["limits"]["samples"]=2
    calls=Ref(0)
    register_adapter!(BenchmarkAdapter(name="shared_archive_fixture",
        generate=(case,dir,rng)->rand(rng,UInt8,case["length"]),
        execute=copy,
        baseline_execute=values->begin
            calls[]+=1
            copy(values)
        end,
        baseline_name="garamon_julia_same_inputs",
        baseline_scenario=(values,case)->Dict("inputs"=>Int.(values)),
        baseline_output_identity=values->bytes2hex(sha256(values)),
        oracle=(values,result)->result==values,
        contract="owned seeded bytes");replace=true)
    mktempdir() do root
        output=joinpath(root,"strategy_campaign")
        cache=joinpath(root,"_baselines")
        @test run_resumable_campaign(config;output,baseline_cache_root=cache)==output
        first,second=expand_cases(config)
        cases=[joinpath(output,"cases",case_id(case)) for case in (first,second)]
        verdicts=TOML.parsefile.(joinpath.(cases,"verdict.toml"))
        @test count(verdict->verdict["baseline_cache_hit"],verdicts)==1
        @test only(filter(verdict->verdict["baseline_cache_hit"],verdicts))["baseline_samples_verified"]==2
        measured_calls=calls[]
        @test run_resumable_campaign(config;output,baseline_cache_root=cache)==output
        @test calls[]==measured_calls
        @test audit_resumable_archive(config,output)["archive_integrity"]=="validated"
        record=only(filter(path->endswith(path,".toml"),readdir(cache;join=true)))
        original=read(record)
        open(record,"a") do io
            print(io,"\ntampered = true\n")
        end
        @test_throws ErrorException audit_resumable_archive(config,output)
        write(record,original)
        mktempdir() do transfer_root
            copied=joinpath(transfer_root,"campaign_copy")
            cp(root,copied)
            @test audit_resumable_archive(config,
                joinpath(copied,"strategy_campaign"))["archive_integrity"]=="validated"
        end
    end
end

@testset "shared standard baseline is measured once for identical inputs" begin
    calls=Ref(0)
    adapter=BenchmarkAdapter(name="shared_baseline_fixture",
        generate=(case,directory,rng)->rand(rng,1:10,8),
        execute=values->copy(values),
        baseline_execute=values->begin
            calls[]+=1
            copy(values)
        end,
        baseline_name="garamon_julia_standard_fixture",
        baseline_scenario=(values,case)->Dict("seeded_inputs"=>values),
        baseline_output_identity=values->bytes2hex(sha256(UInt8.(values))),
        oracle=(values,result)->result==values,
        contract="owned copy of the same eight seeded integers")
    limits=Dict{String,Any}("samples"=>3,"case_seconds"=>30,
        "build_disk_bytes"=>1<<20,"controller_rss_bytes"=>8<<30)
    mktempdir() do root
        cache=(root=joinpath(root,"_baselines"),
            context=Dict{String,Any}("machine"=>"same_machine",
                "sources"=>"same_source"))
        first=Dict{String,Any}("adapter"=>adapter.name,"family"=>"fixture",
            "dimension"=>2,"strategy"=>"candidate_a","seed"=>17,
            "baseline_required"=>true)
        first_rows,first_verdict=GaramonBench.run_case(adapter,first,limits;baseline_cache=cache)
        @test !first_verdict["baseline_cache_hit"]
        @test count(row->row.phase=="baseline_warm",first_rows)==3
        measured_calls=calls[]
        second=merge(first,Dict("strategy"=>"candidate_b"))
        second_rows,second_verdict=GaramonBench.run_case(adapter,second,limits;baseline_cache=cache)
        @test second_verdict["baseline_cache_hit"]
        @test calls[]==measured_calls
        @test count(row->row.phase=="baseline_warm",second_rows)==0
        @test count(row->row.phase=="warm",second_rows)==3
        changed=merge(second,Dict("seed"=>18))
        _,changed_verdict=GaramonBench.run_case(adapter,changed,limits;baseline_cache=cache)
        @test !changed_verdict["baseline_cache_hit"]
        @test calls[]>measured_calls
    end
end
