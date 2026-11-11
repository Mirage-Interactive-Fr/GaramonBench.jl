import Libdl

const _CPP_REFERENCE_ADAPTER = "garamon_cpp_reference"
const _CPP_REFERENCE_OPERATIONS = Dict(:geometric=>0,:wedge=>1,:left=>2,:right=>3,:sum_products=>4)
const _CPP_REFERENCE_SOURCE = joinpath(dirname(@__DIR__),"adapters","cpp_matched","reference.cpp")
const _CPP_REFERENCE_CACHE_AXES = ("capacity_plans","eviction_exponent","frequency_slots","draw_seed")

# Only identical fixture contracts are paired. These translators consume the
# original generator's operands and independent expected coefficients.
const _CPP_REFERENCE_FIXTURES = Dict(
    "garamon_julia"=>:vectors,
    "garamon_generated_product"=>:vectors,
    "garamon_cpu_threaded_packed"=>:vectors,
    "garamon_dense_global"=>:dense,
    "garamon_grade_product"=>:supported,
    "garamon_target_coefficient"=>:supported,
    "garamon_triple_join"=>:supported,
    "garamon_exact_triple_selector"=>:supported,
    "garamon_binary_rank"=>:fixed,
    "garamon_binary_rank_compact_workspace"=>:fixed,
    "garamon_coordinate_subspace"=>:subspace,
    "garamon_plan_cache"=>:trace,
    "garamon_expression_dag"=>:dag,
    "garamon_materialized_trie"=>:trie,
    "garamon_pfaffian_scalar"=>:scalar_chain,
    "garamon_cpu_processes"=>:process_batch,
    "garamon_adaptive_radix"=>:sparse_wedge,
    "garamon_split_matrix"=>:aggregate,
    "garamon_exact_tensor_train"=>:tensor,
    "garamon_wavefront"=>:wavefront,
    "gpu_packed_exact"=>:gpu_batch,
)

function _cpp_reference_fixture(kind,f,case)
    n=case["dimension"]
    diagonal = hasproperty(f,:diagonal) ? f.diagonal : ones(Int,n)
    operation = hasproperty(f,:operation) ? f.operation : :geometric
    expected = get(f,:expected,nothing)
    layout=:matrix
    scalar=Float64
    varying_outputs=false
    if kind in (:vectors,:dense,:supported,:fixed,:trace)
        targets = kind==:vectors ? f.output_masks :
            kind==:dense ? (0:(1<<f.n)-1) : f.targets
        supports = kind in (:vectors,:dense) ? (f.masks,f.masks) :
            kind==:fixed ? (f.left,f.right) : f.supports
        requests = [map(zip,kind==:trace ? supports[f.selected[t]] : supports,values)
            for (t,values) in enumerate(f.coefficients)]
    elseif kind==:subspace
        targets=f.targets
        requests=[map(zip,(f.left,f.right),f.values)]
        expected=reshape(expected,:,1)
        layout=:vector
    elseif kind==:dag
        a,b,c=f.coefficients
        targets=0:(1<<f.n)-1
        requests=[(a,b,f.structure=="shared" ? b : c),
                  (f.changed,b,f.structure=="shared" ? b : c)]
        operation=:sum_products
    elseif kind==:trie
        targets=f.targets
        requests=fill((f.left,f.right),f.horizon)
        expected=repeat(expected,1,f.horizon)
        operation=:wedge
        layout=f.horizon==1 ? :vector : :vectors
    elseif kind==:scalar_chain
        diagonal=[f.G[i,i] for i in 1:n]
        chain=[[(1<<(i-1),f.V[i,j]) for i in 1:n if !iszero(f.V[i,j])] for j in 1:f.k]
        targets=[0]
        requests=fill(chain,f.horizon)
        expected=fill(f.expected,1,f.horizon)
        layout=:vector
    elseif kind==:process_batch
        targets=f.fixture.plan.output_masks
        requests=[map(Garamon._terms,f.fixture.inputs[mod1(t,4)]) for t in 1:f.batch]
    elseif kind==:sparse_wedge
        requests=f.inputs
        targets=sort!(unique([a|b for (left,right) in requests
            for a in keys(left) for b in keys(right) if iszero(a&b)]))
        operation=:wedge
        layout=:dictionaries
    elseif kind==:aggregate
        diagonal=[iseven(i) ? -1 : 1 for i in 1:n]
        targets=0:(1<<n)-1
        requests=collect(zip(f.left_pool[f.indices],f.right_terms))
        expected=reshape(expected,:,1)
        layout=:aggregate
    elseif kind==:tensor
        targets=0:(1<<n)-1
        coefficient(mask,z,o)=prod(iszero(mask & (1<<(i-1))) ? z[i] : o[i] for i in 1:n)
        left=[(mask,coefficient(mask,f.left_zero,f.left_one)) for mask in targets]
        right=[(mask,coefficient(mask,f.right_zero,f.right_one)) for mask in targets]
        requests=fill((left,right),f.horizon)
        expected=repeat(expected,1,f.horizon)
        scalar=Int64
        layout=f.horizon==1 ? :vector : :vectors
    elseif kind==:wavefront
        targets=f.targets
        requests=f.episodes
        scalar=Int64
        layout=:vector
        varying_outputs=true
    else
        batch=Main.gpu_make_batch(f,case["horizon"])
        targets=batch.plan.output_masks
        diagonal=batch.plan.diagonal
        requests=[map(Garamon._terms,f.inputs[mod1(t,4)]) for t in 1:case["horizon"]]
        oracle=[Main.rank_oracle(f,pair...,(:all,0)) for pair in f.inputs]
        expected=[get(oracle[mod1(t,4)],mask,0) for mask in targets, t in 1:case["horizon"]]
    end
    (;diagonal,targets,requests,expected,operation,layout,scalar,varying_outputs)
end

function _cpp_reference_original(case)
    original=copy(case)
    original["adapter"]=pop!(original,"reference_adapter")
    original["baseline_required"]=true
    original
end

function _cpp_reference_match_id(case)
    if case["adapter"]=="garamon_plan_cache"
        return case_id(Dict(key=>value for (key,value) in case if key ∉ _CPP_REFERENCE_CACHE_AXES))
    end
    case_id(case)
end

function _cpp_reference_config(config)
    defaults=config["case_defaults"]
    adapter=defaults["adapter"]
    haskey(_CPP_REFERENCE_FIXTURES,adapter) || return nothing
    all(operation->haskey(_CPP_REFERENCE_OPERATIONS,Symbol(operation)),
        get(config["grid"],"operation",["geometric"])) ||
        return nothing
    result=deepcopy(config)
    result["case_defaults"]["reference_adapter"]=adapter
    result["case_defaults"]["adapter"]=_CPP_REFERENCE_ADAPTER
    result["case_defaults"]["baseline_required"]=false
    get!(result,"repositories",Dict{String,Any}())["cpp"]="artifact:garamon_cpp"
    if adapter=="garamon_plan_cache"
        for axis in _CPP_REFERENCE_CACHE_AXES
            haskey(result["grid"],axis) && (result["grid"][axis]=result["grid"][axis][1:1])
        end
    end
    result
end

# Garamon generates a lookup table with 2^n entries even when the operands
# are sparse. Admit at most a million entries in this campaign's build.
const _CPP_REFERENCE_MAX_DIMENSION = 20

function _cpp_reference_command(command,log)
    # Use the same toolchain as the other native comparisons.
    timeout=Sys.which("timeout")
    bounded=isnothing(timeout) ? command :
        Cmd(`$timeout -k 5s 300s $(command.exec)`;dir=command.dir)
    open(log,"a") do io
        if !success(pipeline(addenv(bounded,cpp_toolchain_environment()...);stdout=io,stderr=io))
            lines=readlines(log)
            error("Garamon C++ build failed: "*join(last(lines,min(12,length(lines))),"\n"))
        end
    end
end

function _cpp_reference_library(cache,diagonal,scalar=Float64)
    key=string(scalar)*":"*join(diagonal,",")
    directory=joinpath(cache,"metric-"*first(bytes2hex(sha256(key)),16))
    library=joinpath(directory,"reference.so")
    isfile(library) && return library
    failure=joinpath(directory,"unavailable.txt")
    isfile(failure) && error(read(failure,String))
    mkpath(directory)
    try
        _cpp_reference_compile(cache,directory,diagonal,scalar,library)
    catch exception
        exception isa InterruptException && rethrow()
        write(failure,failure_message(exception))
        rethrow()
    end
    library
end

function _cpp_reference_compile(cache,directory,diagonal,scalar,library)
    root=ensure_cpp_source()
    (;cmake,cc,cxx,ninja,eigen,eigen_include)=cpp_toolchain()
    log=joinpath(directory,"build.log")
    generator=joinpath(cache,"generator")
    binary=joinpath(generator,"garamon_generator")
    if !isfile(binary)
        _cpp_reference_command(`$cmake -G Ninja -S $root -B $generator -DCMAKE_MAKE_PROGRAM=$ninja -DCMAKE_C_COMPILER=$cc -DCMAKE_CXX_COMPILER=$cxx -DEigen3_DIR=$eigen -DEIGEN3_INCLUDE_DIR=$eigen_include -DCMAKE_BUILD_TYPE=Release`,log)
        _cpp_reference_command(`$cmake --build $generator --target garamon_generator --parallel 1`,log)
    end
    n=length(diagonal)
    config=read(joinpath(root,"conf","e3ga.conf"),String)
    metric=join((join((i==j ? diagonal[i] : 0 for j in 1:n),' ') for i in 1:n),'\n')
    namespace="gbref_"*last(basename(directory),16)
    # The pinned generator can emit a reference to a precomputed function
    # whose entire grade block vanishes in a degenerate metric.
    precomputed=any(iszero,diagonal) ? "0" : n<=8 ? "256" : "32"
    for (tag,value) in (("namespace",namespace),("dimension",string(n)),
                        ("metric",metric),("basis vector name",join(("_"*string(i) for i in 1:n),' ')),
                        ("max dimension precomputed products",precomputed),
                        ("max dimension basis accessor",n<=8 ? "256" : "32"))
        config=replace(config,Regex("<"*tag*">[^<]*</"*tag*">") =>
            "<"*tag*">\n"*value*"\n</"*tag*">")
    end
    file=joinpath(directory,"metric.conf")
    write(file,config)
    generation=joinpath(directory,"generated")
    mkpath(joinpath(generation,"output"))
    islink(joinpath(directory,"data")) || symlink(joinpath(root,"data"),joinpath(directory,"data"))
    _cpp_reference_command(Cmd(`$binary $file`;dir=generation),log)
    headers=joinpath(generation,"output","garamon_"*namespace,"src")
    header="-DGB_REFERENCE_HEADER=\""*namespace*"/Mvec.hpp\""
    scope="-DGB_REFERENCE_NAMESPACE="*namespace
    flags=scalar===Int64 ? ["-DGB_REFERENCE_INT64"] : String[]
    built=joinpath(directory,"building.so")
    _cpp_reference_command(`$cxx -std=c++17 -O3 -fno-fast-math -ffp-contract=off -fPIC -shared $header $scope $flags -I$headers -I$eigen_include $_CPP_REFERENCE_SOURCE -o $built`,log)
    mv(built,library)
    library
end

function _cpp_reference_oracle(f,result)
    if f.layout in (:vector,:aggregate)
        return result==vec(f.expected)
    elseif f.layout==:vectors
        return result==collect(eachcol(f.expected))
    end
    result==f.expected
end

function _cpp_reference_prepare(fixture,library_path,::Type{F}) where {F}
    offsets=Cint[0]
    masks=Cint[]
    values=F[]
    for operands in fixture.requests, terms in operands
        for (mask,value) in terms
            push!(masks,mask)
            push!(values,value)
        end
        push!(offsets,length(masks))
    end
    targets=Cint.(collect(fixture.targets))
    width=fixture.varying_outputs ? 1 : length(targets)
    arity=length(first(fixture.requests))
    library=Libdl.dlopen(library_path)
    try
        prepare=Libdl.dlsym(library,:gb_reference_prepare)
        execute=Libdl.dlsym(library,:gb_reference_execute)
        destroy=Libdl.dlsym(library,:gb_reference_destroy)
        batch=ccall(prepare,Ptr{Cvoid},(Ptr{Cint},Ptr{Cint},Ptr{F},Cint,Cint,Ptr{Cint},Cint,Cint,Cint,Cint),
            offsets,masks,values,length(fixture.requests),arity,targets,width,
            _CPP_REFERENCE_OPERATIONS[fixture.operation],fixture.layout==:aggregate,fixture.varying_outputs)
        batch==C_NULL && error("Garamon C++ could not prepare the benchmark operands")
        (;fixture,library,batch,execute,destroy,width)
    catch
        Libdl.dlclose(library)
        rethrow()
    end
end

_cpp_reference_execute(state)=_cpp_reference_execute(state,state.fixture.scalar)

function _cpp_reference_execute(state,::Type{F}) where {F}
    f=state.fixture
    columns=f.layout==:aggregate ? 1 : length(f.requests)
    output=Matrix{F}(undef,state.width,columns)
    ccall(state.execute,Cint,(Ptr{Cvoid},Ptr{F}),state.batch,output)==0 ||
        error("Garamon C++ could not execute the benchmark episode")
    f.layout in (:aggregate,:vector) && return vec(output)
    f.layout==:vectors && return [output[:,t] for t in axes(output,2)]
    if f.layout==:dictionaries
        return [Dict(mask=>output[i,t] for (i,mask) in enumerate(f.targets)
                     if !iszero(output[i,t])) for t in axes(output,2)]
    end
    output
end

function _cpp_reference_register(source,cache)
    kind=_CPP_REFERENCE_FIXTURES[source.name]
    register_adapter!(BenchmarkAdapter(name=_CPP_REFERENCE_ADAPTER,
        generate=(case,dir,rng)->begin
            original=_cpp_reference_original(case)
            fixture=source.generate(original,dir,rng)
            _cpp_reference_fixture(kind,fixture,case)
        end,
        build=(f,case,dir)->(;fixture=f,library=_cpp_reference_library(cache,f.diagonal,f.scalar)),
        prepare=(built,case,dir)->_cpp_reference_prepare(built.fixture,built.library,built.fixture.scalar),
        execute=_cpp_reference_execute,
        oracle=(state,result)->_cpp_reference_oracle(state.fixture,result),
        cleanup=state->begin
            ccall(state.destroy,Cvoid,(Ptr{Cvoid},),state.batch)
            Libdl.dlclose(state.library)
        end,
        diagnostics=(state,case,dir)->Dict("source_revision"=>CPP_SOURCE_REVISION,
            "original_case_id"=>case_id(_cpp_reference_original(case))),
        contract="Garamon C++ generated algebra; same operands, coefficients and independent oracle");
        replace=true)
end

_cpp_reference_root(archive,id) = joinpath(dirname(dirname(archive)),"cpp-reference",id)

function _cpp_reference_shards(config)
    reference=_cpp_reference_config(config)
    isnothing(reference) && return NamedTuple[]
    grid=reference["grid"]
    shards=NamedTuple[]
    for n in sort(get(grid,"dimension",Int[])), signature in get(grid,"signature",[""])
        2<=n<=_CPP_REFERENCE_MAX_DIMENSION || continue
        shard=deepcopy(reference)
        shard["grid"]["dimension"]=[n]
        haskey(grid,"signature") && (shard["grid"]["signature"]=[signature])
        count=length(expand_cases(shard))
        count==0 && continue
        name="n"*string(n)*(isempty(signature) ? "" : "-"*signature)
        push!(shards,(;name,config=shard,count))
    end
    shards
end

function _run_bounded_cpp_shard(row,shard,output,cache;allow_source_changes)
    # Large native products may stay inside one foreign call past the normal
    # Julia case guard. Keep that call in a process the worker can stop.
    code="""
    using GaramonBench, TOML
    config, adapter, output, cache, override = ARGS
    config=TOML.parse(config)
    GaramonBench.include_technique_adapter(adapter,config)
    source=GaramonBench.ADAPTERS[config["case_defaults"]["reference_adapter"]]
    Base.invokelatest(GaramonBench._cpp_reference_register,source,cache)
    Base.invokelatest(run_resumable_campaign,config;output,allow_source_changes=override=="true")
    """
    julia=joinpath(Sys.BINDIR,Base.julia_exename())
    project=dirname(Base.active_project())
    threads=string(Threads.nthreads())*",0"
    adapter=joinpath(dirname(@__DIR__),row["adapter"])
    config=canonical_toml(shard.config)
    token=get(ENV,"GARAMONBENCH_WORKER_TOKEN",string(uuid4()))
    command=`$julia --startup-file=no --threads=$threads --gcthreads=1 --project=$project -e $code $config $adapter $output $cache $(string(allow_source_changes))`
    child=run(ignorestatus(Cmd(addenv(command,"GARAMONBENCH_WORKER_TOKEN"=>token);detach=true));wait=false)
    pid=getpid(child)
    own_group=Sys.islinux() && pid>0 && ccall(:getpgid,Cint,(Cint,),pid)==pid
    journal=joinpath(output,"active-case.toml")
    heartbeat=stat(journal).mtime
    seconds=get(shard.config["limits"],"case_seconds",120)
    deadline=time()+max(120,seconds)
    try
        while process_running(child)
            sleep(0.25)
            stamp=stat(journal).mtime
            if stamp!=heartbeat
                heartbeat=stamp
                deadline=time()+seconds
            end
            time()<deadline || error("Garamon C++ exceeded the case time budget")
        end
        success(child) || error("Garamon C++ worker failed with exit "*string(child.exitcode))
    finally
        if process_running(child)
            own_group ? ccall(:kill,Cint,(Cint,Cint),-pid,9) : kill(child,Base.SIGKILL)
        end
        wait(child)
        _kill_detached_worker_processes(token)
    end
end

function _run_cpp_reference(row,config,archive,cache;allow_source_changes=false)
    shards=_cpp_reference_shards(config)
    isempty(shards) && return Dict("status"=>"no_matching_contract","validated_cases"=>0)
    source=ADAPTERS[config["case_defaults"]["adapter"]]
    _cpp_reference_register(source,cache)
    results=Dict{String,Any}[]
    for shard in shards
        output=joinpath(_cpp_reference_root(archive,row["id"]),shard.name)
        record=Dict{String,Any}("group"=>shard.name,"planned_cases"=>shard.count)
        try
            if only(shard.config["grid"]["dimension"])>=12 &&
                    !_completed_technique_archive(shard.config,output)
                _run_bounded_cpp_shard(row,shard,output,cache;allow_source_changes)
            else
                Base.invokelatest(run_resumable_campaign,shard.config;output,allow_source_changes)
            end
            record["status"]="complete"
        catch exception
            exception isa InterruptException && rethrow()
            record["status"]="incomplete"
            record["reason"]=failure_message(exception)
            @warn "Garamon C++ reference group incomplete" technique=row["id"] group=shard.name reason=record["reason"]
        end
        status=isfile(joinpath(output,"campaign.toml")) ?
            resumable_status(shard.config,output) : Dict("completed_ids"=>String[])
        record["validated_cases"]=length(status["completed_ids"])
        push!(results,record)
        println("Technique ",row["id"]," Garamon C++ ",shard.name,": ",
            record["validated_cases"],"/",shard.count," validated reference cases")
    end
    Dict("status"=>all(r->r["status"]=="complete",results) ? "complete" : "partial",
        "validated_cases"=>sum(r["validated_cases"] for r in results),"groups"=>results)
end
