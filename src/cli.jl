function cli(args=ARGS)
    isempty(args) && error("commands: external-ga-list | external-ga-fetch NAME... | list CONFIG | run CONFIG OUTPUT [ADAPTER.jl] | resume CONFIG OUTPUT [ADAPTER.jl] | preflight CONFIG OUTPUT [ADAPTER.jl] | resume-status CONFIG OUTPUT | archive-audit CONFIG COPIED_OUTPUT | repeat RUN OUTPUT [ADAPTER.jl] | cpp-matched CONFIG OUTPUT | recipe-plan CONFIG | run-recipe CONFIG OUTPUT | profile-plan CONFIG | profile-preflight CONFIG OUTPUT | profile-capture CONFIG OUTPUT | b1-plan CONFIG | run-b1 CONFIG OUTPUT | audit-k1 MANIFEST OUTPUT SHARD_DIRECTORY...")
    command=first(args)
    if command=="external-ga-list"
        length(args)==1 || error("external-ga-list")
        TOML.print(stdout,Dict("library"=>external_ga_candidates());sorted=true)
        return
    elseif command=="external-ga-fetch"
        length(args)>=2 || error("external-ga-fetch NAME... or all")
        names=args[2:end]==["all"] ? [row["name"] for row in external_ga_candidates()] : args[2:end]
        length(unique(lowercase.(names)))==length(names) || error("duplicate external GA source")
        for name in names
            println(lowercase(name),'\t',ensure_external_ga_source(name))
        end
        return
    elseif command=="b1-plan"
        length(args)==2 || error("b1-plan CONFIG")
        TOML.print(stdout,b1_plan(args[2]);sorted=true);return
    elseif command=="run-b1"
        length(args)==3 || error("run-b1 CONFIG NEW_OUTPUT")
        println(run_b1(args[2];output=args[3]));return
    elseif command=="profile-plan"
        length(args)==2 || error("profile-plan CONFIG")
        TOML.print(stdout,profile_plan(args[2]);sorted=true)
        return
    elseif command in ("profile-preflight","profile-capture")
        length(args)==3 || error("$command CONFIG NEW_OUTPUT")
        action=command=="profile-preflight" ? profile_preflight : profile_capture
        println(action(args[2];output=args[3]));return
    elseif command=="_profile-worker"
        length(args)==3 || error("internal profile worker arguments")
        profile_worker(TOML.parsefile(args[2]),args[3]);return
    elseif command=="recipe-plan"
        length(args)==2 || error("recipe-plan CONFIG")
        TOML.print(stdout,recipe_plan(args[2]);sorted=true)
        return
    elseif command=="resume-status"
        length(args)==3 || error("resume-status CONFIG OUTPUT")
        TOML.print(stdout,resumable_status(args[2],args[3]);sorted=true)
        return
    elseif command=="archive-audit"
        length(args)==3 || error("archive-audit CONFIG COPIED_OUTPUT")
        TOML.print(stdout,audit_resumable_archive(args[2],args[3]);sorted=true)
        return
    elseif command=="technique-plan"
        length(args)==1 || error("technique-plan")
        inventory=technique_inventory()
        summary=Dict("technique_count"=>inventory["technique_count"],
            "pair_count"=>inventory["pair_count"],
            "source_present_count"=>inventory["source_present_count"],
            "test_file_present_count"=>inventory["test_file_present_count"],
            "preflight_registered_count"=>inventory["preflight_registered_count"],
            "research_count"=>inventory["research_count"],
            "registry_sha256"=>inventory["registry_sha256"],
            "matrix_sha256"=>inventory["matrix_sha256"])
        TOML.print(stdout,summary;sorted=true)
        return
    elseif command=="technique-smoke-plan"
        length(args)==1 || error("technique-smoke-plan")
        TOML.print(stdout,Dict("technique"=>technique_smoke_plan());sorted=true)
        return
    elseif command=="technique-smoke"
        length(args)>=2 || error("technique-smoke OUTPUT [ID...]")
        println(run_technique_smoke(args[2];ids=args[3:end]));return
    elseif command=="technique-bench-plan"
        length(args)==1 || error("technique-bench-plan")
        TOML.print(stdout,Dict("technique"=>technique_bench_plan());sorted=true)
        return
    elseif command=="technique-bench"
        length(args)>=3 || error("technique-bench PREFLIGHT_OUTPUT BENCH_OUTPUT [ID...]")
        println(run_technique_bench(args[2],args[3];ids=args[4:end]));return
    elseif command=="technique-profile"
        length(args)>=3 || error("technique-profile PREFLIGHT_OUTPUT PROFILE_OUTPUT [ID...]")
        println(run_technique_profiles(args[2],args[3];ids=args[4:end]));return
    elseif command=="audit-k1"
        length(args)>=4 || error("audit-k1 MANIFEST OUTPUT SHARD_DIRECTORY...")
        report=audit_k1(args[2],args[3],args[4:end])
        println(report["status"],": ",report["distinct_qualified"],"/",report["expected_cases"])
        return
    elseif command=="run-recipe"
        length(args)==3 || error("run-recipe CONFIG OUTPUT")
        println(run_recipe(args[2];output_root=args[3]))
        return
    end
    if command=="cpp-matched"
        length(args)==3 || error("cpp-matched CONFIG OUTPUT")
        println(run_cpp_matched(load_config(args[2]);output_root=args[3]))
        return
    end
    if command=="list"
        length(args)==2 || error("list CONFIG")
        foreach(case->println(case_id(case)),expand_cases(load_config(args[2])))
        return
    end
    command in ("run","repeat","resume","preflight") || error("unknown command")
    length(args) in (3,4) || error("run/resume/preflight CONFIG OUTPUT [ADAPTER.jl] or repeat RUN OUTPUT [ADAPTER.jl]")
    register_smoke_adapter!()
    length(args)==4 && Base.include(Main,abspath(args[4]))
    if command in ("resume","preflight")
        config=load_config(args[2])
        command=="preflight" &&
            get(config["campaign"],"backend","")!="oracle_preflight" &&
            error("preflight command requires campaign.backend = oracle_preflight")
        println(Base.invokelatest(run_resumable_campaign,config;output=args[3]))
        return
    end
    repeat_of=command=="repeat" ? abspath(args[2]) : nothing
    config=load_config(isnothing(repeat_of) ? args[2] : joinpath(repeat_of,"configuration.toml"))
    if !isnothing(repeat_of)
        config["campaign"]["condition"]="isolated"
        config["campaign"]["interference_label"]=""
    end
    # Adapter methods may have just been defined by include above.
    println(Base.invokelatest(run_campaign,config;output_root=args[3],repeat_of))
end
