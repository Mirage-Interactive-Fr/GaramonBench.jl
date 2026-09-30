const SOURCE_EXTENSIONS=Set([".jl",".toml",".cpp",".cc",".c",".hpp",".h",
    ".cmake",".md",".txt",".json",".yaml",".yml",".in",".conf",".cfg",".py"])
const EXCLUDED_COMPONENTS=Set([".git","build","results","outputs",
    "generated","generated_costs","long_horizon_results"])

"""The Garamon dependency actually resolved by Pkg, unless explicitly overridden."""
function garamon_source_root()
    if haskey(ENV,"GARAMON_JULIA_ROOT")
        root=abspath(expanduser(ENV["GARAMON_JULIA_ROOT"]))
        isfile(joinpath(root,"Project.toml")) || error("GARAMON_JULIA_ROOT is not a package root")
        return root
    end
    package_file=Base.find_package("Garamon")
    isnothing(package_file) && error("Garamon dependency is not installed")
    dirname(dirname(package_file))
end

function probe(command::Cmd; limit=20_000)
    try
        executable=Sys.which("timeout")
        command=isnothing(executable) ? command : `$executable 5s $command`
        value=read(pipeline(ignorestatus(command);stderr=devnull),String)
        return first(value,min(length(value),limit))
    catch error
        return "unavailable: "*string(typeof(error))
    end
end

function repository_files(root)
    files=String[]
    for (directory,subdirs,names) in walkdir(root)
        filter!(subdirs) do name
            name in EXCLUDED_COMPONENTS && return false
            # DoctorWatson output directories are measurements; other data
            # directories may contain source fixtures and remain fingerprinted.
            relpath(joinpath(directory,name),root) ∉
                (joinpath("data","garamonbench"),joinpath("data","processed"))
        end
        for name in names
            path=joinpath(directory,name)
            islink(path) && continue
            (splitext(name)[2] in SOURCE_EXTENSIONS || name in ("CMakeLists.txt","LICENSE") || startswith(name,"HOWTO-")) || continue
            push!(files,relpath(path,root))
        end
    end
    sort!(files)
end

"""Fingerprint selected source/config text, including untracked files.
Git identity supplements, and never replaces, the source-content fingerprint.
"""
function repository_identity(root; snapshot=nothing,max_bytes=64<<20)
    root=abspath(expanduser(root)); isdir(root) || error("repository missing: $root")
    files=repository_files(root)
    sum(filesize(joinpath(root,p)) for p in files;init=0)<=max_bytes || error("source snapshot budget")
    entries=Dict{String,Any}[]
    for relative in files
        path=joinpath(root,relative)
        digest=bytes2hex(open(sha256,path))
        push!(entries,Dict("path"=>relative,"sha256"=>digest,"bytes"=>filesize(path)))
        if !isnothing(snapshot)
            destination=joinpath(snapshot,relative); mkpath(dirname(destination))
            cp(path,destination;force=false)
        end
    end
    tag=Dict{String,Any}()
    head=strip(probe(`git -C $root rev-parse HEAD`))
    if occursin(r"^[0-9a-f]{40,64}$",head)
        DrWatson.tag!(tag;gitpath=root,storepatch=false,warn=false)
    else
        tag["status"]="no_commit_or_not_a_git_repository"
    end
    return Dict{String,Any}("root"=>root,"git_head"=>head,
        "git_remote"=>strip(probe(`git -C $root remote get-url origin`)),
        "git_status"=>probe(`git -C $root status --porcelain --untracked-files=normal`),
        "drwatson_tag"=>tag,"files"=>entries,
        "sha256"=>bytes2hex(sha256(canonical_toml(Dict("files"=>entries)))),
        "scope"=>"selected source/config/documentation text including untracked and C++ data templates; excludes generated/build/results and binaries",
        "snapshot_archived"=>!isnothing(snapshot))
end

read_optional(path)=isfile(path) ? read(path,String) : "unavailable"

failure_exit_codes(error)=error isa Base.ProcessFailedException ? [process.exitcode for process in error.procs] : Int[]
function failure_message(error)
    if error isa Base.ProcessFailedException
        return "external process failed; exit codes: "*join(failure_exit_codes(error),",")
    end
    text=sprint(showerror,error)
    occursin("setenv(",text) && return "external process error; inherited environment omitted"
    first(text,min(length(text),2000))
end

function machine_snapshot()
    cpu=Sys.cpu_info()
    affinity=filter(line->startswith(line,"Cpus_allowed_list") || startswith(line,"Mems_allowed_list"),
                    split(read_optional("/proc/self/status"),'\n'))
    return Dict{String,Any}(
        "utc"=>string(now(UTC)),"julia"=>string(VERSION),"kernel"=>string(Sys.KERNEL),
        "machine"=>Sys.MACHINE,"cpu_model"=>isempty(cpu) ? "unknown" : cpu[1].model,
        "logical_cpus"=>Sys.CPU_THREADS,"julia_default_threads"=>Threads.nthreads(:default),
        "julia_interactive_threads"=>Threads.nthreads(:interactive),
        "affinity"=>join(affinity,"\n"),"memory_total_bytes"=>Sys.total_memory(),
        "memory_free_bytes"=>Sys.free_memory(),"controller_maxrss_bytes"=>Sys.maxrss(),
        "loadavg"=>read_optional("/proc/loadavg"),"cpu_counters"=>read_optional("/proc/stat"),
        "memory_counters"=>read_optional("/proc/meminfo"),
        "process_activity"=>probe(`ps -eo pid,comm,pcpu,pmem --sort=-pcpu`;limit=8000),
        "cpu_topology"=>probe(`lscpu -e=CPU,CORE,SOCKET,NODE,ONLINE`),
        "gpu_driver_snapshot"=>probe(`nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,utilization.gpu,temperature.gpu --format=csv,noheader`),
        "gpu_kernel_status"=>"not_probed_by_metadata_collector",
        "cxx_version"=>probe(`c++ --version`),"cmake_version"=>probe(`cmake --version`),
        "git_version"=>probe(`git --version`),
        "thread_environment"=>Dict(key=>get(ENV,key,"unset") for key in
            ("JULIA_NUM_THREADS","JULIA_NUM_GC_THREADS","OPENBLAS_NUM_THREADS","OMP_NUM_THREADS")))
end

function package_versions()
    [Dict("uuid"=>string(uuid),"name"=>info.name,"version"=>string(info.version))
     for (uuid,info) in sort!(collect(Pkg.dependencies());by=x->string(first(x)))]
end

function tree_bytes(directory)
    sum(filesize(joinpath(root,name)) for (root,_,files) in walkdir(directory)
        for name in files if !islink(joinpath(root,name));init=0)
end

function with_build_directory(f::Function;parent=tempdir())
    mktempdir(f,parent;prefix="garamonbench-")
end

"""Archive a small textual result. Compiled objects and executable files are refused."""
function archive_file!(source,destination;max_bytes=64<<20)
    isfile(source) || error("artifact missing")
    splitext(source)[2] in (".csv",".toml",".json",".md",".txt") || error("archive only textual result formats")
    (filemode(source)&0o111)==0 || error("executable artifact refused")
    filesize(source)<=max_bytes || error("artifact budget")
    bytes=read(source); any(iszero,bytes) && error("binary artifact refused")
    mkpath(dirname(destination)); cp(source,destination;force=false)
    return Dict("path"=>basename(destination),"sha256"=>bytes2hex(sha256(bytes)),"bytes"=>length(bytes))
end
