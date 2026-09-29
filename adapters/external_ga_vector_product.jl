haskey(ENV, "GARAMON_JULIA_ROOT") &&
    pushfirst!(LOAD_PATH, expanduser(ENV["GARAMON_JULIA_ROOT"]))
using Garamon, Libdl, Random

include("julia_products_kernels.jl")

const GB_EXTERNAL_VECTOR_SOURCE = joinpath(@__DIR__, "external_ga", "vector_product.cpp")

function gb_external_vector_generate(case, directory, rng)
    case["dimension"] == 3 || error("GAL/Versor vector-product comparison admits EGA3 only")
    case["family"] == "vectors" || error("comparison requires vector inputs")
    case["signature"] == "positive" || error("comparison requires Euclidean metric")
    case["strategy"] in ("garamon_packed", "gal", "versor") || error("unknown library")
    1 <= case["horizon"] <= 10_000 || error("horizon budget")
    fixture_case = copy(case)
    fixture_case["strategy"] = case["strategy"] == "garamon_packed" ? "packed" : "direct"
    gb_generate_vectors(fixture_case, directory, rng)
end

function gb_external_vector_build(fixture, case, directory)
    route = case["strategy"]
    route == "garamon_packed" && return (;fixture, route, library_path=nothing,
        source_revision="local_Garamon_jl")
    root = GaramonBench.ensure_external_ga_source(route)
    include_dir = joinpath(root, route == "gal" ? "public" : "include")
    marker = joinpath(include_dir, route == "gal" ? "gal/vga.hpp" : "vsr/vsr.h")
    isfile(marker) || error("external library header missing")
    compiler = GaramonBench.cpp_toolchain().cxx
    definition = route == "gal" ? "-DGB_GAL" : "-DGB_VERSOR"
    library_path = joinpath(directory, "libgb_" * route * ".so")
    command = `$compiler -std=c++17 -O3 -fno-fast-math -ffp-contract=off -Wno-deprecated-literal-operator -fPIC -shared $definition -I$include_dir $GB_EXTERNAL_VECTOR_SOURCE -o $library_path`
    run(addenv(command, GaramonBench.cpp_toolchain_environment()...))
    revision = only(row["revision"] for row in GaramonBench.external_ga_candidates()
        if row["name"] == route)
    (;fixture, route, library_path, source_revision=revision)
end

function gb_external_vector_prepare(built, case, directory)
    f = built.fixture
    if built.route == "garamon_packed"
        julia_state = gb_prepare_vectors(f, case, directory)
        return (;built..., julia_state, library=nothing, product=C_NULL,
            left=nothing, right=nothing)
    end
    left = Matrix{Float64}(undef, 3, f.horizon)
    right = similar(left)
    for t in 1:f.horizon, i in 1:3
        left[i,t] = f.coefficients[t][1][i]
        right[i,t] = f.coefficients[t][2][i]
    end
    library = Libdl.dlopen(built.library_path)
    product = Libdl.dlsym(library, :gb_vector_batch)
    (;built..., julia_state=nothing, library, product, left, right)
end

function gb_external_vector_execute(state)
    state.route == "garamon_packed" && return gb_execute_vectors(state.julia_state)
    output = Matrix{Float64}(undef, 4, state.fixture.horizon)
    ccall(state.product, Cvoid,
        (Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}, Cint),
        state.left, state.right, output, state.fixture.horizon)
    output
end

GaramonBench.register_adapter!(GaramonBench.BenchmarkAdapter(
    name="external_ga_vector_product",
    generate=gb_external_vector_generate,
    build=gb_external_vector_build,
    prepare=gb_external_vector_prepare,
    execute=gb_external_vector_execute,
    oracle=(state,result)->size(result)==size(state.fixture.expected) &&
        result==state.fixture.expected,
    preflight_evidence=(state,result)->Dict(
        "library"=>state.route,
        "source_revision"=>state.source_revision,
        "output_masks"=>Int.(state.fixture.output_masks),
        "output_sum"=>sum(result)),
    cleanup=state->begin
        isnothing(state.library) || Libdl.dlclose(state.library)
        nothing
    end,
    contract="EGA3 vector geometric product; owned Float64 matrix ordered by masks 0,3,5,6",
    capabilities=Dict(
        "exact_oracle"=>"independent Int64 vector-basis inversion",
        "comparison_group"=>"ega3_vector_product_owned_v1",
        "output_ownership"=>"owned",
        "metric"=>"euclidean",
        "timed_scope"=>"horizon products and owned output, excluding input packing and C++ build",
        "ffi_for_native_libraries"=>true)); replace=true)
