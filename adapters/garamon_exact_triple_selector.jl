# The analytic, unfitted exact selector uses the independent Clifford-word
# oracle and fixtures from the selected triple-product adapter.
isdefined(@__MODULE__, :tj_generate) ||
    Base.include(@__MODULE__, joinpath(@__DIR__, "garamon_triple_join.jl"))

function ts_prepare(fixture,case,directory)
    fixture.strategy=="auto" || error("only the analytic auto selector is admitted")
    base=tj_prepare(merge(fixture,(strategy="direct",)),case,directory)
    (;base,selected=Ref{Symbol}(:none))
end

function ts_execute(state)
    base=state.base
    fixture=base.fixture
    selector=prepare_triple_selector(base.inputs[1]...,base.outputs;
        horizon=fixture.horizon,strategy=:auto)
    state.selected[]=selector.decision.strategy
    output=Matrix{Float64}(undef,length(fixture.targets),fixture.horizon)
    for t in 1:fixture.horizon
        values=run_selected_triple!(selector,base.inputs[t]...)
        for i in eachindex(values)
            output[i,t]=values[i]
        end
    end
    output
end

register_adapter!(BenchmarkAdapter(name="garamon_exact_triple_selector",
    generate=tj_generate,prepare=ts_prepare,execute=ts_execute,
    baseline_execute=state->tj_execute(state.base),
    baseline_name="garamon_julia_direct_nested_product",
    oracle=(state,result)->state.selected[] in
            (:full,:recursive,:join3,:prepared,:workspace) &&
        size(result)==size(state.base.fixture.expected) &&
        result==state.base.fixture.expected,
    contract="owned selected triple-product coefficients; analytic unfitted route selection included",
    capabilities=Dict("exact_oracle"=>"independent Int64 Clifford-word inversions",
        "selector"=>"analytic_v1_unfitted", "hpo_or_learning"=>false,
        "performance_scope"=>"feature extraction, selection, preparation and owned episode",
        "generation_includes_oracle"=>true));replace=true)
