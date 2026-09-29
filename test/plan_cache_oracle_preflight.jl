# Correctness-only plan-retention test, including invalidation and long reuse.
using Test, GaramonBench, TOML
include(joinpath(@__DIR__,"..","adapters","garamon_plan_cache.jl"))
using Garamon

@testset "exact LRU and roulette trace preflight" begin
    config=load_config(joinpath(@__DIR__,"..","config",
        "plan_cache_oracle_preflight.toml"))
    config["grid"]["dimension"]=[2,129]
    config["grid"]["signature"]=["mixed"]
    config["grid"]["trace"]=["hot","scan"]
    config["limits"]["max_cases"]=24
    cases=expand_cases(config)
    @test length(cases)==24
    mktempdir() do temporary
        output=joinpath(temporary,"plan-cache")
        @test run_resumable_campaign(config;output)==output
        @test resumable_status(config,output)["status"]=="complete"
        for case in cases
            directory=joinpath(output,"cases",case_id(case))
            verdict=TOML.parsefile(joinpath(directory,"verdict.toml"))
            @test verdict["oracle_passed"]
            @test verdict["benchmark_backend"]=="oracle_preflight"
            @test !ispath(joinpath(directory,"samples.csv"))
        end
        @test run_resumable_campaign(config;output)==output
        audit=audit_resumable_archive(config,output)
        @test audit["archive_integrity"]=="validated"
        @test length(audit["completed_ids"])==24
    end
    ga=algebra(Int64[1 0; 0 1])
    e=basisvector(ga,1;storage=:sparse)
    cache=ProductPlanCache(max_bytes=1<<20,policy=:roulette,seed=42)
    @test coefficient_mask(cached_product!(cache,e,e),0)==1
    metric(ga)[1,1]=2
    @test coefficient_mask(cached_product!(cache,e,e),0)==2
    @test cache_stats(cache).misses==2
    long=load_config(joinpath(@__DIR__,"..","config",
        "plan_cache_long_oracle_preflight.toml"))
    long["grid"]["dimension"]=[129]
    long["grid"]["signature"]=["degenerate"]
    long["grid"]["strategy"]=["roulette"]
    long["grid"]["trace"]=["phase"]
    case=only(expand_cases(long))
    adapter=getfield(GaramonBench,:ADAPTERS)["garamon_plan_cache"]
    @test GaramonBench.run_case_preflight(adapter,case,long["limits"])["oracle_passed"]
    tuning=load_config(joinpath(@__DIR__,"..","config",
        "plan_cache_tuning_oracle_preflight.toml"))
    tuning["grid"]["dimension"]=[4]
    tuning["grid"]["signature"]=["mixed"]
    tuning["grid"]["trace"]=["scan"]
    tuning["grid"]["horizon"]=[32]
    tuning["grid"]["draw_seed"]=[20260928]
    tuned=expand_cases(tuning)
    @test length(tuned)==10
    expected=nothing
    for tuned_case in tuned
        state=adapter.prepare(adapter.generate(tuned_case,"",
            Random.Xoshiro(tuned_case["seed"])),tuned_case,"")
        result=adapter.execute(state)
        @test adapter.oracle(state,result)
        @test cache_stats(state.cache).multi_candidate_evictions>0
        @test cache_stats(state.cache).eviction_exponent==tuned_case["eviction_exponent"]
        isnothing(expected) ? (expected=result) : (@test result==expected)
    end
    @test_throws ArgumentError ProductPlanCache(policy=:roulette,
        eviction_exponent=-0.5)
    @test_throws ArgumentError ProductPlanCache(policy=:roulette,
        eviction_exponent=Inf)
end
