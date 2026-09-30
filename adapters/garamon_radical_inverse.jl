# N03: exact diagonal-radical inverse. The oracle builds the full left-regular
# matrix by Chevalley word action and solves it by independent Gauss-Jordan.
module GaramonBenchN03
using Garamon
include(joinpath(get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")), "perf", "n03_radical.jl"))

function generate(case, directory, rng)
    case["dimension"] == 4 && case["radical_dimensions"] == 1 &&
        case["active_nonradical_coordinates"] == 2 &&
        case["metric_family"] == "signed" && case["phase"] == 1 &&
        case["strategy"] == "radical_series" ||
        throw(ArgumentError("outside bounded N03 preflight case"))
    input=n03_input(4,1,2,:signed,1,N03_Q)
    expected=n03_oracle_inverse(input.a,input.g)
    (;input,expected)
end

function execute(state)
    n03_inverse(state.input.a,state.input.g)
end

function baseline_execute(state)
    input=state.input
    gram=zeros(N03_Q,length(input.g),length(input.g))
    for i in eachindex(input.g)
        gram[i,i]=input.g[i]
    end
    ga=algebra(gram)
    a=multivector(ga,input.a;storage=:sparse)
    inverse=inv(a)
    Dict{UInt128,N03_Q}(UInt128(mask)=>N03_Q(value)
        for mask in 0:(1<<length(input.g))-1
        for value in (coefficient_mask(inverse,mask),) if !iszero(value))
end

function oracle(state,result)
    result isa Dict{UInt128,N03_Q} || return false
    result==state.expected &&
        n03_oracle_product(state.input.a,result,state.input.g)==n03_unit(N03_Q) &&
        n03_oracle_product(result,state.input.a,state.input.g)==n03_unit(N03_Q)
end
end

using GaramonBench
register_adapter!(BenchmarkAdapter(name="garamon_radical_inverse",
    generate=GaramonBenchN03.generate,execute=GaramonBenchN03.execute,
    baseline_execute=GaramonBenchN03.baseline_execute,
    baseline_name="garamon_julia_general_inverse",
    oracle=GaramonBenchN03.oracle,
    contract="owned exact rational inverse in a diagonal metric with one radical coordinate",
    capabilities=Dict("exact_oracle"=>"independent Chevalley word action and Gauss-Jordan",
        "metric"=>"diagonal signed with one zero diagonal coordinate",
        "radical_corank"=>1,"gpu_kernel"=>false));replace=true)
