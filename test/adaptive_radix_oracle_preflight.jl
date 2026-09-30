using Test, GaramonBench, TOML

@testset "adaptive radix exact oracle and shared scenario baseline" begin
    row=only(filter(item->item["id"]=="43",technique_smoke_plan()))
    @test row["status"]=="runnable"
    config=GaramonBench.technique_smoke_config(row)
    @test length(expand_cases(config))==1
    GaramonBench.include_technique_adapter(joinpath(pkgdir(GaramonBench),row["adapter"]),config)
    mktempdir() do root
        output=joinpath(root,"preflight")
        @test run_resumable_campaign(config;output)==output
        @test audit_resumable_archive(config,output)["archive_integrity"]=="validated"
        case=only(expand_cases(config))
        case["baseline_required"]=true
        adapter=GaramonBench.ADAPTERS["garamon_adaptive_radix"]
        limits=merge(config["limits"],Dict("samples"=>2,"case_seconds"=>120))
        cache=(root=joinpath(root,"_baselines"),
            context=Dict{String,Any}("machine"=>"representative",
                "sources"=>"same_pinned_sources"))
        first_rows,first_verdict=Base.invokelatest(GaramonBench.run_case,
            adapter,case,limits;baseline_cache=cache)
        @test !first_verdict["baseline_cache_hit"]
        @test count(r->r.phase=="baseline_warm",first_rows)==2
        other=merge(case,Dict("index_policy"=>"rebuild"))
        second_rows,second_verdict=Base.invokelatest(GaramonBench.run_case,
            adapter,other,limits;baseline_cache=cache)
        @test second_verdict["baseline_cache_hit"]
        @test count(r->r.phase=="baseline_warm",second_rows)==0
        @test count(r->r.phase=="warm",second_rows)==2
    end
end
