"""One representative oracle case per registered technique, including an
explicit status for every roadmap entry. This is a fast screen, not full P1.
"""
function technique_smoke_plan(;benchmark_root=dirname(@__DIR__))
    registry=TOML.parsefile(joinpath(benchmark_root,"config","techniques.toml"))
    entries=vcat(registry["technique"],get(registry,"combination",Any[]))
    rows=Dict{String,Any}[]
    for entry in entries
        row=Dict{String,Any}("id"=>entry["id"],
            "name"=>get(entry,"name",entry["id"]),
            "state"=>get(entry,"state","implemented"),
            "kind"=>haskey(entry,"techniques") ? "combination" : "technique")
        if !haskey(entry,"preflight_config")
            row["status"]=entry["state"]=="research" ? "research_not_implemented" :
                "adapter_missing"
            push!(rows,row)
            continue
        end
        config=load_config(joinpath(benchmark_root,entry["preflight_config"]))
        selector=get(entry,"preflight_smoke",nothing)
        selector isa AbstractDict || error("missing smoke selector: "*entry["id"])
        all(haskey(config["grid"],key) && value in config["grid"][key]
            for (key,value) in selector) || error("invalid smoke selector: "*entry["id"])
        for (key,values) in config["grid"]
            config["grid"][key]=[get(selector,key,first(values))]
        end
        config["limits"]["max_cases"]=1
        case=only(expand_cases(config))
        row["status"]="runnable"
        row["config"]=entry["preflight_config"]
        row["adapter"]=entry["preflight_adapter"]
        row["environment"]=entry["preflight_environment"]
        row["threads"]=get(entry,"preflight_threads",1)
        row["case"]=case
        row["case_id"]=case_id(case)
        push!(rows,row)
    end
    rows
end

function technique_smoke_config(row;benchmark_root=dirname(@__DIR__))
    config=load_config(joinpath(benchmark_root,row["config"]))
    for (key,value) in row["case"]
        haskey(config["grid"],key) && (config["grid"][key]=[value])
    end
    config["limits"]["max_cases"]=1
    config
end

function include_technique_adapter(adapter,config)
    julia_root=get(configured_repositories(config),"julia",nothing)
    if isnothing(julia_root)
        Base.include(Main,adapter)
    else
        withenv("GARAMON_JULIA_ROOT"=>julia_root) do
            Base.include(Main,adapter)
        end
    end
end

"""A dedicated-machine grid for each implemented route. The smoke case only
selects its strategy and operation; dimensions, signatures and horizons stay
available for the later benchmark. Planning executes no workload.
"""
function technique_bench_config(row;benchmark_root=dirname(@__DIR__))
    config=load_config(joinpath(benchmark_root,row["config"]))
    for key in ("strategy","operation")
        if haskey(row["case"],key) && haskey(config["grid"],key)
            config["grid"][key]=[row["case"][key]]
        end
    end
    # LRU does not use the roulette exponent. Keep the same two-plan traces
    # and seeds as roulette, without repeating identical LRU measurements.
    row["id"] in ("10","12","13") &&
        haskey(config["grid"],"eviction_exponent") &&
        (config["grid"]["eviction_exponent"]=[1.0])
    row["id"] in ("10","11","13") &&
        (config["grid"]["frequency_slots"]=[256])
    row["id"] in ("10","12","13") &&
        (config["grid"]["draw_seed"]=[first(config["grid"]["draw_seed"])])
    config["campaign"]["backend"]="benchmarktools"
    config["campaign"]["condition"]="isolated"
    config["campaign"]["interference_label"]=""
    config["limits"]["samples"]=get(config["limits"],"samples",11)
    config
end

function technique_bench_plan(;benchmark_root=dirname(@__DIR__))
    rows=technique_smoke_plan(;benchmark_root)
    for row in rows
        row["status"]=="runnable" || continue
        config=technique_bench_config(row;benchmark_root)
        row["benchmark_cases"]=length(expand_cases(config))
        row["benchmark_samples_per_case"]=config["limits"]["samples"]
        row["benchmark_backend"]="BenchmarkTools"
    end
    rows
end

function technique_smoke_evidence(row,preflight;benchmark_root=dirname(@__DIR__))
    directory=joinpath(abspath(preflight),row["id"])
    isdir(directory) || error("missing minimal preflight for technique "*row["id"])
    audit=audit_resumable_archive(technique_smoke_config(row;benchmark_root),directory)
    audit["archive_integrity"]=="validated" &&
        audit["completed_ids"]==[row["case_id"]] &&
        all(values(audit["current_sources_match"])) ||
        error("minimal preflight is incomplete or sources changed for technique "*row["id"])
    audit
end

"""A bounded PerfChecker request for the exact case and callbacks already used
by the minimal preflight. GPU profiling uses the CUDA project and omits tools
that are not installed in that project; CUDA kernel/transfer traces are captured
separately by the GPU adapter's diagnostic callback.
"""
function technique_profile_request(row;benchmark_root=dirname(@__DIR__))
    row["status"]=="runnable" || error("profiling requires a runnable route")
    gpu=row["environment"]=="gpu"
    catalogue=row["id"]=="15"
    # Short kernels need a longer episode for the sampling CPU profiler to
    # produce usable stacks. Keep bounded recursive, process and device cases
    # at the shorter episode; this setting does not alter benchmark samples.
    long_cpu_episode=!gpu && !(row["id"] in ("15","19","20","25","27","28"))
    # A single cache-trace or radical call is much slower than a small vector
    # product: 100 × 4096 calls exceeded the native 120 s collector timeout.
    # Recurrence, replay and indexing episodes at 100 × 4096 crossed the
    # aggregate RSS limit. Use 100 × 512 to retain useful sampling time while
    # bounding the live trajectory data. The approximate 2D recurrence at
    # 50 × 64 finished before the sampling profiler saw a useful stack.
    # The process route is slower under Profile; 50 × 64 and 50 × 16 exceeded
    # the 120 s collector limit.
    episode_repetitions=row["id"] in ("10","11","12","13","33") ? 1024 :
        row["id"] in ("17","24","25","30","32","38","39","46") ? 512 : row["id"]=="28" ? 4 :
        long_cpu_episode ? 4096 : 64
    profile_repetitions=row["id"]=="28" ? 20 :
        row["id"]=="25" ? 100 : long_cpu_episode ? 100 : 50
    # Instrumentation creates descendant processes whose aggregate RSS can be
    # much larger than the kernel's live data. These ceilings are sequential
    # and explicit: the 65D indexing route crossed 4 GiB even at 100 × 512.
    profile_rss_bytes=row["id"]=="30" ? 6<<30 : row["id"] in ("32","38","39","45","46") ? 5<<30 :
        row["id"] in ("15","17","24","25","K3") ? 4<<30 : 3<<30
    Dict{String,Any}("schema_version"=>1,
        "profiling"=>Dict{String,Any}(
            "case_config"=>joinpath(benchmark_root,row["config"]),
            "case_id"=>row["case_id"],
            "worker_project"=>joinpath(benchmark_root,gpu ? "gpu" : "worker"),
            "collectors"=>gpu ? ["benchmark","profile","profile_alloc"] :
                catalogue ? ["benchmark","profile_alloc","wall_profile"] :
                ["benchmark","profile","profile_alloc","wall_profile"],
            "diagnostics"=>gpu ? ["latency","gc","memory"] :
                ["latency","gc","memory","jet","alloccheck"],
            "type_stability"=>true,"allow_unavailable"=>true),
        "limits"=>Dict{String,Any}("threads"=>row["threads"],"samples"=>3,
            "profile_repetitions"=>profile_repetitions,
            "profile_episode_repetitions"=>episode_repetitions,
            "allocation_repetitions"=>1,"job_seconds"=>120,
            "total_seconds"=>catalogue ? 900 : 600,"rss_bytes"=>profile_rss_bytes,
            "scratch_bytes"=>256<<20,"archive_bytes"=>256<<20))
end

function technique_profile_evidence(directory,row)
    planfile=joinpath(directory,"profile-plan.toml")
    capturefile=joinpath(directory,"capture.toml")
    preflightfile=joinpath(directory,"preflight.toml")
    all(isfile,(planfile,capturefile,preflightfile)) || return false
    plan=TOML.parsefile(planfile);capture=TOML.parsefile(capturefile)
    plan["case_id"]==row["case_id"] && capture["case_id"]==row["case_id"] &&
        get(capture,"source_unchanged",false)===true &&
        get(capture,"status","")=="captured_review_native_statuses" &&
        get(capture,"incomplete_native_records",1)==0 || return false
    roots=TOML.parsefile(preflightfile)["repositories"]
    all(identity["sha256"]==repository_identity(identity["root"])["sha256"]
        for identity in values(roots)) || return false
    all(isfile(joinpath(directory,"measurements",artifact["path"])) &&
        _resume_sha(joinpath(directory,"measurements",artifact["path"]))==artifact["sha256"]
        for artifact in capture["artifacts"])
end

function _completed_technique_archive(config,directory)
    isdir(directory) || return false
    try
        audit=audit_resumable_archive(config,directory)
        audit["archive_integrity"]=="validated" &&
            audit["same_machine_resume_allowed"] && isempty(audit["pending_ids"])
    catch
        false
    end
end

function _completed_profile_archive(directory,row)
    isdir(directory) || return false
    try
        technique_profile_evidence(directory,row)
    catch
        false
    end
end

"""Capture bounded native PerfChecker evidence route by route. A complete
capture whose sources and artifacts still match is never executed twice.
Incomplete attempts stay on disk for diagnosis and require a new output root.
"""
function run_technique_profiles(preflight,output;ids=String[])
    root=dirname(@__DIR__)
    rows=technique_smoke_plan(;benchmark_root=root)
    requested=Set(ids)
    isempty(requested) || issubset(requested,Set(row["id"] for row in rows)) ||
        error("unknown technique ID")
    selected=isempty(requested) ? rows : filter(row->row["id"] in requested,rows)
    output=abspath(output);mkpath(output)
    report=joinpath(output,"profile-progress.toml")
    previous=isfile(report) ? TOML.parsefile(report) : Dict{String,Any}()
    results=Dict{String,Any}(r["id"]=>Dict{String,Any}(r)
        for r in get(previous,"technique",Any[]))
    for row in selected
        result=Dict{String,Any}("id"=>row["id"],"case_id"=>get(row,"case_id",""))
        directory=joinpath(output,row["id"])
        if row["status"]!="runnable"
            result["status"]=row["status"]
        elseif _completed_profile_archive(directory,row)
            result["status"]="captured"
            result["archive"]=directory
        elseif !samefile(dirname(Base.active_project()),joinpath(root,row["environment"]))
            result["status"]="requires_environment"
        elseif Threads.nthreads()!=row["threads"]
            result["status"]="requires_threads"
        else
            try
                technique_smoke_evidence(row,preflight;benchmark_root=root)
                if ispath(directory)
                    technique_profile_evidence(directory,row) ||
                        error("existing profile attempt is incomplete or sources changed; use a fresh output root")
                else
                    profile_capture(technique_profile_request(row;benchmark_root=root);
                        output=directory)
                    technique_profile_evidence(directory,row) ||
                        error("PerfChecker capture lacks complete auditable evidence")
                end
                result["status"]="captured"
                result["archive"]=directory
            catch exception
                exception isa InterruptException && rethrow()
                result["status"]="failed"
                result["reason"]=failure_message(exception)
            end
        end
        results[row["id"]]=result
        ordered=[results[r["id"]] for r in rows if haskey(results,r["id"])]
        _resume_write(report,Dict("scope"=>"bounded PerfChecker on exact minimal-preflight callbacks",
            "updated_utc"=>string(now(UTC)),"technique"=>ordered,
            "captured_count"=>count(r->r["status"]=="captured",ordered)))
    end
    report
end

"""Run selected native benchmark grids after one exact smoke case per route.
Each technique has an independently resumable DrWatson archive. This function
does not invoke PerfChecker and never reuses another machine's timing data.
"""
function run_technique_bench(preflight,output;ids=String[])
    root=dirname(@__DIR__)
    rows=technique_bench_plan(;benchmark_root=root)
    requested=Set(ids)
    isempty(requested) || issubset(requested,Set(row["id"] for row in rows)) ||
        error("unknown technique ID")
    selected=isempty(requested) ? rows : filter(row->row["id"] in requested,rows)
    output=abspath(output)
    mkpath(output)
    included=Set{String}()
    report=joinpath(output,"bench-progress.toml")
    previous=isfile(report) ? TOML.parsefile(report) : Dict{String,Any}()
    results=Dict{String,Any}(r["id"]=>Dict{String,Any}(r)
        for r in get(previous,"technique",Any[]))
    for row in selected
        result=Dict{String,Any}("id"=>row["id"],"name"=>row["name"],
            "benchmark_cases"=>get(row,"benchmark_cases",0),
            "case_id"=>get(row,"case_id",""))
        directory=joinpath(output,row["id"])
        if row["status"]!="runnable"
            result["status"]=row["status"]
        elseif isdir(directory) && _completed_technique_archive(
            technique_bench_config(row;benchmark_root=root),directory)
            result["status"]="complete"
            result["archive"]=directory
        elseif !samefile(dirname(Base.active_project()),joinpath(root,row["environment"]))
            result["status"]="requires_environment"
            result["environment"]=row["environment"]
        elseif Threads.nthreads()!=row["threads"]
            result["status"]="requires_threads"
            result["threads"]=row["threads"]
        else
            try
                technique_smoke_evidence(row,preflight;benchmark_root=root)
                config=technique_bench_config(row;benchmark_root=root)
                adapter=joinpath(root,row["adapter"])
                if !(adapter in included)
                    include_technique_adapter(adapter,config)
                    push!(included,adapter)
                end
                Base.invokelatest(run_resumable_campaign,
                    config;output=directory)
                result["status"]="complete"
                result["archive"]=directory
            catch exception
                exception isa InterruptException && rethrow()
                result["status"]="failed"
                result["reason"]=failure_message(exception)
            end
        end
        results[row["id"]]=result
        ordered=[results[r["id"]] for r in rows if haskey(results,r["id"])]
        _resume_write(report,
            Dict("scope"=>"isolated native benchmark; one exact smoke case required per technique",
                "updated_utc"=>string(now(UTC)),"technique"=>ordered,
                "complete_count"=>count(r->r["status"]=="complete",ordered)))
    end
    report
end

"""Execute the short screen with the same resumable DrWatson-backed archive
used by the full grid. Completed cases are verified and skipped on replay.
"""
function run_technique_smoke(output;ids=String[])
    root=dirname(@__DIR__)
    rows=technique_smoke_plan(;benchmark_root=root)
    requested=Set(ids)
    isempty(requested) || issubset(requested,Set(row["id"] for row in rows)) ||
        error("unknown technique ID")
    selected=isempty(requested) ? rows : filter(row->row["id"] in requested,rows)
    output=abspath(output)
    mkpath(output)
    included=Set{String}()
    report=joinpath(output,"quickcheck.toml")
    previous=isfile(report) ? TOML.parsefile(report) : Dict{String,Any}()
    results=Dict{String,Any}(r["id"]=>Dict{String,Any}(r)
        for r in get(previous,"technique",Any[]))
    for row in selected
        result=Dict{String,Any}("id"=>row["id"],"name"=>row["name"],
            "case_id"=>get(row,"case_id",""))
        directory=joinpath(output,row["id"])
        if row["status"]!="runnable"
            result["status"]=row["status"]
        elseif isdir(directory) && _completed_technique_archive(
            technique_smoke_config(row;benchmark_root=root),directory)
            result["status"]="oracle_passed"
            result["archive"]=directory
        elseif !samefile(dirname(Base.active_project()),
            joinpath(root,row["environment"]))
            result["status"]="requires_environment"
            result["environment"]=row["environment"]
        elseif Threads.nthreads()!=row["threads"]
            result["status"]="requires_threads"
            result["threads"]=row["threads"]
        else
            try
                config=technique_smoke_config(row;benchmark_root=root)
                adapter=joinpath(root,row["adapter"])
                if !(adapter in included)
                    include_technique_adapter(adapter,config)
                    push!(included,adapter)
                end
                Base.invokelatest(run_resumable_campaign,config;output=directory)
                audit=audit_resumable_archive(config,directory)
                audit["archive_integrity"]=="validated" &&
                    audit["completed_ids"]==[row["case_id"]] ||
                    error("quick preflight archive audit failed")
                result["status"]="oracle_passed"
                result["archive"]=directory
            catch exception
                result["status"]="failed"
                result["reason"]=failure_message(exception)
            end
        end
        results[row["id"]]=result
        ordered=[results[r["id"]] for r in rows if haskey(results,r["id"])]
        _resume_write(report,
            Dict("scope"=>"one representative case per registered technique; not full P1",
                "updated_utc"=>string(now(UTC)),"technique"=>ordered,
                "oracle_passed_count"=>count(r->r["status"]=="oracle_passed",ordered)))
    end
    report
end
