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
            Dict("campaign"=>Dict("condition"=>"isolated")))
        mkpath(joinpath(benchmark,"cases","case-1"))
        write(joinpath(benchmark,"cases","case-1","samples.csv"),"raw")
        summary=joinpath(destination,"summary.csv")
        write(summary,"library,dimension,horizon,median_ns,condition\n"*
            "garamon_packed,3,1024,42,isolated\n")
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
