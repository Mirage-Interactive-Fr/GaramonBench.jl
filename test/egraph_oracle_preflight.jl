using Test, GaramonBench, TOML, Random

@testset "associative e-graph oracle and shared scenario baseline" begin
    row=only(filter(item->item["id"]=="23",technique_smoke_plan()))
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
        adapter=GaramonBench.ADAPTERS["garamon_egraph"]
        limits=merge(config["limits"],Dict("samples"=>2,"case_seconds"=>120))
        cache=(root=joinpath(root,"_baselines"),
            context=Dict{String,Any}("machine"=>"representative",
                "sources"=>"same_pinned_sources"))
        first_rows,first_verdict=Base.invokelatest(GaramonBench.run_case,
            adapter,case,limits;baseline_cache=cache)
        @test !first_verdict["baseline_cache_hit"]
        @test count(r->r.phase=="baseline_warm",first_rows)==2
        other=merge(case,Dict("preparation"=>"rebuild"))
        second_rows,second_verdict=Base.invokelatest(GaramonBench.run_case,
            adapter,other,limits;baseline_cache=cache)
        @test second_verdict["baseline_cache_hit"]
        @test count(r->r.phase=="baseline_warm",second_rows)==0
        @test count(r->r.phase=="warm",second_rows)==2
        medium=merge(case,Dict("dimension"=>12,"support_count"=>8,
            "factor_count"=>4,"horizon"=>16))
        fixture=adapter.generate(medium,"",Xoshiro(medium["seed"]))
        state=adapter.prepare(fixture,medium,"")
        @test adapter.oracle(state,adapter.execute(state))
        @test adapter.execute(state)==adapter.baseline_execute(adapter.baseline_prepare(state))
    end
end
