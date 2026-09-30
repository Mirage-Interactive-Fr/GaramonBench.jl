using Test, GaramonBench, TOML, Random

@testset "bilinear synthesis and verified selector share exact baseline" begin
    rows=Dict(row["id"]=>row for row in technique_smoke_plan()
        if row["id"] in ("40","41"))
    @test Set(keys(rows))==Set(["40","41"])
    configs=Dict(id=>GaramonBench.technique_smoke_config(rows[id])
        for id in ("40","41"))
    for id in ("40","41")
        @test rows[id]["status"]=="runnable"
        @test length(expand_cases(configs[id]))==1
    end
    GaramonBench.include_technique_adapter(
        joinpath(pkgdir(GaramonBench),rows["40"]["adapter"]),configs["40"])
    mktempdir() do root
        for id in ("40","41")
            output=joinpath(root,id)
            @test run_resumable_campaign(configs[id];output)==output
            @test audit_resumable_archive(configs[id],output)["archive_integrity"]=="validated"
        end
        first_case=only(expand_cases(configs["40"]))
        second_case=only(expand_cases(configs["41"]))
        first_case["baseline_required"]=true
        second_case["baseline_required"]=true
        synthesis=GaramonBench.ADAPTERS["garamon_bilinear_synthesis"]
        verified=GaramonBench.ADAPTERS["garamon_verified_superopt"]
        limits=merge(configs["40"]["limits"],Dict("samples"=>2,"case_seconds"=>120))
        cache=(root=joinpath(root,"_baselines"),
            context=Dict{String,Any}("machine"=>"representative",
                "sources"=>"same_pinned_sources"))
        first_rows,first_verdict=Base.invokelatest(GaramonBench.run_case,
            synthesis,first_case,limits;baseline_cache=cache)
        @test !first_verdict["baseline_cache_hit"]
        @test count(r->r.phase=="baseline_warm",first_rows)==2
        second_rows,second_verdict=Base.invokelatest(GaramonBench.run_case,
            verified,second_case,limits;baseline_cache=cache)
        @test second_verdict["baseline_cache_hit"]
        @test count(r->r.phase=="baseline_warm",second_rows)==0
        @test count(r->r.phase=="warm",second_rows)==2
        medium=merge(first_case,Dict("dimension"=>8,"support_count"=>16,
            "horizon"=>16))
        fixture=synthesis.generate(medium,"",Xoshiro(medium["seed"]))
        state=synthesis.prepare(fixture,medium,"")
        @test synthesis.oracle(state,synthesis.execute(state))
        @test synthesis.execute(state)==synthesis.baseline_execute(
            synthesis.baseline_prepare(state))
    end
end
