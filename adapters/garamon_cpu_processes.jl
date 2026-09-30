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
    2<=case["dimension"]<=128 || error("process dimension budget")
    case["family"] in ("sparse8","subalgebra64") || error("process family")
    case["strategy"]=="resident_process" || error("process preflight strategy")
    case["workers"] in (1,2,4) || error("process worker budget")
    case["batch"] in (4,16,64,256) || error("process batch budget")
    fixture = parallel_fixture(case["dimension"],Symbol(case["family"]))
    parallel_admission(fixture,case["batch"])=="admitted" || error("process batch memory/path admission")
    expected = cp28_expected(fixture,case["batch"])
    (;fixture,expected,batch=case["batch"],workers=case["workers"])
end

function cp28_prepare(generated,case,directory)
    Sys.free_memory()>=1<<30 || error("process preflight memory admission")
    project = dirname(Base.active_project())
    pids = addprocs(generated.workers;exeflags=`--startup-file=no --threads=1,0 --gcthreads=1 --project=$project`,
        env=["OPENBLAS_NUM_THREADS"=>"1","JULIA_NUM_THREADS"=>"1,0"])
    try
        for pid in pids
            remotecall_wait(Core.eval,pid,Main,:(pushfirst!(LOAD_PATH,$CP28_TARGET_ROOT)))
            remotecall_wait(Base.include,pid,Main,
                joinpath(CP28_TARGET_ROOT,"perf","parallel_batches_common.jl"))
        # PerfChecker loads this adapter in a private SharedCase module. Sending
        # a function from that module to a fresh Distributed worker asks the
        # worker to deserialize a module it does not have. Evaluate the loaded
        # production entrypoint in the worker's Main instead.
            n=generated.fixture.n;family=generated.fixture.family
            remotecall_fetch(Core.eval,pid,Main,:(parallel_remote_setup($n,$(QuoteNode(family)))))
        end
        return (;generated,pid=first(pids),pids)
    catch
        rmprocs(pids)
        rethrow()
    end
end

function cp28_execute(state)
    batch=state.generated.batch
    ranges=parallel_ranges(batch,length(state.pids))
    jobs=map(zip(state.pids,ranges)) do (pid,(first_job,count))
        remotecall(Core.eval,pid,Main,
            :((worker_id=Distributed.myid(),os_pid=getpid(),
                output=parallel_remote_chunk($first_job,$count,nothing))))
    end
    results=fetch.(jobs)
    (;worker_id=first(results).worker_id,os_pid=first(results).os_pid,
        worker_ids=[r.worker_id for r in results],os_pids=[r.os_pid for r in results],
        output=reduce(hcat,[r.output for r in results]))
end

function cp28_oracle(state,result)
    result.worker_id==state.pid && result.worker_id!=Distributed.myid() &&
        result.os_pid!=getpid() &&
        result.worker_ids==state.pids && all(!=(getpid()),result.os_pids) &&
        size(result.output)==size(state.generated.expected) &&
        result.output==state.generated.expected
end

function cp28_baseline_execute(state)
    fixture=state.generated.fixture
    batch=state.generated.batch
    output=Matrix{Float64}(undef,length(fixture.plan.output_masks),batch)
    for t in 1:batch
        product=geometric_product(fixture.inputs[mod1(t,4)]...)
        for (i,mask) in enumerate(fixture.plan.output_masks)
            output[i,t]=coefficient_mask(product,mask)
        end
    end
    (;output)
end

function cp28_cleanup(state)
    live=intersect(state.pids,workers())
    isempty(live) || rmprocs(live)
    isempty(intersect(state.pids,workers())) || error("process worker survived cleanup")
    nothing
end

register_adapter!(BenchmarkAdapter(name="garamon_cpu_processes",
    generate=cp28_generate,prepare=cp28_prepare,execute=cp28_execute,
    oracle=cp28_oracle,cleanup=cp28_cleanup,
    baseline_execute=cp28_baseline_execute,
    baseline_name="garamon_julia_direct_geometric_product_batch",
    baseline_oracle=(state,result)->result.output==state.generated.expected,
    contract="owned Float64 packed coefficient matrix plus distinct worker identity",
    capabilities=Dict("exact_oracle"=>"independent Int64 Euclidean Clifford-word inversions",
        "execution"=>"one, two or four actual Distributed workers with private resident workspaces",
        "cleanup"=>"rmprocs in adapter cleanup, including failed setup",
        "scope"=>"partitioned batches of 4,16,64,256 jobs cycling four seeded fixture variants",
        "generation_includes_oracle"=>true,"gpu_kernel"=>false));replace=true)
