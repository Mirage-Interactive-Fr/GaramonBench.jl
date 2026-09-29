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

function case_guard(rows,start,limits)
    maximum(r.disk_checkpoint_bytes for r in rows;init=0)<=get(limits,"build_disk_bytes",256<<20) || error("build disk budget")
    Sys.maxrss()<=get(limits,"controller_rss_bytes",2<<30) || error("controller RSS budget")
    time()-start<=get(limits,"case_seconds",120) || error("case time budget")
end

function run_case(adapter,case,limits;capture_trial=Ref{Any}(nothing),artifact_dir=nothing)
    rows=NamedTuple[]; id=case_id(case); oracle_status=false
    state=nothing; start=time(); disk_checkpoints=Int[]
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
            first=measured_stage!(rows,id,"first_execution",temporary,()->adapter.execute(state))
            adapter.oracle(state,first) === true || error("independent oracle rejected first output")
            samples=get(limits,"samples",11)
            samples>=1 || error("sample count")
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
            adapter.oracle(state,adapter.execute(state)) === true || error("independent oracle rejected final output")
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
            Sys.maxrss()<=get(limits,"controller_rss_bytes",2<<30) || error("controller RSS budget")
            time()-start<=get(limits,"case_seconds",120) || error("case time budget")
        finally
            isnothing(state) || adapter.cleanup(state)
        end
    end
    return rows,Dict{String,Any}("case_id"=>id,"oracle_passed"=>oracle_status,
        "contract"=>adapter.contract,"adapter_capabilities"=>adapter.capabilities,
        "temporary_build_removed"=>true,"disk_metric"=>"stage boundary observations; not continuous peak",
        "benchmark_backend"=>"BenchmarkTools", "case_elapsed_seconds"=>time()-start,
        "diagnostics"=>diagnostics)
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
                Sys.maxrss()<=get(limits,"controller_rss_bytes",2<<30) ||
                    error("preflight controller RSS budget")
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
                !haskey(ENV,spec["env"]) && !isdir(expanduser(value))
            package_file=Base.find_package("Garamon")
            isnothing(package_file) && error("Garamon dependency is not installed")
            roots[label]=dirname(dirname(package_file))
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
