import CMake_jll, Clang_jll, Eigen_jll, Ninja_jll

const CPP_SOURCE_REVISION = "6267161e35be57873fa553f266ef04f2ba32d2e5"
const CPP_ARTIFACT_NAME = "garamon_cpp"
const CPP_ARTIFACT_TOML = joinpath(dirname(@__DIR__), "Artifacts.toml")

function pinned_cpp_artifact_root()
    hash = Pkg.Artifacts.artifact_hash(CPP_ARTIFACT_NAME, CPP_ARTIFACT_TOML)
    isnothing(hash) && error("Garamon C++ artifact entry missing")
    joinpath(Pkg.Artifacts.artifact_path(hash), "garamon-" * CPP_SOURCE_REVISION)
end

"""Fetch the pinned Garamon C++ source once. Pkg validates the archive digest
and installs it in its content-addressed artifact store; later loads are local.
"""
function ensure_cpp_source()
    artifact = Pkg.Artifacts.ensure_artifact_installed(CPP_ARTIFACT_NAME,
        CPP_ARTIFACT_TOML; pkg_server_eligible=false)
    root = joinpath(artifact, "garamon-" * CPP_SOURCE_REVISION)
    isfile(joinpath(root, "CMakeLists.txt")) ||
        error("Garamon C++ artifact has no generator source")
    isdir(joinpath(root, "data")) || error("Garamon C++ artifact has no templates")
    root
end

"""Select the immutable artifact unless a caller explicitly names a checkout."""
function cpp_source_root()
    root = get(ENV, "GARAMON_CPP_ROOT", "")
    isempty(root) ? ensure_cpp_source() : abspath(expanduser(root))
end

function cpp_source_revision(root=cpp_source_root())
    artifact = pinned_cpp_artifact_root()
    isdir(artifact) && realpath(root) == realpath(artifact) && return CPP_SOURCE_REVISION
    revision = strip(read(`git -C $root rev-parse HEAD`, String))
    revision == CPP_SOURCE_REVISION ||
        error("Garamon C++ checkout differs from pinned revision $CPP_SOURCE_REVISION")
    revision
end

"""Absolute, versioned build tools supplied by Julia packages."""
function cpp_toolchain()
    all(jll.is_available() for jll in (CMake_jll, Clang_jll, Eigen_jll, Ninja_jll)) ||
        error("C++ toolchain JLL unavailable on this platform")
    cxx = joinpath(dirname(Clang_jll.clang_path), "clang++")
    eigen = joinpath(Eigen_jll.artifact_dir, "share", "eigen3", "cmake")
    eigen_include = joinpath(Eigen_jll.artifact_dir, "include", "eigen3")
    all(isfile, (CMake_jll.cmake_path, Clang_jll.clang_path, cxx,
        Ninja_jll.ninja_path, joinpath(eigen, "Eigen3Config.cmake"),
        joinpath(eigen_include, "Eigen", "Core"))) ||
        error("C++ toolchain JLL is incomplete")
    (; cmake=CMake_jll.cmake_path, cc=Clang_jll.clang_path, cxx,
        ninja=Ninja_jll.ninja_path, eigen, eigen_include)
end

function cpp_toolchain_environment()
    libpath = Clang_jll.LIBPATH[]
    existing = get(ENV, "LD_LIBRARY_PATH", "")
    ("LD_LIBRARY_PATH" => isempty(existing) ? libpath : libpath * ":" * existing,)
end
