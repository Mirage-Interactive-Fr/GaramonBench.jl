# PerfChecker worker bridge for oracle-preflight BenchmarkAdapter cases.
# Loading the adapter source retains its exact generate/build/prepare/execute/oracle
# callbacks. The timed operation calls adapter.execute on the prepared state.
pushfirst!(LOAD_PATH, dirname(dirname(@__DIR__)))
using GaramonBench, Random
# PerfChecker evaluates this bridge in a minimal isolated module. Adapters
# written as ordinary Julia files may use the module-local include shorthand.
if !isdefined(@__MODULE__, :include)
    include(path::AbstractString) = Base.include(@__MODULE__, path)
end

function make_case(parameters)
    case=parameters["case"]
    source=get(parameters,"adapter_source",nothing)
    source isa AbstractString && isfile(source) &&
        startswith(realpath(source),realpath(joinpath(@__DIR__,".."))*"/") ||
        error("profile adapter must be an existing GaramonBench adapter")
    repetitions=get(parameters,"episode_repetitions",1)
    repetitions isa Integer && !(repetitions isa Bool) && 1<=repetitions<=4096 ||
        error("episode repetition budget")
    Base.include(@__MODULE__,source)
    adapter=GaramonBench.ADAPTERS[case["adapter"]]
    make_case_with_adapter(adapter,case,repetitions)
end

# The registry intentionally accepts heterogeneous adapters. Cross that dynamic
# lookup once, outside the measured operation, so callback types are concrete.
function make_case_with_adapter(adapter::GaramonBench.BenchmarkAdapter,case,repetitions)
    prepare=()->begin
        directory=mktempdir()
        state=nothing
        try
            generated=adapter.generate(case,directory,Xoshiro(case["seed"]))
            built=adapter.build(generated,case,directory)
            state=adapter.prepare(built,case,directory)
            (;state,directory)
        catch
            try
                isnothing(state) || adapter.cleanup(state)
            finally
                rm(directory;recursive=true,force=true)
            end
            rethrow()
        end
    end
    operation=repetitions==1 ?
        (prepared->adapter.execute(prepared.state)) :
        (prepared->[adapter.execute(prepared.state) for _ in 1:repetitions])
    verify=repetitions==1 ?
        ((prepared,result)->adapter.oracle(prepared.state,result)===true) :
        ((prepared,results)->length(results)==repetitions &&
            all(result->adapter.oracle(prepared.state,result)===true,results))
    cleanup=prepared->try
        adapter.cleanup(prepared.state)
    finally
        rm(prepared.directory;recursive=true,force=true)
    end
    (;prepare,operation,verify,cleanup,adapter_execute=adapter.execute)
end
