using Test, TOML, GaramonBench

@testset "bench cleanup retains paper artifacts and defaults to keep" begin
    mktempdir() do destination
        preflight=joinpath(destination,"preflight")
        benchmark=joinpath(destination,"benchmark")
        for archive in (preflight,benchmark)
            mkpath(joinpath(archive,"staging","unfinished"))
            write(joinpath(archive,"staging","unfinished","scratch"),"incomplete")
            GaramonBench._resume_write(joinpath(archive,"campaign.toml"),
                Dict("status"=>"complete","run_signature"=>"test-signature"))
        end
        GaramonBench._resume_write(joinpath(benchmark,"configuration.toml"),
            Dict("campaign"=>Dict("condition"=>"isolated"),
                "grid"=>Dict("strategy"=>["garamon_packed","gal","versor"])))
        mkpath(joinpath(benchmark,"cases","case-1"))
        write(joinpath(benchmark,"cases","case-1","samples.csv"),"raw")
        summary=joinpath(destination,"summary.csv")
        write(summary,"library,dimension,horizon,median_ns,condition\n"*
            "garamon_packed,3,1024,42,isolated\n"*
            "gal,3,1024,61,isolated\n"*
            "versor,3,1024,73,isolated\n")
        figure_dir=joinpath(destination,"plots")
        mkpath(figure_dir)
        figure=joinpath(figure_dir,"ega3_vector_libraries.pdf")
        write(figure,"synthetic figure")
        cp(figure,joinpath(figure_dir,"qualified_ega3_vector_libraries.pdf"))
        article=joinpath(destination,"article.pdf")
        write(article,"synthetic article")
        source=joinpath(@__DIR__,"..","papers",
            "Garamon_research_article_2026-09-27_en.tex")
        GaramonBench._resume_write(joinpath(destination,"report.toml"),Dict(
            "summary_csv"=>summary,
            "summary_sha256"=>GaramonBench._resume_sha(summary),
            "figure_pdf"=>figure,
            "figure_sha256"=>GaramonBench._resume_sha(figure),
            "article_pdf"=>article,
            "article_sha256"=>GaramonBench._resume_sha(article),
            "article_source_sha256"=>GaramonBench._resume_sha(source),
            "run_signature"=>"test-signature"))
        @test cleanup_bench_data(destination)==destination
        @test isfile(joinpath(benchmark,"cases","case-1","samples.csv"))
        processed=GaramonBench._publish_qualified_article_data(destination,
            GaramonBench._verified_bench_report(destination);
            processed_root=joinpath(destination,"processed"))
        @test read(processed)==read(summary)
        @test TOML.parsefile(joinpath(dirname(processed),"provenance.toml"))[
            "qualification"]=="complete_isolated_oracle_passed"
        @test cleanup_bench_data(destination;mode=:temporary)==destination
        @test isempty(readdir(joinpath(benchmark,"staging")))
        @test isfile(joinpath(benchmark,"cases","case-1","samples.csv"))
        @test cleanup_bench_data(destination;mode=:paper)==destination
        @test !ispath(preflight) && !ispath(benchmark)
        @test all(isfile,(summary,figure,article,
            joinpath(destination,"cleanup.toml")))
        @test cleanup_bench_data(destination;mode=:paper)==destination
        reused=bench(output=destination,isolated=true)
        @test reused.medians_ns["garamon_packed"]==42
        @test reused.benchmark===nothing
        completed_report=TOML.parsefile(joinpath(destination,"report.toml"))
        completed_report["article_source_sha256"]="source-updated-after-compaction"
        GaramonBench._resume_write(joinpath(destination,"report.toml"),completed_report)
        @test bench(output=destination,isolated=true).medians_ns["garamon_packed"]==42
        @test_throws ErrorException bench(output=destination,isolated=false)
        write(article,"changed article")
        @test_throws ErrorException cleanup_bench_data(destination;mode=:paper)
    end
    @test_throws ArgumentError cleanup_bench_data("/tmp";mode=:invalid)
end

@testset "native technique launcher preserves registered thread protocols" begin
    groups=technique_launch_plan()
    @test length(groups)==3
    @test Set(vcat(getproperty.(groups,:ids)...))==Set(r["id"] for r in technique_smoke_plan())
    @test only(filter(g->"27" in g.ids,groups)).threads==4
    @test only(filter(g->"29" in g.ids,groups)).environment=="gpu"
    @test all(g.threads==1 for g in groups if !("27" in g.ids))
    @test all(g.environment!="gpu" for g in technique_launch_plan(gpu=:off))
    @test length(technique_launch_plan(ids=["27"]))==1
    @test_throws ArgumentError technique_launch_plan(gpu=:invalid)
    @test_throws ErrorException technique_launch_plan(ids=["unknown"])
    group=only(technique_launch_plan(ids=["27"]))
    command=GaramonBench._technique_launch_command(group,"/tmp/benchmark","preflight",true,0)
    @test "--threads=4,0" in command.exec
    project_arg=only(filter(x->startswith(x,"--project="),command.exec))
    @test samefile(project_arg[length("--project=")+1:end],pkgdir(GaramonBench))
end

@testset "technique article data use validated same-case baselines" begin
    mktempdir() do root
        archive=joinpath(root,"benchmark","28")
        mkpath(archive)
        config=Dict{String,Any}("campaign"=>Dict("condition"=>"isolated","seed"=>17),
            "grid"=>Dict("dimension"=>[2,3,4],"strategy"=>["fixture"]),
            "case_defaults"=>Dict("adapter"=>"fixture","baseline_required"=>true),
            "limits"=>Dict("samples"=>2,"max_cases"=>3))
        signature=repeat("a",64)
        GaramonBench._resume_write(joinpath(archive,"campaign.toml"),Dict(
            "condition"=>"isolated","status"=>"running","run_signature"=>signature))
        cases=expand_cases(config)
        cache_path=joinpath(root,"benchmark","_baselines",repeat("b",64)*".toml")
        mkpath(dirname(cache_path))
        GaramonBench._resume_write(cache_path,Dict("time_ns"=>[2.0,2.0]))
        for (index,case) in enumerate(cases[1:2])
            id=case_id(case)
            directory=joinpath(archive,"cases",id)
            mkpath(directory)
            GaramonBench._resume_write(joinpath(directory,"case.toml"),case)
            records=[(case_id=id,phase="warm",sample=i,time_ns=index==1 ? 3.0 : 24.0) for i in 1:2]
            index==1 && append!(records,[(case_id=id,phase="baseline_warm",sample=i,time_ns=2.0) for i in 1:2])
            GaramonBench.write_csv(joinpath(directory,"samples.csv"),records)
            verdict=Dict{String,Any}("case_id"=>id,"oracle_passed"=>true,
                "benchmark_backend"=>"BenchmarkTools","baseline_required"=>true,
                "baseline_oracle_passed"=>true,"baseline_samples_verified"=>2,
                "baseline_name"=>"standard_same_fixture")
            if index==2
                verdict["baseline_cache_file"]=relpath(cache_path,directory)
                verdict["baseline_cache_sha256"]=GaramonBench._resume_sha(cache_path)
                verdict["baseline_cache_hit"]=true
            end
            GaramonBench._resume_write(joinpath(directory,"verdict.toml"),verdict)
            marker=Dict{String,Any}("case_id"=>id,"status"=>"validated",
                "run_signature"=>signature,"warm_samples"=>2,"record_count"=>length(records),
                "diagnostic_artifacts"=>Any[])
            for (file,key) in (("case.toml","case_sha256"),("samples.csv","samples_sha256"),("verdict.toml","verdict_sha256"))
                marker[key]=GaramonBench._resume_sha(joinpath(directory,file))
            end
            GaramonBench._resume_write(joinpath(directory,"completion.toml"),marker)
        end
        row=Dict("id"=>"28","name"=>"fixture")
        rows,parameters=GaramonBench._technique_report_rows(row,config,archive)
        @test length(rows)==2 # The uncompleted third case is never plotted.
        @test getproperty.(rows,:time_ratio)==[1.5,12.0]
        @test getproperty.(rows,:over_baseline_budget)==[false,true]
        @test parameters[case_id(cases[2])]==cases[2]
        report=GaramonBench._refresh_technique_benchmark_article(row,config,archive;
            processed_root=joinpath(root,"processed"),figure_root=joinpath(root,"plots"),
            compile_article=false)
        @test report.completed_cases==2
        @test startswith(read(report.figure_pdf,String),"%PDF-")
        @test occursin("time_ratio,over_baseline_budget",read(report.summary_csv,String))
        provenance=TOML.parsefile(joinpath(dirname(report.summary_csv),"provenance.toml"))
        @test provenance["total_cases"]==3 && provenance["completed_cases"]==2
        @test provenance["campaign_status"]=="running"
        config["campaign"]["condition"]="exploratory_interference"
        @test_throws ErrorException GaramonBench._technique_report_rows(row,config,archive)
        config["campaign"]["condition"]="isolated"
        write(cache_path,"changed cached baseline")
        @test_throws ErrorException GaramonBench._technique_report_rows(row,config,archive)
    end
end

@testset "concurrent article builds publish complete PDFs" begin
    @test GaramonBench._article_plotsdir("probe") ==
        joinpath(pkgdir(GaramonBench),"plots","probe")
    @test GaramonBench._article_papersdir("probe") ==
        joinpath(pkgdir(GaramonBench),"papers","probe")
    if isnothing(Sys.which("latexmk"))
        @test_skip false
    else
        mktempdir() do directory
            source=joinpath(directory,"article.tex")
            write(source,"\\documentclass{article}\n\\begin{document}\nConcurrent publication.\n\\end{document}\n")
            figures=joinpath(directory,"plots")
            papers=joinpath(directory,"papers")
            mkpath(figures)
            tasks=[@async GaramonBench._compile_bench_article(source,figures,papers)
                for _ in 1:2]
            outputs=fetch.(tasks)
            @test outputs[1]==outputs[2]
            @test startswith(read(outputs[1],String),"%PDF-")
            @test occursin("%%EOF",read(outputs[1],String))
            @test read(joinpath(directory,"article.pdf"))==read(outputs[1])
            @test readdir(papers)==["article.pdf"]
        end
    end
end
