const RECIPE_SCRIPTS = Dict(
    "continuous-dimensions"=>"explore_dimensions.jl", "workspace-small"=>"workspace_small.jl",
    "triplejoin"=>"triplejoin_compare.jl", "pruning-recurrences"=>"pruning_recurrences.jl",
    "precompile-lifecycle"=>"precompile_lifecycle.jl", "parallel-batches"=>"parallel_batches.jl",
    "long-horizon"=>"long_horizon.jl", "selector-compare"=>"selector_compare.jl",
    "binary-rank"=>"binary_rank_compare.jl", "n05-pfaffian"=>"n05_compare.jl",
    "k1-binary-rank"=>"binary_rank_compact_compare.jl")
const RECIPE_PARAMETERS = Dict(
    "continuous-dimensions"=>["max_dimension","dimensions","isolated_workers"],
    "parallel-batches"=>["thread_counts","worker_counts"],
    "cpp-matched"=>["reverse"], "selector-compare"=>["reverse"],
    "n05-pfaffian"=>["reverse","shard_index","shard_count","range_first","range_last"],
    "binary-rank"=>["mode"], "k1-binary-rank"=>["mode","dimensions"], "julia-products"=>["native_config"])

"""Validate a bounded recipe without running its measurements or installing dependencies."""
function recipe_plan(config::AbstractDict)
    get(config,"schema_version",0)==1 || error("unsupported recipe schema")
    all(k in ("schema_version","recipe","limits","parameters") for k in keys(config)) || error("unknown top-level recipe field")
    recipe=copy(get(config,"recipe",Dict{String,Any}()))
    all(k in ("id","profile","condition","interference_label","threads") for k in keys(recipe)) || error("unknown recipe field")
    catalogue=TOML.parsefile(joinpath(dirname(@__DIR__),"config","campaigns.toml"))["campaign"]
    id=get(recipe,"id",""); id in getindex.(catalogue,"id") || error("unknown recipe id")
    profile=get(recipe,"profile","smoke"); profile in ("smoke","full") || error("profile must be smoke or full")
    condition=get(recipe,"condition",""); condition in ("exploratory_interference","isolated") || error("declare the measurement condition")
    condition=="exploratory_interference" && isempty(get(recipe,"interference_label","")) && error("interference_label required")
    # Switching a copied exploratory configuration to isolated must also clear
    # its effective label, including any inherited subprocess environment value.
    recipe["interference_label"]=condition=="isolated" ? "" : recipe["interference_label"]
    threads=get(recipe,"threads",1)
    threads isa Integer && 1<=threads<=16 || error("threads must be 1..16")
    condition=="exploratory_interference" && threads>4 && error("exploratory execution capped at four threads/workers")
    # These drivers intentionally use one controller thread; parallel-batches owns its lane grid.
    id!="julia-products" && threads!=1 && error("this recipe requires threads=1; use parallel-batches lane parameters")
    parameters=Dict{String,Any}(get(config,"parameters",Dict()))
    all(k in get(RECIPE_PARAMETERS,id,String[]) for k in keys(parameters)) || error("unsupported recipe parameter")
    if id=="continuous-dimensions"
        maximum=get(parameters,"max_dimension",profile=="smoke" ? 2 : 256)
        maximum isa Integer && 2<=maximum<=256 || error("max_dimension must be 2..256")
        dimensions=get(parameters,"dimensions",collect(2:maximum))
        dimensions isa Vector && !isempty(dimensions) && all(n->n isa Integer && 2<=n<=maximum,dimensions) || error("invalid dimension selection")
        get(parameters,"isolated_workers",false) isa Bool || error("isolated_workers must be boolean")
        parameters["max_dimension"]=maximum; parameters["dimensions"]=sort!(unique(dimensions))
        parameters["isolated_workers"]=get(parameters,"isolated_workers",false)
    elseif id=="parallel-batches"
        tc=get(parameters,"thread_counts",profile=="smoke" ? [1,2] : condition=="isolated" ? [1,2,4,8,16] : [1,2,4])
        wc=get(parameters,"worker_counts",profile=="smoke" ? [1,2] : condition=="isolated" ? [1,2,4,8] : [1,2,4])
        tc isa Vector && wc isa Vector && !isempty(vcat(tc,wc)) || error("nonempty parallel lane grid required")
        all(n->n isa Integer && n in (1,2,4,8,16),tc) && all(n->n isa Integer && n in (1,2,4,8),wc) || error("unsupported lane count")
        condition=="exploratory_interference" && any(>(4),vcat(tc,wc)) && error("exploratory execution capped at four threads/workers")
        length(unique(tc))==length(tc) && length(unique(wc))==length(wc) || error("duplicate lane count")
        parameters["thread_counts"]=tc; parameters["worker_counts"]=wc
    elseif id in ("cpp-matched","selector-compare","n05-pfaffian")
        get(parameters,"reverse",false) isa Bool || error("reverse must be boolean")
        parameters["reverse"]=get(parameters,"reverse",false)
        if id=="n05-pfaffian"
            shard=any(haskey(parameters,k) for k in ("shard_index","shard_count"))
            interval=any(haskey(parameters,k) for k in ("range_first","range_last"))
            shard && interval && error("N05 shard and range are mutually exclusive")
            profile=="smoke" && (shard || interval) && error("N05 smoke cannot select manifest cases")
            if shard
                all(haskey(parameters,k) && parameters[k] isa Integer && !(parameters[k] isa Bool) for k in ("shard_index","shard_count")) || error("N05 requires integer shard_index and shard_count")
                i,c=parameters["shard_index"],parameters["shard_count"]
                1<=i<=c<=36480 || error("N05 shard bounds: 1 <= index <= count <= 36480")
                length(i:c:36480)<=32 || error("N05 shard exceeds 32 cases; increase shard_count")
            elseif interval
                all(haskey(parameters,k) && parameters[k] isa Integer && !(parameters[k] isa Bool) for k in ("range_first","range_last")) || error("N05 requires integer range_first and range_last")
                a,b=parameters["range_first"],parameters["range_last"]
                1<=a<=b<=36480 || error("N05 range outside 1..36480")
                b-a+1<=32 || error("N05 range exceeds 32 cases")
            end
        end
    elseif id=="k1-binary-rank"
        threads isa Bool && error("K1 threads must be integer 1, not a boolean")
        recipe_k1_parameters!(parameters,profile,recipe)
    elseif id=="binary-rank"
        mode=get(parameters,"mode",profile)
        mode in ("smoke","screen","episode_screen","full") || error("binary-rank mode must execute measurements: smoke, screen, episode_screen or full")
        profile=="smoke" && mode!="smoke" && error("smoke profile cannot request a larger binary-rank mode")
        parameters["mode"]=mode
    end
    limits=merge(Dict{String,Any}("wall_seconds"=>1200,"rss_bytes"=>4<<30,
        "scratch_bytes"=>512<<20,"archive_bytes"=>256<<20,"source_bytes"=>64<<20),get(config,"limits",Dict()))
    all(k in ("wall_seconds","rss_bytes","scratch_bytes","archive_bytes","source_bytes") for k in keys(limits)) || error("unknown budget")
    all(v->v isa Real && isfinite(v) && v>0,values(limits)) || error("budgets must be finite and positive")
    merge!(recipe,Dict("id"=>id,"profile"=>profile,"condition"=>condition,"threads"=>threads))
    Dict{String,Any}("schema_version"=>1,"recipe"=>recipe,"limits"=>limits,"parameters"=>parameters)
end
recipe_plan(path::AbstractString)=recipe_plan(TOML.parsefile(path))

function recipe_condition_environment(plan)
    recipe=plan["recipe"]
    Dict("GARAMONBENCH_CONDITION"=>recipe["condition"],
        "GARAMONBENCH_INTERFERENCE_LABEL"=>recipe["condition"]=="isolated" ? "" : recipe["interference_label"])
end
recipe_condition_command(command,plan)=addenv(command,recipe_condition_environment(plan))

function recipe_n05_case_ids(plan)
    p=plan["parameters"]
    ids=haskey(p,"shard_index") ? collect(p["shard_index"]:p["shard_count"]:36480) :
        haskey(p,"range_first") ? collect(p["range_first"]:p["range_last"]) : Int[]
    get(p,"reverse",false) ? reverse(ids) : ids
end
function recipe_verify_n05_selection(results,expected)
    files=[joinpath(d,f) for (d,_,fs) in walkdir(results) for f in fs if f=="n05-shard-environment.toml"]
    length(files)==1 || error("expected one native N05 selection manifest")
    native=TOML.parsefile(only(files))
    native["grid_cases"]==36480 && native["grid_schema"]=="N05-grid-v1" || error("native N05 grid changed")
    native["selected_case_ids"]==expected || error("native N05 selected identities differ from requested subset")
    native["completed_case_ids"]==expected && native["completed"] || error("native N05 subset incomplete")
    isempty(native["failed_case_ids"]) && native["status"]=="qualified" || error("native N05 subset contains failed cases")
    for id in expected
        path=joinpath(dirname(only(files)),"n05-case-$id-qualification.json")
        isfile(path) || error("missing native N05 per-case qualification")
        evidence=JSON.parse(read(path,String))
        evidence["passed"] && only(evidence["runs"])["feature"]=="n05_case_$id" || error("native N05 qualification identity/status mismatch")
    end
    Dict("requested_case_ids"=>expected,"selected_case_ids"=>native["selected_case_ids"],
        "completed_case_ids"=>native["completed_case_ids"],"grid_sha256"=>native["grid_sha256"],
        "native_status"=>native["status"],"coverage_scope"=>"this requested subset only; no full-grid qualification")
end

function replace_required(source,old,new;count=1)
    length(findall(old,source))==count || error("driver interface changed: expected $count occurrence(s) of adapter anchor")
    replace(source,old=>new)
end

# Explicit, checked source adaptation, archived alongside the unmodified source.
# Timed kernels, FeatureSpec contracts, oracles and sample budgets are untouched.
function recipe_adapt(source,id,smoke)
    changes=String[]
    if id ∉ ("precompile-lifecycle","k1-audit")
        count=id=="continuous-dimensions" ? 2 : 1
        source=replace_required(source,"run_suite(","GaramonRecipeCapture.run_suite(";count)
        push!(changes,"capture native suite JSON and every native sample after run_suite returns")
    end
    if id in ("k1-binary-rank","k1-audit")
        source=replace_required(source,"if abspath(PROGRAM_FILE)==@__FILE__","if true # packaged recipe entrypoint")
        if id=="k1-binary-rank"
            source=replace_required(source,"include(\"binary_rank_compact_cases.jl\")","include(joinpath(@__DIR__,\"binary_rank_compact_cases.jl\"))")
        end
        push!(changes,"invoke guarded native K1v2 CLI; original file identity retained for native fingerprint; resolve cases at original path")
    elseif id=="triplejoin"
        source=replace_required(source,"if abspath(PROGRAM_FILE) == abspath(@__FILE__)","if true # packaged recipe entrypoint";count=2)
        push!(changes,"invoke original guarded CLI body")
    elseif id=="precompile-lifecycle"
        source=replace_required(source,"if abspath(PROGRAM_FILE) == @__FILE__","if true # packaged recipe entrypoint")
        push!(changes,"invoke original guarded CLI body; native lifecycle observations, not PerfChecker")
    elseif id=="selector-compare"
        source=replace_required(source,"if abspath(PROGRAM_FILE)==@__FILE__","if true # packaged recipe entrypoint")
        push!(changes,"invoke original guarded CLI body; analytical unfitted selector, no learned-model validation inferred")
    elseif id=="n05-pfaffian"
        source=replace_required(source,"if abspath(PROGRAM_FILE)==@__FILE__","if true # packaged recipe entrypoint";count=2)
        source=replace_required(source,"include(\"n05_pfaffian.jl\")","include(joinpath(@__DIR__,\"n05_pfaffian.jl\"))")
        source=replace_required(source,"include(\"n05_shards.jl\")","GaramonRecipeCapture.include_n05_shards(joinpath(@__DIR__,\"n05_shards.jl\"))")
        push!(changes,"invoke guarded controller import and CLI body; resolve fixture include and checked native shard adaptation from original driver directory")
        push!(changes,"preserve distinct coordinates_construction_included and preexisting_contractions comparison keys; full is the bounded native slice, not the replay matrix")
    elseif smoke && id=="workspace-small"
        anchor="    common = joinpath(@__DIR__,\"workspace_small_common.jl\")"
        source=replace_required(source,anchor,"    filter!(c -> c.n == 2 && c.family == :cap12 && c.horizon in (0,1), cases)\n"*anchor)
        push!(changes,"smoke selects n=2, cap12, horizons 0/1 after original admission; original skip rows retained")
    elseif smoke && id=="pruning-recurrences"
        anchor="    entrypoint=joinpath(temporary,\"pruning.jl\")"
        source=replace_required(source,anchor,"    filter!(c -> c.n == 2 && c.signature == :positive && c.regime == :contracting && c.recurrence == :affine && c.horizon == 8, cases)\n"*anchor)
        push!(changes,"smoke selects n=2, positive, contracting, affine H=8, all five methods; original skip rows retained")
    end
    source,changes
end

function recipe_external_jobs(plan,root,destination)
    id=plan["recipe"]["id"]; smoke=plan["recipe"]["profile"]=="smoke"; p=plan["parameters"]
    id=="k1-binary-rank" && return recipe_k1_jobs(plan,root,destination)
    output=joinpath(destination,"native"); mkpath(output)
    script=joinpath(root,"perf",RECIPE_SCRIPTS[id])
    project=joinpath(root,"perf","controller")
    isfile(script) || error("target recipe script unavailable; exact private target checkout required")
    if id=="parallel-batches"
        return [(;script,project,threads=mode=="threads" ? n : 1,
                 name="$(mode)_$n",args=vcat([mode,string(n),joinpath(output,"$(mode)_$n.csv")],smoke ? ["--smoke"] : String[]))
                for (mode,counts) in (("threads",p["thread_counts"]),("processes",p["worker_counts"])) for n in counts]
    end
    args = if id=="continuous-dimensions"
        vcat([joinpath(output,"dimensions.csv"),string(p["max_dimension"]),"--dimensions="*join(p["dimensions"],',')],p["isolated_workers"] ? ["--isolated"] : String[])
    elseif id in ("workspace-small","pruning-recurrences")
        [joinpath(output,id*".csv")]
    elseif id in ("selector-compare","n05-pfaffian")
        selection=id=="n05-pfaffian" && haskey(p,"shard_index") ? ["--shard=$(p["shard_index"])/$(p["shard_count"])"] :
            id=="n05-pfaffian" && haskey(p,"range_first") ? ["--range=$(p["range_first"]):$(p["range_last"])"] : String[]
        vcat(smoke ? ["--smoke"] : String[],selection,p["reverse"] ? ["--reverse"] : String[],[output])
    elseif id=="binary-rank"
        ["--"*p["mode"],output]
    elseif id=="triplejoin"
        vcat([output],smoke ? ["--smoke"] : String[])
    else
        vcat(smoke ? ["--smoke"] : String[],[output])
    end
    [(;script,project,threads=1,name=id,args)]
end

# Linux process-tree observation: only descendants of the command started here.
# PID start ticks prevent accidentally signalling a recycled PID.
function recipe_processes()
    table=Dict{Int,NamedTuple}()
    for name in readdir("/proc")
        pid=tryparse(Int,name); isnothing(pid) && continue
        try
            stat=read("/proc/$pid/stat",String); fields=split(stat[findlast(')',stat)+2:end])
            status=read("/proc/$pid/status",String); rss=match(r"(?m)^VmRSS:\s+(\d+)\s+kB",status)
            table[pid]=(;parent=parse(Int,fields[2]),start=fields[20],rss=isnothing(rss) ? 0 : 1024parse(Int,rss[1]))
        catch
            # A process can exit between directory and status reads.
        end
    end
    table
end
function recipe_descendants!(known,root,table)
    haskey(table,root) && !haskey(known,root) && (known[root]=table[root].start)
    changed=true
    while changed
        changed=false
        for (pid,record) in table
            if !haskey(known,pid) && haskey(known,record.parent) && haskey(table,record.parent) && table[record.parent].start==known[record.parent]
                known[pid]=record.start; changed=true
            end
        end
    end
    [pid for (pid,start) in known if haskey(table,pid) && table[pid].start==start]
end
function recipe_stop!(process,known,root)
    table=recipe_processes(); live=recipe_descendants!(known,root,table)
    # The controller starts a dedicated group. Detached descendants are also tracked.
    root>0 && root in live && ccall(:kill,Cint,(Cint,Cint),-root,15)
    for pid in live; ccall(:kill,Cint,(Cint,Cint),pid,15); end
    sleep(0.3)
    table=recipe_processes()
    for (pid,start) in known
        haskey(table,pid) && table[pid].start==start && ccall(:kill,Cint,(Cint,Cint),pid,9)
    end
    process_running(process) && kill(process,Base.SIGKILL)
    wait(process)
end
function recipe_supervise(command,log,scratch,limits,deadline)
    Sys.islinux() || error("recipe process-tree budget supervisor currently requires Linux")
    peakrss=0; peakdisk=0; known=Dict{Int,String}(); reason=""; started=time()
    open(log,"w") do io
        process=run(pipeline(ignorestatus(Cmd(command;detach=true));stdout=io,stderr=io);wait=false)
        root=getpid(process)
        try
            while process_running(process)
                table=recipe_processes(); live=recipe_descendants!(known,root,table)
                peakrss=max(peakrss,sum(table[pid].rss for pid in live;init=0))
                peakdisk=max(peakdisk,tree_bytes(scratch))
                reason=time()>deadline ? "wall_seconds" : peakrss>limits["rss_bytes"] ? "aggregate_rss_bytes" : peakdisk>limits["scratch_bytes"] ? "scratch_bytes" : ""
                isempty(reason) || break
                sleep(0.2)
            end
        finally
            if process_running(process)
                recipe_stop!(process,known,root)
            else
                live=recipe_descendants!(known,root,recipe_processes())
                filter!(!=(root),live)
                if !isempty(live)
                    reason="descendants_survived_controller"
                    recipe_stop!(process,known,root)
                end
            end
        end
        wait(process)
        return Dict{String,Any}("exit_code"=>process.exitcode,"term_signal"=>process.termsignal,
            "process_success"=>success(process),"wall_seconds"=>time()-started,
            "observed_process_tree_peak_rss_bytes"=>peakrss,"observed_scratch_peak_bytes"=>peakdisk,
            "budget_exceeded"=>reason,"poll_interval_seconds"=>0.2,
            "budget_semantics"=>"sampled aggregate descendant RSS and scratch; wall checked every poll; not an OS hard memory cap")
    end
end

# Suppress inherited environment serialization in diagnostics. Native measurements
# are copied verbatim unless they contain a process-environment error dump.
function recipe_archive_tree(source,destination,budget)
    artifacts=Dict{String,Any}[]; total=0
    for (directory,_,files) in walkdir(source), file in sort(files)
        path=joinpath(directory,file); relative=relpath(path,source)
        islink(path) && error("symlink artifact refused")
        total+=filesize(path); total<=budget || error("native archive byte budget exceeded")
        extension=splitext(path)[2]
        source_snapshot=occursin("/sources/","/"*relative)
        extension in (".csv",".toml",".json",".md",".txt",".partial",".log") ||
            (source_snapshot && (extension in SOURCE_EXTENSIONS || basename(path) in ("CMakeLists.txt","LICENSE") || startswith(basename(path),"HOWTO-"))) || error("non-text recipe artifact refused: $relative")
        bytes=read(path); any(iszero,bytes) && error("binary recipe artifact refused")
        text=String(copy(bytes))
        !source_snapshot && occursin("setenv(",text) && error("artifact contains a process environment dump; refused")
        target=joinpath(destination,relative); mkpath(dirname(target)); cp(path,target)
        push!(artifacts,Dict("path"=>relative,"sha256"=>bytes2hex(sha256(bytes)),"bytes"=>length(bytes)))
    end
    artifacts
end

"""Execute a fresh catalogued campaign; never import or requalify old results."""
function run_recipe(config;output_root)
    plan=recipe_plan(config); recipe=plan["recipe"]; id=recipe["id"]; limits=plan["limits"]
    Sys.islinux() || error("run-recipe currently requires Linux /proc")
    bench=dirname(@__DIR__); root=abspath(expanduser(get(ENV,"GARAMON_JULIA_ROOT","~/.julia/dev/Garamon")))
    isdir(root) || error("exact target Julia source is required")
    # Reject output inside a fingerprinted source tree, which would invalidate itself.
    output_root=abspath(output_root)
    any(p->output_root==p || startswith(output_root,p*"/"),(root,bench)) && error("place recipe results outside source repositories")
    runid=Dates.format(now(UTC),dateformat"yyyymmddTHHMMSS")*"_recipe_"*id*"_"*first(string(uuid4()),8)
    output=joinpath(output_root,runid); mkpath(output)
    metadata=Dict{String,Any}("schema_version"=>1,"run_id"=>runid,"status"=>"running",
        "recipe_id"=>id,"condition"=>recipe["condition"],"interference_label"=>get(recipe,"interference_label",""),
        "isolation_status"=>"operator declaration; machine snapshots do not certify isolation",
        "fresh_execution"=>true,"seed_policy"=>"native driver seeds/formulas preserved; see frozen source and parameters",
        "forwarded_condition_environment"=>recipe_condition_environment(plan),
        "jobs"=>Dict{String,Any}[],"started_utc"=>string(now(UTC)))
    n05_ids=id=="n05-pfaffian" ? recipe_n05_case_ids(plan) : Int[]
    !isempty(n05_ids) && (metadata["requested_case_ids"]=n05_ids)
    write_toml(joinpath(output,"configuration.toml"),plan)
    write_toml(joinpath(output,"requested-configuration.toml"),config)
    write_toml(joinpath(output,"machine_before.toml"),machine_snapshot())
    roots=Dict("benchmark"=>bench,"julia"=>root)
    id=="cpp-matched" && (roots["cpp"]=cpp_source_root())
    identities=Dict{String,Any}()
    temporary_path=""
    try
        for (name,path) in roots
            identities[name]=repository_identity(path;snapshot=joinpath(output,"sources",name),max_bytes=limits["source_bytes"])
        end
        metadata["repositories"]=identities
        tree_bytes(output)<=limits["archive_bytes"] || error("source snapshots exceed archive budget")
        with_build_directory() do temporary
            temporary_path=temporary
            temp=joinpath(temporary,"tmp"); mkpath(temp)
            results=joinpath(temporary,"results"); mkpath(results)
            deadline=time()+limits["wall_seconds"]
            try
            if haskey(RECIPE_SCRIPTS,id)
                jobs=recipe_external_jobs(plan,root,results)
                for job in jobs
                    source=read(job.script,String)
                    adaptation_id=get(job,:adaptation_id,id)
                    adapted,changes=recipe_adapt(source,adaptation_id,recipe["profile"]=="smoke")
                    actual=joinpath(temporary,job.name*"-adapted.jl"); write(actual,adapted)
                    # Retain both executed adaptation and original source; includes resolve
                    # at the original path. This is not an unmodified-driver claim.
                    mkpath(joinpath(output,"adaptations"))
                    cp(actual,joinpath(output,"adaptations",job.name*".jl"))
                    capture=joinpath(results,"evidence",job.name); mkpath(capture)
                    entry=joinpath(temporary,job.name*"-entry.jl")
                    hook=joinpath(bench,"adapters","recipes","capture.jl")
                    write(entry,(id=="precompile-lifecycle" ? "" : "include("*repr(hook)*")\n") *
                        "try\n Base.include_string(Main, read("*repr(actual)*", String), "*repr(job.script)*")\n" *
                        "catch e\n message = e isa Base.ProcessFailedException ? \"external process failed (environment omitted)\" : sprint(showerror,e)\n" *
                        " occursin(\"setenv(\",message) && (message=\"process error (environment omitted)\")\n println(stderr, first(message,min(length(message),2000))); exit(1)\nend\n")
                    cp(entry,joinpath(output,"adaptations",job.name*"-entry.jl"))
                    command=`$(Base.julia_cmd()) --startup-file=no --threads=$(job.threads),0 --gcthreads=1 --project=$(job.project) $entry $(job.args)`
                    command=addenv(command,"TMPDIR"=>temp,"GARAMONBENCH_CAPTURE"=>capture,
                        "JULIA_NUM_THREADS"=>"$(job.threads),0","JULIA_NUM_PRECOMPILE_TASKS"=>"1",
                        "JULIA_PKG_PRECOMPILE_AUTO"=>"0","OPENBLAS_NUM_THREADS"=>"1","OMP_NUM_THREADS"=>"1")
                    command=recipe_condition_command(command,plan)
                    log=joinpath(results,job.name*"-execution.txt")
                    record=Dict{String,Any}("name"=>job.name,"command_arguments"=>collect(command),
                        "original_driver_sha256"=>bytes2hex(sha256(source)),"adapted_driver_sha256"=>bytes2hex(sha256(adapted)),"adaptations"=>changes)
                    push!(metadata["jobs"],record)
                    merge!(record,recipe_supervise(command,log,temporary,limits,deadline))
                    record["process_success"] && isempty(record["budget_exceeded"]) || error("recipe child failed or exceeded budget; see job metadata")
                end
                if id=="precompile-lifecycle"
                    metadata["qualification_kind"]="native exact checks and cache stability; not a PerfChecker verdict"
                    metadata["native_observation_files"]=filter(f->endswith(f,".csv"),readdir(joinpath(results,"native")))
                    length(metadata["native_observation_files"])==3 || error("missing native lifecycle observations")
                else
                    captures=[joinpath(d,f) for (d,_,fs) in walkdir(joinpath(results,"evidence")) for f in fs if endswith(f,"-capture.toml")]
                    expected_suites=id=="k1-binary-rank" ? count(j->get(j,:measured,true),jobs) : isempty(n05_ids) ? length(jobs) : length(n05_ids)
                    length(captures)==expected_suites || error("captured PerfChecker suite count differs from requested cases/jobs")
                    evidence=TOML.parsefile.(captures)
                    metadata["native_suites"]=evidence
                    all(e->e["passed"] && e["samples"]>0,evidence) || error("native suite failed or has no samples")
                    !isempty(n05_ids) && (metadata["n05_selection_verification"]=recipe_verify_n05_selection(results,n05_ids))
                    id=="k1-binary-rank" && (metadata["k1_selection_verification"]=recipe_verify_k1(results,plan))
                    metadata["qualification_kind"]="native PerfChecker verdict, preserved without reinterpretation"
                end
            else
                nativeconfig=id=="julia-products" ? get(plan["parameters"],"native_config",joinpath(bench,"config","julia_products.toml")) : joinpath(bench,"config","cpp_matched.toml")
                native=load_config(abspath(expanduser(nativeconfig)))
                native["campaign"]["condition"]=recipe["condition"]
                native["campaign"]["interference_label"]=get(recipe,"interference_label","")
                if id=="cpp-matched"
                    native["external_cpp"]["smoke"]=recipe["profile"]=="smoke"
                    native["external_cpp"]["reverse"]=plan["parameters"]["reverse"]
                end
                path=joinpath(temporary,"native-config.toml"); write_toml(path,native)
                write_toml(joinpath(output,"native-configuration.toml"),native)
                args=id=="julia-products" ? ["run",path,results,joinpath(bench,"adapters","garamon_julia.jl")] : ["cpp-matched",path,results]
                # A small wrapper prevents Julia's top-level process exception from
                # serializing ENV; detailed native failures are stored by the backend.
                entry=joinpath(temporary,"packaged-entry.jl")
                write(entry,"using GaramonBench\ntry GaramonBench.cli() catch e; println(stderr, GaramonBench.failure_message(e)); exit(1); end\n")
                command=`$(Base.julia_cmd()) --startup-file=no --threads=$(recipe["threads"]),0 --gcthreads=1 --project=$bench $entry $args`
                command=addenv(command,"TMPDIR"=>temp,"OPENBLAS_NUM_THREADS"=>"1","OMP_NUM_THREADS"=>"1",
                    "JULIA_NUM_PRECOMPILE_TASKS"=>"1","JULIA_PKG_PRECOMPILE_AUTO"=>"0")
                command=recipe_condition_command(command,plan)
                record=Dict{String,Any}("name"=>id,"command_arguments"=>collect(command))
                push!(metadata["jobs"],record)
                merge!(record,recipe_supervise(command,joinpath(results,"execution.txt"),temporary,limits,deadline))
                record["process_success"] && isempty(record["budget_exceeded"]) || error("packaged recipe failed or exceeded budget")
                metadata["qualification_kind"]="nested fresh packaged backend; inspect native run.toml and raw samples"
            end
            finally
            metadata["temporary_bytes_before_cleanup"]=tree_bytes(temporary)
            # Copy only text result formats. No generated entrypoints, temporary
            # depots, libraries, executables or C++ builds leave this directory.
            metadata["artifacts"]=recipe_archive_tree(results,joinpath(output,"measurements"),limits["archive_bytes"]-tree_bytes(output))
            end
        end
        metadata["temporary_build_removed"]=true
        for (name,path) in roots
            repository_identity(path;max_bytes=limits["source_bytes"])["sha256"]==identities[name]["sha256"] || error("source changed during recipe: $name")
        end
        metadata["status"]="passed"
    catch exception
        metadata["status"]="failed"; metadata["failure"]=failure_message(exception)
        rethrow()
    finally
        metadata["temporary_build_started"]=!isempty(temporary_path)
        metadata["temporary_build_removed"]=isempty(temporary_path) || !ispath(temporary_path)
        metadata["finished_utc"]=string(now(UTC))
        write_toml(joinpath(output,"machine_after.toml"),machine_snapshot())
        write_toml(joinpath(output,"run.toml"),metadata)
    end
    output
end
run_recipe(path::AbstractString;kwargs...)=run_recipe(TOML.parsefile(path);kwargs...)
