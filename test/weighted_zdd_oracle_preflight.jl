using Test, GaramonBench, Random
include(joinpath(@__DIR__,"..","adapters","garamon_weighted_zdd.jl"))

@testset "N20 exact weighted ZDD product preflight" begin
    config=load_config(joinpath(@__DIR__,"..","config",
        "weighted_zdd_oracle_preflight.toml"))
    cases=expand_cases(config)
    @test length(cases)==1
    case=only(cases)
    adapter=GaramonBench.ADAPTERS["garamon_weighted_zdd"]
    fixture=adapter.generate(case,"",Xoshiro(case["seed"]))
    state=adapter.prepare(fixture,case,"")
    result=adapter.execute(state)
    @test adapter.oracle(state,result)
    @test length(state.left.nodes)>0 && length(state.right.nodes)>0
    @test all(Garamon.weighted_zdd_coefficient(
        Garamon.weighted_zdd_product(state.left,state.right,fixture.g),mask)==
        get(fixture.expected,big(mask),zero(Rational{BigInt})) for mask in 0:15)
    corrupt=copy(result);corrupt[big(0)]=get(corrupt,big(0),zero(Rational{BigInt}))+1
    @test !adapter.oracle(state,corrupt)
    @test GaramonBench.run_case_preflight(adapter,case,config["limits"])["oracle_passed"]
end
