using Test, GaramonBench, Random

Base.include(Main,joinpath(@__DIR__,"..","adapters","garamon_exact_triple_selector.jl"))

@testset "unfitted exact triple selector minimal oracle" begin
    config=GaramonBench.load_config(joinpath(@__DIR__,"..","config",
        "exact_triple_selector_oracle_preflight.toml"))
    config["grid"]["horizon"]=[1,2]
    for (dimension,horizon) in ((4,1),(4,2))
        case=only(filter(c->c["dimension"]==dimension &&
            c["signature"]=="mixed" && c["horizon"]==horizon,
            GaramonBench.expand_cases(config)))
        fixture=tj_generate(case,"",Random.Xoshiro(case["seed"]))
        state=ts_prepare(fixture,case,"")
        @test ts_execute(state)==fixture.expected
        @test state.selected[] in (:full,:recursive,:join3,:prepared,:workspace)
        @test GaramonBench.ADAPTERS["garamon_exact_triple_selector"].oracle(state,ts_execute(state))
        @test GaramonBench.run_case_preflight(
            GaramonBench.ADAPTERS["garamon_exact_triple_selector"],case,
            config["limits"])["oracle_passed"]
    end
end
