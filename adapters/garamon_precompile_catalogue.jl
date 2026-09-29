# One native catalogue cache, one package load/JIT, then exact execution.
pushfirst!(LOAD_PATH, get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")))
using GaramonBench, Garamon, Random, SHA
include(joinpath(get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")),
    "perf", "precompile_lifecycle.jl"))

function pc15_reference()
    # EGA3 known catalogue input, duplicated independently of the kernel.
    left = UInt64.(0:7)
    right = UInt64.(0:7)
    expected = zeros(Int64, 8)
    for (ai, a) in enumerate(left), (bi, b) in enumerate(right)
        inversions = count(i > j for i in 1:3 for j in 1:3
            if !iszero(a & (UInt64(1) << (i-1))) &&
               !iszero(b & (UInt64(1) << (j-1))))
        sign = isodd(inversions) ? -1 : 1
        expected[Int(xor(a, b))+1] += sign *
            (1 + mod(ai, 3)) * (1 + mod(2bi, 3))
    end
    expected
end

function pc15_cache_map(depot)
    result = Dict{String,String}()
    directory = joinpath(depot, "compiled")
    isdir(directory) || return result
    for (root, _, files) in walkdir(directory), file in files
        path = joinpath(root, file)
        (endswith(file, ".ji") || endswith(file, ".so")) || continue
        result[relpath(path, depot)] = bytes2hex(sha256(read(path)))
    end
    result
end

function pc15_generate(case, directory, rng)
    case["dimension"] == 3 && case["scenario"] == "known" &&
        case["strategy"] == "generated" ||
        error("precompilation catalogue smoke contract")
    environment = lifecycle_environment(joinpath(directory, "catalogue"), true)
    (; environment, expected=pc15_reference())
end

function pc15_build(generated, case, directory)
    environment = generated.environment
    expression = "Base.compilecache(Base.identify_package(\"GaramonLifecycle\"))"
    command = `$(Base.julia_cmd()) --startup-file=no --threads=1 --pkgimages=yes --project=$(environment.package) -e $expression`
    error_log = joinpath(directory, "precompile-stderr.txt")
    try
        open(error_log, "w") do io
            run(pipeline(addenv(command, environment.env); stdout=devnull, stderr=io))
        end
    catch
        error("catalogue precompilation failed: " * read(error_log, String))
    end
    cache = lifecycle_cache_info(environment.depot)
    harness_native = any(occursin("GaramonLifecycle", joinpath(root, name)) &&
        any(extension -> endswith(name, extension), (".so", ".dylib", ".dll"))
        for (root, _, names) in walkdir(joinpath(
            environment.depot, "compiled")) for name in names)
    cache.files > 0 && cache.harness_bytes > 0 && harness_native ||
        error("catalogue precompilation did not create a native package cache")
    (; generated..., cache_before_load=cache,
      cache_map_before_load=pc15_cache_map(environment.depot), code_precompiled=true)
end

function pc15_prepare(built, case, directory)
    environment = built.environment
    # The resident child uses the same Julia options as compilecache. READY is
    # emitted after load, plan/artifact construction and explicit JIT, before
    # any product execution; RUN requests are sent by execute(state).
    expression = """
        using GaramonLifecycle
        fixture = GaramonLifecycle.lifecycle_fixture(0)
        plan = GaramonLifecycle.lifecycle_plan(fixture)
        artifact = GaramonLifecycle.lifecycle_artifact(plan, fixture, :generated)
        ready = precompile(GaramonLifecycle.lifecycle_execute,
            (typeof(artifact), typeof(fixture), Symbol))
        println("READY ", ready)
        flush(stdout)
        for request in eachline(stdin)
            request == "RUN" || error("unknown catalogue worker request")
            result = GaramonLifecycle.lifecycle_execute(artifact, fixture, :generated)
            output = zeros(Float64, 8)
            for (mask, value) in result.values
                output[Int(mask)+1] = value
            end
            println(join(output, ','))
            flush(stdout)
        end
        """
    command = `$(Base.julia_cmd()) --startup-file=no --threads=1 --compiled-modules=yes --pkgimages=yes --project=$(environment.package) -e $expression`
    process = open(addenv(command, environment.env), "r+")
    try
        readiness = readline(process)
        readiness == "READY true" || error("catalogue worker failed to load/JIT: " * readiness)
        cache_after_load = lifecycle_cache_info(environment.depot)
        built.cache_before_load.digest == cache_after_load.digest ||
            error("loading/JIT changed the disk precompilation cache: " *
                string([key for key in union(keys(built.cache_map_before_load),
                    keys(pc15_cache_map(environment.depot))) if
                    get(built.cache_map_before_load, key, "") !=
                    get(pc15_cache_map(environment.depot), key, "")]))
        return (; built..., process, package_loaded=true, method_ready=true,
          cache_after_load)
    catch
        close(process)
        rethrow()
    end
end

function pc15_execute(state)
    println(state.process, "RUN")
    flush(state.process)
    output = parse.(Float64, split(readline(state.process), ','))
    lifecycle_cache_info(state.environment.depot).digest ==
        state.cache_after_load.digest ||
        error("execution modified the disk precompilation cache")
    output
end

pc15_cleanup(state) = close(state.process)

function pc15_oracle(state, result)
    state.code_precompiled && state.package_loaded && state.method_ready &&
        state.cache_before_load.digest == state.cache_after_load.digest &&
        result == state.expected
end

register_adapter!(BenchmarkAdapter(name="garamon_precompile_catalogue",
    generate=pc15_generate, build=pc15_build, prepare=pc15_prepare,
    execute=pc15_execute, oracle=pc15_oracle, cleanup=pc15_cleanup,
    contract="owned Float64 vector of all EGA3 generated-product coefficients",
    capabilities=Dict("exact_oracle"=>"independent Int64 Clifford-word inversions",
        "precompilation"=>"native catalogue cache in disposable isolated depot",
        "loading_jit"=>"Base.require plus explicit generated-execution specialization",
        "execution"=>"separate generated-product call; no performance samples",
        "generation_includes_oracle"=>true, "gpu_kernel"=>false)); replace=true)
