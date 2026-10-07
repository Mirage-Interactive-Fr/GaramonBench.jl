timed_call(f)=@timed f()
jit_bytes()=isdefined(Base,:jit_total_bytes) ? Base.jit_total_bytes() : 0

function stage_record(caseid,phase,measurement,directory,jit_before)
    (;case_id=caseid,phase,sample=0,time_ns=measurement.time*1e9,
      gc_ns=measurement.gctime*1e9,allocated_bytes=measurement.bytes,
      allocation_scope="Julia_controller",compile_ns=measurement.compile_time*1e9,
      recompile_ns=measurement.recompile_time*1e9,
      jit_code_bytes_delta=max(0,jit_bytes()-jit_before),
      controller_peak_rss_bytes=Sys.maxrss(),disk_checkpoint_bytes=tree_bytes(directory))
end

function measured_stage!(rows,caseid,phase,directory,f)
    before=jit_bytes(); observed=timed_call(f)
    push!(rows,stage_record(caseid,phase,observed,directory,before))
    return observed.value
end

function resident_rss_bytes()
    Sys.islinux() || return Sys.maxrss()
    # maxrss is the process lifetime high-water mark, not current memory.
    parse(Int,split(read("/proc/self/statm",String))[2])*Sys.PAGESIZE
end

struct ControllerMemoryBudget <: Exception
    observed::Int
    limit::Int
end
Base.showerror(io::IO,e::ControllerMemoryBudget)=print(io,
    "controller RSS budget: current resident bytes ",e.observed," exceed ",e.limit)

function controller_memory_guard(limits)
    limit=get(limits,"controller_rss_bytes",2<<30)
    observed=resident_rss_bytes()
    if observed>limit
        GC.gc(true) # Outside the timed kernel: reclaim prior case state.
        observed=resident_rss_bytes()
    end
    observed<=limit || throw(ControllerMemoryBudget(observed,limit))
    nothing
end

function paired_case_budget(limits,rows,elapsed;baseline_required=false,verification_only=false)
    nominal=Float64(get(limits,"case_seconds",120))
    baseline_required || return nominal
    # A slow exact reference must receive enough time for the declared
    # sample count. This changes admission only, never the timed functions.
    candidate=maximum((r.time_ns/1e9 for r in rows if r.phase in
        ("first_execution","warm"));init=0.0)
    reference=maximum((r.time_ns/1e9 for r in rows if r.phase in
        ("baseline_first_execution","baseline_warm"));init=0.0)
    remaining=verification_only ? 1 : get(limits,"samples",11)+1
    required=elapsed+2*remaining*(candidate+reference)
    minimum_seconds=Float64(get(limits,"paired_case_min_seconds",3600))
    maximum_seconds=Float64(get(limits,"paired_case_max_seconds",21600))
    0<minimum_seconds<=maximum_seconds || error("invalid paired case time limits")
    max(nominal,min(max(minimum_seconds,required),maximum_seconds))
end

function case_guard(rows,start,limits)
    maximum(r.disk_checkpoint_bytes for r in rows;init=0)<=get(limits,"build_disk_bytes",256<<20) || error("build disk budget")
    controller_memory_guard(limits)
    time()-start<=get(limits,"case_seconds",120) || error("case time budget")
end

function _run_case_unlocked(adapter,case,limits;capture_trial=Ref{Any}(nothing),
                            artifact_dir=nothing,baseline_cache=nothing)
    limits=Dict{String,Any}(limits)
    declared_seconds=get(limits,"case_seconds",120)
    rows=NamedTuple[]; id=case_id(case); oracle_status=false
    baseline_required=get(case,"baseline_required",false)
    baseline_required && (limits["case_seconds"]=paired_case_budget(limits,NamedTuple[],0;
        baseline_required=true))
    baseline_required && (isnothing(adapter.baseline_execute) ||
        isempty(adapter.baseline_name)) &&
        error("a named Garamon.jl standard baseline is required for "*id)
    state=nothing; baseline_state=nothing; start=time(); disk_checkpoints=Int[]
    baseline_record=nothing; baseline_key=nothing; baseline_file=nothing
    baseline_output_hash=nothing; baseline_cache_hit=false
    diagnostics=Dict{String,Any}()
    with_build_directory() do temporary
        try
            generated=measured_stage!(rows,id,"generation",temporary,
                ()->adapter.generate(case,temporary,Xoshiro(case["seed"])))
            case_guard(rows,start,limits)
            built=measured_stage!(rows,id,"build",temporary,()->adapter.build(generated,case,temporary))
            case_guard(rows,start,limits)
            state=measured_stage!(rows,id,"preparation",temporary,()->adapter.prepare(built,case,temporary))
            case_guard(rows,start,limits)
            if baseline_required
                if !isnothing(baseline_cache) && !isnothing(adapter.baseline_scenario)
                    get(case,"baseline_equality_required",true) ||
                        error("shared baseline currently requires identical exact outputs")
                    isnothing(adapter.baseline_output_identity) &&
                        error("shared baseline requires a full output identity")
                    scenario=adapter.baseline_scenario(state,case)
                    scenario isa AbstractDict || error("baseline scenario must be a dictionary")
                    identity=Dict("context"=>baseline_cache.context,
                        "scenario"=>scenario,"baseline_name"=>adapter.baseline_name,
                        "samples"=>get(limits,"samples",11))
                    baseline_key=bytes2hex(sha256(canonical_toml(identity)))
                    baseline_file=joinpath(baseline_cache.root,baseline_key*".toml")
                    if isfile(baseline_file)
                        baseline_record=TOML.parsefile(baseline_file)
                        baseline_record["identity"]==identity &&
                            length(baseline_record["time_ns"])==get(limits,"samples",11) ||
                            error("shared baseline identity or samples changed")
                        baseline_cache_hit=true
                    end
                end
                if !baseline_cache_hit
                    baseline_state=measured_stage!(rows,id,"baseline_preparation",temporary,
                        ()->adapter.baseline_prepare(state))
                    case_guard(rows,start,limits)
                end
            end
            first=measured_stage!(rows,id,"first_execution",temporary,()->adapter.execute(state))
            adapter.oracle(state,first) === true || error("independent oracle rejected first output")
            if baseline_cache_hit
                adapter.baseline_output_identity(first)==baseline_record["output_sha256"] ||
                    error("cached standard baseline has different output on this scenario")
            elseif baseline_required
                baseline_first=measured_stage!(rows,id,"baseline_first_execution",temporary,
                    ()->adapter.baseline_execute(baseline_state))
                baseline_check=isnothing(adapter.baseline_oracle) ? adapter.oracle :
                    adapter.baseline_oracle
                baseline_check(state,baseline_first) === true ||
                    error("independent oracle rejected Garamon.jl baseline")
                get(case,"baseline_equality_required",true) &&
                    baseline_first!=first &&
                    error("strategy and standard baseline returned different exact outputs")
                !isnothing(baseline_file) &&
                    (baseline_output_hash=adapter.baseline_output_identity(baseline_first))
            end
            samples=get(limits,"samples",11)
            samples>=1 || error("sample count")
            limits["case_seconds"]=paired_case_budget(limits,rows,time()-start;baseline_required)
            # BenchmarkTools stops at either its sample count or its seconds
            # deadline. A short warm deadline silently produced fewer samples
            # for a slower high-dimensional case. The case wall budget is the
            # actual deadline; the requested sample count remains mandatory.
            seconds=get(limits,"case_seconds",120)-(time()-start)
            seconds>0 || error("no case time remains for warm samples")
            trial=@benchmark $(adapter.execute)($state) samples=samples evals=1 seconds=seconds
            length(trial.times)==samples ||
                error("warm samples incomplete within case time budget: $(length(trial.times))/$samples")
            capture_trial[]=trial
            for i in eachindex(trial.times)
                push!(rows,(;case_id=id,phase="warm",sample=i,time_ns=trial.times[i],
                    gc_ns=trial.gctimes[i],allocated_bytes=trial.memory,
                    allocation_scope="BenchmarkTools_estimate_not_per_sample",
                    compile_ns="unmeasured",recompile_ns="unmeasured",
                    jit_code_bytes_delta="unmeasured",controller_peak_rss_bytes=Sys.maxrss(),
                    disk_checkpoint_bytes=tree_bytes(temporary)))
            end
            if baseline_required && !baseline_cache_hit
                remaining=get(limits,"case_seconds",120)-(time()-start)
                remaining>0 || error("no case time remains for baseline samples")
                baseline_trial=@benchmark $(adapter.baseline_execute)($baseline_state) samples=samples evals=1 seconds=remaining
                length(baseline_trial.times)==samples ||
                    error("baseline samples incomplete within case time budget")
                for i in eachindex(baseline_trial.times)
                    push!(rows,(;case_id=id,phase="baseline_warm",sample=i,
                        time_ns=baseline_trial.times[i],gc_ns=baseline_trial.gctimes[i],
                        allocated_bytes=baseline_trial.memory,
                        allocation_scope="BenchmarkTools_estimate_not_per_sample",
                        compile_ns="unmeasured",recompile_ns="unmeasured",
                        jit_code_bytes_delta="unmeasured",controller_peak_rss_bytes=Sys.maxrss(),
                        disk_checkpoint_bytes=tree_bytes(temporary)))
                end
                # Reserve the final exact reference verification using the
                # measured warm cost, including observed GC time variation.
                limits["case_seconds"]=paired_case_budget(limits,rows,time()-start;
                    baseline_required=true,verification_only=true)
                baseline_check(state,adapter.baseline_execute(baseline_state)) === true ||
                    error("independent oracle rejected final Garamon.jl baseline")
            end
            adapter.oracle(state,adapter.execute(state)) === true || error("independent oracle rejected final output")
            if !isnothing(baseline_file) && !baseline_cache_hit
                baseline_rows=[row for row in rows if row.phase=="baseline_warm"]
                identity=Dict("context"=>baseline_cache.context,
                    "scenario"=>adapter.baseline_scenario(state,case),
                    "baseline_name"=>adapter.baseline_name,
                    "samples"=>get(limits,"samples",11))
                baseline_record=Dict{String,Any}(
                    "identity"=>identity,"output_sha256"=>baseline_output_hash,
                    "time_ns"=>[row.time_ns for row in baseline_rows],
                    "gc_ns"=>[row.gc_ns for row in baseline_rows],
                    "allocated_bytes"=>[row.allocated_bytes for row in baseline_rows],
                    "source_case_id"=>id)
                _resume_write(baseline_file,baseline_record)
            end
            oracle_status=true
            if !isnothing(artifact_dir)
                observed=adapter.diagnostics(state,case,artifact_dir)
                observed isa AbstractDict || error("adapter diagnostics must return a dictionary")
                diagnostics=Dict{String,Any}(string(k)=>v for (k,v) in observed)
                adapter.oracle(state,adapter.execute(state)) === true ||
                    error("independent oracle rejected post-diagnostic output")
            end
            append!(disk_checkpoints,[r.disk_checkpoint_bytes for r in rows])
            maximum(disk_checkpoints;init=0)<=get(limits,"build_disk_bytes",256<<20) || error("build disk budget")
            controller_memory_guard(limits)
            time()-start<=get(limits,"case_seconds",120) || error("case time budget")
        finally
            isnothing(baseline_state) || adapter.baseline_cleanup(baseline_state)
            isnothing(state) || adapter.cleanup(state)
        end
    end
    verdict=Dict{String,Any}("case_id"=>id,"oracle_passed"=>oracle_status,
        "baseline_required"=>baseline_required,
        "baseline_name"=>baseline_required ? adapter.baseline_name : "none",
        "baseline_oracle_passed"=>baseline_required ? oracle_status : false,
        "baseline_samples_verified"=>baseline_required ? get(limits,"samples",11) : 0,
        "contract"=>adapter.contract,"adapter_capabilities"=>adapter.capabilities,
        "temporary_build_removed"=>true,"disk_metric"=>"stage boundary observations; not continuous peak",
        "benchmark_backend"=>"BenchmarkTools", "case_elapsed_seconds"=>time()-start,
        "declared_case_seconds"=>declared_seconds,
        "effective_case_seconds"=>limits["case_seconds"],
        "diagnostics"=>diagnostics)
    if !isnothing(baseline_file)
        verdict["baseline_cache_file"]=isnothing(artifact_dir) ? baseline_file :
            relpath(baseline_file,artifact_dir)
        verdict["baseline_cache_sha256"]=_resume_sha(baseline_file)
        verdict["baseline_cache_hit"]=baseline_cache_hit
    end
    return rows,verdict
end

function run_case(adapter,case,limits;capture_trial=Ref{Any}(nothing),
                  artifact_dir=nothing,baseline_cache=nothing)
    if isnothing(baseline_cache)
        return _run_case_unlocked(adapter,case,limits;capture_trial,artifact_dir)
    end
    mkpath(baseline_cache.root)
    _resume_lock(baseline_cache.root) do
        _run_case_unlocked(adapter,case,limits;capture_trial,artifact_dir,baseline_cache)
    end
end

"""Run the adapter contract twice and check both complete outputs, without
BenchmarkTools or PerfChecker measurements. Build products remain disposable.
"""
function run_case_preflight(adapter,case,limits)
    id=case_id(case)
    state=nothing
    started=time()
    evidence=Dict{String,Any}()
    with_build_directory() do temporary
        try
            generated=adapter.generate(case,temporary,Xoshiro(case["seed"]))
            state=adapter.prepare(adapter.build(generated,case,temporary),case,temporary)
            for repetition in 1:2
                result=adapter.execute(state)
                adapter.oracle(state,result) === true ||
                    error("independent oracle rejected preflight output: "*id)
                if repetition==2
                    raw=adapter.preflight_evidence(state,result)
                    raw isa AbstractDict || error("preflight evidence must be a dictionary")
                    evidence=Dict{String,Any}(string(k)=>v for (k,v) in raw)
                    ncodeunits(canonical_toml(evidence))<=65536 ||
                        error("preflight evidence exceeds 64 KiB")
                end
                tree_bytes(temporary)<=get(limits,"build_disk_bytes",256<<20) ||
                    error("preflight build disk budget")
                controller_memory_guard(limits)
                time()-started<=get(limits,"case_seconds",120) ||
                    error("preflight case time budget")
            end
        finally
            isnothing(state) || adapter.cleanup(state)
        end
    end
    Dict{String,Any}("case_id"=>id,"oracle_passed"=>true,
        "contract"=>adapter.contract,"adapter_capabilities"=>adapter.capabilities,
        "temporary_build_removed"=>true,"benchmark_backend"=>"oracle_preflight",
        "execution_count"=>2,"samples_collected"=>0,
        "preflight_evidence"=>evidence)
end

function _run_case_perfchecker_loaded(adapter,case,limits;artifact_dir=nothing)
    captured=Ref{Any}(nothing)
    capture_trial=Ref{Any}(nothing)
    mktempdir() do temporary
        entrypoint=joinpath(temporary,"case.jl")
        write(entrypoint,"# GaramonBench custom executor: "*case_id(case)*"\n")
        feature=PerfChecker.FeatureSpec(Symbol(case_id(case));
            description="GaramonBench exact owned result: "*adapter.contract,
            backend=:benchmark,entrypoint,
            comparison_key="garamonbench/"*case_id(case)*"/v1",
            oracle=PerfChecker.OracleSpec(),options=Dict(:case_identity=>case_id(case)))
        root=dirname(@__DIR__)
        package=PerfChecker.PackageSuite("GaramonBench";worker_environment=joinpath(root,"worker"),
            source=root,versions=VersionNumber[],dev_sources=String[],features=[feature])
        suite=PerfChecker.SoftwareSuite(:garamonbench_exact,[package];
            description="GaramonBench adapter with independent exact oracle")
        executor=function (planned,configuration,setup,workload)
            rows,verdict=run_case(adapter,case,limits;capture_trial,artifact_dir)
            captured[]=(rows,verdict)
            qualification=Dict{String,Any}("correctness"=>Dict("status"=>"passed",
                "required"=>true,"message"=>"independent full-output oracle before and after samples"),
                "execution"=>Dict("mode"=>"shared_process_adapter","contract"=>adapter.contract),
                "case_identity"=>case_id(case))
            PerfChecker.CheckerResult([PerfChecker.to_table(capture_trial[])],nothing,
                [:garamonbench,:exact_oracle],[PerfChecker.PackageSpec(name="GaramonBench")],[qualification])
        end
        result=PerfChecker.run_suite(suite;profile=:quick,strict=false,executor)
        PerfChecker.suite_passed(result) || error("PerfChecker feature failed: $(PerfChecker.suite_verdict(result))")
        rows,verdict=captured[]
        run=only(result.runs)
        table=only(run.result.tables)
        raw=[row.time_ns for row in rows if row.phase=="warm"]
        raw==Float64.(table.times) || error("PerfChecker/raw sample mismatch")
        verdict["benchmark_backend"]="PerfChecker"
        verdict["perfchecker_verdict"]=string(PerfChecker.suite_verdict(result))
        verdict["perfchecker_feature_status"]=string(run.status)
        verdict["perfchecker_version"]=string(pkgversion(PerfChecker))
        verdict["perfchecker_samples_verified"]=length(raw)
        return rows,verdict
    end
end
run_case_perfchecker(adapter,case,limits;artifact_dir=nothing)=(require_perfchecker();
    Base.invokelatest(_run_case_perfchecker_loaded,adapter,case,limits;artifact_dir))

function configured_repositories(config)
    roots=Dict("benchmark"=>dirname(@__DIR__))
    for (label,spec) in get(config,"repositories",Dict())
        value=spec isa AbstractString ? spec : get(ENV,spec["env"],spec["default"])
        if value=="artifact:garamon_cpp"
            roots[label]=ensure_cpp_source()
        elseif label=="julia" && spec isa AbstractDict &&
                !haskey(ENV,spec["env"])
            roots[label]=garamon_source_root()
        else
            roots[label]=expanduser(value)
        end
    end
    return roots
end

function run_campaign(config::AbstractDict;output_root,repeat_of=nothing)
    cases=expand_cases(config)
    for case in cases
        haskey(ADAPTERS,case["adapter"]) || error("load adapter $(case["adapter"]) before running")
    end
    condition=config["campaign"]["condition"]
    backend=get(config["campaign"],"backend","benchmarktools")
    backend in ("benchmarktools","perfchecker") || error("unknown benchmark backend")
    roots=configured_repositories(config)
    limits=get(config,"limits",Dict())
    stamp=Dates.format(now(UTC),dateformat"yyyymmddTHHMMSS")
    runid=stamp*"_"*condition*"_"*first(string(uuid4()),8)
    output=joinpath(abspath(output_root),runid); mkpath(output)
    sourceidentities=Dict{String,Any}()
    manifest=Dict{String,Any}("schema_version"=>SCHEMA_VERSION,"run_id"=>runid,
        "condition"=>condition,"interference_label"=>get(config["campaign"],"interference_label",""),
        "isolation_status"=>"declared_by_operator_not_certified_by_snapshot",
        "status"=>"running","cases_expected"=>length(cases),"cases_passed"=>0,
        "julia_packages"=>package_versions(),"benchmark_backend"=>backend,
        "not_a_perfchecker_campaign"=>backend!="perfchecker",
        "repeat_of"=>isnothing(repeat_of) ? "none" : abspath(repeat_of))
    write_toml(joinpath(output,"configuration.toml"),config)
    write_toml(joinpath(output,"machine_before.toml"),machine_snapshot())
    manifest_path=joinpath(output,"run.toml")
    allrows=NamedTuple[]; verdicts=Dict{String,Any}[]
    try
        for (label,root) in roots
            sourceidentities[label]=repository_identity(root;
                snapshot=joinpath(output,"sources",label),
                max_bytes=get(limits,"source_snapshot_bytes",64<<20))
        end
        manifest["repositories"]=sourceidentities
        if !isnothing(repeat_of)
            parent=TOML.parsefile(joinpath(repeat_of,"run.toml"))
            parentconfig=TOML.parsefile(joinpath(repeat_of,"configuration.toml"))
            case_id.(expand_cases(parentconfig))==case_id.(cases) || error("repeat case corpus differs")
            for label in keys(sourceidentities)
                parent["repositories"][label]["sha256"]==sourceidentities[label]["sha256"] ||
                    error("repeat source differs: $label")
            end
        end
        for file in ("Project.toml","Manifest.toml")
            source=joinpath(dirname(@__DIR__),file)
            isfile(source) && archive_file!(source,joinpath(output,"environment",file))
        end
        write_toml(manifest_path,manifest)
        for case in cases
            write_toml(joinpath(output,case_id(case)*".toml"),case)
            runner=backend=="perfchecker" ? run_case_perfchecker : run_case
            rows,verdict=runner(ADAPTERS[case["adapter"]],case,limits)
            append!(allrows,rows); push!(verdicts,verdict)
            write_csv(joinpath(output,"samples.csv"),allrows)
            manifest["cases_passed"]=length(verdicts)
            manifest["case_verdicts"]=verdicts
            write_toml(manifest_path,manifest)
            tree_bytes(output)<=get(limits,"archive_bytes",256<<20) || error("archive budget")
        end
        for (label,root) in roots
            observed=repository_identity(root;max_bytes=get(limits,"source_snapshot_bytes",64<<20))
            observed["sha256"]==sourceidentities[label]["sha256"] || error("source changed during run: $label")
        end
        manifest["status"]="passed"
    catch error
        manifest["status"]="failed"
        manifest["failure"]=failure_message(error)
        manifest["exit_codes"]=failure_exit_codes(error)
        rethrow()
    finally
        manifest["archive_bytes_at_finalization"]=tree_bytes(output)
        write_toml(joinpath(output,"machine_after.toml"),machine_snapshot())
        write_toml(manifest_path,manifest)
    end
    return output
end

"""Tiny harness self-test, explicitly not a Garamon performance result."""
function register_smoke_adapter!()
    register_adapter!(BenchmarkAdapter(name="harness_smoke",
        contract="owned Int64 vector of exact squares; harness validation only",
        generate=(case,dir,rng)->rand(rng,Int64(1):Int64(9),case["length"]),
        execute=state->state .* state,
        oracle=(state,result)->result==[sum(state[i] for _ in 1:state[i]) for i in eachindex(state)],
        capabilities=Dict("scientific_garamon_result"=>false));replace=true)
end
