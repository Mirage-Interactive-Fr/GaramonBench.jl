# ID28: one owned packed output produced in an actual Julia worker process.
# Reuses only the production process batch kernel and fixture construction;
# correctness is checked here with independent integer blade words.
pushfirst!(LOAD_PATH, get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")))
using Garamon, GaramonBench, Distributed, Random
const CP28_TARGET_ROOT = get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon"))
include(joinpath(CP28_TARGET_ROOT, "perf", "parallel_batches_common.jl"))

function cp28_word(a::BigInt,b::BigInt,n::Int)
    left = [i for i in 1:n if !iszero(a & (big(1) << (i-1)))]
    right = [i for i in 1:n if !iszero(b & (big(1) << (i-1)))]
    inversions = sum(count(j->j<i,right) for i in left;init=0)
    xor(a,b), isodd(inversions) ? Int64(-1) : Int64(1)
end

function cp28_expected(fixture,batch)
    n = fixture.n
    pairs = fixture.inputs
    structural = sort!(unique(BigInt[xor(BigInt(a),BigInt(b))
        for (left,right) in pairs for a in keys(left.values) for b in keys(right.values)]))
    sort!(BigInt.(fixture.plan.output_masks))==structural ||
        error("packed plan omits or adds structural output masks")
    positions = Dict(BigInt(mask)=>i for (i,mask) in enumerate(fixture.plan.output_masks))
    out = zeros(Int64,length(positions),batch)
    for t in 1:batch
        left,right = pairs[mod1(t,4)]
        for (a,x) in left.values, (b,y) in right.values
            isinteger(x) && isinteger(y) || error("noninteger process fixture")
            mask,sign = cp28_word(BigInt(a),BigInt(b),n)
            out[positions[mask],t] += sign*Int64(x)*Int64(y)
        end
    end
    out
end

function cp28_generate(case,directory,rng)
    case["dimension"]==4 || error("process preflight dimension budget")
    case["family"]=="sparse8" || error("process preflight family")
    case["strategy"]=="resident_process" || error("process preflight strategy")
    case["workers"]==1 || error("single worker required for minimal preflight")
    case["batch"]==4 || error("one cycle of four variants required")
    fixture = parallel_fixture(4,:sparse8)
    expected = cp28_expected(fixture,4)
    (;fixture,expected,batch=4)
end

function cp28_prepare(generated,case,directory)
    Sys.free_memory()>=1<<30 || error("process preflight memory admission")
    project = dirname(Base.active_project())
    pids = addprocs(1;exeflags=`--startup-file=no --threads=1,0 --gcthreads=1 --project=$project`,
        env=["OPENBLAS_NUM_THREADS"=>"1","JULIA_NUM_THREADS"=>"1,0"])
    try
        pid = only(pids)
        remotecall_wait(Core.eval,pid,Main,:(pushfirst!(LOAD_PATH,$CP28_TARGET_ROOT)))
        remotecall_wait(Base.include,pid,Main,
            joinpath(CP28_TARGET_ROOT,"perf","parallel_batches_common.jl"))
        # PerfChecker loads this adapter in a private SharedCase module. Sending
        # a function from that module to a fresh Distributed worker asks the
        # worker to deserialize a module it does not have. Evaluate the loaded
        # production entrypoint in the worker's Main instead.
        remotecall_fetch(Core.eval,pid,Main,:(parallel_remote_setup(4,:sparse8)))
        return (;generated,pid)
    catch
        rmprocs(pids)
        rethrow()
    end
end

function cp28_execute(state)
    batch=state.generated.batch
    remotecall_fetch(Core.eval,state.pid,Main,
        :((worker_id=Distributed.myid(),os_pid=getpid(),
            output=parallel_remote_chunk(1,$batch,nothing))))
end

function cp28_oracle(state,result)
    result.worker_id==state.pid && result.worker_id!=Distributed.myid() &&
        result.os_pid!=getpid() &&
        size(result.output)==size(state.generated.expected) &&
        result.output==state.generated.expected
end

function cp28_cleanup(state)
    state.pid in workers() || return nothing
    rmprocs(state.pid)
    state.pid in workers() && error("process preflight worker survived cleanup")
    nothing
end

register_adapter!(BenchmarkAdapter(name="garamon_cpu_processes",
    generate=cp28_generate,prepare=cp28_prepare,execute=cp28_execute,
    oracle=cp28_oracle,cleanup=cp28_cleanup,
    contract="owned Float64 packed coefficient matrix plus distinct worker identity",
    capabilities=Dict("exact_oracle"=>"independent Int64 Euclidean Clifford-word inversions",
        "execution"=>"one actual Distributed worker with resident workspace",
        "cleanup"=>"rmprocs in adapter cleanup, including failed setup",
        "scope"=>"one batch of four fixture variants, not process throughput",
        "generation_includes_oracle"=>true,"gpu_kernel"=>false));replace=true)
