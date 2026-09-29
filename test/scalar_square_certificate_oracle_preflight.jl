using Test, GaramonBench, Random
include(joinpath(@__DIR__, "..", "adapters", "garamon_scalar_square_certificate.jl"))

@testset "N04 scalar-square certificate exact preflight" begin
    config=load_config(joinpath(@__DIR__, "..", "config",
        "scalar_square_certificate_oracle_preflight.toml"))
    cases=expand_cases(config)
    @test length(cases)==1
    case=only(cases)
    adapter=GaramonBench.ADAPTERS["garamon_scalar_square_certificate"]
    fixture=adapter.generate(case,"",Xoshiro(case["seed"]))
    state=adapter.prepare(fixture,case,"")
    result=adapter.execute(state)
    @test adapter.oracle(state,result)
    @test result.output[1]==GaramonBenchN04.n04_oracle_power(
        state.g,first(state.inputs),case["exponent"])
    @test GaramonBenchN04.n04_certify(state.g,first(state.inputs)).lambda==-3//4
    corrupt=deepcopy(result)
    corrupt.output[1][big(3)]=get(corrupt.output[1],big(3),zero(GaramonBenchN04.N04Q))+1
    @test !adapter.oracle(state,corrupt)
    cert=GaramonBenchN04.n04_certify(state.g,first(state.inputs))
    changed=copy(first(state.inputs));changed[big(5)]=2
    @test !GaramonBenchN04.n04_bound(cert,state.g,changed)
    @test_throws ArgumentError GaramonBenchN04.n04_power(cert,state.g,changed,3)
    @test GaramonBench.run_case_preflight(adapter,case,config["limits"])["oracle_passed"]
end
