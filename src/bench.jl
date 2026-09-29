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

"""Run and resume the small EGA3 library comparison under DrWatson's data directory.

Use `bench(; isolated=true)` only when the caller has actually reserved the
machine for measurement. Repeating a call with the same output verifies and
skips completed cases.
"""
function bench(; output::Union{Nothing,AbstractString}=nothing, isolated::Bool=false)
    destination = isnothing(output) ? DrWatson.datadir("garamonbench", "external-ga-vectors",
        isolated ? "isolated" : "exploratory") : abspath(expanduser(output))
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
    return (;output=destination, preflight=preflight_output,
        benchmark=benchmark_output, summary_csv, figure_pdf, article_pdf,
        medians_ns=medians)
end
