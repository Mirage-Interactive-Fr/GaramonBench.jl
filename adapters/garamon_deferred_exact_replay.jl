# N24 preflight: two exact reconstruction paths, checked against a separate
# rational oracle that enumerates ambient basis words instead of path tables.
module GaramonBenchDeferredReplay
include(joinpath(get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")),
    "perf","pruning_recurrences_common.jl"))

function generate(case,directory,rng)
    case["dimension"]==2 && case["signature"]=="positive" &&
        case["regime"]=="contracting" && case["recurrence"]=="bilinear" &&
        case["horizon"]==2 && case["strategy"]=="deferred_and_replay" ||
        throw(ArgumentError("outside bounded N24 preflight case"))
    fixture=pruning_fixture(2,:positive,:contracting,:bilinear,2)
    oracle=pruning_oracle(fixture)
    # This is a cross-check of the independent oracle, not the assertion used
    # to qualify the deferred and replay algorithms below.
    pruning_run(fixture,:exact,Rational{BigInt};record=true).history==oracle ||
        error("N24 independent rational oracle mismatch")
    (;fixture,oracle)
end

function execute(state)
    deferred=pruning_run(state.fixture,:deferred,Rational{BigInt};
        record=true,measure_buffers=false)
    replay=pruning_run(state.fixture,:replay,Rational{BigInt};
        record=true,measure_buffers=false)
    (;deferred,replay)
end

function oracle(state,result)
    result isa NamedTuple || return false
    expected=last(state.oracle)
    all(run->run.value==expected && last(run.history)==expected &&
        run.counts.omitted>0 && run.counts.corrections==1,
        (result.deferred,result.replay)) &&
        result.deferred.counts.correction_paths>0 &&
        result.replay.counts.replay_paths>0
end
end

using GaramonBench
register_adapter!(BenchmarkAdapter(name="garamon_deferred_exact_replay",
    generate=GaramonBenchDeferredReplay.generate,
    execute=GaramonBenchDeferredReplay.execute,
    oracle=GaramonBenchDeferredReplay.oracle,
    preflight_evidence=(state,result)->Dict(
        "contract"=>"exact_after_terminal_checkpoint",
        "deferred_omitted_paths"=>result.deferred.counts.omitted,
        "deferred_correction_paths"=>result.deferred.counts.correction_paths,
        "replay_omitted_paths"=>result.replay.counts.omitted,
        "replay_paths"=>result.replay.counts.replay_paths),
    contract="two owned Rational{BigInt} restored final trajectories, deferred correction and exact replay",
    capabilities=Dict("exact_oracle"=>"independent ambient basis-word rational recurrence",
        "methods"=>"deferred,replay", "recurrence"=>"bilinear with quadratic error transport",
        "restoration"=>"exact after terminal checkpoint", "gpu_kernel"=>false));replace=true)
