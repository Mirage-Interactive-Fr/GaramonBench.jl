# Packaged matched benchmark sources

Imported on 2026-09-27 from the locally validated matched campaign, then adapted
only for package-relative benchmark/worker paths and an explicit
`GARAMON_JULIA_ROOT`. The original files remain in their original repositories.
The initial inputs had these SHA256 identities:

| Input | SHA256 |
|---|---|
| Garamon/perf/cpp_matched.jl | `8f516a5d257ad0cf2cbd188c97b4d09e66bdba23e77dad92ffb051af3572726f` |
| Garamon/perf/cpp_matched_common.jl | `667ddb4a50987b5a95a8f18da3af3bd41fc41375c59453c3967cd2b7b91904a6` |
| CMakeLists.txt | `22af2d7ecb2d8092e9f657bae91bd58eefa7fa7d860e3213e673f24f52c7b37e` |
| native.cpp | `54689ef61073d701598f049087ecf1166d9e254debb23c4e82f57ce95936f0ed` |
| packed.cpp | `cfdd6b615256ef548633ab32c17b536e100513a81fc84fa6c39d4505e727cc04` |
| upstream.cpp | `3c8d4e02a8fd806a7e3ab6c6000f6afdae433196942daf5c7e3da821bc83cb4f` |

The benchmark C++ sources are intrinsic experimental code; they do not come
from a clean clone of the upstream generator. They are therefore distributed
here, rather than assumed to exist in an upstream `benchmark/` directory.

Upstream generator: https://github.com/vincentnozick/garamon.git, revision
`6267161e35be57873fa553f266ef04f2ba32d2e5`. `GaramonBench/Artifacts.toml`
pins its source archive by SHA256 and installed Git tree hash. `__init__` loads
it once through Pkg.Artifacts; subsequent loads are local. `GARAMON_CPP_ROOT`
can select an existing checkout at the same revision. CMake, Clang, Ninja and
Eigen are versioned JLL dependencies. Templates and generator source are
fingerprinted and snapshotted for each run; compiled output is temporary.

The upstream generator unconditionally reads its existing `data/setup.py` and
`data/sample/sample.py` templates, plus extensionless HOWTO text files. These
third-party inputs are copied unchanged into the temporary mirror and source
snapshot. The harness itself uses Julia and introduces no Python script; those
files exist only because the generator requires them, even in a C++ campaign.

The Julia implementation under test is a separate, modified checkout with
`PackedProductBatch`, `pack_product_batch` and `run_packed_batch`. Its URL may
require private access. Set `GARAMON_JULIA_ROOT` to that exact checkout or a
supplied source snapshot and instantiate its dependencies. GaramonBench does
not contain credentials or pretend that its Manifest supplies the target code.

Pairing: `julia_jit` and `julia_precompile` both call `run_packed_batch`.
`cpp_packed` ports the same column/path loop, consumes the same packed buffers
and path order, and shares Julia-side validation and zeroed output allocation.
Those three use `matched-packed-paths-v1`. The actual generated upstream
`Mvec<double>` implementation remains `unpaired-upstream-mvec`; its timing
must not be described as the same-algorithm language comparison.
