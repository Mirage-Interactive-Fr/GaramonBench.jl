# N04: exact rational scalar-square certificate in a nonorthogonal metric.
# The oracle uses antisymmetrized Chevalley vector action, independent of the
# production geometric product used to construct the certificate.
module GaramonBenchN04
include(joinpath(get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")), "perf", "n04_short_identity.jl"))

function generate(case, directory, rng)
    case["strategy"] == "certify_each" || throw(ArgumentError("N04 strategy"))
    n04_fixture(case["dimension"],case["exponent"],case["horizon"],
        Symbol(case["metric_family"]),Symbol(case["shape"]),Symbol(case["changes"]))
end

function prepare(state,case,directory)
    certificate=n04_certify(state.g,first(state.inputs))
    # Refused certificates take the exact binary-power fallback.
    state
end

execute(state)=n04_episode(state,:certify_each;trace=true)

function oracle(state,result)
    result isa NamedTuple || return false
    result.certifications==state.H && result.refusals>=0 && result.reuse==0 &&
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
