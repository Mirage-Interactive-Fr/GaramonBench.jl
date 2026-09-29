using Test, GaramonBench, Random
include(joinpath(@__DIR__, "..", "adapters", "garamon_pfaffian_scalar.jl"))

@testset "Pfaffian scalar and same-contract routes" begin
    config = load_config(joinpath(@__DIR__, "..", "config",
        "pfaffian_scalar_oracle_preflight.toml"))
    cases = expand_cases(config)
    @test length(cases)==4
    adapter = GaramonBench.ADAPTERS["garamon_pfaffian_scalar"]
    @test Set(case["strategy"] for case in cases)==
        Set(["pfaffian","precontracted","full","recursive"])
    for case in cases
        fixture = adapter.generate(case,"",Random.Xoshiro(case["seed"]))
        @test fixture.expected!=0
        state = adapter.prepare(fixture,case,"")
        observed = adapter.execute(state)
        @test adapter.oracle(state,observed)
        @test !adapter.oracle(state,observed .+ 1)
        @test GaramonBench.run_case_preflight(adapter,case,config["limits"])["oracle_passed"]
    end
    first_case = first(cases)
    fixture = adapter.generate(first_case,"",Random.Xoshiro(first_case["seed"]))
    @test_throws ArgumentError n05_scalar(Float64.(fixture.G),Float64.(fixture.V);
        output=:bivector)
    @test_throws ArgumentError n05_scalar(Float64.(fixture.G),
        Float64.(fixture.V[:,1:3]))
end
