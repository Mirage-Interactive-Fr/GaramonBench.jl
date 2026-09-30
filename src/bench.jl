function _external_article_dirs(archive::AbstractString,condition::AbstractString)
    signature=TOML.parsefile(joinpath(archive,"campaign.toml"))["run_signature"]
    archive_id=first(bytes2hex(sha256(abspath(archive))),12)
    figure_dir=DrWatson.plotsdir("garamonbench","external-ga-vectors",
        condition,first(signature,12),archive_id)
    paper_dir=DrWatson.papersdir("garamonbench","external-ga-vectors",
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
    isolated::Bool=false,cleanup::Symbol=:keep)
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
    preflight_output = run_resumable_campaign(preflight;
        output=joinpath(destination, "preflight"))
    resumable_status(preflight, preflight_output)["status"] == "complete" ||
        error("external GA preflight incomplete")
    condition=isolated ? "isolated" : "exploratory"
    article_source=joinpath(root,"papers","Garamon_research_article_2026-09-27_en.tex")
    function on_progress(archive,completed,total)
        isempty(completed) && return
        try
            julia=joinpath(Sys.BINDIR,Base.julia_exename())
            code="using GaramonBench; GaramonBench._refresh_external_article(ARGS[1],ARGS[2])"
            run(`$julia --startup-file=no --threads=1 --project=$root -e $code $archive $condition`)
        catch exception
            @warn "Article update failed; validated benchmark cases remain resumable" exception
        end
    end
    benchmark_output = run_resumable_campaign(benchmark;
        output=joinpath(destination, "benchmark"),on_progress)
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
