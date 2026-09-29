# Loaded explicitly by the resumable controller under the pinned gpu/ project.
# The target's integer word oracle is independent of CPU and CUDA kernels.
using GaramonBench, CUDA, Garamon

const GB_GPU_TARGET=get(ENV,"GARAMON_JULIA_ROOT",joinpath(homedir(),".julia","dev","Garamon"))
include(joinpath(GB_GPU_TARGET,"perf","gpu_packed_compare.jl"))

function gb_gpu_case(case)
    n=case["dimension"]
    family=Symbol(case["family"])
    signature=Symbol(case["signature"])
    horizon=case["horizon"]
    strategy=case["strategy"]
    n isa Integer && 2<=n<=128 || error("GPU packed preflight dimension outside UInt128 domain")
    family in (:low_rank_high_grade,:higher_rank) || error("unsupported GPU fixture family")
    signature in (:positive,:mixed,:degenerate) || error("unsupported GPU fixture signature")
    horizon isa Integer && 1<=horizon<=8192 || error("GPU packed preflight horizon budget")
    strategy in ("cpu_packed","gpu_host_owned") || error("unsupported GPU packed route")
    strategy=="gpu_host_owned" && !CUDA.functional() &&
        error("GPU route unavailable: CUDA.functional() is false")
    compact_fixture(n,family,signature)
end

GaramonBench.register_adapter!(GaramonBench.BenchmarkAdapter(
    name="gpu_packed_exact",
    contract="same diagonal-metric packed plan and ordered Float64 host-owned output; independent Int64 word oracle",
    generate=(case,directory,rng)->gb_gpu_case(case),
    build=(fixture,case,directory)->(;fixture,batch=gpu_make_batch(fixture,case["horizon"])),
    prepare=(built,case,directory)->begin
        resident=case["strategy"]=="gpu_host_owned" ?
            gpu_resident_batch(built.batch;max_bytes=512<<20) : nothing
        (;built...,resident,strategy=case["strategy"],horizon=case["horizon"])
    end,
    execute=state->state.strategy=="gpu_host_owned" ?
        gpu_owned_matrix(state.resident) : run_packed_batch(state.batch),
    oracle=(state,result)->gpu_exact_oracle(
        state.fixture,state.batch,result,state.horizon),
    cleanup=state->begin
        state.resident===nothing || CUDA.synchronize()
        nothing
    end,
    diagnostics=(state,case,directory)->begin
        state.strategy=="gpu_host_owned" ||
            return Dict("status"=>"not_applicable_cpu_route")
        free_before=CUDA.free_memory()
        phases=(
            ("device_kernel_reused_output",()->gpu_run!(state.resident)),
            ("resident_to_host_owned",()->gpu_owned_matrix(state.resident)),
            ("complete_episode",()->gpu_complete_matrix(state.batch;max_bytes=512<<20)))
        records=Dict{String,Any}[]
        for (phase,operation) in phases
            file=joinpath(directory,"gpu-"*phase*".txt")
            before=CUDA.free_memory()
            open(file,"w") do io
                profile=CUDA.@profile trace=true operation()
                show(io,MIME"text/plain"(),profile)
                println(io)
            end
            after=CUDA.free_memory()
            observed=phase=="device_kernel_reused_output" ?
                Array(gpu_run!(state.resident)) : operation()
            gpu_exact_oracle(state.fixture,state.batch,observed,state.horizon) ||
                error("GPU diagnostic phase failed independent oracle: "*phase)
            push!(records,Dict("phase"=>phase,"trace"=>basename(file),
                "free_vram_before_bytes"=>before,"free_vram_after_bytes"=>after,
                "free_vram_semantics"=>"snapshots; not a peak allocation metric"))
        end
        Dict("status"=>"captured_and_oracle_checked","profiler"=>"CUDA.@profile_CUPTI",
            "free_vram_before_diagnostics_bytes"=>free_before,
            "free_vram_after_diagnostics_bytes"=>CUDA.free_memory(),
            "phases"=>records)
    end,
    capabilities=Dict("scientific_garamon_result"=>true,
        "cuda_required_for"=>"gpu_host_owned",
        "gpu_output"=>"synchronized_and_host_owned",
        "oracle"=>"independent_Int64_ordered_word",
        "gpu_vram_metrics"=>"free_memory_snapshots_not_peak",
        "gpu_kernel_transfer_breakdown"=>"CUDA_CUPTI_trace_text_for_three_phases")))
