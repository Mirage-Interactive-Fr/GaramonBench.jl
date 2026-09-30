function _external_article_dirs(archive::AbstractString,condition::AbstractString)
    signature=TOML.parsefile(joinpath(archive,"campaign.toml"))["run_signature"]
    archive_id=first(bytes2hex(sha256(abspath(archive))),12)
    figure_dir=_article_plotsdir("garamonbench","external-ga-vectors",
        condition,first(signature,12),archive_id)
    paper_dir=_article_papersdir("garamonbench","external-ga-vectors",
        condition,first(signature,12),archive_id)
    figure_dir,paper_dir,signature
end

function _sync_qualified_external_figure(figure::AbstractString,
    condition::AbstractString,completed::Integer,expected::Integer)
    qualified=joinpath(dirname(figure),"qualified_ega3_vector_libraries.pdf")
    if condition=="isolated" && completed==expected
        cp(figure,qualified;force=true)
    elseif isfile(qualified)
        rm(qualified)
    end
    qualified
end

function _refresh_external_article(archive::AbstractString,condition::AbstractString)
    root=dirname(@__DIR__)
    benchmark=load_config(joinpath(root,"config","external_ga_vector_bench.toml"))
    benchmark["campaign"]["condition"]=condition
    figure_dir,paper_dir,_=_external_article_dirs(archive,condition)
    source=joinpath(root,"papers","Garamon_research_article_2026-09-27_en.tex")
    rows=_bench_completed_rows(benchmark,archive)
    figure=joinpath(figure_dir,"ega3_vector_libraries.pdf")
    isempty(rows) || _render_bench_plot(rows,figure)
    expected=length(benchmark["grid"]["strategy"])
    _sync_qualified_external_figure(figure,condition,length(rows),expected)
    pdf=_compile_bench_article(source,figure_dir,paper_dir;
        publish_canonical=condition=="isolated")
    println("Article updated: ",length(rows),"/",expected," validated routes; ",pdf)
    pdf
end

function _verified_bench_report(destination::AbstractString;check_source::Bool=true)
    path=joinpath(destination,"report.toml")
    isfile(path) || error("benchmark report is missing; cleanup requires a completed article")
    report=TOML.parsefile(path)
    for (name,digest) in (("summary_csv","summary_sha256"),
        ("figure_pdf","figure_sha256"),("article_pdf","article_sha256"))
        artifact=report[name]
        isfile(artifact) && _resume_sha(artifact)==report[digest] ||
            error("benchmark artifact is missing or changed: "*name)
    end
    source=joinpath(dirname(@__DIR__),"papers",
        "Garamon_research_article_2026-09-27_en.tex")
    if check_source
        _resume_sha(source)==report["article_source_sha256"] ||
            error("article source changed after the completed PDF")
    end
    report
end

function _compact_bench_result(destination,report)
    rows=_report_rows(report["summary_csv"])
    medians=Dict(row["library"]=>parse(Float64,row["median_ns"])
        for row in rows)
    (;output=destination,preflight=nothing,benchmark=nothing,
        summary_csv=report["summary_csv"],figure_pdf=report["figure_pdf"],
        article_pdf=report["article_pdf"],medians_ns=medians)
end

"""Copy only a complete isolated paper table into DrWatson's processed data.
The raw campaign remains in data/garamonbench and stays outside Git.
"""
function _publish_qualified_article_data(destination,report;
        processed_root=DrWatson.datadir("processed","garamonbench"))
    benchmark=joinpath(destination,"benchmark")
    configuration=TOML.parsefile(joinpath(benchmark,"configuration.toml"))
    configuration["campaign"]["condition"]=="isolated" || return nothing
    manifest=TOML.parsefile(joinpath(benchmark,"campaign.toml"))
    manifest["status"]=="complete" &&
        manifest["run_signature"]==report["run_signature"] ||
        error("qualified article table requires a complete matching campaign")
    rows=_report_rows(report["summary_csv"])
    expected=Set(configuration["grid"]["strategy"])
    Set(row["library"] for row in rows)==expected && length(rows)==length(expected) &&
        all(row["condition"]=="isolated" for row in rows) ||
        error("qualified article table has missing or duplicate routes")
    signature=report["run_signature"]
    archive_id=first(bytes2hex(sha256(abspath(destination))),12)
    directory=joinpath(processed_root,"external-ga-vectors",first(signature,12),archive_id)
    mkpath(directory)
    source=report["summary_csv"]
    target=joinpath(directory,"summary.csv")
    if isfile(target)
        _resume_sha(target)==report["summary_sha256"] ||
            error("processed article table differs from the qualified campaign")
    else
        cp(source,target)
    end
    _resume_write(joinpath(directory,"provenance.toml"),Dict(
        "schema_version"=>1,"qualification"=>"complete_isolated_oracle_passed",
        "run_signature"=>signature,"summary_sha256"=>report["summary_sha256"],
        "article_source_sha256"=>report["article_source_sha256"],
        "figure_sha256"=>report["figure_sha256"],
        "article_sha256"=>report["article_sha256"],
        "library_count"=>length(rows)))
    target
end

"""
    cleanup_bench_data(output; mode=:keep)

`:keep` retains all data (the default). `:temporary` clears only unvalidated
staging contents after a completed report. `:paper` retains the verified
summary, figure, PDF and their hashes, then removes the preflight and raw
campaign archives. A compacted run remains readable on later `bench` calls.
"""
function cleanup_bench_data(output::AbstractString;mode::Symbol=:keep)
    mode in (:keep,:temporary,:paper) ||
        throw(ArgumentError("cleanup mode must be :keep, :temporary, or :paper"))
    destination=abspath(expanduser(output))
    mode==:keep && return destination
    marker=joinpath(destination,"cleanup.toml")
    report=_verified_bench_report(destination;check_source=!isfile(marker))
    if isfile(marker)
        compact=TOML.parsefile(marker)
        compact["run_signature"]==report["run_signature"] ||
            error("compacted run signature differs from the report")
        if mode==:paper
            for archive in (joinpath(destination,"preflight"),
                joinpath(destination,"benchmark"))
                islink(archive) && error("refusing to clean a linked archive")
                isdir(archive) && rm(archive;recursive=true)
            end
        end
        return destination
    end
    preflight=joinpath(destination,"preflight")
    benchmark=joinpath(destination,"benchmark")
    for archive in (preflight,benchmark)
        islink(archive) && error("refusing to clean a linked archive")
        isfile(joinpath(archive,"campaign.toml")) ||
            error("completed campaign manifest is missing: "*archive)
        TOML.parsefile(joinpath(archive,"campaign.toml"))["status"]=="complete" ||
            error("campaign is incomplete: "*archive)
    end
    configuration=TOML.parsefile(joinpath(benchmark,"configuration.toml"))
    condition=configuration["campaign"]["condition"]
    TOML.parsefile(joinpath(benchmark,"campaign.toml"))["run_signature"]==
        report["run_signature"] || error("campaign and article signatures differ")
    if condition=="isolated"
        qualified=joinpath(dirname(report["figure_pdf"]),
            "qualified_ega3_vector_libraries.pdf")
        isfile(qualified) && _resume_sha(qualified)==report["figure_sha256"] ||
            error("qualified isolated figure is missing or changed")
    end
    if mode==:temporary
        for archive in (preflight,benchmark)
            staging=joinpath(archive,"staging")
            isdir(staging) || continue
            for entry in readdir(staging;join=true)
                rm(entry;recursive=true)
            end
        end
        return destination
    end
    _resume_write(marker,Dict("mode"=>"paper","run_signature"=>report["run_signature"],
        "condition"=>condition,"summary_sha256"=>report["summary_sha256"],
        "figure_sha256"=>report["figure_sha256"],
        "article_sha256"=>report["article_sha256"],
        "completed_utc"=>string(now(UTC))))
    for archive in (preflight,benchmark)
        rm(archive;recursive=true)
    end
    destination
end

"""Run and resume the small EGA3 library comparison under DrWatson's data directory.

Use `bench(; isolated=true)` only when the caller has actually reserved the
machine for measurement. Repeating a call with the same output verifies and
skips completed cases.
"""
function bench(; output::Union{Nothing,AbstractString}=nothing,
    isolated::Bool=false,cleanup::Symbol=:keep,
    show_progress::Bool=true,campaign::Symbol=:external,
    ids=String[],gpu::Symbol=:auto,article_every_cases::Int=0)
    campaign in (:external,:techniques) || throw(ArgumentError("campaign must be :external or :techniques"))
    if campaign==:techniques
        isolated || throw(ArgumentError("the technique benchmark requires isolated=true on the dedicated machine"))
        cleanup==:keep || throw(ArgumentError("technique campaigns currently retain their auditable raw archives"))
        destination=isnothing(output) ? DrWatson.datadir(joinpath(dirname(@__DIR__),
            "data","garamonbench","techniques-dedicated-001")) : abspath(expanduser(output))
        return run_technique_campaign(destination;ids,gpu,show_progress,article_every_cases)
    end
    cleanup in (:keep,:temporary,:paper) ||
        throw(ArgumentError("cleanup must be :keep, :temporary, or :paper"))
    destination = isnothing(output) ? DrWatson.datadir("garamonbench", "external-ga-vectors",
        isolated ? "isolated" : "exploratory") : abspath(expanduser(output))
    compact_marker=joinpath(destination,"cleanup.toml")
    if isfile(compact_marker)
        cleanup==:paper && cleanup_bench_data(destination;mode=:paper)
        report=_verified_bench_report(destination;check_source=false)
        marker=TOML.parsefile(compact_marker)
        marker["condition"]==(isolated ? "isolated" : "exploratory") ||
            error("compacted benchmark uses a different isolation condition")
        marker["run_signature"]==report["run_signature"] ||
            error("compacted benchmark signature differs from its report")
        return _compact_bench_result(destination,report)
    end
    root = dirname(@__DIR__)
    preflight = load_config(joinpath(root, "config", "external_ga_vector_preflight.toml"))
    benchmark = load_config(joinpath(root, "config", "external_ga_vector_bench.toml"))
    for config in (preflight, benchmark)
        config["repositories"]["julia"] = pkgdir(Garamon)
    end
    if isolated
        for config in (preflight, benchmark)
            config["campaign"]["condition"] = "isolated"
            config["campaign"]["interference_label"] = ""
        end
    end
    preflight_meter=_campaign_meter("Preflight";enabled=show_progress)
    preflight_output=try
        result=run_resumable_campaign(preflight;
            output=joinpath(destination,"preflight"),
            on_progress=(archive,completed,total)->
                _campaign_meter_update!(preflight_meter,archive,completed,total))
        _campaign_meter_close!(preflight_meter;complete=true)
        result
    catch
        _campaign_meter_close!(preflight_meter;complete=false)
        rethrow()
    end
    resumable_status(preflight, preflight_output)["status"] == "complete" ||
        error("external GA preflight incomplete")
    condition=isolated ? "isolated" : "exploratory"
    article_source=joinpath(root,"papers","Garamon_research_article_2026-09-27_en.tex")
    benchmark_meter=_campaign_meter("Benchmark";enabled=show_progress)
    function on_progress(archive,completed,total)
        _campaign_meter_update!(benchmark_meter,archive,completed,total)
        isempty(completed) && return
        try
            julia=joinpath(Sys.BINDIR,Base.julia_exename())
            code="using GaramonBench; GaramonBench._refresh_external_article(ARGS[1],ARGS[2])"
            run(`$julia --startup-file=no --threads=1 --project=$root -e $code $archive $condition`)
        catch exception
            @warn "Article update failed; validated benchmark cases remain resumable" exception
        end
    end
    benchmark_output=try
        result=run_resumable_campaign(benchmark;
            output=joinpath(destination,"benchmark"),on_progress)
        _campaign_meter_close!(benchmark_meter;complete=true)
        result
    catch
        _campaign_meter_close!(benchmark_meter;complete=false)
        rethrow()
    end
    resumable_status(benchmark, benchmark_output)["status"] == "complete" ||
        error("external GA benchmark incomplete")

    summary_csv,rows=_bench_summary(benchmark,benchmark_output,destination)
    medians=Dict(row.library=>row.median_ns for row in rows)
    figure_dir,paper_dir,signature=_external_article_dirs(benchmark_output,condition)
    figure_pdf=_render_bench_plot(summary_csv,
        joinpath(figure_dir,"ega3_vector_libraries.pdf"))
    _sync_qualified_external_figure(figure_pdf,condition,length(rows),
        length(benchmark["grid"]["strategy"]))
    article_pdf=_compile_bench_article(article_source,figure_dir,paper_dir;
        publish_canonical=isolated)
    _resume_write(joinpath(destination,"report.toml"),
        Dict("summary_csv"=>summary_csv,"summary_sha256"=>_resume_sha(summary_csv),
            "figure_pdf"=>figure_pdf,"figure_sha256"=>_resume_sha(figure_pdf),
            "article_pdf"=>article_pdf,"article_sha256"=>_resume_sha(article_pdf),
            "article_source_sha256"=>_resume_sha(article_source),
            "run_signature"=>signature))
    isolated && _publish_qualified_article_data(destination,
        _verified_bench_report(destination))
    cleanup_bench_data(destination;mode=cleanup)
    println("EGA3 vector product; 1024 pairs per sample; 31 warm samples")
    println(isolated ? "Condition: isolated (declared by caller)" :
        "Condition: exploratory; replay on an isolated machine")
    for strategy in benchmark["grid"]["strategy"]
        println(strategy, ": median ", round(medians[strategy] / 1e3; digits=2),
            " µs per batch")
    end
    println("Archive: ", destination)
    println("CSV: ", summary_csv)
    println("Figure: ", figure_pdf)
    println("Article: ", article_pdf)
    return (;output=destination,
        preflight=cleanup==:paper ? nothing : preflight_output,
        benchmark=cleanup==:paper ? nothing : benchmark_output,
        summary_csv, figure_pdf, article_pdf,
        medians_ns=medians)
end

"""Plan native environments and thread counts without running or saving anything.
The controller may use `-t auto`; measurements use their declared protocol.
"""
function technique_launch_plan(;ids=String[],gpu::Symbol=:auto)
    gpu in (:auto,:required,:off) || throw(ArgumentError("gpu must be :auto, :required or :off"))
    rows=technique_smoke_plan()
    requested=Set(ids)
    isempty(requested) || issubset(requested,Set(r["id"] for r in rows)) || error("unknown technique ID")
    selected=isempty(requested) ? rows : filter(r->r["id"] in requested,rows)
    groups=Dict{Tuple{String,Int},Vector{String}}()
    for row in selected
        row["environment"]=="gpu" && gpu==:off && continue
        push!(get!(groups,(row["environment"],row["threads"]),String[]),row["id"])
    end
    [(environment=key[1],threads=key[2],ids=groups[key],
        project=normpath(joinpath(dirname(@__DIR__),key[1])))
        for key in sort!(collect(keys(groups));by=k->(k[1]=="gpu",k[2]))]
end

function _technique_launch_command(group,output,phase,show_progress,article_every_cases)
    code="""
    using GaramonBench, TOML
    phase, output, progress, every = ARGS[1:4]
    ids = ARGS[5:end]
    preflight = joinpath(output, "preflight")
    report = phase == "preflight" ? run_technique_smoke(preflight; ids) :
        phase == "profiles" ? run_technique_profiles(preflight, joinpath(output, "profiles"); ids) :
        run_technique_bench(preflight, joinpath(output, "benchmark"); ids,
            show_progress=progress=="true", article_every_cases=parse(Int,every))
    records = TOML.parsefile(report)["technique"]
    selected = filter(r->r["id"] in ids, records)
    expected = phase == "preflight" ? "oracle_passed" : phase == "profiles" ? "captured" : "complete"
    length(selected)==length(ids) && all(r->r["status"]==expected,selected) ||
        error("native stage incomplete; inspect "*report)
    phase == "benchmark" && !all(r->get(r,"article_status","")=="updated",selected) &&
        error("benchmark cases retained but article update incomplete; inspect "*report)
    println("Stage complete: ",phase,"; ",join(ids,", "))
    """
    julia=joinpath(Sys.BINDIR,Base.julia_exename())
    args=[julia,"--startup-file=no","--threads="*string(group.threads)*",0",
        "--gcthreads=1","--project="*group.project,"-e",code,
        string(phase),abspath(output),string(show_progress),string(article_every_cases)]
    append!(args,group.ids)
    addenv(Cmd(args),"OPENBLAS_NUM_THREADS"=>"1","OMP_NUM_THREADS"=>"1")
end

"""Run reproducible native groups sequentially, with automatic environment and
thread selection. Ctrl-C retains validated cases; repeat the same output path
to resume. `phase=:preflight` performs no timings; `:profiles` adds bounded
PerfChecker captures; `:benchmark` prepares and runs dedicated-machine grids.
"""
function run_technique_campaign(output;ids=String[],gpu::Symbol=:auto,
        phase::Symbol=:benchmark,show_progress::Bool=true,
        article_every_cases::Int=0)
    phase in (:preflight,:profiles,:benchmark) || throw(ArgumentError("invalid campaign phase"))
    article_every_cases>=0 || throw(ArgumentError("article_every_cases must be nonnegative"))
    VERSION>=v"1.13" || error("Julia 1.13 or later is required")
    groups=technique_launch_plan(;ids,gpu)
    destination=abspath(expanduser(output))
    mkpath(destination)
    _resume_lock(destination) do
        julia=joinpath(Sys.BINDIR,Base.julia_exename())
        # Instantiate every selected environment before measurements, so a
        # later GPU setup cannot change the source fingerprint of a CPU run.
        for project in unique(g.project for g in groups)
            run(`$julia --startup-file=no --threads=1,0 --project=$project -e "using Pkg; Pkg.instantiate()"`)
        end
        gpu_status=gpu==:off ? "disabled" : "not_requested"
        if any(g->g.environment=="gpu",groups)
            project=normpath(joinpath(dirname(@__DIR__),"gpu"))
            probe_code="using CUDA; exit(CUDA.functional() ? 0 : 2)"
            available=success(run(ignorestatus(`$julia --startup-file=no --threads=1,0 --project=$project -e $probe_code`)))
            gpu_status=available ? "available" : "unavailable"
            !available && gpu==:required && error("GPU required, but CUDA is not functional")
            if !available
                println("GPU unavailable: route 29 is recorded as skipped.")
                filter!(g->g.environment!="gpu",groups)
            end
        end
        records=Dict{String,Any}[]
        stages=phase==:preflight ? [:preflight] : [:preflight,phase]
        report=joinpath(destination,"launch-progress.toml")
        function save(status)
            _resume_write(report,Dict("status"=>status,"phase"=>string(phase),
                "gpu_status"=>gpu_status,"controller_threads"=>Threads.nthreads(),
                "logical_cpus"=>Sys.CPU_THREADS,"updated_utc"=>string(now(UTC)),
                "groups"=>records))
        end
        save("running")
        try
            for stage in stages, group in groups
                println("Stage ",stage,"; threads=",group.threads,
                    "; environment=",group.environment,"; routes=",join(group.ids,", "))
                run(_technique_launch_command(group,destination,stage,show_progress,article_every_cases))
                push!(records,Dict("stage"=>string(stage),"environment"=>group.environment,
                    "threads"=>group.threads,"ids"=>group.ids,"status"=>"complete"))
                save("running")
            end
            save(gpu_status=="unavailable" ? "complete_gpu_skipped" : "complete")
        catch
            save("interrupted")
            rethrow()
        end
        report
    end
end
