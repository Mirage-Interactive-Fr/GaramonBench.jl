# SharedScenarioRuntime loads this source into an isolated module.
# Only target dependencies are imported; the controller package is not loaded.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, Random
Base.include(@__MODULE__,joinpath(@__DIR__,"..","julia_products_kernels.jl"))

function make_case(parameters)
    case=parameters["case"]
    case["adapter"]=="garamon_julia" && case["family"]=="vectors" || error("only existing Julia vector cases supported")
    repetitions=get(parameters,"episode_repetitions",1)
    repetitions isa Integer && !(repetitions isa Bool) && 1<=repetitions<=4096 || error("episode repetition budget")
    operation=repetitions==1 ? gb_execute_vectors : state->[
        gb_execute_vectors(state) for _ in 1:repetitions]
    verify=repetitions==1 ?
        ((state,result)->size(result)==size(state.fixture.expected) && result==state.fixture.expected) :
        ((state,results)->length(results)==repetitions && all(result->
            size(result)==size(state.fixture.expected) && result==state.fixture.expected,results))
    (
        prepare=()->gb_prepare_vectors(gb_generate_vectors(case,"",Xoshiro(case["seed"])),case,""),
        operation=operation,
        verify=verify,
        cleanup=state->nothing,
    )
end
