using Test, GaramonBench, TOML, JSON
include("recipe_k1.jl")
include("profiling.jl")
include("bounds_b1.jl")
include("resume.jl")
include("techniques.jl")

@testset "article figures retain measured values and conditional slots" begin
    source=joinpath(pkgdir(GaramonBench),"papers",
        "Garamon_research_article_2026-09-27_en.tex")
    blocks=GaramonBench._article_exploratory_blocks(source)
    @test length(blocks)==29
    @test blocks["cpppacked"][1][2]==[.566444,.138876,.362696,.741087]
    @test blocks["n05temps"][2][1]==[1.0,2.0,4.0]
    content=read(source,String)
    @test all(occursin("exploratory_"*key*".pdf",content)
        for key in keys(blocks))
    @test occursin("exploratory_resident-highdim.pdf",content)
    @test occursin("ega3_vector_libraries.pdf",content)
end

@testset "portable Garamon C++ source and toolchain" begin
    source=ensure_cpp_source()
    @test source==ensure_cpp_source()
    @test cpp_source_revision(source)==GaramonBench.CPP_SOURCE_REVISION
    @test isfile(joinpath(source,"CMakeLists.txt"))
    toolchain=cpp_toolchain()
    @test all(isfile,(toolchain.cmake,toolchain.cc,toolchain.cxx,toolchain.ninja,
        joinpath(toolchain.eigen,"Eigen3Config.cmake")))
    config=load_config(joinpath(@__DIR__,"..","config","cpp_matched.toml"))
    @test GaramonBench.configured_repositories(config)["cpp"]==source
end

@testset "optional pinned external GA sources" begin
    catalogue=external_ga_candidates()
    @test length(catalogue)==6
    @test Set(row["name"] for row in catalogue)==
        Set(("gatl","versor","gal","klein","gafro","grassmann_jl"))
    @test all(length(row["revision"])==40 && length(row["git_tree_sha1"])==40
              for row in catalogue)
    @test all(row["status"]=="ega3_vector_product_adapter_oracle_qualified"
              for row in catalogue if row["name"] in ("gal","versor"))
    @test all(row["status"]=="source_only_adapter_and_oracle_not_qualified"
              for row in catalogue if !(row["name"] in ("gal","versor")))
    @test all(startswith(row["artifact"],"ga_") for row in catalogue)
    @test_throws ArgumentError ensure_external_ga_source("unknown")
    root=ensure_external_ga_source("gatl")
    @test root==ensure_external_ga_source("GATL")
    @test isfile(joinpath(root,"cpp","include","gatl","ga3e.hpp"))
end

@testset "configuration and DrWatson identities" begin
    config=load_config(joinpath(@__DIR__,"..","config","smoke.toml"))
    cases=expand_cases(config)
    @test length(cases)==2
    @test length(unique(case_id.(cases)))==2
    @test case_id(cases[1])==case_id(Dict(reverse(collect(cases[1]))))
    changed=copy(cases[1]); changed["seed"]+=1
    @test case_id(changed)!=case_id(cases[1])
end

@testset "external evidence validation (synthetic fixture)" begin
    mktempdir() do directory
        cases=GaramonBench.cpp_expected_cases(true)
        warmheader="dimension,corpus,horizon,strategy,comparison_group,status,median_ms,p95_ms,allocated_julia_bytes,samples\n"
        rows=["3,mixed,32,$(case["strategy"]),test-group,pass,1,2,0,1" for case in cases]
        warm=joinpath(directory,"cpp-matched-warm.csv")
        write(warm,warmheader*join(rows,"\n")*"\n")
        rawheader="dimension,corpus,horizon,strategy,sample,time_ns,gc_time_ns,allocated_julia_bytes,julia_allocations\n"
        write(joinpath(directory,"cpp-matched-samples.csv"),rawheader*
              join(["3,mixed,32,$(case["strategy"]),1,1000000,0,0,0" for case in cases],"\n")*"\n")
        qualification=Dict("verdict"=>"validated","runs"=>
            [Dict("status"=>"pass","feature"=>"cpp_3_mixed_32_$(case["strategy"])") for case in cases])
        path=joinpath(directory,"cpp-matched-qualification-d3.json")
        write(path,JSON.json(qualification))
        @test length(GaramonBench.verify_cpp_artifacts(directory,cases))==4
        write(warm,replace(warmheader*join(rows,"\n"),",pass,"=>",failed,";count=1))
        @test_throws ErrorException GaramonBench.verify_cpp_artifacts(directory,cases)
        write(warm,warmheader*join(rows,"\n"))
        qualification["verdict"]="provisional"
        write(path,JSON.json(qualification))
        @test_throws ErrorException GaramonBench.verify_cpp_artifacts(directory,cases)
    end
end

@testset "source snapshots include dirty and untracked content" begin
    mktempdir() do root
        write(joinpath(root,"tracked.jl"),"f()=1\n")
        first=repository_identity(root)
        write(joinpath(root,"untracked.jl"),"g()=2\n")
        second=repository_identity(root)
        @test first["sha256"]!=second["sha256"]
        mkdir(joinpath(root,"data")); write(joinpath(root,"data","Template.hpp"),"int f();\n")
        third=repository_identity(root)
        @test second["sha256"]!=third["sha256"]
        write(joinpath(root,"discard.so"),UInt8[0,1,2])
        @test third["sha256"]==repository_identity(root)["sha256"]
        @test_throws ErrorException archive_file!(joinpath(root,"discard.so"),joinpath(root,"copy.so"))
    end
end

@testset "temporary build cleanup on failure" begin
    observed=Ref("")
    @test_throws ErrorException with_build_directory() do dir
        observed[]=dir; write(joinpath(dir,"binary.o"),UInt8[1,2]); error("deliberate failure")
    end
    @test !ispath(observed[])
end

@testset "process failures do not serialize environment values" begin
    command=addenv(Cmd([first(Base.julia_cmd()),"--startup-file=no","-e","exit(7)"]),
                   "GARAMONBENCH_TEST_SECRET"=>"sentinel_value_must_not_be_archived")
    caught=try
        run(pipeline(command;stdout=devnull,stderr=devnull)); nothing
    catch exception
        exception
    end
    @test caught isa Base.ProcessFailedException
    @test GaramonBench.failure_exit_codes(caught)==[7]
    @test !occursin("sentinel_value",GaramonBench.failure_message(caught))
    @test !occursin("setenv",GaramonBench.failure_message(caught))
end

@testset "full raw-sample archive and exact oracle" begin
    register_smoke_adapter!()
    config=load_config(joinpath(@__DIR__,"..","config","smoke.toml"))
    mktempdir() do output
        run=run_campaign(config;output_root=output)
        manifest=TOML.parsefile(joinpath(run,"run.toml"))
        @test manifest["status"]=="passed"
        @test manifest["cases_passed"]==2
        @test manifest["condition"]=="exploratory_interference"
        @test manifest["not_a_perfchecker_campaign"]==false
        @test all(v["perfchecker_verdict"]=="validated" for v in manifest["case_verdicts"])
        @test occursin("warm",read(joinpath(run,"samples.csv"),String))
        @test all(v["oracle_passed"] for v in manifest["case_verdicts"])
        @test isfile(joinpath(run,"sources","benchmark","src","GaramonBench.jl"))
    end
end

@testset "slow case preserves the requested raw sample count" begin
    adapter=BenchmarkAdapter(name="slow_sample_count",
        contract="owned exact Int64 squares; harness sample-deadline regression",
        generate=(case,dir,rng)->Int64[1,2],
        execute=state->begin
            sleep(0.02)
            state.*state
        end,
        oracle=(state,result)->result==Int64[1,4],
        capabilities=Dict("scientific_garamon_result"=>false))
    case=first(expand_cases(load_config(joinpath(@__DIR__,"..","config","smoke.toml"))))
    rows,verdict=GaramonBench.run_case_perfchecker(adapter,case,
        Dict("samples"=>3,"sample_seconds"=>0.001,"case_seconds"=>5))
    @test count(row->row.phase=="warm",rows)==3
    @test verdict["perfchecker_samples_verified"]==3
    @test verdict["oracle_passed"]
end

@testset "recipe catalogue, limits and checked adapters" begin
    template=TOML.parsefile(joinpath(@__DIR__,"..","config","recipe.toml"))
    catalogue=TOML.parsefile(joinpath(@__DIR__,"..","config","campaigns.toml"))["campaign"]
    @test length(catalogue)==13
    for entry in catalogue
        config=deepcopy(template); config["recipe"]["id"]=entry["id"]
        @test recipe_plan(config)["recipe"]["id"]==entry["id"]
    end
    bad=deepcopy(template); bad["recipe"]["threads"]=8
    @test_throws ErrorException recipe_plan(bad)
    bad=deepcopy(template); bad["recipe"]["id"]="parallel-batches"
    bad["parameters"]["worker_counts"]=[8]
    @test_throws ErrorException recipe_plan(bad)
    bad["recipe"]["condition"]="isolated"
    @test recipe_plan(bad)["parameters"]["worker_counts"]==[8]
    bad=deepcopy(template); bad["parameters"]["typo"]=true
    @test_throws ErrorException recipe_plan(bad)
    bad=deepcopy(template); bad["limits"]["wall_seconds"]=-1
    @test_throws ErrorException recipe_plan(bad)
    @test_throws ErrorException GaramonBench.recipe_adapt("changed interface", "long-horizon", true)
    adapted,changes=GaramonBench.recipe_adapt("result=run_suite(suite)","long-horizon",true)
    @test occursin("GaramonRecipeCapture.run_suite",adapted)
    @test length(changes)==1
    if Sys.islinux()
        mktempdir() do temp
            limits=Dict("rss_bytes"=>1<<30,"scratch_bytes"=>1<<20)
            command=Cmd([first(Base.julia_cmd()),"--startup-file=no","-e","sleep(10)"])
            result=GaramonBench.recipe_supervise(command,joinpath(temp,"child.txt"),temp,limits,time()+0.4)
            @test result["budget_exceeded"]=="wall_seconds"
            @test !result["process_success"]
        end
    end
end

@testset "binary-rank episode screening recipe" begin
    config=TOML.parsefile(joinpath(@__DIR__,"..","config","recipe.toml"))
    config["recipe"]["id"]="binary-rank"
    config["recipe"]["profile"]="full"
    config["parameters"]["mode"]="episode_screen"
    plan=recipe_plan(config)
    @test plan["parameters"]["mode"]=="episode_screen"
    @test plan["recipe"]["threads"]==1
    # A synthetic file only satisfies path validation; no driver is executed.
    mktempdir() do root
        mkpath(joinpath(root,"perf"))
        write(joinpath(root,"perf","binary_rank_compare.jl"),"# test fixture\n")
        jobs=GaramonBench.recipe_external_jobs(plan,root,joinpath(root,"results"))
        @test only(jobs).args[1]=="--episode_screen"
        @test only(jobs).threads==1
    end
    config["recipe"]["profile"]="smoke"
    @test_throws ErrorException recipe_plan(config)
    config["recipe"]["profile"]="full"
    config["parameters"]["mode"]="prepare"
    @test_throws ErrorException recipe_plan(config)
end

@testset "N05 recipe configuration, arguments and guarded adapter" begin
    config=TOML.parsefile(joinpath(@__DIR__,"..","config","recipe.toml"))
    config["recipe"]["id"]="n05-pfaffian"
    plan=recipe_plan(config)
    @test plan["recipe"]["profile"]=="smoke"
    @test plan["parameters"]["reverse"]==false
    stub="if abspath(PROGRAM_FILE)==@__FILE__\n using PerfChecker\nend\ninclude(\"n05_pfaffian.jl\")\ninclude(\"n05_shards.jl\")\nresult=run_suite(suite)\nif abspath(PROGRAM_FILE)==@__FILE__\n n05_campaign(output)\nend\n"
    adapted,changes=GaramonBench.recipe_adapt(stub,"n05-pfaffian",true)
    @test length(findall("if true # packaged recipe entrypoint",adapted))==2
    @test occursin("GaramonRecipeCapture.run_suite(suite)",adapted)
    @test occursin("include(joinpath(@__DIR__,\"n05_pfaffian.jl\"))",adapted)
    @test occursin("preexisting_contractions",last(changes))
    @test_throws ErrorException GaramonBench.recipe_adapt(replace(stub,"include(\"n05_pfaffian.jl\")"=>"include(\"changed.jl\")"),"n05-pfaffian",true)
    mktempdir() do root
        mkpath(joinpath(root,"perf")); write(joinpath(root,"perf","n05_compare.jl"),stub)
        write(joinpath(root,"perf","n05_protocol.toml"),"protocol = \"fixture\"\n")
        smoke=only(GaramonBench.recipe_external_jobs(plan,root,joinpath(root,"smoke")))
        @test smoke.args[1]=="--smoke"
        @test smoke.threads==1
        config["recipe"]["profile"]="full"; config["parameters"]["reverse"]=true
        full=only(GaramonBench.recipe_external_jobs(recipe_plan(config),root,joinpath(root,"full")))
        @test full.args[1]=="--reverse"
        @test !("--smoke" in full.args) && !("--prepare-only" in full.args)
        identity=repository_identity(root)
        @test "perf/n05_protocol.toml" in getindex.(identity["files"],"path")
    end
    config["recipe"]["threads"]=8
    @test_throws ErrorException recipe_plan(config)
    config["recipe"]["threads"]=4
    @test_throws ErrorException recipe_plan(config) # N05 native controller requires one.
end

@testset "recipe condition propagation without stale isolated label" begin
    template=TOML.parsefile(joinpath(@__DIR__,"..","config","recipe.toml"))
    catalogue=TOML.parsefile(joinpath(@__DIR__,"..","config","campaigns.toml"))["campaign"]
    for entry in catalogue
        config=deepcopy(template); config["recipe"]["id"]=entry["id"]
        config["recipe"]["interference_label"]="Etendue3D"
        exploratory=recipe_plan(config)
        @test GaramonBench.recipe_condition_environment(exploratory)==Dict(
            "GARAMONBENCH_CONDITION"=>"exploratory_interference",
            "GARAMONBENCH_INTERFERENCE_LABEL"=>"Etendue3D")
        config["recipe"]["condition"]="isolated"
        isolated=recipe_plan(config)
        @test isolated["recipe"]["interference_label"]==""
        @test GaramonBench.recipe_condition_environment(isolated)==Dict(
            "GARAMONBENCH_CONDITION"=>"isolated","GARAMONBENCH_INTERFERENCE_LABEL"=>"")
    end
    expression="print(ENV[\"GARAMONBENCH_CONDITION\"], \"|\", ENV[\"GARAMONBENCH_INTERFERENCE_LABEL\"])"
    base=Cmd([first(Base.julia_cmd()),"--startup-file=no","--threads=1,0","-e",expression])
    inherited=addenv(base,"GARAMONBENCH_CONDITION"=>"exploratory_interference",
                    "GARAMONBENCH_INTERFERENCE_LABEL"=>"Etendue3D")
    config=deepcopy(template); config["recipe"]["interference_label"]="Etendue3D"
    @test read(GaramonBench.recipe_condition_command(inherited,recipe_plan(config)),String)=="exploratory_interference|Etendue3D"
    config["recipe"]["condition"]="isolated"
    @test read(GaramonBench.recipe_condition_command(inherited,recipe_plan(config)),String)=="isolated|"
end

@testset "N05 bounded manifest selections and fresh evidence" begin
    config=TOML.parsefile(joinpath(@__DIR__,"..","config","recipe.toml"))
    config["recipe"]["id"]="n05-pfaffian";config["recipe"]["profile"]="full"
    config["parameters"]=Dict{String,Any}("shard_index"=>1,"shard_count"=>1140)
    plan=recipe_plan(config);ids=GaramonBench.recipe_n05_case_ids(plan)
    @test length(ids)==32
    @test ids==collect(1:1140:36480)
    for badparameters in (Dict("shard_index"=>0,"shard_count"=>1140),Dict("shard_index"=>1),
        Dict("shard_index"=>1,"shard_count"=>100),Dict("shard_index"=>1141,"shard_count"=>1140),
        Dict("range_first"=>1,"range_last"=>33),Dict("range_first"=>0,"range_last"=>3),
        Dict("range_first"=>1,"range_last"=>36481),Dict("range_first"=>2,"range_last"=>1),
        Dict("range_first"=>1),Dict("shard_index"=>1,"shard_count"=>1140,"range_first"=>1,"range_last"=>2))
        bad=deepcopy(config);bad["parameters"]=badparameters
        @test_throws ErrorException recipe_plan(bad)
    end
    smoke=deepcopy(config);smoke["recipe"]["profile"]="smoke"
    @test_throws ErrorException recipe_plan(smoke)
    mktempdir() do root
        mkpath(joinpath(root,"perf"));write(joinpath(root,"perf","n05_compare.jl"),"# synthetic fixture\n")
        job=only(GaramonBench.recipe_external_jobs(plan,root,joinpath(root,"out")))
        @test "--shard=1/1140" in job.args
        @test !("--smoke" in job.args)
        config["parameters"]=Dict{String,Any}("range_first"=>10,"range_last"=>11,"reverse"=>true)
        plan=recipe_plan(config)
        @test GaramonBench.recipe_n05_case_ids(plan)==[11,10]
        job=only(GaramonBench.recipe_external_jobs(plan,root,joinpath(root,"out2")))
        @test "--range=10:11" in job.args && "--reverse" in job.args
        native=joinpath(root,"evidence");mkpath(native)
        metadata=Dict("grid_cases"=>36480,"grid_schema"=>"N05-grid-v1","grid_sha256"=>"synthetic",
            "selected_case_ids"=>[11,10],"completed_case_ids"=>[11,10],"completed"=>true,
            "failed_case_ids"=>Int[],"status"=>"qualified")
        path=joinpath(native,"n05-shard-environment.toml")
        GaramonBench.write_toml(path,metadata)
        for id in (11,10)
            write(joinpath(native,"n05-case-$id-qualification.json"),JSON.json(Dict("passed"=>true,"runs"=>[Dict("feature"=>"n05_case_$id")])) )
        end
        @test GaramonBench.recipe_verify_n05_selection(native,[11,10])["completed_case_ids"]==[11,10]
        @test_throws ErrorException GaramonBench.recipe_verify_n05_selection(native,[10,11])
        metadata["completed_case_ids"]=[11];GaramonBench.write_toml(path,metadata)
        @test_throws ErrorException GaramonBench.recipe_verify_n05_selection(native,[11,10])
    end
end
