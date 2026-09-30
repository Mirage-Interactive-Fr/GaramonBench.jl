# N04: exact rational scalar-square certificate in a nonorthogonal metric.
# The oracle uses antisymmetrized Chevalley vector action, independent of the
# production geometric product used to construct the certificate.
module GaramonBenchN04
include(joinpath(get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")), "perf", "n04_short_identity.jl"))

function generate(case, directory, rng)
    case["dimension"] == 3 && case["exponent"] == 3 &&
        case["horizon"] == 1 && case["metric_family"] == "general" &&
        case["shape"] == "simple_bivector" && case["changes"] == "stable" &&
        case["strategy"] == "certify_each" ||
        throw(ArgumentError("outside bounded N04 preflight case"))
    n04_fixture(3,3,1,:general,:simple_bivector,:stable)
end

function prepare(state,case,directory)
    certificate=n04_certify(state.g,first(state.inputs))
    certificate===nothing && error("N04 representative case must exercise certificate path")
    certificate.lambda==-3//4 || error("unexpected nonorthogonal bivector square")
    state
end

execute(state)=n04_episode(state,:certify_each;trace=true)

function oracle(state,result)
    result isa NamedTuple || return false
    result.certifications==1 && result.refusals==0 && result.reuse==0 &&
        n04_qualify(state,result.output) &&
        all(x->x isa N04Terms,result.output)
end
end

using GaramonBench
register_adapter!(BenchmarkAdapter(name="garamon_scalar_square_certificate",
    generate=GaramonBenchN04.generate,prepare=GaramonBenchN04.prepare,
    execute=GaramonBenchN04.execute,oracle=GaramonBenchN04.oracle,
    baseline_execute=state->GaramonBenchN04.n04_episode(state,:binary;trace=true),
    baseline_name="garamon_julia_binary_geometric_power",
    baseline_oracle=(state,result)->GaramonBenchN04.n04_qualify(state,result.output),
    contract="owned exact rational power and certificate-path counts for a nonorthogonal bivector",
    capabilities=Dict("exact_oracle"=>"antisymmetrized Chevalley vector action",
        "certificate"=>"full exact square, bound to metric and coefficients",
        "metric"=>"general symmetric rational with one off-diagonal entry",
        "gpu_kernel"=>false));replace=true)
