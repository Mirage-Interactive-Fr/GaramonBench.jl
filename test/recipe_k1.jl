using Test, GaramonBench, TOML, JSON

@testset "K1v2 parameters and fresh-process partition" begin
    config=TOML.parsefile(joinpath(@__DIR__,"..","config","recipe.toml"))
    config["recipe"]["id"]="k1-binary-rank"
    smoke=recipe_plan(config)
    @test smoke["parameters"]["mode"]=="decision_smoke"
    @test smoke["recipe"]["threads"]==1
    for p in (Dict("mode"=>"full"),Dict("mode"=>"prepare"),Dict("mode"=>"shards","dimensions"=>[2]),Dict("dimensions"=>[2]))
        bad=deepcopy(config);bad["parameters"]=p
        @test_throws ErrorException recipe_plan(bad)
    end
    config["recipe"]["profile"]="full"
    @test_throws ErrorException recipe_plan(config)
    for dims in ([],[1],[129],[true],[2.0],[2,2],"2:128")
        bad=deepcopy(config);bad["parameters"]=Dict("dimensions"=>dims)
        @test_throws ErrorException recipe_plan(bad)
    end
    config["parameters"]=Dict("mode"=>"shards","dimensions"=>[128,2])
    plan=recipe_plan(config)
    @test plan["parameters"]["dimensions"]==[2,128]
    for label in ("   ","bad\nlabel",repeat("x",257))
        bad=deepcopy(config);bad["recipe"]["interference_label"]=label
        @test_throws ErrorException recipe_plan(bad)
    end
    bad=deepcopy(config);bad["recipe"]["threads"]=2
    @test_throws ErrorException recipe_plan(bad)
    bad["recipe"]["threads"]=true
    @test_throws ErrorException recipe_plan(bad)
    isolated=deepcopy(config);isolated["recipe"]["condition"]="isolated"
    @test recipe_plan(isolated)["recipe"]["interference_label"]==""
    mktempdir() do root
        mkpath(joinpath(root,"perf"))
        controller=joinpath(root,"perf","binary_rank_compact_compare.jl")
        auditor=joinpath(root,"perf","binary_rank_compact_audit.jl")
        write(controller,"# fixture");write(auditor,"# fixture")
        jobs=GaramonBench.recipe_external_jobs(plan,root,joinpath(root,"results"))
        @test length(jobs)==4
        @test [j.name for j in jobs]==["k1-manifest","k1-n002","k1-n128","k1-coverage"]
        @test [j.measured for j in jobs]==[false,true,true,false]
        @test all(j->j.threads==1,jobs)
        @test jobs[1].args[1]=="--prepare"
        @test jobs[2].args[1:2]==["--shard","2"]
        @test jobs[3].args[1:2]==["--shard","128"]
        @test jobs[4].args[3:end]==[jobs[2].args[3],jobs[3].args[3]]
        @test jobs[4].script==auditor
        @test jobs[4].adaptation_id=="k1-audit"
        @test only(GaramonBench.recipe_external_jobs(smoke,root,joinpath(root,"smoke"))).args[1]=="--decision_smoke"
        screen=deepcopy(config);screen["parameters"]=Dict("mode"=>"decision_screen")
        @test only(GaramonBench.recipe_external_jobs(recipe_plan(screen),root,joinpath(root,"screen"))).args[1]=="--decision_screen"
        complete=deepcopy(config);complete["parameters"]["dimensions"]=collect(2:128)
        fulljobs=GaramonBench.recipe_external_jobs(recipe_plan(complete),root,joinpath(root,"all"))
        @test length(fulljobs)==129
        @test count(j->j.measured,fulljobs)==127
        @test [parse(Int,j.args[2]) for j in fulljobs if j.measured]==collect(2:128)
        @test all(j->!("--full" in j.args),fulljobs)
    end
    stub="include(\"binary_rank_compact_cases.jl\")\nrun_suite(suite)\nif abspath(PROGRAM_FILE)==@__FILE__\nend"
    adapted,changes=GaramonBench.recipe_adapt(stub,"k1-binary-rank",true)
    @test occursin("GaramonRecipeCapture.run_suite",adapted)
    @test occursin("include(joinpath(@__DIR__,\"binary_rank_compact_cases.jl\"))",adapted)
    @test occursin("if true # packaged recipe entrypoint",adapted)
    @test length(changes)==2
    @test_throws ErrorException GaramonBench.recipe_adapt(replace(stub,"binary_rank_compact_cases"=>"changed_cases"),"k1-binary-rank",true)
    auditor,_=GaramonBench.recipe_adapt("if abspath(PROGRAM_FILE)==@__FILE__\nend","k1-audit",false)
    @test !occursin("GaramonRecipeCapture",auditor)
end

@testset "K1v2 completion and evidence provenance" begin
    config=TOML.parsefile(joinpath(@__DIR__,"..","config","recipe.toml"))
    config["recipe"]["id"]="k1-binary-rank";plan=recipe_plan(config)
    mktempdir() do root
        native=joinpath(root,"native","decision_smoke");mkpath(native)
        ids=["fixture-$i" for i in 1:12]
        p=Dict("grid_version"=>"K1v2","case_count"=>12,"measurement_condition"=>"exploratory_interference",
            "interference_label"=>"Etendue3D","condition_declaration"=>"environment","completed"=>true,
            "source_unchanged"=>true,"execution_state"=>"completed","source_sha256"=>"fixture-sha","mode"=>"decision_smoke",
            "cases"=>[Dict("execution_id"=>id) for id in ids],"started_execution_ids"=>ids,"measured_execution_ids"=>ids,
            "passed_execution_ids"=>ids,"failed_execution_ids"=>String[],"not_started_execution_ids"=>String[])
        q=Dict("measurement_condition"=>"exploratory_interference","interference_label"=>"Etendue3D",
            "condition_declaration"=>"environment","source_fingerprint"=>"fixture-sha",
            "execution"=>Dict("threads"=>1,"measurement_condition"=>"exploratory_interference","interference_label"=>"Etendue3D"))
        qualification=Dict("passed"=>true,"runs"=>[Dict("status"=>"pass","qualification"=>deepcopy(q)) for _ in 1:12])
        protocol=joinpath(native,"k1-binary-rank-protocol.toml");evidence=joinpath(native,"k1-binary-rank-qualification.json")
        GaramonBench.write_toml(protocol,p);write(evidence,JSON.json(qualification))
        @test GaramonBench.recipe_verify_k1(root,plan)["executed_cases"]==12
        for (key,value) in (("measurement_condition","isolated"),("source_unchanged",false),("completed",false),("passed_execution_ids",ids[1:11]))
            bad=deepcopy(p);bad[key]=value;GaramonBench.write_toml(protocol,bad)
            @test_throws ErrorException GaramonBench.recipe_verify_k1(root,plan)
        end
        GaramonBench.write_toml(protocol,p)
        for (key,value) in (("interference_label","wrong"),("source_fingerprint","changed"),("condition_declaration","legacy_direct_default"))
            bad=deepcopy(qualification);bad["runs"][1]["qualification"][key]=value;write(evidence,JSON.json(bad))
            @test_throws ErrorException GaramonBench.recipe_verify_k1(root,plan)
        end
    end
end

@testset "K1v2 audit facade performs no measurements" begin
    mktempdir() do root
        mkpath(joinpath(root,"perf"));source=joinpath(root,"perf","binary_rank_compact_audit.jl")
        write(source,"using SHA\nfunction compact_coverage_audit(manifest, archives)\nDict(\"expected_cases\"=>41148, \"status\"=>\"partial\", \"distinct_qualified\"=>324, \"auditor_sha256\"=>bytes2hex(sha256(read(@__FILE__))))\nend\n")
        output=joinpath(root,"audit.toml")
        report=audit_k1(joinpath(root,"fixture-manifest"),output,[joinpath(root,"fixture-shard")];root)
        @test report["status"]=="partial"
        @test occursin("no new performance",TOML.parsefile(output)["operation"])
        @test_throws ErrorException audit_k1("manifest",output,["shard"];root)
        @test_throws ErrorException audit_k1("manifest",joinpath(root,"other.toml"),String[];root)
    end
end
