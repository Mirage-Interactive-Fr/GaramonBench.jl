# Exact matched-path preflight. The upstream generator and benchmark library are
# compiled only inside each case's disposable build directory.
using GaramonBench, Libdl

const GB_CPP_JULIA_ROOT=get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon"))
pushfirst!(LOAD_PATH,GB_CPP_JULIA_ROOT)
const GB_CPP_UPSTREAM_ROOT=GaramonBench.cpp_source_root()
include(joinpath(@__DIR__,"cpp_matched","common.jl"))
include(joinpath(@__DIR__,"cpp_matched","driver.jl"))

function gb_cpp_matched_case(case)
    n=case["dimension"]
    family=Symbol(case["family"])
    horizon=case["horizon"]
    strategy=case["strategy"]
    n in (3,7) || error("matched Garamon C++ fixture admits EGA3/EGA7 only")
    family in (:mixed,:vectors) || error("matched C++ fixture family")
    horizon isa Integer && 1<=horizon<=10000 || error("matched C++ horizon budget")
    strategy in ("julia_packed","cpp_packed") || error("unmatched C++ strategy")
    cm_inputs(n,family,horizon)
end

function gb_cpp_build_library(n,directory)
    isdir(GB_CPP_UPSTREAM_ROOT) || error("Garamon C++ source artifact missing")
    GaramonBench.cpp_source_revision(GB_CPP_UPSTREAM_ROOT)
    toolchain=GaramonBench.cpp_toolchain()
    cmake=toolchain.cmake; cc=toolchain.cc; cxx=toolchain.cxx
    ninja=toolchain.ninja; eigen=toolchain.eigen
    eigen_include=toolchain.eigen_include
    budget=256<<20
    generator_build=joinpath(directory,"generator-build")
    cm_guarded_process(`$cmake -G Ninja -S $GB_CPP_UPSTREAM_ROOT -B $generator_build -DCMAKE_MAKE_PROGRAM=$ninja -DCMAKE_C_COMPILER=$cc -DCMAKE_CXX_COMPILER=$cxx -DEigen3_DIR=$eigen -DEIGEN3_INCLUDE_DIR=$eigen_include -DCMAKE_BUILD_TYPE=Release`,
        directory,budget)
    cm_guarded_process(`$cmake --build $generator_build --parallel 1`,directory,budget)
    symlink(joinpath(GB_CPP_UPSTREAM_ROOT,"data"),joinpath(directory,"data"))
    generation=joinpath(directory,"generation")
    mkpath(joinpath(generation,"output"))
    config=joinpath(GB_CPP_UPSTREAM_ROOT,"conf","e$(n)ga.conf")
    generator=joinpath(generator_build,"garamon_generator")
    cm_guarded_process(`$generator $config`,directory,budget;
        working_directory=generation)
    generated=joinpath(generation,"output","garamon_e$(n)ga","src")
    isdir(generated) || error("Garamon C++ generated algebra missing")
    compiled=joinpath(directory,"compiled")
    source=joinpath(@__DIR__,"cpp_matched")
    cm_guarded_process(`$cmake -G Ninja -S $source -B $compiled -DCMAKE_MAKE_PROGRAM=$ninja -DCMAKE_CXX_COMPILER=$cxx -DEigen3_DIR=$eigen -DCMAKE_BUILD_TYPE=Release -DGARAMON_DIMENSION=$n -DGARAMON_GENERATED_SOURCE=$generated`,
        directory,budget)
    cm_guarded_process(`$cmake --build $compiled --target garamon_packed --parallel 1`,
        directory,budget)
    library=joinpath(compiled,"libgaramon_packed.so")
    isfile(library) || error("matched packed C++ library missing")
    library
end

GaramonBench.register_adapter!(GaramonBench.BenchmarkAdapter(
    name="cpp_packed_exact",
    contract="EGA3/EGA7 identical packed plan, ordered Float64 owned matrix; independent Int64 sign oracle",
    generate=(case,directory,rng)->gb_cpp_matched_case(case),
    build=(inputs,case,directory)->begin
        plan=cm_plan(inputs)
        batch=cm_pack(plan,inputs)
        library_path=case["strategy"]=="cpp_packed" ?
            gb_cpp_build_library(case["dimension"],directory) : ""
        (;inputs,batch,library_path)
    end,
    prepare=(built,case,directory)->begin
        backend=case["strategy"]=="cpp_packed" ?
            cm_cpp_library(built.library_path) : nothing
        expected=cm_expected(built.inputs,built.batch)
        (;built...,backend,expected,strategy=case["strategy"])
    end,
    execute=state->state.strategy=="cpp_packed" ?
        cm_cpp_packed(state.batch,state.backend) : run_packed_batch(state.batch),
    oracle=(state,result)->size(result)==size(state.expected) && result==state.expected,
    cleanup=state->begin
        state.backend===nothing || Libdl.dlclose(state.backend.library)
        nothing
    end,
    diagnostics=(state,case,directory)->begin
        state.strategy=="cpp_packed" || return Dict("status"=>"not_applicable_julia_route")
        source=joinpath(dirname(state.library_path),"..","command.log")
        if isfile(source)
            cp(source,joinpath(directory,"cpp-final-build-log.txt"))
        end
        Dict("status"=>"matched_packed_library_built_and_oracle_checked",
            "library_sha256"=>GaramonBench._resume_sha(state.library_path),
            "compiler"=>strip(GaramonBench.probe(addenv(`$(GaramonBench.cpp_toolchain().cxx) --version`,
                GaramonBench.cpp_toolchain_environment()...))),
            "generated_objects_cleaned_after_case"=>true)
    end,
    capabilities=Dict("scientific_garamon_result"=>true,
        "matched_contract"=>"same_plan_inputs_coefficients_outputs_precision",
        "comparison_group"=>"matched_packed_paths_v1",
        "upstream_mvec_included"=>false,
        "compile_policy"=>"fresh_per_case_preflight_inefficient_for_extensive_campaign")))
