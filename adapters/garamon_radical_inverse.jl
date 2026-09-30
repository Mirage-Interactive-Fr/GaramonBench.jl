# N03: exact diagonal-radical inverse. The oracle builds the full left-regular
# matrix by Chevalley word action and solves it by independent Gauss-Jordan.
module GaramonBenchN03
using Garamon
include(joinpath(get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")), "perf", "n03_radical.jl"))

function generate(case, directory, rng)
    2<=case["dimension"]<=128 && case["strategy"] == "radical_series" ||
        throw(ArgumentError("outside bounded N03 campaign domain"))
    input=n03_input(case["dimension"],case["radical_dimensions"],
        case["active_nonradical_coordinates"],Symbol(case["metric_family"]),case["phase"],N03_Q)
    expected=n03_oracle_inverse(input.a,input.g)
    (;input,expected)
end

function execute(state)
    n03_inverse(state.input.a,state.input.g)
end

function baseline_execute(state)
    input=state.input
    # Ordinary inv supports at most five coordinates. In larger ambient
    # dimensions use the exactly isomorphic active coordinate subalgebra;
    # unused axes cannot contribute. No radical-series algorithm is used.
    axes=length(input.g)<=5 ? collect(eachindex(input.g)) :
        [i for i in eachindex(input.g) if any(mask->!iszero(mask&n03_bit(i)),keys(input.a))]
    length(axes)<=5 || throw(ArgumentError("ordinary inverse active-coordinate budget"))
    gram=zeros(N03_Q,length(axes),length(axes))
    for (j,i) in enumerate(axes)
        gram[j,j]=input.g[i]
    end
    ga=algebra(gram)
    reduced=Dict(foldl(|,(n03_bit(j) for (j,i) in enumerate(axes) if !iszero(mask&n03_bit(i)));init=UInt128(0))=>value for (mask,value) in input.a)
    a=multivector(ga,reduced;storage=:sparse)
    inverse=inv(a)
    Dict{UInt128,N03_Q}(foldl(|,(n03_bit(i) for (j,i) in enumerate(axes) if !iszero(mask&n03_bit(j)));init=UInt128(0))=>N03_Q(value)
        for (mask,value) in sparse(inverse).values if !iszero(value))
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
    contract="owned exact rational inverse in a diagonal metric with one or two radical coordinates",
    capabilities=Dict("exact_oracle"=>"independent Chevalley word action and Gauss-Jordan",
        "metric"=>"diagonal positive or signed nonradical part and exact zero radical coordinates",
        "baseline_scope"=>"ordinary inverse in the complete active coordinate subalgebra, at most five axes",
        "gpu_kernel"=>false));replace=true)
