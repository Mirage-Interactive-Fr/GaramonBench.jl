# N25 is deliberately approximate. A separate word-action implementation
# reproduces the seeded path sample; exhaustive first-step Bernoulli averaging
# verifies the Horvitz-Thompson expectation without relying on a lucky draw.
module GaramonBenchApproximateRoulette
using Random
include(joinpath(get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")),
    "perf","pruning_recurrences_common.jl"))
include("pruning_standard_baseline.jl")

function candidates(x,step)
    T=eltype(x)
    j=mod1(step,2)
    result=Tuple{Int,T}[]
    for left in (0,1<<(j-1)), right in 0:3
        left_indices=[i for i in 1:2 if !iszero(left & (1<<(i-1)))]
        right_indices=[i for i in 1:2 if !iszero(right & (1<<(i-1)))]
        inversions=sum((i>k for i in left_indices for k in right_indices);init=0)
        factor=isodd(inversions) ? -1 : 1
        for i in intersect(left_indices,right_indices)
            factor*=i==1 ? 1 : -1
        end
        weight=left==0 ? T(3//4) : T(1//4)
        value=T(1//2)*weight*factor*x[right+1]
        push!(result,(xor(left,right)+1,value))
    end
    result
end

function probability(text)
    parts=split(text,'/')
    length(parts)==2 || throw(ArgumentError("roulette probability must be a fraction"))
    p=parse(Int,parts[1])//parse(Int,parts[2])
    0<p<=1 || throw(ArgumentError("roulette probability must be in (0,1]"))
    p
end

function seeded_reference(initial,horizon,seed,p)
    x=Float64.(initial)
    rng=Xoshiro(seed)
    history=[copy(x)]
    kept=0;omitted=0
    scale=inv(Float64(p));cutoff=Float64(p)
    for step in 1:horizon
        output=zeros(Float64,4)
        for (index,value) in candidates(x,step)
            if rand(rng)<cutoff
                output[index]+=scale*value;kept+=1
            else
                omitted+=1
            end
        end
        output[1]+=Float64(1//65_536)
        x=output
        push!(history,copy(x))
    end
    (;history,kept,omitted)
end

function exhaustive_first_mean(initial,p)
    Q=Rational{BigInt}
    probability=Q(p)
    terms=candidates(Q.(initial),1)
    length(terms)==8 || error("N25 bounded first-step candidate count")
    average=fill(zero(Q),4)
    for pattern in 0:255
        output=fill(zero(Q),4)
        retained=count(path->!iszero(pattern & (1<<(path-1))),1:8)
        for (path,(index,value)) in enumerate(terms)
            !iszero(pattern & (1<<(path-1))) && (output[index]+=value/probability)
        end
        output[1]+=Q(1//65_536)
        weight=probability^retained*(1-probability)^(8-retained)
        average .+= weight.*output
    end
    average
end

function errors(history,exact)
    residuals=[maximum(abs.(BigFloat.(history[t]).-BigFloat.(exact[t])))
               for t in eachindex(history)]
    final=last(residuals)
    scale=maximum(abs,BigFloat.(last(exact)))
    (;final_abs_error=Float64(final),max_abs_error=Float64(maximum(residuals)),
        final_relative_error=Float64(final/max(scale,big"1e-100")))
end

function generate(case,directory,rng)
    case["dimension"]==2 && case["signature"]=="indefinite" &&
        case["regime"]=="contracting" && case["recurrence"]=="affine" &&
        case["horizon"]==2 && case["strategy"]=="roulette" ||
        throw(ArgumentError("outside bounded N25 preflight case"))
    fixture=pruning_fixture(2,:indefinite,:contracting,:affine,2)
    exact=pruning_oracle(fixture)
    p=probability(case["survival_probability"])
    exhaustive_first_mean(fixture.initial,p)==exact[2] ||
        error("N25 Horvitz-Thompson first-step expectation is not exact")
    (;fixture,exact,p,scenario_seed=case["seed"],draw_seed=case["draw_seed"])
end

function execute(state)
    run=pruning_run(state.fixture,:roulette,Float64;
        seed=state.draw_seed,record=true,survival_probability=state.p,
        measure_buffers=false)
    (;history=run.history,value=run.value,
        counts=(;candidates=run.counts.candidates,kept=run.counts.kept,
            omitted=run.counts.omitted))
end

function oracle(state,result)
    result isa NamedTuple || return false
    reference=seeded_reference(state.fixture.initial,state.fixture.horizon,state.draw_seed,state.p)
    expected_errors=errors(reference.history,state.exact)
    observed_errors=errors(result.history,state.exact)
    result.history==reference.history && result.value==last(reference.history) &&
        observed_errors==expected_errors &&
        all(isfinite,Tuple(observed_errors)) &&
        result.counts.candidates==16 &&
        result.counts.kept==reference.kept && result.counts.omitted==reference.omitted &&
        (state.p!=1 || observed_errors.final_abs_error==0) &&
        exhaustive_first_mean(state.fixture.initial,state.p)==state.exact[2]
end
end

using GaramonBench
register_adapter!(BenchmarkAdapter(name="garamon_approximate_roulette",
    generate=GaramonBenchApproximateRoulette.generate,
    execute=GaramonBenchApproximateRoulette.execute,
    baseline_execute=state->GaramonBenchApproximateRoulette.standard_pruning_history(state.fixture),
    baseline_name="garamon_julia_full_exact_recurrence",
    baseline_oracle=(state,result)->result==state.exact,
    oracle=GaramonBenchApproximateRoulette.oracle,
    preflight_evidence=(state,result)->begin
        metrics=GaramonBenchApproximateRoulette.errors(result.history,state.exact)
        Dict(
        "contract"=>"approximate", "scenario_seed"=>state.scenario_seed,
        "draw_seed"=>state.draw_seed,
        "survival_probability"=>string(state.p),
        "final_abs_error"=>metrics.final_abs_error,
        "max_abs_error"=>metrics.max_abs_error,
        "final_relative_error"=>metrics.final_relative_error,
        "candidates"=>result.counts.candidates,"kept"=>result.counts.kept,
        "omitted"=>result.counts.omitted,
        "first_step_expectation_exact"=>true)
    end,
    contract="owned seeded Float64 trajectory; error audited outside timed kernel; approximate, never exact",
    capabilities=Dict("correctness_contract"=>"approximate",
        "independent_oracle"=>"rewritten seeded Clifford word action and exhaustive first-step expectation",
        "error_reporting"=>"final absolute, maximal absolute, final relative outside timed operation",
        "roulette"=>"independent Bernoulli(p), Horvitz-Thompson factor 1/p",
        "gpu_kernel"=>false));replace=true)
