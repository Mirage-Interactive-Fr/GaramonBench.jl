# Native PerfChecker scenario for the experimental B1W implementation.
# The fixture and independent word oracle are outside every timed operation.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, LinearAlgebra
Base.include(@__MODULE__,joinpath(get(ENV,"GARAMON_JULIA_ROOT",joinpath(homedir(),".julia","dev","Garamon")),
                              "perf","bounds_b1.jl"))
using .BoundsB1Prototype

function b1w_word_oracle(a,b,diagonal)
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

function b1w_fixture(case)
    n=case["dimension"];K=n<=64 ? UInt64 : UInt128
    full=K((big(1)<<n)-1)
    masks=case["family"]=="low_grade" ? K[0,1,2,3] : unique(K[0,1,full,full⊻K(1)])
    diagonal=ones(Int64,n)
    case["signature"]=="mixed" && (diagonal[2:2:n].=-1)
    case["signature"]=="degenerate" && (diagonal[1]=0)
    ga=algebra(Diagonal(Float64.(diagonal)))
    coefficients=(-2.0,-1.0,1.0,2.0)
    inputs=[(multivector(ga,Dict(m=>coefficients[mod1(i+p,4)] for (i,m) in enumerate(masks));storage=:sparse),
             multivector(ga,Dict(m=>coefficients[mod1(2i+p,4)] for (i,m) in enumerate(masks));storage=:sparse)) for p in 1:4]
    expected=[b1w_word_oracle(a,b,diagonal) for (a,b) in inputs]
    (;inputs,expected)
end

function b1w_build(fixture,strategy)
    pair=fixture.inputs[1]
    strategy in ("workspace_native","workspace_native_singlepass") ? b1_workspace(pair...) :
        b1_workspace(prepare_product(pair...),pair...)
end

function b1w_evaluate(workspace,pair,strategy)
    strategy=="workspace_native_singlepass" ? b1_workspace_product_singlepass!(workspace,pair...) :
        b1_workspace_product!(workspace,pair...)
end

function b1w_run_episode(fixture,strategy,horizon)
    workspace=b1w_build(fixture,strategy)
    [b1w_evaluate(workspace,fixture.inputs[mod1(i,4)],strategy) for i in 1:horizon]
end

function b1w_verify_outputs(fixture,outputs,horizon)
    length(outputs)==horizon &&
        length(unique(objectid(output.values) for output in outputs))==horizon &&
        all(outputs[i].values==fixture.expected[mod1(i,4)] for i in 1:horizon)
end

function make_case(parameters)
    case=parameters["case"]
    case["adapter"]=="bounds_b1w" || error("B1W profiling adapter required")
    repetitions=get(parameters,"episode_repetitions",1)
    repetitions isa Integer && !(repetitions isa Bool) && 1<=repetitions<=4096 ||
        error("B1W profiling repetition budget")
    phase=case["phase"];strategy=case["strategy"];horizon=case["horizon"]
    phase in ("build","hot","episode") && strategy in ("workspace","workspace_native","workspace_native_singlepass") ||
        error("unsupported B1W phase or strategy")
    fixture=b1w_fixture(case)
    prepare=()->(;fixture,workspace=phase=="hot" ? b1w_build(fixture,strategy) : nothing)
    single=phase=="build" ? state->b1w_build(state.fixture,strategy) :
        phase=="hot" ? state->b1w_evaluate(state.workspace,state.fixture.inputs[1],strategy) :
        state->b1w_run_episode(state.fixture,strategy,horizon)
    verify_one=phase=="build" ? ((state,workspace)->
        b1_workspace_product!(workspace,state.fixture.inputs[1]...).values==state.fixture.expected[1]) :
        phase=="hot" ? ((state,output)->output.values==state.fixture.expected[1]) :
        ((state,outputs)->b1w_verify_outputs(state.fixture,outputs,horizon))
    operation=repetitions==1 ? single : state->[single(state) for _ in 1:repetitions]
    verify=repetitions==1 ? verify_one : ((state,results)->
        length(results)==repetitions && all(result->verify_one(state,result),results))
    (;prepare,operation,verify,cleanup=state->nothing)
end
