using Test, GaramonBench, Random

# Correctness only: no BenchmarkTools samples or performance publication.
const VARIANT_IDS = split(get(ENV,"GARAMONBENCH_VARIANT_IDS",
    "17,19,20,21,24,31,33,34,35,K1,K3"),',')

@testset "parametric campaign boundaries" begin
    rows=technique_smoke_plan()
    @test all(row["benchmark_cases"]>1 for row in technique_bench_plan())
    catalogue=only(filter(r->r["id"]=="15",rows))
    catalogue_cases=expand_cases(GaramonBench.technique_bench_config(catalogue))
    @test length(catalogue_cases)==21
    @test all(c["dimension"]==(c["scenario"]=="known" ? 3 : 4) for c in catalogue_cases)
    @test all(c["request_index"]==1 for c in catalogue_cases if c["scenario"]=="known")
    for id in VARIANT_IDS
        row=only(filter(r->r["id"]==id,rows))
        config=GaramonBench.technique_bench_config(row)
        cases=expand_cases(config)
        @test length(cases)>1
        # Include both ambient-dimension boundaries without traversing a grid.
        selected=[copy(first(cases)),copy(last(cases))]
        if id=="17"
            push!(selected,merge(copy(last(cases)),Dict("dimension"=>8,"horizon"=>1)))
        end
        if id=="28"
            selected=[merge(copy(first(cases)),Dict("dimension"=>4,"family"=>"sparse8",
                "workers"=>2,"batch"=>16)),merge(copy(first(cases)),
                Dict("dimension"=>8,"family"=>"subalgebra64","workers"=>4,"batch"=>4))]
        elseif id=="15"
            selected=[merge(copy(first(cases)),Dict("dimension"=>4,"scenario"=>"changing",
                "request_index"=>4,"horizon"=>8))]
        end
        scope=Module(gensym(:CampaignVariant))
        Core.eval(scope,:(include(path)=Base.include(@__MODULE__,path)))
        Base.include(scope,joinpath(pkgdir(GaramonBench),row["adapter"]))
        adapter=GaramonBench.ADAPTERS[row["case"]["adapter"]]
        @testset "$id" begin
            for case in selected
                mktempdir() do directory
                    fixture=adapter.generate(case,directory,Random.Xoshiro(case["seed"]))
                    built=adapter.build(fixture,case,directory)
                    state=adapter.prepare(built,case,directory)
                    try
                        result=adapter.execute(state)
                        @test adapter.oracle(state,result)
                        @test adapter.oracle(state,adapter.execute(state))
                        # The full rational high-dimensional sandwich is
                        # deliberately reserved for the dedicated campaign.
                        # Its small-dimensional equivalent is checked here.
                        id=="17" && case["dimension"]>8 && return
                        baseline=adapter.baseline_prepare(state)
                        try
                            reference=adapter.baseline_execute(baseline)
                            if isnothing(adapter.baseline_oracle)
                                @test reference==result
                            else
                                @test adapter.baseline_oracle(state,reference)
                            end
                        finally
                            adapter.baseline_cleanup(baseline)
                        end
                    finally
                        adapter.cleanup(state)
                    end
                end
            end
        end
    end
end
