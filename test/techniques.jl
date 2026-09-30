@testset "all roadmap techniques and symmetric compatibility cells" begin
    typed_adapter=BenchmarkAdapter(name="typed-callback-probe",
        generate=(case,dir,rng)->1,execute=x->x+1,
        oracle=(state,result)->result==state+1,contract="test")
    @test fieldtype(typeof(typed_adapter),:execute)!==Function
    @test typed_adapter.oracle(1,typed_adapter.execute(1))
    inventory=technique_inventory()
    @test inventory["technique_count"]==46
    @test inventory["pair_count"]==1035
    @test inventory["research_count"]==8
    @test inventory["source_present_count"]==38
    @test inventory["test_file_present_count"]==33
    @test inventory["preflight_registered_count"]==38
    @test only(filter(row->row["id"]=="45",inventory["techniques"]))["contract"]=="decision"
    @test all(row["preflight_registered"] && row["preflight_environment"]=="."
        for row in inventory["techniques"] if row["id"] in
            ("01","02","03","04","05","06","07","08","09","10","11","14","16","18","27","30"))
    gpu=only(filter(row->row["id"]=="29",inventory["techniques"]))
    @test gpu["preflight_registered"] && gpu["preflight_environment"]=="gpu"
    @test all(TOML.parsefile(joinpath(@__DIR__,"..",row["preflight_config"]))["campaign"]["backend"]=="oracle_preflight"
        for row in inventory["techniques"] if row["preflight_registered"])
    @test all(!row["preflight_qualified"] && !row["perfchecker_profile_qualified"]
        for row in inventory["techniques"])
    @test all(row["source_present"] for row in inventory["techniques"]
        if row["state"]!="research")
    matrix=compatibility_matrix(joinpath(@__DIR__,"..","config","compatibility_matrix.csv"))
    @test length(matrix)==46^2
    @test matrix[("10","11")]=="X1"
    @test matrix[("11","10")]=="X1"
    @test matrix[("01","25")]=="C12"
    @test matrix[("25","01")]=="C12"
    smoke=technique_smoke_plan()
    @test length(smoke)==48
    @test count(row->row["status"]=="runnable",smoke)==40
    @test count(row->row["status"]=="adapter_missing",smoke)==0
    @test count(row->row["status"]=="research_not_implemented",smoke)==8
    runnable=filter(row->row["status"]=="runnable",smoke)
    @test length(unique(row["case_id"] for row in runnable))==40
    @test Set(row["id"] for row in runnable if row["kind"]=="combination")==Set(["K1","K3"])
    @test only(filter(row->row["id"]=="27",runnable))["threads"]==4
    @test only(filter(row->row["id"]=="29",runnable))["environment"]=="gpu"
    bench=technique_bench_plan()
    @test length(bench)==48
    @test count(row->row["status"]=="runnable",bench)==40
    @test all(row["benchmark_cases"]>=1 && row["benchmark_backend"]=="BenchmarkTools"
        for row in bench if row["status"]=="runnable")
    grade=only(filter(row->row["id"]=="05",bench))
    xorjoin=only(filter(row->row["id"]=="06",bench))
    @test GaramonBench.technique_bench_config(grade)["grid"]["operation"]==["left"]
    @test GaramonBench.technique_bench_config(xorjoin)["grid"]["operation"]==["geometric"]
    @test only(filter(row->row["id"]=="10",bench))["benchmark_cases"]==504
    @test only(filter(row->row["id"]=="11",bench))["benchmark_cases"]==12600
    @test only(filter(row->row["id"]=="12",bench))["benchmark_cases"]==1512
    @test only(filter(row->row["id"]=="13",bench))["benchmark_cases"]==504
    @test only(filter(row->row["id"]=="44",bench))["benchmark_cases"]==4590
    @test only(filter(row->row["id"]=="38",bench))["benchmark_cases"]==2880
    @test only(filter(row->row["id"]=="39",bench))["benchmark_cases"]==540
    @test only(filter(row->row["id"]=="45",bench))["benchmark_cases"]==2430
    @test only(filter(row->row["id"]=="46",bench))["benchmark_cases"]==1440
    @test only(filter(row->row["id"]=="32",bench))["benchmark_cases"]==3240
    modular=only(filter(row->row["id"]=="44",bench))
    modular_cases=expand_cases(GaramonBench.technique_bench_config(modular))
    direct=filter(case->case["mode"]=="direct_bigint",modular_cases)
    @test length(direct)==270
    @test all(case["prime_bits"]==17 && case["max_primes"]==1
        for case in direct)
    @test only(filter(row->row["id"]=="25",bench))["benchmark_cases"]==35
    @test all(GaramonBench.technique_bench_config(row)["campaign"]["backend"]=="benchmarktools"
        for row in bench if row["status"]=="runnable")
    profile_cases=String[]
    for row in runnable
        request=technique_profile_request(row)
        plan=profile_plan(request)
        @test plan["case_id"]==row["case_id"]
        @test realpath(plan["adapter_source"])==realpath(joinpath(@__DIR__,"..",row["adapter"]))
        catalog=Base.invokelatest(GaramonBench.profile_catalog,plan,["benchmark"])
        @test only(catalog.scenarios).id==row["case_id"]
        push!(profile_cases,plan["case_id"])
    end
    @test length(unique(profile_cases))==40
    requests=Dict(row["id"]=>technique_profile_request(row) for row in runnable)
    @test requests["02"]["limits"]["profile_episode_repetitions"]==4096
    @test requests["03"]["limits"]["profile_repetitions"]==100
    @test requests["20"]["limits"]["profile_episode_repetitions"]==64
    @test requests["10"]["limits"]["profile_episode_repetitions"]==1024
    @test requests["44"]["limits"]["profile_episode_repetitions"]==4096
    @test requests["44"]["limits"]["profile_repetitions"]==100
    @test requests["38"]["limits"]["profile_episode_repetitions"]==512
    @test requests["38"]["limits"]["rss_bytes"]==5<<30
    @test requests["39"]["limits"]["profile_episode_repetitions"]==512
    @test requests["39"]["limits"]["rss_bytes"]==5<<30
    @test requests["45"]["limits"]["profile_episode_repetitions"]==4096
    @test requests["45"]["limits"]["rss_bytes"]==5<<30
    @test requests["46"]["limits"]["profile_episode_repetitions"]==512
    @test requests["46"]["limits"]["rss_bytes"]==5<<30
    @test requests["32"]["limits"]["profile_episode_repetitions"]==512
    @test requests["32"]["limits"]["rss_bytes"]==5<<30
    alternate=deepcopy(only(filter(row->row["id"]=="45",runnable)))
    alternate["case"]["coefficient_bits"]=128
    alternate["case"]["cancellation"]="near_zero"
    alternate["case_id"]=case_id(alternate["case"])
    @test profile_plan(technique_profile_request(alternate))["case_id"]==
        alternate["case_id"]
    @test requests["17"]["limits"]["profile_episode_repetitions"]==512
    @test requests["17"]["limits"]["rss_bytes"]==4<<30
    @test requests["24"]["limits"]["profile_episode_repetitions"]==512
    @test requests["25"]["limits"]["profile_episode_repetitions"]==512
    @test requests["30"]["limits"]["profile_episode_repetitions"]==512
    @test requests["28"]["limits"]["profile_episode_repetitions"]==4
    @test requests["28"]["limits"]["profile_repetitions"]==20
    @test requests["25"]["limits"]["rss_bytes"]==4<<30
    @test requests["30"]["limits"]["rss_bytes"]==6<<30
    @test requests["K3"]["limits"]["rss_bytes"]==4<<30
    @test !("profile" in requests["15"]["profiling"]["collectors"])
    mktempdir() do root
        smoke_dir=joinpath(root,"smoke")
        run_technique_smoke(smoke_dir;ids=["22"])
        run_technique_smoke(smoke_dir;ids=["23"])
        smoke_rows=TOML.parsefile(joinpath(smoke_dir,"quickcheck.toml"))["technique"]
        @test Set(row["id"] for row in smoke_rows)==Set(["22","23"])
        bench_dir=joinpath(root,"bench")
        run_technique_bench(smoke_dir,bench_dir;ids=["22"])
        run_technique_bench(smoke_dir,bench_dir;ids=["23"])
        bench_rows=TOML.parsefile(joinpath(bench_dir,"bench-progress.toml"))["technique"]
        @test Set(row["id"] for row in bench_rows)==Set(["22","23"])
    end
end
