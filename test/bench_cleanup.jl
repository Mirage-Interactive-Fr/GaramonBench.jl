using Test, TOML, GaramonBench

@testset "output permissions and stable fallback preserve resume" begin
    mktempdir() do root
        writable=joinpath(root,"normal")
        @test GaramonBench._prepare_bench_output(writable)==writable
        @test isempty(readdir(writable))
        if !Sys.iswindows() && ccall(:geteuid,Cuint,())!=0
            locked=joinpath(root,"locked");mkpath(locked);chmod(locked,0o555)
            fallback=joinpath(root,"fallback")
            try
                requested=joinpath(locked,"run-001")
                first=GaramonBench._prepare_bench_output(requested;fallback_root=fallback)
                @test startswith(first,fallback*"/")
                @test isempty(readdir(first))
                write(joinpath(first,"campaign.toml"),"completed = true\n")
                @test GaramonBench._prepare_bench_output(requested;fallback_root=fallback)==first
                @test read(joinpath(first,"campaign.toml"),String)=="completed = true\n"
                @test GaramonBench._prepare_bench_output(joinpath(locked,"run-002");fallback_root=fallback)!=first
            finally
                chmod(locked,0o755)
            end
            write(joinpath(locked,"campaign.toml"),"completed = true\n")
            chmod(locked,0o555)
            try
                @test_throws ArgumentError GaramonBench._prepare_bench_output(locked;fallback_root=fallback)
                @test read(joinpath(locked,"campaign.toml"),String)=="completed = true\n"
            finally
                chmod(locked,0o755)
            end
        end
    end
end

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

@testset "archived grade-product grids survive TOML reordering" begin
    row=only(filter(row->row["id"]=="03",technique_smoke_plan()))
    original=GaramonBench._resume_config(GaramonBench.technique_bench_config(row))
    cases=expand_cases(original)
    ids=case_id.(cases)
    @test length(ids)==168
    mktempdir() do archive
        config_file=joinpath(archive,"configuration.toml")
        manifest_file=joinpath(archive,"campaign.toml")
        manifest=Dict("case_ids"=>ids)
        GaramonBench.write_toml(config_file,original)
        GaramonBench.write_toml(manifest_file,manifest)
        restored=GaramonBench._technique_archive_config(archive)
        @test Dict(case_id(case)=>case for case in expand_cases(restored))==
            Dict(case_id(case)=>case for case in cases)
        @test case_id.(GaramonBench._technique_archived_cases(restored,manifest))==ids
        # Independent case identity, rather than enumeration order, defines
        # membership. Reporting retains the manifest's original order.
        manifest["case_ids"]=reverse(ids)
        GaramonBench.write_toml(manifest_file,manifest)
        @test GaramonBench._technique_archive_config(archive)==restored
        @test case_id.(GaramonBench._technique_archived_cases(restored,manifest))==reverse(ids)
        changed=deepcopy(restored)
        changed["grid"]["dimension"][1]=13
        GaramonBench.write_toml(config_file,changed)
        @test_throws ErrorException GaramonBench._technique_archive_config(archive)
        GaramonBench.write_toml(config_file,restored)
        manifest["case_ids"][end]=manifest["case_ids"][1]
        GaramonBench.write_toml(manifest_file,manifest)
        @test_throws ErrorException GaramonBench._technique_archive_config(archive)
    end
end

@testset "technique article data use validated same-case baselines" begin
    mktempdir() do root
        archive=joinpath(root,"benchmark","28")
        mkpath(archive)
        config=Dict{String,Any}("campaign"=>Dict("condition"=>"isolated","seed"=>17,
                "backend"=>"benchmarktools"),
            "grid"=>Dict("dimension"=>[2,3,4],"strategy"=>["fixture"]),
            "case_defaults"=>Dict("adapter"=>"fixture","baseline_required"=>true),
            "limits"=>Dict("samples"=>2,"max_cases"=>3))
        signature=repeat("a",64)
        cases=expand_cases(config)
        GaramonBench._resume_write(joinpath(archive,"campaign.toml"),Dict(
            "condition"=>"isolated","status"=>"running","run_signature"=>signature,
            "case_ids"=>case_id.(cases)))
        GaramonBench._resume_write(joinpath(archive,"configuration.toml"),config)
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
        caption_path=replace(report.figure_pdf,r"\.pdf$"=>"_caption.tex")
        @test occursin("median warm time",read(caption_path,String))
        @test occursin("time_ratio,over_baseline_budget",read(report.summary_csv,String))
        provenance=TOML.parsefile(joinpath(dirname(report.summary_csv),"provenance.toml"))
        @test provenance["total_cases"]==3 && provenance["completed_cases"]==2
        @test provenance["campaign_status"]=="running"
        # The current registry has a different grid for technique 28. An
        # output-only rebuild must use the grid recorded with these samples.
        from_raw=refresh_technique_article(root;ids=["28"],
            processed_root=joinpath(root,"raw-recovery"),
            figure_root=joinpath(root,"raw-plots"),paper_root=joinpath(root,"raw-paper"),
            publish_canonical=false)
        @test getproperty.(from_raw.figures,:completed_cases)==[2]
        text_tool=Sys.which("pdftotext")
        if !isnothing(text_tool)
            first_pages=read(Cmd([text_tool,"-f","1","-l","3","-layout",from_raw.article_pdf,"-"]),String)
            @test occursin("Benchmark results at a glance",first_pages)
            @test occursin("Verified paired timings are available for 1 of",first_pages)
            @test occursin("No observed gain",first_pages)
            @test occursin("2/3",first_pages)
        end
        recovered_config=GaramonBench._technique_archive_config(archive)
        @test recovered_config==config
        discovery=GaramonBench._article_recovery_index(joinpath(root,"another-campaign"),
            root,root)
        @test archive in discovery.archives["28"]
        raw_row=merge(row,Dict("case"=>Dict("adapter"=>"fixture","strategy"=>"fixture")))
        recovered=GaramonBench._recover_raw_technique_figure(raw_row,
            discovery.archives["28"],joinpath(root,"old-raw-reports"),
            joinpath(root,"old-raw-plots"))
        @test recovered.completed_cases==2
        # A retained plot can belong to a previous campaign. Its archived
        # paired measurements must be reused even when the current campaign
        # has no cases for that technique.
        original_summary=read(report.summary_csv)
        parameters_file=joinpath(dirname(report.summary_csv),"case_parameters.toml")
        original_parameters=read(parameters_file)
        write(report.figure_pdf,"legacy plot to regenerate")
        # The derived PDF's hash no longer matches. A unique intact data
        # report remains sufficient, including when stored in an old layout.
        legacy=joinpath(root,"gpu","data","processed","old-layout","28")
        mkpath(legacy)
        for file in ("summary.csv","case_parameters.toml","provenance.toml")
            cp(joinpath(dirname(report.summary_csv),file),joinpath(legacy,file))
        end
        rm(caption_path)
        rebuilt=refresh_technique_article(joinpath(root,"other-campaign");
            ids=["16"],processed_root=root,
            figure_root=joinpath(root,"plots"),paper_root=joinpath(root,"paper"),
            publish_canonical=false)
        @test getproperty.(rebuilt.figures,:id)==["28"]
        @test startswith(read(report.figure_pdf,String),"%PDF-")
        @test isfile(caption_path)
        @test read(report.summary_csv)==original_summary
        @test read(parameters_file)==original_parameters
        write(report.summary_csv,"changed summary")
        @test_throws GaramonBench.MissingTechniqueMeasurements GaramonBench._refresh_retained_technique_figure(
            row,joinpath(root,"processed"),joinpath(root,"plots"))
        write(report.summary_csv,original_summary)
        orphan=Dict("id"=>"16","name"=>"orphan")
        write(joinpath(root,"plots","plot_technique_16.pdf"),"untraceable legacy plot")
        @test_throws GaramonBench.MissingTechniqueMeasurements GaramonBench._refresh_retained_technique_figure(
            orphan,joinpath(root,"processed"),joinpath(root,"plots"))
        pending_path=joinpath(root,"plots","plot_technique_16_pending.tex")
        stale_caption=joinpath(root,"plots","plot_technique_16_caption.tex")
        write(stale_caption,"old unverified caption")
        @test_logs (:warn,r"Timing measurements are required") begin
            partial=refresh_technique_article(joinpath(root,"other-campaign");
                ids=["16"],processed_root=root,figure_root=joinpath(root,"plots"),
                paper_root=joinpath(root,"partial-paper"),publish_canonical=false)
            @test getproperty.(partial.pending_measurements,:id)==["16"]
            @test getproperty.(partial.figures,:id)==["28"]
            @test isfile(partial.article_pdf)
        end
        @test !isfile(joinpath(root,"plots","plot_technique_16.pdf"))
        @test !isfile(stale_caption) && isfile(pending_path)
        # Removing an old plot must not erase the pending measurement request.
        @test_logs (:warn,r"Timing measurements are required") begin
            partial=refresh_technique_article(joinpath(root,"other-campaign");
                ids=["16"],processed_root=root,figure_root=joinpath(root,"plots"),
                paper_root=joinpath(root,"partial-paper"),publish_canonical=false)
            @test getproperty.(partial.pending_measurements,:id)==["16"]
        end
        # Qualified new data replaces the pending slot automatically.
        GaramonBench._refresh_technique_benchmark_article(orphan,config,archive;
            processed_root=joinpath(root,"new-measurements"),
            figure_root=joinpath(root,"plots"),compile_article=false)
        @test !isfile(pending_path) && isfile(joinpath(root,"plots","plot_technique_16.pdf"))
        config["campaign"]["condition"]="exploratory_interference"
        @test_throws ErrorException GaramonBench._technique_report_rows(row,config,archive)
        config["campaign"]["condition"]="isolated"
        write(cache_path,"changed cached baseline")
        @test_throws ErrorException GaramonBench._technique_report_rows(row,config,archive)
    end
end

@testset "article synthesis separates unanimity from effect size" begin
    function entry(ratios;id="09",contract="exact")
        rows=[(;dimension=n,time_ratio=ratio) for (n,values) in ratios for ratio in values]
        GaramonBench._article_performance_entry(
            Dict("id"=>id,"name"=>"fixture","contract"=>contract),rows,length(rows)+2)
    end
    modest=entry([2=>[0.99,0.9999,0.98],3=>[0.98,0.97,0.96]])
    @test modest.group==:robust && modest.net==0 && modest.planned==8
    window=entry([2=>[0.99,0.9999],3=>[0.98,0.97],4=>[1.1,1.2]])
    @test window.group==:windows && window.unanimous==[2,3]
    mixed=entry([2=>[0.5,0.9,1.3],3=>[0.7,0.98,1.4]])
    @test mixed.group==:mixed && mixed.wins==4 && mixed.net==3
    @test entry([2=>[0.3,0.8],3=>[0.4,1.2]]).group==:isolated
    @test entry([2=>[1.0,1.2]]).group==:none
    @test entry([2=>[0.5]];id="02").group==:control
    @test entry([2=>[0.5]];contract="approximate").group==:approximate
    @test startswith(GaramonBench._article_ratio_tex(0.9999),"1-")
    fragment=sprint(io->GaramonBench._article_summary_tex(io,[window],48,[window]))
    @test occursin(raw"\ref{fig:technique-09}",fragment)
    @test occursin("All faster: 2, 3",fragment)
end

@testset "technique plots distinguish measured scenario categories" begin
    parameters=Dict(
        "a"=>Dict("strategy"=>"dense","support"=>"basis","signature"=>"mixed"),
        "b"=>Dict("strategy"=>"dense","support"=>"broad","signature"=>"mixed"),
        "c"=>Dict("strategy"=>"sparse","support"=>"basis","signature"=>"mixed"),
        "d"=>Dict("strategy"=>"sparse","support"=>"broad","signature"=>"mixed"))
    rows=[(;case_id=id) for id in ("a","b","c","d")]
    @test GaramonBench._technique_plot_axes(rows,parameters)==("strategy","support")
    caption=GaramonBench._technique_caption_text(rows,parameters,8)
    @test occursin("4 of 8 planned cases",caption)
    @test occursin("pattern of nonzero input blades",caption)
    parameters["c"]["strategy"]="dense"
    parameters["d"]["strategy"]="dense"
    @test GaramonBench._technique_plot_axes(rows,parameters)==("support","")

    dag_cases=Dict(
        "a"=>Dict("structure"=>"shared","dimension"=>3),
        "b"=>Dict("structure"=>"distinct","dimension"=>3),
        "c"=>Dict("structure"=>"shared","dimension"=>4),
        "d"=>Dict("structure"=>"distinct","dimension"=>4))
    @test GaramonBench._technique_plot_axes(rows,dag_cases)==("structure","")
    @test occursin("shared or distinct",
        GaramonBench._technique_axis_meaning("structure"))

    catalogue_cases=Dict(
        "a"=>Dict("scenario"=>"known","horizon"=>1,"request_index"=>1),
        "b"=>Dict("scenario"=>"late","horizon"=>8,"request_index"=>4),
        "c"=>Dict("scenario"=>"changing","horizon"=>32,"request_index"=>12),
        "d"=>Dict("scenario"=>"late","horizon"=>32,"request_index"=>1))
    @test GaramonBench._technique_plot_axes(rows,catalogue_cases)==("scenario","")
    catalogue_caption=GaramonBench._technique_caption_text(rows,catalogue_cases,21)
    @test occursin("horizon=1/8/32",catalogue_caption)
    @test occursin("request\\_index=1/4/12",catalogue_caption)

    near_baseline=[(time_ratio=0.5,),(time_ratio=1.5,)]
    low,high,marker_y=GaramonBench._technique_ratio_limits(near_baseline)
    @test 0.1<low<0.5 && 1.5<high<10 && isnothing(marker_y)
    @test GaramonBench._technique_ratio_ticks(low,high)[1]==[0.5,1.0]
    wide=[(time_ratio=0.03,),(time_ratio=14.0,)]
    low,high,marker_y=GaramonBench._technique_ratio_limits(wide;
        has_exclusions=true)
    @test low<0.03 && high>14 && 14<marker_y<high
end

@testset "article rendering overrides an inherited XKCD theme" begin
    @eval import CairoMakie
    cairo=CairoMakie
    previous=cairo.Makie.current_default_theme()
    try
        @eval import XKCDMakie
        cairo.set_theme!(XKCDMakie.theme_xkcd())
        mktempdir() do directory
            parameters=Dict("a"=>Dict("structure"=>"shared"),
                "b"=>Dict("structure"=>"distinct"))
            rows=[(case_id="a",dimension=3,time_ratio=0.6),
                (case_id="b",dimension=4,time_ratio=1.2)]
            figure=joinpath(directory,"plot.pdf")
            GaramonBench._render_technique_plot_loaded(cairo,
                Dict("id"=>"16","name"=>"DAG"),rows,parameters,2,figure)
            @test cairo.Makie.current_default_theme()[:xkcd_enabled][]==true
            fonts_tool=Sys.which("pdffonts")
            if isnothing(fonts_tool)
                @test_skip false
            else
                @test !occursin("xkcd",lowercase(read(`$fonts_tool $figure`,String)))
            end
            if !isnothing(Sys.which("latexmk")) && !isnothing(fonts_tool)
                legacy=joinpath(directory,"legacy.pdf")
                GaramonBench._draw_technique_plot(cairo,
                    Dict("id"=>"16","name"=>"DAG"),rows,parameters,2,legacy)
                @test occursin("xkcd",lowercase(read(`$fonts_tool $legacy`,String)))
                source=joinpath(directory,"article.tex")
                write(source,"\\documentclass{article}\\usepackage{graphicx}\\begin{document}\\includegraphics[width=5cm]{plot.pdf}\\end{document}")
                # A stale plot in the caller's directory must not shadow the
                # freshly generated file passed through the figure directory.
                figures=joinpath(directory,"fresh");mkpath(figures)
                cp(figure,joinpath(figures,"plot.pdf"))
                cp(legacy,figure;force=true)
                pdf=cd(directory) do
                    GaramonBench._compile_bench_article(source,figures,
                        joinpath(directory,"paper");publish_canonical=false)
                end
                @test !occursin("xkcd",lowercase(read(`$fonts_tool $pdf`,String)))
                published=read(pdf)
                cp(legacy,joinpath(figures,"plot.pdf");force=true)
                @test_throws ErrorException GaramonBench._compile_bench_article(
                    source,figures,joinpath(directory,"paper");publish_canonical=false)
                @test read(pdf)==published
            end
        end
    finally
        cairo.set_theme!(previous)
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
