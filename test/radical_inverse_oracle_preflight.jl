using Test, GaramonBench, Random
include(joinpath(@__DIR__, "..", "adapters", "garamon_radical_inverse.jl"))

@testset "N03 diagonal radical exact preflight" begin
    config=load_config(joinpath(@__DIR__, "..", "config",
        "radical_inverse_oracle_preflight.toml"))
    cases=expand_cases(config)
    @test length(cases)==1
    case=only(cases)
    adapter=GaramonBench.ADAPTERS["garamon_radical_inverse"]
    state=adapter.generate(case,"",Xoshiro(case["seed"]))
    result=adapter.execute(state)
    @test adapter.oracle(state,result)
    @test result==GaramonBenchN03.n03_oracle_inverse(state.input.a,state.input.g)
    corrupt=copy(result);corrupt[UInt128(0)]=get(corrupt,UInt128(0),zero(GaramonBenchN03.N03_Q))+1
    @test !adapter.oracle(state,corrupt)
    @test GaramonBenchN03.n03_radical_mask(state.input.g)==GaramonBenchN03.n03_bit(4)
    @test_throws ArgumentError GaramonBenchN03.n03_inverse(state.input.a,
        [1 0 0 0; 0 1 0 0; 0 0 -1 0; 0 0 0 0])
    @test GaramonBench.run_case_preflight(adapter,case,config["limits"])["oracle_passed"]
end
