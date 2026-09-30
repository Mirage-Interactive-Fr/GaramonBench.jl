const PROFILE_COLLECTORS = ("benchmark","profile","wall_profile","profile_alloc")
const PROFILE_DIAGNOSTICS = ("latency","gc","memory","heap","jet","alloccheck")
const PROFILE_LIMITS = Dict("threads"=>1,"samples"=>7,"profile_repetitions"=>1000,
    "profile_episode_repetitions"=>256,
    "allocation_repetitions"=>1,"job_seconds"=>120,"total_seconds"=>600,
    "rss_bytes"=>2<<30,"scratch_bytes"=>128<<20,"archive_bytes"=>256<<20,
    "source_bytes"=>64<<20,"type_text_bytes"=>65536)

function profile_manifest_dependencies(project)
    file=joinpath(project,"Manifest.toml")
    isfile(file) ? get(TOML.parsefile(file),"deps",Dict()) : Dict()
end

"""Describe one existing case and static capabilities. Never instantiate or load a target."""
function _profile_plan_loaded(input)
    VERSION.major==1 && VERSION.minor==13 || error("profiling controller requires Julia 1.13")
    pkgversion(PerfChecker)==v"1.0.0-rc1" || error("profiling adapter audited for PerfChecker 1.0.0-rc1 only")
    raw=input isa AbstractString ? TOML.parsefile(input) : deepcopy(input)
    get(raw,"schema_version",0)==1 || error("profiling schema must be 1")
    base=input isa AbstractString ? dirname(abspath(input)) : pwd()
    options=get(raw,"profiling",Dict())
    allowed=Set(["case_config","case_id","worker_project","collectors","diagnostics","type_stability","allow_unavailable"])
    all(k->k in allowed,keys(options)) || error("unknown profiling option")
    resolve(p)=abspath(base,expanduser(p))
    casefile=resolve(get(options,"case_config","julia_products.toml"))
    source=load_config(casefile);cases=expand_cases(source)
    selector=get(raw,"select",Dict())
    selected=if haskey(options,"case_id")
        isempty(selector) || error("choose case_id or select, not both")
        filter(c->case_id(c)==options["case_id"],cases)
    else
        isempty(selector) && error("an explicit case identity or selector is required")
        all(v->v isa Union{AbstractString,Integer,Bool},values(selector)) || error("selector values must be scalar")
        filter(c->all(get(c,k,nothing)==v for (k,v) in selector),cases)
    end
    length(selected)==1 || error("profiling must select exactly one existing case")
    case=only(selected)
    root=dirname(@__DIR__)
    smoke=filter(row->row["status"]=="runnable" &&
        abspath(joinpath(root,row["config"]))==casefile &&
        all(get(row["case"],key,nothing)==get(case,key,nothing)
            for key in ("adapter","strategy","operation")),
        technique_smoke_plan(;benchmark_root=root))
    length(smoke)<=1 || error("ambiguous technique profile registration")
    generic_adapter=isempty(smoke) ? nothing :
        abspath(joinpath(root,only(smoke)["adapter"]))
    adapter_case=case["adapter"]=="garamon_generated_product" &&
        case["family"]=="bounded_generated_product" &&
        case["dimension"] isa Integer && 2<=case["dimension"]<=16 &&
        case["signature"] in ("positive","mixed","degenerate") &&
        case["strategy"] in ("prepared","generated") && case["horizon"] in (1,32) &&
        get(source["campaign"],"backend","")=="oracle_preflight"
    supported=!isnothing(generic_adapter) || adapter_case ||
        (case["adapter"]=="garamon_julia" && case["family"]=="vectors") ||
        (case["adapter"]=="bounds_b1w" && case["family"] in ("low_grade","high_grade") &&
         case["signature"] in ("positive","mixed","degenerate") &&
         case["strategy"] in ("workspace","workspace_native","workspace_native_singlepass") &&
         case["phase"] in ("build","hot","episode") &&
         case["dimension"] isa Integer && 2<=case["dimension"]<=128 &&
         case["horizon"] in (1,32,1024))
    supported || error("unsupported profiling adapter or case")
    limits=merge(PROFILE_LIMITS,get(raw,"limits",Dict()))
    all(k->haskey(PROFILE_LIMITS,k),keys(limits)) || error("unknown profiling limit")
    all(v->v isa Integer && !(v isa Bool) && v>0,values(limits)) || error("positive integer profiling limits required")
    limits["threads"]<=4 || error("profiling phase limited to four threads")
    limits["samples"]<=31 && limits["profile_repetitions"]<=100000 &&
        limits["profile_episode_repetitions"]<=4096 && limits["allocation_repetitions"]<=100 ||
        error("profiling repetition budget")
    limits["job_seconds"]<=limits["total_seconds"]<=1800 || error("profiling time budget")
    collectors=String.(get(options,"collectors",collect(PROFILE_COLLECTORS)))
    diagnostics=String.(get(options,"diagnostics",collect(PROFILE_DIAGNOSTICS)))
    collectors isa Vector && diagnostics isa Vector || error("collector and diagnostic lists required")
    all(c->c in PROFILE_COLLECTORS,collectors) && allunique(collectors) || error("unknown or duplicate collector")
    all(c->c in PROFILE_DIAGNOSTICS,diagnostics) && allunique(diagnostics) || error("unknown or duplicate diagnostic")
    types=get(options,"type_stability",true);types isa Bool || error("type_stability must be Bool")
    allow=get(options,"allow_unavailable",true);allow isa Bool || error("allow_unavailable must be Bool")
    worker=resolve(get(options,"worker_project",".."));isfile(joinpath(worker,"Project.toml")) || error("worker project missing")
    deps=profile_manifest_dependencies(worker)
    declared=get(TOML.parsefile(joinpath(worker,"Project.toml")),"deps",Dict())
    dependency_ready(name)=haskey(deps,name) && haskey(declared,name)
    capabilities=Dict{String,Any}[]
    for collector in collectors
        status=collector=="benchmark" && !dependency_ready("BenchmarkTools") ?
            "blocked_worker_manifest_dependency" : "implemented_not_runtime_probed"
        push!(capabilities,Dict("kind"=>"collector","name"=>collector,"status"=>status,
            "interface"=>collector=="wall_profile" ? "FeatureSpec/run_suite" : "ScenarioSpec/run_scenarios"))
    end
    for diagnostic in diagnostics
        package=diagnostic=="jet" ? "JET" : diagnostic=="alloccheck" ? "AllocCheck" : "builtin"
        status=package=="builtin" || dependency_ready(package) ? "implemented_not_runtime_probed" : "blocked_worker_manifest_dependency"
        push!(capabilities,Dict("kind"=>"diagnostic","name"=>diagnostic,"package"=>package,"status"=>status,
            "functional_compatibility"=>"not_probed; installed source alone does not establish availability"))
    end
    types && push!(capabilities,Dict("kind"=>"diagnostic","name"=>"type_stability","package"=>"InteractiveUtils",
        "status"=>"implemented_not_runtime_probed","scope"=>"code_warntype text and exact argument types; no automatic stable/unstable verdict"))
    condition=source["campaign"]["condition"]
    label=condition=="isolated" ? "" : get(source["campaign"],"interference_label","")
    isempty(strip(label)) && condition=="exploratory_interference" && error("nonblank interference label required")
    roots=configured_repositories(source);haskey(roots,"julia") || error("Julia target root missing")
    Dict{String,Any}("schema_version"=>1,"status"=>"static_plan_not_runtime_qualification",
        "case_id"=>case_id(case),"case"=>case,"case_configuration"=>casefile,
        "case_configuration_sha256"=>bytes2hex(sha256(read(casefile))),
        "worker_project"=>worker,"julia_root"=>abspath(expanduser(roots["julia"])),
        "condition"=>condition,"interference_label"=>label,"isolation_certified"=>false,
        "limits"=>limits,"capabilities"=>capabilities,"collectors"=>collectors,"diagnostics"=>diagnostics,
        "type_stability"=>types,"allow_unavailable"=>allow,"julia"=>string(VERSION),
        "perfchecker"=>string(pkgversion(PerfChecker)),"interface_version"=>"local_RC1_scenario_API",
        "perfchecker_api_sources"=>Dict(name=>bytes2hex(sha256(read(joinpath(dirname(pathof(PerfChecker)),name))))
            for name in ("scenarios.jl","scenario_runtime.jl","diagnostics.jl","profile_exports.jl")),
        "adapter_source"=>isnothing(generic_adapter) ? "" : generic_adapter,
        "contract"=>!isnothing(generic_adapter) ?
            "same registered BenchmarkAdapter callbacks as its audited one-case oracle preflight" :
            adapter_case ?
            "same BenchmarkAdapter generate/build/prepare/execute/oracle callbacks as oracle_preflight; owned Float64 structural coefficient matrix" :
            case["adapter"]=="bounds_b1w" ?
            "independent Int64 word oracle; workspace preparation included for build/episode, H owned outputs for episode" :
            "owned_all_coefficients; same native adapter kernels and Int64 oracle; fresh prepared state per evaluation",
        "timing_scope"=>case["adapter"]=="bounds_b1w" ?
            "operation only; build and episode include workspace construction, hot excludes it; fixture and oracle excluded" :
            "operation only; generation, oracle construction, plan/workspace preparation and verification excluded",
        "latency_scope"=>"source load and complete first/warm lifecycle; process startup excluded",
        "allocation_scope"=>"ScenarioSpec native stacks, sampling_rate=1; no allocation type serialized",
        "cpu_profile_scope"=>"profile collector repeats one exact operation in a single sample window; each owned result verified outside the timed window",
        "rendering"=>"native piles plus folded/Speedscope; no HTML/Makie/pprof promised")
end
profile_plan(input)=(require_perfchecker();Base.invokelatest(_profile_plan_loaded,input))

function profile_catalog(plan,collectors;episode_repetitions=1)
    root=dirname(@__DIR__)
    b1w=plan["case"]["adapter"]=="bounds_b1w"
    generic=!isempty(get(plan,"adapter_source",""))
    benchmark_adapter=plan["case"]["adapter"]=="garamon_generated_product"
    source=joinpath(root,"adapters","profiling",b1w ? "bounds_b1w.jl" :
        generic || benchmark_adapter ? "benchmark_adapter.jl" : "julia_products.jl")
    fixtures=b1w ? String[] : generic ? [plan["adapter_source"]] : benchmark_adapter ?
        [joinpath(root,"adapters","garamon_generated_product.jl"),
         joinpath(root,"adapters","julia_products_kernels.jl")] :
        [joinpath(root,"adapters","julia_products_kernels.jl")]
    spec=PerfChecker.ScenarioSpec(plan["case_id"];source,factory="make_case",
        implementation=get(plan["case"],"strategy",
            get(plan["case"],"operation",plan["case"]["adapter"])),
        parameters=Dict("case"=>plan["case"],"episode_repetitions"=>episode_repetitions,
            "adapter_source"=>get(plan,"adapter_source",joinpath(root,"adapters","garamon_generated_product.jl"))),
        fixtures,collectors=Symbol.(collectors),repeatable=true)
    PerfChecker.ScenarioCatalog(root,[spec])
end

"""Archive static provenance and an executable native scenario request; no target evaluation."""
function _profile_preflight_loaded(input;output)
    plan=profile_plan(input);output=abspath(output)
    ispath(output) && error("fresh profiling output required")
    benchroot=dirname(@__DIR__)
    inside(path,root)=path==root || startswith(path,root*"/")
    archived_data=joinpath(benchroot,"data","garamonbench")
    (inside(output,plan["julia_root"]) ||
        (inside(output,benchroot) && !inside(output,archived_data))) &&
        error("profiling outputs must be outside source repositories or in DoctorWatson data/garamonbench")
    mkpath(output);write_toml(joinpath(output,"profile-plan.toml"),plan)
    roots=Dict("benchmark"=>dirname(@__DIR__),"julia"=>plan["julia_root"])
    identities=Dict(k=>repository_identity(v;snapshot=joinpath(output,"sources",k),max_bytes=plan["limits"]["source_bytes"]) for (k,v) in roots)
    for file in ("Project.toml","Manifest.toml")
        path=joinpath(plan["worker_project"],file)
        isfile(path) && archive_file!(path,joinpath(output,"worker-environment",file))
    end
    catalog=profile_catalog(plan,["benchmark"])
    write_toml(joinpath(output,"scenario.toml"),PerfChecker.scenario_catalog_dict(catalog))
    write_toml(joinpath(output,"preflight.toml"),Dict("status"=>"static_preflight_only","created_utc"=>string(now(UTC)),
        "repositories"=>identities,"target_loaded"=>false,"environment_instantiated"=>false,"oracle_executed"=>false,
        "limits"=>plan["limits"],"qualification"=>"not_checked"))
    tree_bytes(output)<=plan["limits"]["archive_bytes"] || error("profiling archive budget")
    output
end
profile_preflight(input;output)=(require_perfchecker();
    Base.invokelatest(_profile_preflight_loaded,input;output))

function profile_environment(plan)
    Dict("GARAMON_JULIA_ROOT"=>plan["julia_root"],"GARAMONBENCH_CONDITION"=>plan["condition"],
        "GARAMONBENCH_INTERFERENCE_LABEL"=>plan["interference_label"],"JULIA_PKG_OFFLINE"=>"true",
        "JULIA_PKG_PRECOMPILE_AUTO"=>"0","OPENBLAS_NUM_THREADS"=>"1","OMP_NUM_THREADS"=>"1")
end

function profile_export(bundle,directory,collector)
    collector in ("profile","profile_alloc") || return Dict("status"=>"not_applicable")
    mkpath(directory);metric=collector=="profile" ? "julia.cpu.samples" : "julia.alloc.bytes"
    try
        PerfChecker.write_folded_profile(bundle,joinpath(directory,"stacks.folded");metric)
        PerfChecker.write_speedscope_profile(bundle,joinpath(directory,"stacks.speedscope.json");metric)
        Dict("status"=>"exported","metric"=>metric,"rendered"=>false)
    catch exception
        Dict("status"=>"no_usable_stack_evidence","reason"=>failure_message(exception),"rendered"=>false)
    end
end

# Keep one harness frame rooted in the package source in PerfChecker wall
# stacks. Some exact prototypes currently live in perf/ rather than src/ and
# would otherwise have no module root for its source-path filter.
Base.@noinline profiled_operation(operation,state)=operation(state)

"""PerfChecker ScenarioSpec currently excludes wall_profile. Run its FeatureSpec
backend against the very same case factory, operation and oracle instead."""
function profile_wall_feature(plan,directory)
    mkpath(directory)
    source=only(profile_catalog(plan,["benchmark"]).scenarios).source
    request=joinpath(directory,"wall-case.toml")
    write_toml(request,Dict("case"=>plan["case"],"episode_repetitions"=>1,
        "adapter_source"=>get(plan,"adapter_source","")))
    mktempdir() do staging
        entry=joinpath(staging,"wall-feature.jl")
        open(entry,"w") do io
            println(io,"using TOML")
            println(io,"pushfirst!(LOAD_PATH,",repr(dirname(@__DIR__)),")")
            println(io,"using GaramonBench")
            println(io,"include(",repr(source),")")
            println(io,"const garamonbench_wall_case = make_case(TOML.parsefile(",repr(request),"))")
            println(io,"perf_setup() = garamonbench_wall_case.prepare()")
            println(io,"perf_workload(state) = GaramonBench.profiled_operation(garamonbench_wall_case.operation, state)")
            println(io,"perf_oracle(state, result) = garamonbench_wall_case.verify(state, result)")
        end
        cp(entry,joinpath(directory,"wall-feature.txt"))
        feature=PerfChecker.FeatureSpec(Symbol("wall_"*plan["case_id"]);
            backend=:wall_profile,entrypoint=entry,
            description="wall profile of the same exact GaramonBench case",
            comparison_key="garamonbench/wall/"*plan["case_id"],
            oracle=PerfChecker.OracleSpec(function_name=:perf_oracle),
            state_policy=:reuse,
            options=Dict(:threads=>plan["limits"]["threads"],
                :profile_seconds=>min(0.5,plan["limits"]["job_seconds"]/4),
                :profile_delay=>0.001,:targets=>["GaramonBench"]))
        package=PerfChecker.PackageSuite("GaramonBench";
            worker_environment=joinpath(dirname(@__DIR__),"worker"),source=dirname(@__DIR__),
            versions=VersionNumber[],dev_sources=String[],features=[feature])
        suite=PerfChecker.SoftwareSuite(:garamonbench_wall,[package])
        result=PerfChecker.run_suite(suite;profile=:quick,strict=false)
        PerfChecker.write_suite_json(result,joinpath(directory,"wall-suite.json"))
        run=only(result.runs)
        complete=PerfChecker.suite_passed(result) && run.status==:pass &&
            run.result isa PerfChecker.CheckerResult &&
            !isempty(run.result.tables) && !isempty(only(run.result.tables).samples)
        if complete
            table=only(run.result.tables)
            open(joinpath(directory,"stacks.folded"),"w") do io
                for i in eachindex(table.samples)
                    labels=replace.(table.stack[i],';'=>':')
                    println(io,join(labels,';'),' ',table.samples[i])
                end
            end
        end
        Dict("kind"=>"collector","name"=>"wall_profile","executed"=>true,
            "status"=>complete ? "complete" : "incomplete",
            "feature_status"=>string(run.status),
            "verdict"=>string(PerfChecker.suite_verdict(result)),
            "stack_samples"=>complete ? sum(only(run.result.tables).samples) : 0,
            "scope"=>"same make_case operation and independent oracle; FeatureSpec backend")
    end
end

# Runs only inside the supervised profiling controller, never in profile-plan/preflight.
function _profile_worker_loaded(plan,output)
    records=Dict{String,Any}[];limits=plan["limits"]
    for capability in plan["capabilities"]
        kind=capability["kind"];name=capability["name"]
        if capability["status"]!="implemented_not_runtime_probed"
            push!(records,merge(capability,Dict("executed"=>false)));continue
        end
        name=="type_stability" && continue # Separate target process, supervised by caller.
        directory=joinpath(output,kind*"-"*name);mkpath(directory)
        if kind=="collector"
            if name=="wall_profile"
                push!(records,profile_wall_feature(plan,directory))
                write_toml(joinpath(output,"capture-progress.toml"),
                    Dict("records"=>records,"status"=>"in_progress"))
                continue
            end
            count=name=="benchmark" ? limits["samples"] : name=="profile" ? limits["profile_repetitions"] : limits["allocation_repetitions"]
            episode_repetitions=name=="profile" ? limits["profile_episode_repetitions"] : 1
            bundles=PerfChecker.run_scenarios(profile_catalog(plan,[name];episode_repetitions);project=plan["worker_project"],
                samples=count,timeout=limits["job_seconds"],threads=limits["threads"],reports=directory)
            bundle=only(bundles);q=bundle.manifest["qualification"]
            exported=profile_export(bundle,joinpath(directory,"exports"),name)
            complete=q["correctness"]=="passed" && q["availability"]=="complete" &&
                !(get(exported,"status","")=="no_usable_stack_evidence")
            push!(records,Dict("kind"=>kind,"name"=>name,"executed"=>true,"status"=>complete ? "complete" : "incomplete",
                "qualification"=>q,"exports"=>exported,"repetitions"=>count,
                "episode_repetitions"=>episode_repetitions))
        else
            diagnosis=PerfChecker.diagnose(profile_catalog(plan,["benchmark"]);project=plan["worker_project"],
                tools=[Symbol(name)],timeout=limits["job_seconds"],threads=limits["threads"],reports=directory)
            open(joinpath(directory,"diagnosis.json"),"w") do io
                JSON.print(io,diagnosis,2)
                println(io)
            end
            native=only(diagnosis["records"])
            push!(records,Dict("kind"=>kind,"name"=>name,"executed"=>true,"status"=>native["status"],
                "correctness"=>get(native,"correctness","not_checked"),"performance"=>"not_compared"))
        end
        write_toml(joinpath(output,"capture-progress.toml"),Dict("records"=>records,"status"=>"in_progress"))
    end
    write_toml(joinpath(output,"capture-results.toml"),Dict("records"=>records,"status"=>"finished_not_a_speed_verdict"))
end
profile_worker(plan,output)=(require_perfchecker();
    Base.invokelatest(_profile_worker_loaded,plan,output))

"""Fresh bounded capture; never imports old measurements. Optional unavailable tools remain explicit."""
function _profile_capture_loaded(input;output)
    Sys.islinux() || error("profiling capture requires the Linux process-tree budget supervisor")
    plan=profile_plan(input)
    any(c->c["status"]!="implemented_not_runtime_probed",plan["capabilities"]) && !plan["allow_unavailable"] &&
        error("requested profiling capabilities are blocked; inspect profile-plan")
    profile_preflight(input;output);output=abspath(output);limits=plan["limits"]
    write_toml(joinpath(output,"machine-before.toml"),machine_snapshot())
    metadata=Dict{String,Any}("status"=>"running","started_utc"=>string(now(UTC)),"case_id"=>plan["case_id"],
        "condition"=>plan["condition"],"interference_label"=>plan["interference_label"],"performance"=>"not_compared")
    try
        with_build_directory() do temporary
            request=joinpath(temporary,"request.toml");write_toml(request,plan)
            results=joinpath(temporary,"results");mkpath(results)
            command=Cmd([first(Base.julia_cmd()),"--startup-file=no","--threads=1,0","--gcthreads=1",
                "--project="*dirname(@__DIR__),joinpath(dirname(@__DIR__),"scripts","garamonbench.jl"),"_profile-worker",request,results])
            command=addenv(command,profile_environment(plan))
            deadline=time()+limits["total_seconds"]
            job=recipe_supervise(command,joinpath(temporary,"execution.txt"),temporary,limits,deadline)
            metadata["controller_job"]=job
            if plan["type_stability"] && job["process_success"] && time()<deadline
                typerequest=Dict("source"=>only(profile_catalog(plan,["benchmark"]).scenarios).source,
                    "case"=>plan["case"],"adapter_source"=>get(plan,"adapter_source",""),
                    "type_text_bytes"=>limits["type_text_bytes"])
                path=joinpath(temporary,"types.toml");write_toml(path,typerequest)
                cmd=Cmd([first(Base.julia_cmd()),"--startup-file=no","--threads="*string(limits["threads"]),
                    "--project="*plan["worker_project"],joinpath(dirname(@__DIR__),"adapters","profiling","types.jl"),path,joinpath(results,"code_warntype.txt")])
                metadata["type_job"]=recipe_supervise(addenv(cmd,profile_environment(plan)),joinpath(temporary,"types-execution.txt"),temporary,
                    limits,min(deadline,time()+limits["job_seconds"]))
            end
            # Capture native data even on timeout/failure, without accumulated generated sources/binaries.
            for name in ("execution.txt","types-execution.txt")
                isfile(joinpath(temporary,name)) && archive_file!(joinpath(temporary,name),joinpath(output,name))
            end
            metadata["artifacts"]=profile_archive_results(results,joinpath(output,"measurements"),limits["archive_bytes"])
            metadata["status"]=job["process_success"] ? "captured_review_native_statuses" : "incomplete"
            nativefile=joinpath(results,"capture-results.toml")
            if isfile(nativefile)
                records=TOML.parsefile(nativefile)["records"]
                metadata["requested_capabilities"]=length(plan["capabilities"])
                metadata["complete_native_records"]=count(r->r["status"]=="complete",records)
                metadata["unavailable_native_records"]=count(r->!get(r,"executed",false),records)
                metadata["incomplete_native_records"]=count(r->get(r,"executed",false) && r["status"]!="complete",records)
                metadata["incomplete_native_records"]>0 && (metadata["status"]="incomplete")
            end
            if plan["type_stability"]
                type_ok=haskey(metadata,"type_job") && metadata["type_job"]["process_success"] && isfile(joinpath(results,"code_warntype.txt.toml"))
                metadata["type_stability_status"]=type_ok ? "captured_no_automatic_stability_verdict" : "incomplete"
                type_ok || (metadata["status"]="incomplete")
            end
        end
        before=TOML.parsefile(joinpath(output,"preflight.toml"))["repositories"]
        for (key,identity) in before
            observed=repository_identity(identity["root"];max_bytes=limits["source_bytes"])
            observed["sha256"]==identity["sha256"] || error("profiling source changed: $key")
        end
        metadata["source_unchanged"]=true
    catch exception
        metadata["status"]="failed";metadata["failure"]=failure_message(exception);rethrow()
    finally
        metadata["finished_utc"]=string(now(UTC));write_toml(joinpath(output,"capture.toml"),metadata)
        write_toml(joinpath(output,"machine-after.toml"),machine_snapshot())
    end
    tree_bytes(output)<=limits["archive_bytes"] || error("profiling final archive budget")
    output
end
profile_capture(input;output)=(require_perfchecker();
    Base.invokelatest(_profile_capture_loaded,input;output))

function profile_archive_results(source,destination,budget)
    files=Dict{String,Any}[];total=0
    for (directory,subdirs,names) in walkdir(source)
        any(name->islink(joinpath(directory,name)),subdirs) && error("profile directory symlink refused")
        # Native RunBundle writes an empty artifacts/ directory as well as documents.
        mkpath(joinpath(destination,relpath(directory,source)))
        for name in names
            path=joinpath(directory,name);islink(path) && error("profile symlink refused")
            relative=relpath(path,source)
            heap_sidecar=startswith(relative,"diagnostic-heap/artifacts/") &&
                (name=="after-operation.heapsnapshot" ||
                 startswith(name,"after-operation.heapsnapshot."))
            (heap_sidecar || splitext(name)[2] in
                (".json",".jsonl",".toml",".csv",".txt",".folded")) ||
                error("unexpected profile artifact: "*relpath(path,source))
            (filemode(path)&0o111)==0 || error("executable profile artifact refused")
            total+=filesize(path);total<=budget || error("profile artifact budget")
            bytes=read(path)
            if !heap_sidecar
                any(iszero,bytes) && error("binary profile artifact refused")
                content=String(copy(bytes));isvalid(content) || error("non-UTF8 profile artifact refused")
                # Diagnostic stack traces can mention the setenv function. Refuse a
                # direct environment dump, not an incidental code symbol in a trace.
                (startswith(strip(content),"setenv(") ||
                    occursin(r"\"message\"\s*:\s*\"setenv\(",content)) &&
                    error("profile artifact contains environment dump: "*relative)
            end
            target=joinpath(destination,relative);cp(path,target)
            push!(files,Dict("path"=>relative,"sha256"=>bytes2hex(sha256(bytes)),"bytes"=>length(bytes)))
        end
    end
    files
end
