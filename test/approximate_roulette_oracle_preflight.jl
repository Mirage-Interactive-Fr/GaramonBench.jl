using Test, GaramonBench, Random
include(joinpath(@__DIR__,"..","adapters","garamon_approximate_roulette.jl"))

@testset "N25 stochastic approximate roulette" begin
    config=load_config(joinpath(@__DIR__,"..","config",
        "approximate_roulette_oracle_preflight.toml"))
    cases=expand_cases(config)
    @test length(cases)==35
    case=only(filter(c->c["survival_probability"]=="1/2" &&
        c["draw_seed"]==20260928,cases))
    adapter=GaramonBench.ADAPTERS["garamon_approximate_roulette"]
    state=adapter.generate(case,"",Xoshiro(case["seed"]))
    @test GaramonBenchApproximateRoulette.exhaustive_first_mean(state.fixture.initial,state.p)==state.exact[2]
    result=adapter.execute(state)
    @test adapter.oracle(state,result)
    @test adapter.execute(state)==result
    measured=GaramonBenchApproximateRoulette.pruning_run(state.fixture,:roulette,Float64;
        seed=state.draw_seed,record=true,survival_probability=state.p)
    unmeasured=GaramonBenchApproximateRoulette.pruning_run(state.fixture,:roulette,Float64;
        seed=state.draw_seed,record=true,survival_probability=state.p,
        measure_buffers=false)
    @test measured.buffer_bytes>0
    @test unmeasured.buffer_bytes===nothing
    @test measured.value==unmeasured.value==result.value
    @test measured.history==unmeasured.history==result.history
    @test result.counts.kept+result.counts.omitted==result.counts.candidates==16
    @test result.counts.omitted>0
    metrics=GaramonBenchApproximateRoulette.errors(result.history,state.exact)
    @test metrics.final_abs_error>0
    @test metrics.max_abs_error>=metrics.final_abs_error
    @test result.value!=Float64.(last(state.exact))
    changed_history=copy.(result.history)
    changed_history[2][1]+=1
    changed=merge(result,(history=changed_history,))
    @test !adapter.oracle(state,changed)
    verdict=GaramonBench.run_case_preflight(adapter,case,config["limits"])
    @test verdict["oracle_passed"]
    @test verdict["preflight_evidence"]["contract"]=="approximate"
    @test verdict["preflight_evidence"]["survival_probability"]=="1//2"
    @test verdict["preflight_evidence"]["final_abs_error"]==metrics.final_abs_error
    for pcase in filter(c->c["draw_seed"]==20260928,cases)
        pstate=adapter.generate(pcase,"",Xoshiro(pcase["seed"]))
        @test pstate.fixture.initial==state.fixture.initial
        @test GaramonBenchApproximateRoulette.exhaustive_first_mean(
            pstate.fixture.initial,pstate.p)==pstate.exact[2]
        @test adapter.oracle(pstate,adapter.execute(pstate))
        if pstate.p==1
            @test adapter.execute(pstate).counts.omitted==0
            @test GaramonBenchApproximateRoulette.errors(
                adapter.execute(pstate).history,pstate.exact).final_abs_error==0
        end
    end
    bad=copy(case);bad["survival_probability"]="0/1"
    @test_throws ArgumentError adapter.generate(bad,"",Xoshiro(case["seed"]))
    @test_throws ArgumentError GaramonBenchApproximateRoulette.pruning_run(
        state.fixture,:roulette;survival_probability=0)
    println("N25 seeded preflight error: ",metrics)
end
