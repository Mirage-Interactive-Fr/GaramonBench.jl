cmake_minimum_required(VERSION 3.16)
project(garamon_matched_benchmark LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# One generated algebra per temporary build. The packed kernel is generic and
# deliberately separate from the upstream, algebra-specific Mvec implementation.
if(NOT DEFINED GARAMON_DIMENSION OR NOT DEFINED GARAMON_GENERATED_SOURCE)
    message(FATAL_ERROR "Set GARAMON_DIMENSION and GARAMON_GENERATED_SOURCE")
endif()
find_package(Eigen3 REQUIRED NO_MODULE)

add_library(garamon_packed SHARED packed.cpp)
add_executable(garamon_native native.cpp)
target_link_libraries(garamon_native PRIVATE garamon_packed)
add_library(garamon_upstream SHARED upstream.cpp)
target_link_libraries(garamon_upstream PRIVATE Eigen3::Eigen)
target_include_directories(garamon_upstream PRIVATE "${GARAMON_GENERATED_SOURCE}")
target_compile_definitions(garamon_upstream PRIVATE
    GARAMON_DIMENSION=${GARAMON_DIMENSION}
    GARAMON_NAMESPACE=e${GARAMON_DIMENSION}ga
    GARAMON_HEADER="e${GARAMON_DIMENSION}ga/Mvec.hpp")
foreach(target IN ITEMS garamon_packed garamon_upstream garamon_native)
    target_compile_options(${target} PRIVATE -O2 -march=native -ffp-contract=off)
endforeach()
