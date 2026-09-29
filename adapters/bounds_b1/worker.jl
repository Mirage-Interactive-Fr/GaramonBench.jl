using GaramonBench,PerfChecker,BenchmarkTools,TOML,SHA,LinearAlgebra

const B1_REQUEST=TOML.parsefile(ARGS[1])
push!(LOAD_PATH,B1_REQUEST["julia_root"])
using Garamon
realpath(dirname(dirname(pathof(Garamon))))==realpath(B1_REQUEST["julia_root"]) || error("wrong Garamon checkout loaded")
Base.include(@__MODULE__,joinpath(B1_REQUEST["julia_root"],"perf","bounds_b1.jl"))
using .BoundsB1Prototype

# Independent ordered-word oracle, independent of prepared paths and sign/XOR
# helpers. Only tiny exactly representable integers are used in this pilot.
function b1_word_oracle(a,b,diagonal)
    K=keytype(a.values);result=Dict{K,Int64}()
    for (am,av) in a.values,(bm,bv) in b.values
        word=[i for i in eachindex(diagonal) if !iszero(am & (one(K)<<(i-1)))]
        value=Int64(av)*Int64(bv)
        for j in eachindex(diagonal)
            iszero(bm & (one(K)<<(j-1))) && continue
            position=length(word)+1
            while position>1 && word[position-1]>j
                value=-value;position-=1
            end
            if position>1 && word[position-1]==j
                value*=diagonal[j];deleteat!(word,position-1)
            else
                insert!(word,position,j)
            end
        end
        mask=foldl(|,(one(K)<<(i-1) for i in word);init=zero(K))
        result[mask]=get(result,mask,0)+value
    end
    filter!(p->!iszero(last(p)),result)
end

function b1_fixture(n,family,signature)
    K=n<=64 ? UInt64 : UInt128;full=K((big(1)<<n)-1)
    masks=family=="low_grade" ? K[0,1,2,3] : unique(K[0,1,full,full ⊻ K(1)])
    diagonal=ones(Int64,n)
    signature=="mixed" && (diagonal[2:2:n].=-1)
    signature=="degenerate" && (diagonal[1]=0)
    ga=algebra(Diagonal(Float64.(diagonal)));coefficients=(-2.0,-1.0,1.0,2.0)
    inputs=[(multivector(ga,Dict(m=>coefficients[mod1(i+p,4)] for (i,m) in enumerate(masks));storage=:sparse),
             multivector(ga,Dict(m=>coefficients[mod1(2i+p,4)] for (i,m) in enumerate(masks));storage=:sparse)) for p in 1:4]
    expected=[b1_word_oracle(a,b,diagonal) for (a,b) in inputs]
    (;inputs,expected)
end
b1_build(fixture)=prepare_product(fixture.inputs[1]...)
b1_build_execution(fixture,route)=route==:workspace ?
    b1_workspace(b1_build(fixture),fixture.inputs[1]...) :
    route in (:workspace_native,:workspace_native_singlepass) ? b1_workspace(fixture.inputs[1]...) : b1_build(fixture)
function b1_batch(fixture,execution,route,horizon)
    if route==:workspace_native_singlepass
        return [b1_workspace_product_singlepass!(execution,fixture.inputs[mod1(i,4)]...) for i in 1:horizon]
    end
    if route in (:workspace,:workspace_native)
        return [b1_workspace_product!(execution,fixture.inputs[mod1(i,4)]...) for i in 1:horizon]
    end
    [b1_product(execution,fixture.inputs[mod1(i,4)]...;variant=route) for i in 1:horizon]
end
b1_episode(fixture,route,horizon)=b1_batch(fixture,b1_build_execution(fixture,route),route,horizon)
function b1_exact_owned(fixture,outputs,horizon)
    length(outputs)==horizon && length(unique(objectid(x.values) for x in outputs))==horizon &&
        all(outputs[i].values==fixture.expected[mod1(i,4)] for i in 1:horizon)
end

function b1_suite(request)
    job=request["job"]
    features=[FeatureSpec(Symbol("b1_"*string(i));entrypoint=@__FILE__,backend=:benchmark,oracle=OracleSpec(),
        comparison_key="B1/owned/$(c["dimension"])/$(c["family"])/$(c["signature"])/H$(c["horizon"])/pass$(c["passage"])",
        options=Dict(:b1_case=>c)) for (i,c) in enumerate(job["cases"])]
    SoftwareSuite(Symbol(job["id"]),[PackageSuite("Garamon";source=request["julia_root"],
        worker_environment=joinpath(dirname(dirname(@__DIR__)),"worker"),versions=VersionNumber[],dev_sources=String[],features)])
end

function b1_worker(request,output)
    ispath(output) && error("fresh B1 worker output required");mkpath(output)
    VERSION.major==1 && VERSION.minor==13 || error("B1 worker requires Julia 1.13")
    Threads.nthreads()==1 || error("B1 worker requires one thread");BLAS.set_num_threads(1)
    job=request["job"];limits=request["limits"];options=Base.JLOptions()
    cpu=options.cpu_target==C_NULL ? "" : unsafe_string(options.cpu_target)
    effective=Dict("check_bounds"=>Int(options.check_bounds),"opt_level"=>Int(options.opt_level),
        "cpu_target"=>cpu,"threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads(),
        "gc_mark_threads"=>Int(options.nmarkthreads),"gc_sweep_threads"=>Int(options.nsweepthreads),
        "opt_level_min"=>Int(options.opt_level_min),
        "math_mode_code"=>Int(options.fast_math),"pkgimages_code"=>Int(options.use_pkgimages),
        "compiled_modules_code"=>Int(options.use_compiled_modules),"sysimage_target"=>Sys.sysimage_target())
    options.check_bounds==(job["check_bounds"]=="yes" ? 1 : 0) || error("B1 effective bounds option differs")
    options.opt_level==job["opt_level"] || error("B1 effective optimization differs")
    cpu==job["cpu_target"] || error("B1 effective CPU target differs")
    options.use_pkgimages==0 || error("B1 package images must be disabled")
    get(ENV,"GARAMONBENCH_CONDITION","")==request["condition"] &&
        get(ENV,"GARAMONBENCH_INTERFERENCE_LABEL","")==request["interference_label"] || error("B1 effective condition differs")
    sourcefiles=sort(vcat([@__FILE__,joinpath(request["julia_root"],"perf","bounds_b1.jl")],
        [joinpath(request["julia_root"],"src",f) for f in readdir(joinpath(request["julia_root"],"src")) if endswith(f,".jl")]))
    fingerprint()=bytes2hex(sha256(join(read.(sourcefiles,String),"\n")))
    original=fingerprint();started=String[];completed=String[]
    environment=Dict{String,Any}("status"=>"running","requested"=>job,"effective_options"=>effective,
        "julia"=>string(VERSION),"perfchecker"=>string(pkgversion(PerfChecker)),"cpu"=>Sys.CPU_NAME,
        "measurement_condition"=>request["condition"],"interference_label"=>request["interference_label"],
        "source_sha256"=>original,"source_files"=>sourcefiles,"process_arguments"=>read("/proc/self/cmdline",String),
        "source_unchanged"=>false,"started_case_ids"=>started,"completed_case_ids"=>completed,
        "execution"=>"PerfChecker custom executor in this option-verified process; no nested measurement worker",
        "actual_project"=>Base.active_project(),
        "catalogue_worker_environment"=>joinpath(dirname(dirname(@__DIR__)),"worker"),
        "catalogue_worker_environment_used"=>false,
        "ownership"=>"all H sparse outputs retained and independent; private validation/copies paid on every product",
        "phase_contract"=>"build, hot on shared prepared plan, directly measured build plus H product episode",
        "cold_contract"=>request["cold_contract"])
    # Store argv as an array, not NUL-containing process text in a text archive.
    environment["process_arguments"]=split(environment["process_arguments"],'\0';keepempty=false)
    envpath=joinpath(output,"environment.toml")
    GaramonBench.write_toml(envpath,environment)
    samplespath=joinpath(output,"samples.csv");coldpath=joinpath(output,"first-observations.csv")
    write(samplespath,"case_id,phase,sample,time_ns,gc_time_ns,allocated_bytes,allocations\n")
    write(coldpath,"case_id,phase,time_ns,compile_ns,recompile_ns,allocated_bytes,gc_time_ns\n")
    fixtures=Dict{Tuple,Any}();plans=Dict{Tuple,Any}();workspaces=Dict{Tuple,Any}()
    function coldrow(id,phase,observation)
        open(coldpath,"a") do io
            println(io,join((id,phase,observation.time*1e9,observation.compile_time*1e9,
                observation.recompile_time*1e9,observation.bytes,observation.gctime*1e9),','))
        end
    end
    function samples(id,phase,trial)
        length(trial.times)==limits["samples"] || error("B1 insufficient samples for $id/$phase: $(length(trial.times)) of $(limits["samples"])")
        open(samplespath,"a") do io
            for i in eachindex(trial.times)
                println(io,join((id,phase,i,trial.times[i],trial.gctimes[i],trial.memory,trial.allocs),','))
            end
        end
    end
    function executor(planned,config,setup,workload)
        c=planned.feature.options[:b1_case];id=c["id"];push!(started,id)
        GaramonBench.write_toml(envpath,environment)
        Sys.maxrss()<=limits["rss_bytes"] || error("B1 process RSS admission refused")
        key=(c["dimension"],c["family"],c["signature"])
        fixture=get!(fixtures,key) do;b1_fixture(key...);end
        route=Symbol(c["route"]);horizon=c["horizon"]
        execution=if route in (:workspace,:workspace_native,:workspace_native_singlepass)
            get!(workspaces,(key...,route)) do
                first_build=@timed b1_build_execution(fixture,route)
                coldrow(id,:build,first_build);first_build.value
            end
        else
            get!(plans,key) do
                first_build=@timed b1_build(fixture)
                coldrow(id,:build,first_build);first_build.value
            end
        end
        observation=@timed b1_batch(fixture,execution,route,horizon)
        coldrow(id,:first_batch_in_case,observation)
        b1_exact_owned(fixture,observation.value,horizon) || error("B1 first batch oracle/ownership failed")
        count=limits["samples"];seconds=limits["sample_seconds"]
        build=@benchmark b1_build_execution($fixture,$route) samples=count evals=1 seconds=seconds
        samples(id,:build,build)
        hot=@benchmark b1_batch($fixture,$execution,$route,$horizon) samples=count evals=1 seconds=seconds
        samples(id,:hot,hot)
        b1_exact_owned(fixture,b1_episode(fixture,route,horizon),horizon) || error("B1 episode oracle/ownership failed")
        episode=@benchmark b1_episode($fixture,$route,$horizon) samples=count evals=1 seconds=seconds
        samples(id,:episode,episode)
        episode.memory<=limits["max_episode_bytes"] || error("B1 measured episode allocation budget exceeded")
        b1_exact_owned(fixture,b1_batch(fixture,execution,route,horizon),horizon) &&
            b1_exact_owned(fixture,b1_episode(fixture,route,horizon),horizon) || error("B1 post-sample oracle/ownership failed")
        push!(completed,id)
        GaramonBench.write_toml(envpath,environment)
        PerfChecker.CheckerResult([PerfChecker.to_table(episode)],nothing,[:B1,Symbol(request["condition"]),:complete_episode],
            [PerfChecker.PackageSpec(name="Garamon")],[Dict{String,Any}(
                "correctness"=>Dict("status"=>"passed","required"=>true,"message"=>"independent Int64 word oracle and all H owned results before/after timing"),
                "measurement_condition"=>request["condition"],"interference_label"=>request["interference_label"],
                "effective_julia_options"=>effective,"source_fingerprint"=>original,"case_id"=>id,
                "execution"=>Dict("mode"=>"shared_process_explicit_options","threads"=>1))])
    end
    suite=b1_suite(request)
    try
        result=run_suite(suite;profile=:quick,strict=false,executor)
        write_suite_json(result,joinpath(output,"qualification.json"))
        environment["source_unchanged"]=fingerprint()==original
        environment["rss_bytes"]=Sys.maxrss()
        environment["status"]=suite_passed(result) && environment["source_unchanged"] ? "validated" : "failed"
        environment["verdict"]=string(suite_verdict(result))
        environment["status"]=="validated" || error("B1 qualification or source integrity failed")
    finally
        environment["not_completed_case_ids"]=setdiff([c["id"] for c in job["cases"]],completed)
        GaramonBench.write_toml(envpath,environment)
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    try
        b1_worker(B1_REQUEST,abspath(ARGS[2]))
    catch e
        println(stderr,GaramonBench.failure_message(e));exit(1)
    end
end
