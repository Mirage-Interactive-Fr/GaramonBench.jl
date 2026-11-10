haskey(ENV, "GARAMON_JULIA_ROOT") &&
    pushfirst!(LOAD_PATH, expanduser(ENV["GARAMON_JULIA_ROOT"]))
using Garamon, GaramonBench, Libdl

include("julia_products_kernels.jl")

const GB_CROSS_VECTOR_SOURCE = joinpath(@__DIR__, "external_ga", "prepared_vector_product.cpp")
const GB_JULIA_VECTOR_ROUTES = Dict("garamon_direct"=>"direct",
    "garamon_workspace"=>"workspace", "garamon_packed"=>"packed")
const GB_NATIVE_VECTOR_ROUTES = Dict("gal"=>("GB_GAL","public"),
    "versor"=>("GB_VERSOR","include"), "klein"=>("GB_KLEIN","public"),
    "garamon_cpp"=>("GB_GARAMON_CPP",""))
const GB_CROSS_TYPES = Dict("Float16"=>Float16,"Float32"=>Float32,
    "Float64"=>Float64,"BigFloat"=>BigFloat)

function gb_cross_vector_generate(case, directory, rng)
    case["dimension"] == 3 || error("external vector-product comparison requires EGA3")
    case["family"] == "vectors" || error("comparison requires vector inputs")
    case["signature"] == "positive" || error("comparison requires Euclidean metric")
    route = case["scenario"]
    haskey(GB_JULIA_VECTOR_ROUTES,route) || haskey(GB_NATIVE_VECTOR_ROUTES,route) ||
        error("unknown library")
    precision = case["precision"]
    haskey(GB_CROSS_TYPES,precision) || error("unsupported comparison precision")
    if haskey(GB_NATIVE_VECTOR_ROUTES,route)
        supported = route == "klein" ? ("Float32",) : ("Float32","Float64")
        precision in supported || error("unsupported precision for "*route)
    end
    precision=="BigFloat" && !(64 <= case["bigfloat_bits"] <= 4096) &&
        error("BigFloat precision must be between 64 and 4096 bits")
    fixture_case = copy(case)
    fixture_case["strategy"] = get(GB_JULIA_VECTOR_ROUTES,route,"direct")
    gb_generate_vectors(fixture_case, directory, rng)
end

function gb_cross_build_command(command,stage)
    success(addenv(command,GaramonBench.cpp_toolchain_environment()...)) ||
        error("C++ comparison build failed during "*stage)
end

function gb_generate_cpp_ega3(directory,toolchain)
    root = GaramonBench.cpp_source_root()
    revision = GaramonBench.cpp_source_revision(root)
    (;cmake,cc,cxx,ninja,eigen,eigen_include) = toolchain
    build = joinpath(directory,"generator")
    generation = joinpath(directory,"algebra")
    mkpath(joinpath(generation,"output"))
    symlink(joinpath(root,"data"),joinpath(directory,"data"))
    gb_cross_build_command(`$cmake -G Ninja -S $root -B $build -DCMAKE_MAKE_PROGRAM=$ninja -DCMAKE_C_COMPILER=$cc -DCMAKE_CXX_COMPILER=$cxx -DEigen3_DIR=$eigen -DEIGEN3_INCLUDE_DIR=$eigen_include -DCMAKE_BUILD_TYPE=Release`,"generator configuration")
    gb_cross_build_command(`$cmake --build $build --target garamon_generator --parallel 1`,"generator compilation")
    binary = joinpath(build,"garamon_generator")
    config = joinpath(root,"conf","e3ga.conf")
    gb_cross_build_command(Cmd(`$binary $config`;dir=generation),"EGA3 generation")
    include_dir = joinpath(generation,"output","garamon_e3ga","src")
    (; includes=[include_dir,eigen_include], revision)
end

function gb_cross_vector_build(fixture, case, directory)
    route = case["scenario"]
    scalar_type = GB_CROSS_TYPES[case["precision"]]
    bits = scalar_type === BigFloat ? case["bigfloat_bits"] : 0
    haskey(GB_JULIA_VECTOR_ROUTES,route) && return (;fixture,route,scalar_type,bits,
        library_path=nothing,source_revision="local_Garamon_jl")
    toolchain = GaramonBench.cpp_toolchain()
    definition, subdirectory = GB_NATIVE_VECTOR_ROUTES[route]
    if route == "garamon_cpp"
        (;includes,revision) = gb_generate_cpp_ega3(directory,toolchain)
    else
        root = GaramonBench.ensure_external_ga_source(route)
        includes = [joinpath(root,subdirectory)]
        revision = only(row["revision"] for row in GaramonBench.external_ga_candidates()
            if row["name"] == route)
    end
    flags = ["-D"*definition; "-I".*includes]
    scalar_type == Float32 && push!(flags,"-DGB_FLOAT32")
    route == "klein" && push!(flags,"-msse4.1")
    library_path = joinpath(directory,"libgb_"*route*".so")
    compiler = toolchain.cxx
    command = `$compiler -std=c++17 -O3 -fno-fast-math -ffp-contract=off -Wno-deprecated-literal-operator -fPIC -shared $flags $GB_CROSS_VECTOR_SOURCE -o $library_path`
    gb_cross_build_command(command,route*" adapter compilation")
    (;fixture,route,scalar_type,bits,library_path,source_revision=revision)
end

function gb_cross_precision(f,bits)
    bits==0 || bits==precision(BigFloat) ? f() : setprecision(f,BigFloat,bits)
end

function gb_cross_vector_prepare(built, case, directory)
    f, T = built.fixture, built.scalar_type
    julia_state = gb_cross_precision(built.bits) do
        gb_prepare_vectors(f,case,directory;scalar_type=T)
    end
    if isnothing(built.library_path)
        return (;built...,julia_state,library=nothing,product=C_NULL,batch=C_NULL)
    end
    left = Matrix{T}(undef,3,f.horizon)
    right = similar(left)
    for t in 1:f.horizon, i in 1:3
        left[i,t] = f.coefficients[t][1][i]
        right[i,t] = f.coefficients[t][2][i]
    end
    library = Libdl.dlopen(built.library_path)
    try
        product = Libdl.dlsym(library,:gb_vector_product)
        batch = gb_cross_prepare_native(T,library,left,right,f.horizon)
        batch == C_NULL && error("native vector batch preparation failed")
        return (;built...,julia_state,library,product,batch)
    catch
        Libdl.dlclose(library)
        rethrow()
    end
end

function gb_cross_prepare_native(::Type{F},library,left,right,count) where {F<:Union{Float32,Float64}}
    prepare = Libdl.dlsym(library,:gb_vector_prepare)
    ccall(prepare,Ptr{Cvoid},(Ptr{F},Ptr{F},Cint),left,right,count)
end

function gb_cross_execute_native(::Type{F},state) where {F<:Union{Float32,Float64}}
    output = Matrix{F}(undef,4,state.fixture.horizon)
    ccall(state.product,Cint,(Ptr{Cvoid},Ptr{F}),state.batch,output) == 0 ||
        error("native vector batch execution failed")
    output
end

gb_cross_vector_execute(state) = isnothing(state.library) ?
    gb_cross_precision(()->gb_execute_vectors(state.julia_state),state.bits) :
    gb_cross_execute_native(state.scalar_type,state)

gb_cross_vector_baseline(state) =
    gb_cross_precision(()->gb_execute_vectors_baseline(state.julia_state),state.bits)

function gb_cross_vector_cleanup(state)
    isnothing(state.library) && return nothing
    destroy = Libdl.dlsym(state.library,:gb_vector_destroy)
    ccall(destroy,Cvoid,(Ptr{Cvoid},),state.batch)
    Libdl.dlclose(state.library)
    nothing
end

GaramonBench.register_adapter!(GaramonBench.BenchmarkAdapter(
    name="garamon_cross_library",
    generate=gb_cross_vector_generate,
    build=gb_cross_vector_build,
    prepare=gb_cross_vector_prepare,
    execute=gb_cross_vector_execute,
    baseline_execute=gb_cross_vector_baseline,
    baseline_name="Garamon.jl direct vector product",
    oracle=(state,result)->size(result)==size(state.fixture.expected) &&
        result==state.fixture.expected && eltype(result)==state.scalar_type &&
        (state.bits==0 || all(x->precision(x)==state.bits,result)),
    preflight_evidence=(state,result)->Dict(
        "library"=>state.route,
        "precision"=>string(state.scalar_type),
        "bigfloat_bits"=>state.bits,
        "source_revision"=>state.source_revision,
        "output_masks"=>Int.(state.fixture.output_masks),
        "output_sum"=>Int(sum(result))),
    diagnostics=(state,case,dir)->Dict("library"=>state.route,
        "source_revision"=>state.source_revision,"precision"=>case["precision"],
        "bigfloat_bits"=>state.bits),
    cleanup=gb_cross_vector_cleanup,
    contract="EGA3 vector product; owned same-precision matrix ordered by masks 0,3,5,6",
    capabilities=Dict(
        "exact_oracle"=>"independent Int64 vector-basis inversion",
        "comparison_group"=>"ega3_vector_product_owned_v2",
        "output_ownership"=>"owned",
        "metric"=>"euclidean",
        "timed_scope"=>"horizon products and owned output, excluding operand preparation and C++ build",
        "ffi_for_native_libraries"=>true)); replace=true)
