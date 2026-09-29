const B1_SCREEN_DIMENSIONS=[2,3,4,6,8,12,16,32,64,65,96,128]
const B1_LIMITS=Dict{String,Any}("samples"=>7,"sample_seconds"=>0.02,"job_seconds"=>180,
    "total_seconds"=>1200,"rss_bytes"=>2<<30,"max_episode_bytes"=>512<<20,
    "scratch_bytes"=>512<<20,"archive_bytes"=>256<<20,"source_bytes"=>64<<20)

function b1_plan(input)
    raw=input isa AbstractString ? TOML.parsefile(input) : deepcopy(input)
    get(raw,"schema_version",0)==1 || error("B1 schema must be 1")
    all(k in ("schema_version","campaign","compiler","limits") for k in keys(raw)) || error("unknown B1 field")
    c=get(raw,"campaign",Dict());compiler=get(raw,"compiler",Dict())
    all(k in ("profile","condition","interference_label","dimensions","families","signatures","horizons","routes") for k in keys(c)) || error("unknown B1 campaign field")
    all(k in ("check_bounds","opt_levels","cpu_targets") for k in keys(compiler)) || error("unknown B1 compiler option")
    profile=get(c,"profile","smoke");profile in ("smoke","screen") || error("B1 profile must be smoke or screen")
    condition=get(c,"condition","");condition in ("exploratory_interference","isolated") || error("declare B1 condition")
    label=get(c,"interference_label","")
    label isa AbstractString && length(label)<=256 && !any(iscntrl,label) || error("invalid B1 interference label")
    label=strip(label)
    condition=="isolated" && !isempty(label) && error("clear B1 isolated label explicitly")
    condition=="exploratory_interference" && isempty(label) && error("B1 exploratory label required")
    function selection(source,key,default,valid)
        values=get(source,key,default)
        values isa Vector && !isempty(values) && all(valid,values) && allunique(values) || error("invalid B1 $key selection")
        collect(values)
    end
    dimensions=selection(c,"dimensions",profile=="smoke" ? [8] : B1_SCREEN_DIMENSIONS,n->n isa Integer && !(n isa Bool) && 2<=n<=128)
    families=selection(c,"families",profile=="smoke" ? ["low_grade"] : ["low_grade","high_grade"],x->x in ("low_grade","high_grade"))
    signatures=selection(c,"signatures",profile=="smoke" ? ["positive"] : ["positive","mixed","degenerate"],x->x in ("positive","mixed","degenerate"))
    horizons=selection(c,"horizons",profile=="smoke" ? [1] : [1,32,1024],x->x isa Integer && !(x isa Bool) && x in (1,32,1024))
    routes=selection(c,"routes",["checked","inbounds"],x->x in
        ("checked","inbounds","workspace","workspace_native","workspace_native_singlepass"))
    bounds=selection(compiler,"check_bounds",["auto"],x->x in ("yes","auto"))
    levels=selection(compiler,"opt_levels",[2],x->x isa Integer && !(x isa Bool) && x in (2,3))
    targets=selection(compiler,"cpu_targets",["native"],x->x in ("generic","native"))
    profile=="smoke" && (length(dimensions)*length(families)*length(signatures)*length(horizons)!=1 || horizons!=[1]) && error("B1 smoke is one fixture at H1")
    limits=merge(B1_LIMITS,get(raw,"limits",Dict()))
    all(haskey(B1_LIMITS,k) for k in keys(limits)) || error("unknown B1 budget")
    all(v->v isa Real && !(v isa Bool) && isfinite(v) && v>0,values(limits)) || error("B1 budgets must be finite and positive")
    limits["samples"] isa Integer && limits["samples"]<=31 || error("B1 samples must be 1..31")
    limits["sample_seconds"]<=5 && limits["job_seconds"]<=limits["total_seconds"]<=7200 || error("B1 time budget exceeds pilot limit")
    jobs=Dict{String,Any}[]
    for n in sort(dimensions),bound in bounds,level in levels,target in targets
        id="B1-n"*lpad(string(n),3,'0')*"-$bound-O$level-$target"
        cases=Dict{String,Any}[]
        for passage in 1:2,family in families,signature in signatures,horizon in horizons,
            route in (passage==1 ? routes : reverse(routes))
            caseid="$id-$family-$signature-H$horizon-$route-pass$passage"
            push!(cases,Dict("id"=>caseid,"dimension"=>n,"family"=>family,"signature"=>signature,
                "horizon"=>horizon,"route"=>route,"passage"=>passage))
        end
        push!(jobs,Dict("id"=>id,"dimension"=>n,"check_bounds"=>bound,"opt_level"=>level,"cpu_target"=>target,"cases"=>cases))
    end
    Dict{String,Any}("schema_version"=>1,"technique"=>"B1-private-validated-paths-v1","status"=>"planned_not_measured",
        "profile"=>profile,"condition"=>condition,"interference_label"=>label,"threads"=>1,
        "families"=>families,"signatures"=>signatures,"horizons"=>horizons,"routes"=>routes,"dimensions"=>sort(dimensions),
        "limits"=>limits,"jobs"=>jobs,"case_count"=>sum(length(j["cases"]) for j in jobs),
        "coverage"=>"explicit selected cases only; fresh Julia process per dimension/compiler combination; two route orders",
        "option_contract"=>"explicit Julia CLI and verified JLOptions in measurement process; PerfChecker shared-process executor; no nested benchmark worker",
        "cold_contract"=>"first route calls recorded in passage order; shared helpers may already be compiled; not independent cold-start speed ratios")
end

function b1_command(plan,job,request,output;executable=first(Base.julia_cmd()))
    worker=joinpath(dirname(@__DIR__),"adapters","bounds_b1","worker.jl")
    command=Cmd([executable,"--startup-file=no","--threads=1,0","--gcthreads=1","--check-bounds="*job["check_bounds"],
        "-O"*string(job["opt_level"]),"--cpu-target="*job["cpu_target"],"--math-mode=ieee","--pkgimages=no",
        "--compiled-modules=existing","--project="*dirname(@__DIR__),worker,request,output])
    addenv(command,"JULIA_NUM_THREADS"=>"1,0","OPENBLAS_NUM_THREADS"=>"1","OMP_NUM_THREADS"=>"1",
        "JULIA_NUM_PRECOMPILE_TASKS"=>"1","JULIA_PKG_PRECOMPILE_AUTO"=>"0",
        "GARAMONBENCH_CONDITION"=>plan["condition"],"GARAMONBENCH_INTERFERENCE_LABEL"=>plan["interference_label"])
end

"""Fresh bounded B1 observations, never imported historical timing results."""
function run_b1(input;output)
    VERSION.major==1 && VERSION.minor==13 || error("B1 controller requires Julia 1.13")
    plan=b1_plan(input);output=abspath(output);ispath(output) && error("use a fresh B1 output directory")
    root=abspath(expanduser(get(ENV,"GARAMON_JULIA_ROOT","~/.julia/dev/Garamon")));bench=dirname(@__DIR__)
    any(p->output==p || startswith(output,p*"/"),(root,bench)) && error("place B1 output outside source trees")
    isfile(joinpath(root,"perf","bounds_b1.jl")) || error("target B1 prototype is required")
    mkpath(output);limits=plan["limits"]
    metadata=Dict{String,Any}("status"=>"running","condition"=>plan["condition"],"interference_label"=>plan["interference_label"],
        "planned_cases"=>plan["case_count"],"jobs"=>Dict{String,Any}[],"isolation_certified"=>false,"started_utc"=>string(now(UTC)))
    write_toml(joinpath(output,"manifest.toml"),plan)
    write_toml(joinpath(output,"machine-before.toml"),machine_snapshot())
    identities=Dict{String,Any}()
    try
        for (name,path) in (("julia",root),("benchmark",bench))
            identities[name]=repository_identity(path;snapshot=joinpath(output,"sources",name),max_bytes=limits["source_bytes"])
        end
        metadata["repositories"]=identities
        tree_bytes(output)<=limits["archive_bytes"] || error("B1 source snapshots exceed archive budget")
        deadline=time()+limits["total_seconds"]
        with_build_directory() do temporary
            results=joinpath(temporary,"results");mkpath(results)
            try
                for job in plan["jobs"]
                    time()<deadline || error("B1 total time budget; remaining jobs not started")
                    request=merge(plan,Dict("job"=>job,"julia_root"=>root));delete!(request,"jobs")
                    path=joinpath(temporary,job["id"]*".toml");write_toml(path,request)
                    destination=joinpath(results,job["id"])
                    command=b1_command(plan,job,path,destination)
                    record=Dict{String,Any}("id"=>job["id"],"requested_cases"=>[c["id"] for c in job["cases"]],"command_arguments"=>collect(command))
                    push!(metadata["jobs"],record)
                    merge!(record,recipe_supervise(command,joinpath(results,job["id"]*"-execution.txt"),temporary,limits,
                        min(deadline,time()+limits["job_seconds"])))
                    record["process_success"] && isempty(record["budget_exceeded"]) || error("B1 worker failed or exceeded budget")
                    evidence=TOML.parsefile(joinpath(destination,"environment.toml"))
                    evidence["status"]=="validated" && evidence["completed_case_ids"]==record["requested_cases"] || error("B1 worker coverage differs")
                    record["completed_case_ids"]=evidence["completed_case_ids"]
                end
            finally
                metadata["artifacts"]=recipe_archive_tree(results,joinpath(output,"measurements"),limits["archive_bytes"]-tree_bytes(output))
            end
        end
        for (name,path) in (("julia",root),("benchmark",bench))
            repository_identity(path;max_bytes=limits["source_bytes"])["sha256"]==identities[name]["sha256"] || error("B1 source changed during campaign")
        end
        metadata["status"]="validated"
    catch e
        metadata["status"]="failed_or_incomplete";metadata["failure"]=failure_message(e);rethrow()
    finally
        metadata["finished_utc"]=string(now(UTC))
        completed=reduce(vcat,[get(j,"completed_case_ids",String[]) for j in metadata["jobs"]];init=String[])
        metadata["completed_case_ids"]=completed
        metadata["not_qualified_case_ids"]=setdiff([c["id"] for j in plan["jobs"] for c in j["cases"]],completed)
        write_toml(joinpath(output,"run.toml"),metadata)
        write_toml(joinpath(output,"machine-after.toml"),machine_snapshot())
    end
    output
end
