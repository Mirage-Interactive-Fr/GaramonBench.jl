# A per-case, append-only campaign for a dedicated Linux machine. A completion
# directory is published by an atomic rename only after oracle and raw-sample
# checks pass. flock releases automatically when a process dies.

function _resume_lock(f,root)
    Sys.islinux() || error("resumable campaign currently requires Linux")
    open(joinpath(root,".run.lock"),"a+") do io
        descriptor=reinterpret(Cint,fd(io))
        ccall(:flock,Cint,(Cint,Cint),descriptor,Cint(2|4))==0 ||
            error("another process holds this campaign")
        try
            f()
        finally
            ccall(:flock,Cint,(Cint,Cint),descriptor,Cint(8))
        end
    end
end

function _resume_write(path,data)
    temporary=path*".tmp-"*string(uuid4())
    try
        write_toml(temporary,data)
        mv(temporary,path;force=true)
    finally
        isfile(temporary) && rm(temporary)
    end
end

_resume_sha(path)=bytes2hex(open(sha256,path))

function _resume_execution(manifest)
    haskey(manifest,"active_execution") || return manifest
    active=manifest["active_execution"]
    any(r->r==active,get(manifest,"source_revisions",Any[])) ||
        error("active source revision is not in the recorded history")
    active
end

function _resume_record_execution!(manifest,output,config,sources,machine,environment,limits)
    signature=_resume_signature(config,sources,machine,environment)
    revisions=get!(manifest,"source_revisions",Any[])
    if !any(r->r["run_signature"]==signature,revisions)
        directory=joinpath(output,"revisions",signature)
        # An interrupted snapshot has no published revision and may be rebuilt.
        isdir(directory) && rm(directory;recursive=true)
        mkpath(directory)
        archived=_resume_sources(config;output=directory,
            limit=get(limits,"source_snapshot_bytes",64<<20))
        _resume_signature(config,archived,machine,environment)==signature ||
            error("sources changed while recording a resume override")
        for (name,path) in _resume_environment_files()
            archive_file!(path,joinpath(directory,"environment",name))
        end
        _resume_environment()==environment || error("environment changed while recording a resume override")
        push!(revisions,Dict("run_signature"=>signature,"repositories"=>archived,
            "environment"=>environment,"accepted_utc"=>string(now(UTC)),
            "previous_signature"=>_resume_execution(manifest)["run_signature"]))
    end
    manifest["active_execution"]=only(filter(r->r["run_signature"]==signature,revisions))
    manifest["mixed_source_revisions"]=true
    _resume_write(joinpath(output,"campaign.toml"),manifest)
    @warn "Resuming with changed sources or dependencies; validated cases retain their original revision" output signature
end

const RESUME_CORE_FILES=Set(["case.toml","samples.csv","verdict.toml","completion.toml"])
const RESUME_ARTIFACT_EXTENSIONS=Set([".toml",".csv",".json",".txt",".folded"])

function _resume_artifacts(directory)
    artifacts=Dict{String,Any}[]
    for (root,folders,files) in walkdir(directory)
        any(name->islink(joinpath(root,name)),folders) &&
            error("diagnostic artifact directory contains a symlink")
        for name in files
            path=joinpath(root,name)
            relative=relpath(path,directory)
            relative in RESUME_CORE_FILES && continue
            islink(path) && error("diagnostic artifact is a symlink: "*relative)
            splitext(path)[2] in RESUME_ARTIFACT_EXTENSIONS ||
                error("unsupported diagnostic artifact: "*relative)
            (filemode(path)&0o111)==0 || error("executable diagnostic artifact: "*relative)
            bytes=read(path)
            any(iszero,bytes) && error("binary diagnostic artifact: "*relative)
            isvalid(String(copy(bytes))) || error("non-UTF8 diagnostic artifact: "*relative)
            push!(artifacts,Dict("path"=>relative,"sha256"=>bytes2hex(sha256(bytes)),
                "bytes"=>length(bytes)))
        end
    end
    sort!(artifacts;by=item->item["path"])
end

function _resume_machine()
    machine_id=isfile("/etc/machine-id") ? strip(read("/etc/machine-id",String)) :
        error("stable /etc/machine-id required to prevent cross-machine skips")
    isempty(machine_id) && error("empty machine ID")
    stable=Dict{String,Any}("machine_id_sha256"=>bytes2hex(sha256(machine_id)),
        "architecture"=>Sys.MACHINE,"cpu"=>Sys.CPU_NAME,
        "logical_cpus"=>Sys.CPU_THREADS,"julia"=>string(VERSION),
        "gpu_identity"=>probe(`nvidia-smi --query-gpu=uuid,name,compute_cap,driver_version --format=csv,noheader`))
    stable["sha256"]=bytes2hex(sha256(canonical_toml(stable)))
    stable
end

function _resume_config(config)
    clean=deepcopy(config)
    pop!(clean,"config_path",nothing)
    clean
end

function _resume_sources(config;output=nothing,limit=64<<20)
    Dict(label=>repository_identity(root;
            snapshot=isnothing(output) ? nothing : joinpath(output,"sources",label),
            max_bytes=limit)
        for (label,root) in sort!(collect(configured_repositories(config));by=first))
end

function _resume_environment_files()
    root=dirname(@__DIR__)
    active=Base.active_project()
    isnothing(active) && error("an active Julia project is required for a reproducible run")
    files=Dict("Project.toml"=>joinpath(root,"Project.toml"),
        "Manifest.toml"=>joinpath(root,"Manifest.toml"),
        "ActiveProject.toml"=>active,
        "ActiveManifest.toml"=>joinpath(dirname(active),"Manifest.toml"))
    all(isfile,values(files)) || error("instantiate the active Julia project before benchmarking")
    files
end

_resume_environment()=Dict(name=>_resume_sha(path)
    for (name,path) in _resume_environment_files())

function _resume_signature(config,sources,machine,environment)
    identity=Dict("configuration"=>_resume_config(config),
        "sources"=>Dict(k=>v["sha256"] for (k,v) in sources),
        "machine"=>machine["sha256"],"environment"=>environment)
    bytes2hex(sha256(canonical_toml(identity)))
end

function _resume_verify_case(directory,case,signature,samples_expected;
                             backend="perfchecker")
    complete=joinpath(directory,"completion.toml")
    isfile(complete) || error("case directory lacks completion marker: "*directory)
    marker=TOML.parsefile(complete)
    id=case_id(case)
    marker["status"]=="validated" && marker["case_id"]==id &&
        marker["run_signature"]==signature || error("completion identity differs: "*id)
    if haskey(marker,"execution_signature")
        manifest=TOML.parsefile(joinpath(dirname(dirname(directory)),"campaign.toml"))
        accepted=[manifest["run_signature"]; [r["run_signature"] for r in get(manifest,"source_revisions",Any[])]]
        marker["execution_signature"] in accepted || error("unknown case source revision: "*id)
    end
    required=backend=="oracle_preflight" ?
        (("case.toml","case_sha256"),("verdict.toml","verdict_sha256")) :
        (("case.toml","case_sha256"),("samples.csv","samples_sha256"),
         ("verdict.toml","verdict_sha256"))
    for (name,key) in required
        path=joinpath(directory,name)
        isfile(path) && _resume_sha(path)==marker[key] ||
            error("completed case artifact changed: "*joinpath(id,name))
    end
    TOML.parsefile(joinpath(directory,"case.toml"))==case ||
        error("completed case parameters changed: "*id)
    verdict=TOML.parsefile(joinpath(directory,"verdict.toml"))
    qualified=backend=="oracle_preflight" ?
        verdict["benchmark_backend"]=="oracle_preflight" &&
        verdict["execution_count"]==2 && verdict["samples_collected"]==0 &&
        marker["record_count"]==0 && marker["warm_samples"]==0 &&
        !ispath(joinpath(directory,"samples.csv")) :
        backend=="benchmarktools" ? verdict["benchmark_backend"]=="BenchmarkTools" :
        verdict["benchmark_backend"]=="PerfChecker" &&
            verdict["perfchecker_verdict"]=="validated"
    verdict["case_id"]==id && verdict["oracle_passed"]===true && qualified ||
        error("completed case qualification invalid: "*id)
    if backend!="oracle_preflight"
        lines=readlines(joinpath(directory,"samples.csv"))
        !isempty(lines) && length(lines)-1==marker["record_count"] ||
            error("completed case row count invalid: "*id)
        warm=count(line->split(line,',';limit=3)[2]=="warm",lines[2:end])
        warm==samples_expected && marker["warm_samples"]==samples_expected ||
            error("completed case sample count invalid: "*id)
        if get(case,"baseline_required",false)
            baseline=count(line->split(line,',';limit=3)[2]=="baseline_warm",lines[2:end])
            cache_valid=false
            if haskey(verdict,"baseline_cache_file")
                reference=verdict["baseline_cache_file"]
                prefix="../../../_baselines/"
                if startswith(reference,prefix) &&
                   occursin(r"^[0-9a-f]{64}\.toml$",reference[length(prefix)+1:end])
                    path=normpath(joinpath(directory,reference))
                    cache_valid=isfile(path) &&
                        _resume_sha(path)==verdict["baseline_cache_sha256"] &&
                        length(TOML.parsefile(path)["time_ns"])==samples_expected
                end
            end
            (baseline==samples_expected || baseline==0 && cache_valid &&
                get(verdict,"baseline_cache_hit",false)===true) &&
                verdict["baseline_required"]===true &&
                verdict["baseline_oracle_passed"]===true &&
                verdict["baseline_samples_verified"]==samples_expected &&
                verdict["baseline_name"]!="none" ||
                error("completed case baseline evidence invalid: "*id)
            haskey(verdict,"baseline_cache_file") && !cache_valid &&
                error("shared baseline artifact invalid: "*id)
        end
    end
    get(marker,"diagnostic_artifacts",Any[])==_resume_artifacts(directory) ||
        error("completed case diagnostic artifact changed: "*id)
    marker
end

function _resume_prepare(output,config,cases,limits;allow_source_changes::Bool=false)
    manifest_path=joinpath(output,"campaign.toml")
    first_run=!isfile(manifest_path)
    setup_marker=joinpath(output,".garamonbench-setup.toml")
    recovered_setup=false
    if first_run
        entries=setdiff(readdir(output),[".run.lock"])
        if !isempty(entries)
            setup_temp(name)=startswith(name,".garamonbench-setup.toml.tmp-")
            isfile(setup_marker) || all(setup_temp,entries) ||
                error("existing output lacks a campaign manifest")
            if isfile(setup_marker)
                get(TOML.parsefile(setup_marker),"status","")=="setting_up" ||
                    error("invalid incomplete setup marker")
            end
            allowed=Set([".garamonbench-setup.toml","sources","environment",
                "cases","staging","configuration.toml","machine_before.toml"])
            written=("configuration.toml","machine_before.toml","campaign.toml")
            all(name->name in allowed || setup_temp(name) ||
                any(target->startswith(name,target*".tmp-"),written),entries) ||
                error("unrecognized files in incomplete setup")
            for folder in ("cases","staging")
                path=joinpath(output,folder)
                isdir(path) && any(item->"completion.toml" in item[3],walkdir(path)) &&
                    error("incomplete setup contains completed case evidence")
            end
            for name in entries
                rm(joinpath(output,name);recursive=true)
            end
            recovered_setup=true
        end
        _resume_write(setup_marker,Dict("status"=>"setting_up",
            "created_utc"=>string(now(UTC))))
    end
    machine=_resume_machine()
    sources=_resume_sources(config;output=first_run ? output : nothing,
        limit=get(limits,"source_snapshot_bytes",64<<20))
    environment=_resume_environment()
    signature=_resume_signature(config,sources,machine,environment)
    if first_run
        mkpath(joinpath(output,"cases"))
        mkpath(joinpath(output,"staging"))
        for (name,path) in _resume_environment_files()
            archive_file!(path,joinpath(output,"environment",name))
        end
        _resume_write(joinpath(output,"configuration.toml"),_resume_config(config))
        _resume_write(joinpath(output,"machine_before.toml"),machine_snapshot())
        manifest=Dict{String,Any}("schema_version"=>1,
            "run_signature"=>signature,"machine"=>machine,
            "environment"=>environment,"repositories"=>sources,
            "case_ids"=>case_id.(cases),"case_count"=>length(cases),
            "condition"=>config["campaign"]["condition"],
            "interference_label"=>get(config["campaign"],"interference_label",""),
            "status"=>"prepared","created_utc"=>string(now(UTC)),
            "recovered_incomplete_setup"=>recovered_setup,
            "resume_policy"=>"validated cases are never remeasured; incomplete cases may be retried")
        _resume_write(manifest_path,manifest)
        rm(setup_marker)
    else
        manifest=TOML.parsefile(manifest_path)
        manifest["schema_version"]==1 &&
            TOML.parsefile(joinpath(output,"configuration.toml"))==_resume_config(config) &&
            manifest["machine"]["sha256"]==machine["sha256"] &&
            manifest["case_ids"]==case_id.(cases) &&
            manifest["condition"]==config["campaign"]["condition"] ||
            error("resume refused: configuration or machine changed")
        if _resume_execution(manifest)["run_signature"]!=signature
            allow_source_changes || error("resume refused: sources or environment changed; use allow_source_changes=true to retain validated cases explicitly")
            _resume_record_execution!(manifest,output,config,sources,machine,environment,limits)
        end
        isdir(joinpath(output,"cases")) && isdir(joinpath(output,"staging")) ||
            error("resume directories missing")
        isfile(setup_marker) && rm(setup_marker)
    end
    TOML.parsefile(manifest_path)
end

function _resume_progress(output,cases,signature,samples;backend="perfchecker")
    completed=String[]
    for case in cases
        id=case_id(case)
        final=joinpath(output,"cases",id)
        stage=joinpath(output,"staging",id)
        if ispath(final)
            _resume_verify_case(final,case,signature,samples;backend)
            push!(completed,id)
        elseif ispath(stage) && isfile(joinpath(stage,"completion.toml"))
            _resume_verify_case(stage,case,signature,samples;backend)
            mv(stage,final)
            push!(completed,id)
        end
    end
    completed
end

function resumable_status(config,output)
    cases=expand_cases(config)
    manifest=TOML.parsefile(joinpath(output,"campaign.toml"))
    completed=_resume_progress(output,cases,manifest["run_signature"],
        get(get(config,"limits",Dict()),"samples",11);
        backend=get(config["campaign"],"backend","perfchecker"))
    skipped=_resume_budget_ids(output,cases,manifest)
    pending=setdiff(case_id.(cases),union(completed,skipped))
    Dict("status"=>isempty(pending) ? (isempty(skipped) ? "complete" : "complete_with_budget_skips") : "incomplete",
        "case_count"=>length(cases),"completed_ids"=>completed,
        "budget_skipped_ids"=>skipped,"pending_ids"=>pending)
end
resumable_status(path::AbstractString,output)=resumable_status(load_config(path),output)

"""Audit an archive after copying it to another path or machine. This reads only
archived evidence; current-machine/source matches are reported separately.
"""
function audit_resumable_archive(config,output)
    output=abspath(output)
    manifest=TOML.parsefile(joinpath(output,"campaign.toml"))
    archived_config=TOML.parsefile(joinpath(output,"configuration.toml"))
    archived_config==_resume_config(config) || error("transfer configuration differs")
    cases=expand_cases(config)
    manifest["case_ids"]==case_id.(cases) || error("transfer case identities differ")
    machine=manifest["machine"]
    stable=Dict(k=>v for (k,v) in machine if k!="sha256")
    bytes2hex(sha256(canonical_toml(stable)))==machine["sha256"] ||
        error("archived machine fingerprint changed")
    for revision in [manifest; get(manifest,"source_revisions",Any[])]
        snapshot=revision===manifest ? output : joinpath(output,"revisions",revision["run_signature"])
        environment=revision["environment"]
        for (name,digest) in environment
            path=joinpath(snapshot,"environment",name)
            isfile(path) && _resume_sha(path)==digest ||
                error("archived environment changed: "*name)
        end
        sources=revision["repositories"]
        for (label,identity) in sources
            root=joinpath(snapshot,"sources",label)
            isdir(root) || error("source snapshot missing: "*label)
            entries=identity["files"]
            expected=sort!(String[entry["path"] for entry in entries])
            actual=String[]
            for (directory,subdirs,files) in walkdir(root)
                any(name->islink(joinpath(directory,name)),subdirs) &&
                    error("source snapshot symlink directory: "*label)
                for name in files
                    path=joinpath(directory,name)
                    islink(path) && error("source snapshot symlink file: "*label)
                    push!(actual,relpath(path,root))
                end
            end
            sort!(actual)==expected || error("source snapshot inventory changed: "*label)
            for entry in entries
                path=joinpath(root,entry["path"])
                filesize(path)==entry["bytes"] && _resume_sha(path)==entry["sha256"] ||
                    error("source snapshot content changed: "*label*"/"*entry["path"])
            end
            bytes2hex(sha256(canonical_toml(Dict("files"=>entries))))==identity["sha256"] ||
                error("source inventory fingerprint changed: "*label)
        end
        signature=_resume_signature(config,sources,machine,environment)
        signature==revision["run_signature"] || error("archived run signature changed")
    end
    signature=manifest["run_signature"]
    execution=_resume_execution(manifest)
    sources=execution["repositories"]
    environment=execution["environment"]
    samples=get(get(config,"limits",Dict()),"samples",11)
    completed=String[]
    for case in cases
        id=case_id(case)
        final=joinpath(output,"cases",id)
        stage=joinpath(output,"staging",id)
        if ispath(final)
            _resume_verify_case(final,case,signature,samples;
                backend=get(config["campaign"],"backend","perfchecker"))
            push!(completed,id)
        elseif isfile(joinpath(stage,"completion.toml"))
            _resume_verify_case(stage,case,signature,samples;
                backend=get(config["campaign"],"backend","perfchecker"))
            push!(completed,id)
        end
    end
    current_machine_match=_resume_machine()["sha256"]==machine["sha256"]
    current_environment_match=_resume_environment()==environment
    current_sources=Dict{String,Bool}()
    roots=configured_repositories(config)
    Set(keys(roots))==Set(keys(sources)) || error("archived repository labels differ")
    for (label,root) in roots
        current_sources[label]=try
            repository_identity(root)["sha256"]==sources[label]["sha256"]
        catch
            false
        end
    end
    skipped=_resume_budget_ids(output,cases,manifest)
    Dict("archive_integrity"=>"validated","case_count"=>length(cases),
        "completed_ids"=>completed,
        "budget_skipped_ids"=>skipped,
        "pending_ids"=>setdiff(case_id.(cases),union(completed,skipped)),
        "current_machine_matches"=>current_machine_match,
        "current_environment_matches"=>current_environment_match,
        "current_sources_match"=>current_sources,
        "mixed_source_revisions"=>get(manifest,"mixed_source_revisions",false),
        "source_revision_signatures"=>[signature; [r["run_signature"] for r in get(manifest,"source_revisions",Any[])]],
        "same_machine_resume_allowed"=>current_machine_match &&
            current_environment_match && all(values(current_sources)),
        "cross_machine_measurements_reused"=>false)
end
audit_resumable_archive(path::AbstractString,output)=
    audit_resumable_archive(load_config(path),output)

struct MemoryBudgetRestart <: Exception
    caseid::String
end
Base.showerror(io::IO,e::MemoryBudgetRestart)=print(io,
    "case ",e.caseid," skipped at the RSS budget; restart worker to continue")

# Budget exclusions are separate from validated measurements. Never turn an
# incomplete sample set into a completion marker or a numerical article result.
function _resume_budget_ids(output,cases,manifest)
    skipped=String[]
    accepted=[manifest["run_signature"]; [r["run_signature"] for r in get(manifest,"source_revisions",Any[])]]
    for case in cases
        id=case_id(case)
        path=joinpath(output,"budget-skips",id*".toml")
        isfile(path) || continue
        record=TOML.parsefile(path)
        record["status"]=="memory_budget_exceeded" && record["case_id"]==id &&
            record["case"]==case && record["run_signature"]==manifest["run_signature"] &&
            record["execution_signature"] in accepted &&
            record["observed_rss_bytes"]>record["limit_rss_bytes"] ||
            error("invalid memory budget exclusion: "*id)
        ispath(joinpath(output,"cases",id)) && error("case is both validated and budget-excluded: "*id)
        push!(skipped,id)
    end
    skipped
end

mutable struct _CampaignMeter
    label::String
    enabled::Bool
    output::IO
    meter::Union{Nothing,ProgressMeter.Progress}
    last_count::Int
end

_campaign_meter(label;enabled::Bool=true,output::IO=stderr)=
    _CampaignMeter(String(label),enabled,output,nothing,0)

function _campaign_meter_update!(display::_CampaignMeter,archive,completed,total)
    display.enabled || return nothing
    count=length(completed)
    if isnothing(display.meter)
        display.meter=ProgressMeter.Progress(total;start=count,
            desc=display.label,dt=0.5,output=display.output,enabled=true)
        count>0 && println(display.output,display.label,": resumed ",count,
                           "/",total," validated cases")
    end
    count>=display.last_count || error("validated progress cannot decrease")
    display.last_count=count
    ProgressMeter.update!(display.meter,count;force=true,
        showvalues=[("Validated",string(count," / ",total))])
    nothing
end

function _campaign_meter_close!(display::_CampaignMeter;complete::Bool,failure=nothing)
    isnothing(display.meter) && return nothing
    complete ? ProgressMeter.finish!(display.meter) :
        ProgressMeter.cancel(display.meter,
            display.label*(isnothing(failure) || failure isa InterruptException ?
                ": interrupted; validated cases remain resumable" :
                ": failed: "*failure_message(failure)*"; validated cases retained"))
    nothing
end

function run_resumable_campaign(config;output,on_progress=nothing,baseline_cache_root=nothing,
                                allow_source_changes::Bool=false,skip_memory_budget::Bool=false)
    cases=expand_cases(config)
    backend=get(config["campaign"],"backend","")
    backend in ("perfchecker","benchmarktools","oracle_preflight") ||
        error("resumable campaign requires PerfChecker, BenchmarkTools or oracle preflight")
    all(c->haskey(ADAPTERS,c["adapter"]),cases) ||
        error("load every requested adapter before launch")
    output=abspath(output)
    if !isnothing(baseline_cache_root)
        backend=="benchmarktools" || error("shared baselines require BenchmarkTools")
        abspath(baseline_cache_root)==joinpath(dirname(output),"_baselines") ||
            error("shared baselines must be beside the route archive")
    end
    mkpath(output)
    _resume_lock(output) do
        limits=get(config,"limits",Dict())
        manifest=_resume_prepare(output,config,cases,limits;allow_source_changes)
        execution=_resume_execution(manifest)
        signature=manifest["run_signature"]
        baseline_cache=isnothing(baseline_cache_root) ? nothing :
            (root=abspath(baseline_cache_root),context=Dict{String,Any}(
                "sources"=>Dict(k=>v["sha256"] for (k,v) in execution["repositories"]),
                "machine"=>manifest["machine"]["sha256"],
                "environment"=>execution["environment"],
                "condition"=>manifest["condition"],
                "threads"=>Threads.nthreads()))
        samples=get(limits,"samples",11)
        completed=_resume_progress(output,cases,signature,samples;backend)
        skipped=_resume_budget_ids(output,cases,manifest)
        pending()=setdiff(case_id.(cases),union(completed,skipped))
        _resume_write(joinpath(output,"progress.toml"),
            Dict("status"=>"running","completed_ids"=>completed,
                "budget_skipped_ids"=>skipped,"pending_ids"=>pending()))
        isnothing(on_progress) || on_progress(output,completed,length(cases))
        try
            for case in cases
                id=case_id(case)
                (id in completed || id in skipped) && continue
                # Release previous case objects outside every measured kernel.
                GC.gc(true)
                stage=joinpath(output,"staging",id)
                if ispath(stage)
                    isdir(stage) || error("unexpected staging file: "*stage)
                    # No completion marker: this work did not pass qualification.
                    rm(stage;recursive=true)
                end
                mkpath(stage)
                _resume_write(joinpath(stage,"case.toml"),case)
                rows,verdict=try
                    if backend=="oracle_preflight"
                        NamedTuple[],run_case_preflight(ADAPTERS[case["adapter"]],case,limits)
                    elseif backend=="benchmarktools"
                        run_case(ADAPTERS[case["adapter"]],case,limits;
                            artifact_dir=stage,baseline_cache)
                    else
                        run_case_perfchecker(ADAPTERS[case["adapter"]],case,limits;
                            artifact_dir=stage)
                    end
                catch exception
                    if skip_memory_budget && exception isa ControllerMemoryBudget
                        mkpath(joinpath(output,"budget-skips"))
                        _resume_write(joinpath(output,"budget-skips",id*".toml"),Dict(
                            "status"=>"memory_budget_exceeded","case_id"=>id,"case"=>case,
                            "run_signature"=>signature,"execution_signature"=>execution["run_signature"],
                            "observed_rss_bytes"=>exception.observed,"limit_rss_bytes"=>exception.limit,
                            "reason"=>failure_message(exception),"recorded_utc"=>string(now(UTC))))
                        push!(skipped,id)
                        println(stderr,"Case ",id,": skipped (memory budget); validated cases retained")
                        throw(MemoryBudgetRestart(id))
                    end
                    rethrow()
                end
                backend=="oracle_preflight" || write_csv(joinpath(stage,"samples.csv"),rows)
                _resume_write(joinpath(stage,"verdict.toml"),verdict)
                current=_resume_sources(config;
                    limit=get(limits,"source_snapshot_bytes",64<<20))
                all(k->current[k]["sha256"]==execution["repositories"][k]["sha256"],
                    keys(current)) || error("sources changed during case "*id)
                marker=Dict{String,Any}("status"=>"validated","case_id"=>id,
                    "run_signature"=>signature,
                    "execution_signature"=>execution["run_signature"],
                    "case_sha256"=>_resume_sha(joinpath(stage,"case.toml")),
                    "verdict_sha256"=>_resume_sha(joinpath(stage,"verdict.toml")),
                    "record_count"=>length(rows),
                    "warm_samples"=>count(row->row.phase=="warm",rows),
                    "diagnostic_artifacts"=>_resume_artifacts(stage))
                backend=="oracle_preflight" ||
                    (marker["samples_sha256"]=_resume_sha(joinpath(stage,"samples.csv")))
                _resume_write(joinpath(stage,"completion.toml"),marker)
                _resume_verify_case(stage,case,signature,samples;backend)
                tree_bytes(output)<=get(limits,"archive_bytes",256<<20) ||
                    error("resumable archive budget")
                mv(stage,joinpath(output,"cases",id))
                push!(completed,id)
                _resume_write(joinpath(output,"progress.toml"),
                    Dict("status"=>"running","completed_ids"=>completed,
                        "budget_skipped_ids"=>skipped,"pending_ids"=>pending()))
                isnothing(on_progress) || on_progress(output,completed,length(cases))
            end
            manifest["status"]=isempty(skipped) ? "complete" : "complete_with_budget_skips"
            manifest["budget_skipped_ids"]=skipped
            manifest["completed_utc"]=string(now(UTC))
            _resume_write(joinpath(output,"campaign.toml"),manifest)
        catch exception
            _resume_write(joinpath(output,"progress.toml"),
                Dict("status"=>exception isa MemoryBudgetRestart ? "restart_required" : exception isa InterruptException ? "interrupted" : "failed","completed_ids"=>completed,
                    "budget_skipped_ids"=>skipped,"pending_ids"=>pending(),
                    "failure"=>failure_message(exception)))
            rethrow()
        finally
            _resume_write(joinpath(output,"machine_after.toml"),machine_snapshot())
        end
        _resume_write(joinpath(output,"progress.toml"),
            Dict("status"=>manifest["status"],"completed_ids"=>completed,"budget_skipped_ids"=>skipped,
                "pending_ids"=>String[]))
    end
    output
end
run_resumable_campaign(path::AbstractString;kwargs...)=
    run_resumable_campaign(load_config(path);kwargs...)
