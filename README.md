# GaramonBench.jl

## Quick start (Julia 1.13)

Install the package once:

~~~julia
using Pkg
Pkg.develop(url="https://github.com/Mirage-Interactive-Fr/GaramonBench.jl.git")
using GaramonBench
bench()
~~~

The bench() entry point first checks correctness, then measures the geometric
product of two EGA3 vectors with Garamon.jl, GAL, and Versor. The pinned C++
sources are fetched through Julia artifacts and compiled on demand. No manual
source checkout is required. The completed run writes raw samples and a
summary CSV, generates vector PDF plots with XKCDMakie/CairoMakie, and compiles
the English article with latexmk. TeX Live and latexmk are required for the
article compilation step.

The default layout follows DrWatson:

~~~text
data/garamonbench/external-ga-vectors/<condition>/
    preflight/
    benchmark/cases/<ID>/samples.csv
    summary.csv
    report.toml
plots/garamonbench/external-ga-vectors/<condition>/<signature>/<archive-id>/
    exploratory_*.pdf
    ega3_vector_libraries.pdf
papers/garamonbench/external-ga-vectors/<condition>/<signature>/<archive-id>/
    Garamon_research_article_2026-09-27_en.pdf
~~~

The article source is in papers/. The 29 exploratory figure PDFs reproduce
values already documented in that source; generating them does not run new
measurements. The EGA3 library plot is refreshed after each validated case
and again after the final CSV audit. A separate Julia process renders the
figures so plotting packages do not remain loaded during measurement.

To resume after an interruption, repeat bench() with the same project,
machine, sources, and output path. Completed validated cases are checked and
skipped. An article compilation failure does not invalidate completed
measurements. For a dedicated machine, declare its isolation explicitly:

~~~julia
bench(isolated=true)
~~~

For a dedicated results disk, set the output directory and use that same
directory on every resumed run:

~~~julia
bench(output="/data/garamonbench/run-001", isolated=true)
~~~

A new machine, Julia version, source revision, or configuration requires a
new results directory. The EGA3 run uses 1,024 input pairs per sample,
31 warm samples, and a shared seed. Preparation and compilation are recorded
separately from product timing. The isolation flag is an operator
declaration, not an automatic system check.

## Advanced campaigns


Reproducible benchmark campaigns for Garamon Julia and the upstream C++
generator. This package is a separate harness. It neither modifies nor relocates
the existing Garamon campaigns. Its registry has 46 technique IDs, 30 runnable
one-case adapters and two runnable combinations. One route is explicitly
approximate; the other registered routes require their stated exact oracle.
It also has an optional CUDA packed-product route and a matched C++/Julia
campaign. CUDA remains an experimental target implementation in Garamon.jl.

## Install and run

Use Julia 1.13. The included `Manifest.toml` records the resolved
environment; retain it with shared results. Installation does not require a
CUDA toolkit or compiler.

```julia
using Pkg
Pkg.activate(expanduser("~/.julia/dev/GaramonBench"))
Pkg.instantiate()
Pkg.test()
```

From the package root:

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl list config/julia_products.toml
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl run config/smoke.toml /path/to/results
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl run config/julia_products.toml /path/to/results adapters/garamon_julia.jl
```

Set `GARAMON_JULIA_ROOT` to select the Julia target checkout (default:
`~/.julia/dev/Garamon`). On first `using GaramonBench`, Julia's artifact manager
downloads the exact Garamon C++ source revision declared in `Artifacts.toml`;
subsequent loads use the verified local artifact. Set `GARAMON_CPP_ROOT` only to
use an existing checkout at that same revision. Both source identities are
captured even though the initial Julia campaign does not run C++.
Garamon.jl is a direct public Git dependency pinned by commit in
`Project.toml`; the top-level `bench()` entry point resolves it automatically.
PerfChecker is a public Git URL dependency pinned by the Manifest's tree hash
and the Project's release reference.

## Dedicated-machine launch and restart

Copy the **current** GaramonBench and Garamon source trees, including local
changes, to sibling directories `~/.julia/dev/GaramonBench` and
`~/.julia/dev/Garamon` on the benchmark machine. Keep the Project/Manifest files
and `Artifacts.toml` with GaramonBench. The GPU Manifest refers to Garamon at
`../../Garamon`. Use Julia **1.13** and run these commands from
`~/.julia/dev/GaramonBench`:

```sh
cd ~/.julia/dev/GaramonBench
julia --startup-file=no --project=../Garamon -e 'using Pkg; Pkg.instantiate()'
julia --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate()'
julia --startup-file=no --project=worker -e 'using Pkg; Pkg.instantiate()'
julia --startup-file=no --project=gpu -e 'using Pkg; Pkg.instantiate()'
```

The first load installs pinned Garamon C++ source through Pkg.Artifacts if
needed; subsequent loads reuse it. The matched C++ lane obtains Clang, CMake,
Ninja and Eigen through JLL packages. The GPU lane requires a working NVIDIA
driver and `CUDA.functional() == true`. Choose a fresh result directory on a
disk with sufficient space; set `BENCH_RUN` again if opening a new shell.
The preflight commands below are **short correctness checks**, one process at a
time. All three Julia calls use the same directory.

```sh
BENCH_RUN=/data/garamonbench/run-001
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl technique-smoke "$BENCH_RUN/preflight"
julia --startup-file=no --check-bounds=yes --threads=4,0 --project=. scripts/garamonbench.jl technique-smoke "$BENCH_RUN/preflight" 27
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=gpu scripts/garamonbench.jl technique-smoke "$BENCH_RUN/preflight" 29
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl preflight config/cpp_packed_minimal_preflight.toml "$BENCH_RUN/cpp-preflight" adapters/garamon_cpp_packed.jl
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl archive-audit config/cpp_packed_minimal_preflight.toml "$BENCH_RUN/cpp-preflight"
```

Check `preflight/quickcheck.toml` for `oracle_passed_count = 32`. The C++ audit
must say `archive_integrity = "validated"`, show two completed IDs and no
pending IDs. The 16 research-only techniques are explicitly unimplemented and
do not count toward 32. **After** the source-matched PerfChecker qualification
is complete, run the native campaigns below on the dedicated machine, with
other heavy jobs stopped. Each lane has its own project/thread setting; run
them sequentially to avoid measurement interference. The C++ grid contains
matched packed Julia and C++ cases with identical inputs and output contract.

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl technique-bench "$BENCH_RUN/preflight" "$BENCH_RUN/julia"
julia --startup-file=no --threads=4,0 --project=. scripts/garamonbench.jl technique-bench "$BENCH_RUN/preflight" "$BENCH_RUN/julia" 27
julia --startup-file=no --threads=1,0 --project=gpu scripts/garamonbench.jl technique-bench "$BENCH_RUN/preflight" "$BENCH_RUN/julia" 29
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl resume config/cpp_packed_native_benchmark.toml "$BENCH_RUN/cpp" adapters/garamon_cpp_packed.jl
```

**After interruption, repeat the identical command with the identical result
path, project, thread count and sources.** `julia/bench-progress.toml` reports
Julia route status; `julia/ID/` holds each route's DrWatson case archive. For
the C++ grid, inspect progress and integrity without running samples:

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl resume-status config/cpp_packed_native_benchmark.toml "$BENCH_RUN/cpp"
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl archive-audit config/cpp_packed_native_benchmark.toml "$BENCH_RUN/cpp"
```

On restart, the controller verifies and skips every completed case. Incomplete
cases are recovered or retried; altered completed cases are refused rather
than overwritten. A change of source, Manifest, configuration or machine
requires a **new** result root. Do not reuse timings copied from another
machine as checkpoints. Generated C++ code and binaries are cleaned from
temporary build directories after each case; preserve the archived raw samples
until coverage has been audited. The six optional GA-library artifacts below
are source-only. GAL and Versor already have the narrow EGA3 vector-product
adapter used by `bench()`; other comparisons remain future work.

## Optional sources for future GA-library comparisons

`Artifacts.toml` also pins six external GA source snapshots by commit, archive
SHA256 and artifact tree hash. They are **lazy**: loading GaramonBench fetches
only Garamon C++; these candidates are fetched explicitly when needed:

```sh
julia --startup-file=no --project=. scripts/garamonbench.jl external-ga-list
julia --startup-file=no --project=. scripts/garamonbench.jl external-ga-fetch gatl gal
julia --startup-file=no --project=. scripts/garamonbench.jl external-ga-fetch all
```

The installed paths are stable Pkg artifact roots. The candidates are
[GATL](https://github.com/laffernandes/gatl),
[Versor](https://github.com/wolftype/versor),
[GAL](https://github.com/jeremyong/gal),
[Klein](https://github.com/jeremyong/klein),
[gafro](https://github.com/idiap/gafro), and
[Grassmann.jl](https://github.com/chakravala/Grassmann.jl).
An artifact installs source, not a built C++ library or a resolved Julia
runtime environment. The GAL and Versor adapters build on demand and pass an
independent full-output oracle. Further adapters need equivalent contracts.
GATL, Versor, GAL and Grassmann.jl are candidates for matched Euclidean
products; Klein belongs to a separate PGA3 contract and gafro to a robotics
CGA contract. A result enters a common comparison group only after the
metric, basis convention, operation, inputs, output ownership, numeric type,
episode horizon, preparation scope and compilation scope all match. Existing
external-library measurements are exploratory until repeated in isolation.

**Initial condition: exploratory interference from Etendue3D.** This label is
stored in every run manifest. It does not establish exclusive machine access.
Once competing work is actually stopped, repeat the complete corpus:

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl repeat /path/to/previous/run /path/to/results adapters/garamon_julia.jl
```

The repeat receives its own ID and condition `isolated`, references its parent,
and refuses changed case identities or source fingerprints. Machine snapshots
do not certify isolation; this is an explicit operator declaration. Do not
aggregate exploratory and isolated observations without preserving this label.

## Actual DrWatson integration

- `dict_list` expands the configuration grid into individual cases.
- `savename` builds readable case names; a canonical TOML SHA256 suffix covers
  every parameter, including seeds and contracts.
- `tag!` records the Git description of each target repository.

The package also has a per-case resumable entry point for an **existing**
`BenchmarkAdapter` corpus:

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl resume config/julia_products.toml /path/to/dedicated-run adapters/garamon_julia.jl
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl resume-status config/julia_products.toml /path/to/dedicated-run
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl archive-audit config/julia_products.toml /path/to/copied-run
```

`resume` uses the same DrWatson `dict_list` and `savename` case identities as
`run`, plus the canonical case digest. It writes one immutable
`cases/CASE_ID/` directory only after the independent oracle, PerfChecker,
raw-sample count and source check pass. A process lock prevents concurrent
controllers; it is released automatically after a crash. Restarting with the
same path verifies every completed case's checksums and skips it. A completed
case with changed or missing data causes refusal, never silent remeasurement.
Incomplete staging is retried; a completed staging directory is recovered
without rerunning the experiment. Configuration, source-content fingerprints
(including dirty and untracked files), the exact Project/Manifest, Julia
version and a stable machine fingerprint must match. A different machine
requires its own output directory. The status command checks the archived
case evidence but does not certify that the current host matches the run.
`archive-audit` is read-only and works after copying the archive to a new path.
It recomputes the archived configuration, case, Project/Manifest, source-file
and diagnostic hashes, then reports current machine, environment and source
matches separately. A valid copied archive never authorizes reuse of timing
samples on a different machine; start a new output directory there. The local
transfer test copies a completed archive, audits it and rejects a tampered
source snapshot.

This entry point covers adapters accepted by `run`, including the Julia vector
product, exact CUDA packed product, and the matched C++/Julia packed product
below. The older monolithic paired C++ driver and other native `perf/` GPU
campaigns still need per-case checkpoints. Do not use their all-at-once entry
points as though they had this guarantee. The technique inventory and theoretical compatibility
matrix are under `config/techniques.toml` and `config/compatibility_matrix.csv`.
The catalogue has 46 technique IDs and 1,035 pairs; this is a static inventory,
not a claim that those experiments are all implemented or qualified.

Git tags alone cannot reconstruct dirty checkouts and untracked source. The
harness additionally hashes and snapshots selected text sources, including C++
generator templates under `data/`. Every run retains its exact configuration,
resolved package versions, Project/Manifest, source inventories, raw samples,
oracle verdicts and before/after machine snapshots. No result cache silently
reuses measurements from another machine state.

## Measurement contract

An adapter exposes generation, build, preparation, execution, independent oracle
and cleanup callbacks. First execution and each earlier stage record complete
wall time, GC, Julia controller allocations, compile/recompile time, generated
code-size change and controller peak RSS. Warm measurements use BenchmarkTools,
one evaluation per sample, and archive every raw elapsed/GC sample. Its memory
estimate is labeled as an estimate, not as a per-sample observation.

The included adapter compares `a*b` and `run_product_values!` under the same
owned matrix output contract, sorted by blade mask. The integer oracle is
independent and checks every coefficient. Small integer fixtures are exactly
representable in Float64. Input generation currently includes the oracle cost;
the capability metadata says so. Preparation/JIT and warm timing remain
separate; no summed median is described as an end-to-end p95.

The vector adapter now also accepts `prepared` (`run_product`) and `packed`
(`run_packed_batch`) on the same inputs and owned output matrix. Preparation
includes plan or workspace construction and, for `packed`, packing the whole
batch; the hot operation excludes those costs. The separate preflight grid
crosses all four routes at dimensions 3/65 and horizons 1/32:

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl resume config/julia_vectors_four_path_preflight.toml /fresh/output/four-path adapters/garamon_julia.jl
julia --startup-file=no --threads=1,0 --project=. test/julia_four_path_runtime.jl
```

For a correctness-only preflight, use `preflight` with an
`oracle_preflight` configuration. It runs generation, build, preparation,
two complete executions and the independent oracle on both outputs. It
collects **no timing samples**, does not call PerfChecker or CUDA profiling,
and retains the same per-case checksums, source snapshots, resume checks and
transfer audit. It loads PerfChecker only if a measurement command is selected.
The Julia grid covers 13 dimensions (2–8, 16, 32, 64, 65, 96, 128), three
diagonal signatures (positive, mixed, degenerate), four paths and horizons
1/32 (312 cases). C++ and optional GPU grids use the same matched contracts
as their measurement configurations:

```sh
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl preflight config/julia_vectors_signature_oracle_preflight.toml /fresh/output/julia-oracle adapters/garamon_julia.jl
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl preflight config/cpp_packed_oracle_preflight.toml /fresh/output/cpp-oracle adapters/garamon_cpp_packed.jl
julia --startup-file=no --threads=1,0 --project=gpu scripts/garamonbench.jl preflight config/gpu_packed_oracle_preflight.toml /fresh/output/gpu-oracle adapters/garamon_gpu_packed.jl
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl archive-audit config/julia_vectors_signature_oracle_preflight.toml /fresh/output/julia-oracle
```

For the fast code-validation pass, `technique-smoke-plan` lists all 46 roadmap
entries and two wired combinations, with representative DrWatson case IDs.
`technique-smoke` runs one oracle-checked case per registered route through the
resumable archive and records explicit `adapter_missing`,
`research_not_implemented`, `requires_environment` or `requires_threads`
statuses. Its pass status covers only that selected case; it is not a full
dimension/signature qualification. Route 25 is approximate and archives its
seed, omitted contributions and error relative to an independent exact answer;
that error is calculated in the oracle and archive, outside the timed trajectory.
It is never reported as an exact-product pass. Use a fresh output root when
sources change:

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl technique-smoke-plan
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl technique-smoke /fresh/output/quick-cpu
julia --startup-file=no --threads=4,0 --project=. scripts/garamonbench.jl technique-smoke /fresh/output/quick-cpu4 27
julia --startup-file=no --threads=1,0 --project=gpu scripts/garamonbench.jl technique-smoke /fresh/output/quick-gpu 29
```

The three calls may use **one shared preflight output root**. The progress
manifest retains earlier technique statuses; each completed case has its own
source snapshot and oracle archive. One smoke case is sufficient to authorize
a route for profiling. The 16 research-only ideas remain explicitly unmeasured.
K1 combines a two-factor XOR product, rank-reduced support and workspace; K3
shares contractions in Pfaffian scalar chains with a dedicated workspace.
Neither claims a generic three-factor join or generic expression DAG.

The `technique-profile` command uses the **same adapter callbacks and case ID**
after auditing its minimal preflight. It captures bounded PerfChecker timing,
CPU and allocation profiles, wall profile, latency, GC and memory,
JET, AllocCheck and type text where available. GPU uses the CUDA project and
its available subset; the adapter's CUPTI kernel/transfer traces are separate.
Callback types are retained in each adapter; the profiling worker crosses the
heterogeneous registry once before its measured operation. This keeps registry
dispatch outside the kernel timing and makes type diagnostics interpretable.
Heap snapshots are opt-in because the full worker snapshot exceeded the
256 MiB default archive budget in the first ZDD pilot.
The precompiled-catalogue route omits the short CPU scenario collector: it
gave no usable stack while repeatedly rebuilding the catalogue. Its wall
profile and lifecycle diagnostics remain enabled with a 900 s total cap.
Most short CPU kernels use 100 windows of 4,096 calls for stack sampling.
The cache and radical routes use 100 × 1,024; replay, approximate recurrence
and 65D indexing use 100 × 512. The resident-process route uses 20 × 4;
other bounded recursive and device routes use 50 × 64. Aggregate descendant
RSS ceilings are 3 GiB by default, 4 GiB for catalogue, replay, approximate
recurrence and K3, and 6 GiB for 65D indexing. These bounds cover profiler
processes, not just the algebraic result. The window changes only the
profiling collector, not the three benchmark samples. The recurrence adapters
keep reflective buffer-size accounting outside their timed execution path.
A complete, source-matched capture is checked and skipped on replay. An
incomplete capture is preserved and requires a fresh output root. These are
exploratory diagnostics, not speed rankings:

```sh
julia --startup-file=no --threads=1 --project=. scripts/garamonbench.jl technique-profile /fresh/preflight /fresh/profiles 20
julia --startup-file=no --threads=4 --project=. scripts/garamonbench.jl technique-profile /fresh/preflight /fresh/profiles 27
julia --startup-file=no --threads=1 --project=gpu scripts/garamonbench.jl technique-profile /fresh/preflight /fresh/profiles 29
```

`technique-bench-plan` prepares native BenchmarkTools grids for all 32 registered
routes without running them. It fixes the selected strategy and operation while
retaining each route's dimensions, signatures, supports and horizons. The
`technique-bench` launcher is for the later dedicated-machine run, after the
minimal preflight and PerfChecker work. It requires the exact smoke archive,
checks its source fingerprints, saves each case separately, and skips qualified
cases on restart on the same machine. Run CPU, four-thread CPU and GPU lanes
with their matching project and thread count:

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl technique-bench-plan
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl technique-bench /fresh/preflight /fresh/bench
julia --startup-file=no --threads=4,0 --project=. scripts/garamonbench.jl technique-bench /fresh/preflight /fresh/bench 27
julia --startup-file=no --threads=1,0 --project=gpu scripts/garamonbench.jl technique-bench /fresh/preflight /fresh/bench 29
```

Each route's timing archive is tied to the local machine, Julia environment,
source fingerprint and configuration. A moved archive can be audited, but
timing checkpoints from one machine are not reused on another. Run the minimal
preflight again on the benchmark machine before its timing campaign.

For the exact matched packed C++/Julia route, the dedicated-machine inputs are
`config/cpp_packed_minimal_preflight.toml` (two oracle cases) and
`config/cpp_packed_native_benchmark.toml` (twelve native timing cases). They
use the same adapter and clean generated libraries after each case:

```sh
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl preflight config/cpp_packed_minimal_preflight.toml /fresh/cpp-preflight adapters/garamon_cpp_packed.jl
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl resume config/cpp_packed_native_benchmark.toml /fresh/cpp-bench adapters/garamon_cpp_packed.jl
```

The generated-product adapter has a separate PerfChecker worker route that
loads the very same `generate`, `prepare`, `execute` and oracle callbacks as its
preflight case. A short diagnostic capture can be launched after that case
passes:

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl profile-capture config/profiling_generated_product_quick.toml /fresh/output/generated-profile
```

The GPU command requires a functional device with enough free VRAM. Its
absence is an explicit failed GPU case, not a silently substituted CPU run.
Use a fresh output directory for any source or configuration change; completed
cases cannot be reused across a changed source fingerprint or another machine.

The exact selected triple-product preflight uses a separate adapter for
`(a*b)*c`. Its independent integer oracle computes blade inversions and
diagonal metric factors directly. The direct path, prepared triple join
with reusable workspace, and three expression strategies (`recursive`,
`recursive_grades`, `join3`) return the same owned selected-coefficient
matrix. The grid crosses 14 dimensions (including 128/129), three diagonal
signatures, five paths and horizons 1/32 (420 cases):

```sh
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl preflight config/triple_join_oracle_preflight.toml /fresh/output/triple-join-oracle adapters/garamon_triple_join.jl
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl archive-audit config/triple_join_oracle_preflight.toml /fresh/output/triple-join-oracle
```

This qualifies the selected-output triple-join contract only. A full-output
triple product and non-diagonal metric need separate cases.

The selected binary-product preflight compares a complete product followed
by extraction with `product_coefficient` querying the same masks. Its
separate integer oracle implements the seven grade-selection rules and
Clifford-word inversions. The grid crosses 14 dimensions, three diagonal
signatures, all seven product operations, two paths and horizons 1/32
(1,176 cases). It includes high-grade masks and the 128/129 transition:

```sh
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl preflight config/target_coefficient_oracle_preflight.toml /fresh/output/target-oracle adapters/garamon_target_coefficient.jl
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl archive-audit config/target_coefficient_oracle_preflight.toml /fresh/output/target-oracle
```

These cases qualify exact selected coefficients from sparse operands under
diagonal metrics. Dense storage and general metrics are separate domains.

The homogeneous-grade preflight compares the direct product with a bounded
`prepare_grade_product` plan admitting sparse subsets of a complete grade.
The independent word oracle checks every structurally possible coefficient.
Its 1,344 cases cross 14 dimensions, three diagonal signatures, grade pairs
1×1 and (n−1)×1, four operations, two paths and horizons 1/32. A separate
test checks that an oversized 129D grade pair is refused before enumeration:

```sh
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl preflight config/grade_product_oracle_preflight.toml /fresh/output/grade-oracle adapters/garamon_grade_product.jl
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl archive-audit config/grade_product_oracle_preflight.toml /fresh/output/grade-oracle
```

Grade 2 and central-grade blocks need separate admissible shards; their
resource budgets can reject them while the 1×1 and top-grade cases pass.

The plan-cache preflight runs changing-coefficient traces with direct
products, LRU and seeded roulette eviction. Roulette chooses which complete
plan to retain; every product still includes every exact contribution. The
cache is sized for one structural plan, so scan, phase and shift traces force
evictions. Oracles check the complete owned result at every step and verify
the cache budget. The main grid has 1,008 cases across 14 dimensions, three
signatures, four trace shapes and horizons 1/32. A separate 108-case grid
uses 1,024 changing inputs in dimensions 3/65/129:

```sh
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl preflight config/plan_cache_oracle_preflight.toml /fresh/output/cache-oracle adapters/garamon_plan_cache.jl
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl preflight config/plan_cache_long_oracle_preflight.toml /fresh/output/cache-long-oracle adapters/garamon_plan_cache.jl
```

The target-dependent test also changes a metric after caching and requires a
new plan and exact changed result. These are policy correctness tests, not
evidence that either cache is faster.

The parameterized cache grid in `config/plan_cache_tuning_oracle_preflight.toml`
uses a two-plan capacity so roulette eviction has multiple eligible victims.
It declares 14 dimensions, three signatures, scan/phase/shift traces, horizons
32/1,024, five seeds and exponents 0, 0.5, 1, 2 and 4 in the weights
`(1 + hits)^(-exponent)`. The full configuration has 12,600 parameter
combinations; the benchmark planner avoids duplicate LRU exponent runs and
retains 1,260 LRU plus 6,300 roulette cases. None is a completed performance
campaign. The approximate contribution roulette has
a separate 35-cell grid in `config/approximate_roulette_oracle_preflight.toml`:
seven survival probabilities from 1/16 to 1 and five draw seeds distinct from
the scenario seed. It reports an error against an exact oracle and never enters
the exact-product comparison.

The blade-index preflight checks mask and explicit-index interfaces against
an independent complementary combinadic rank formula, then verifies
rank/unrank roundtrips. Its 56 cases cover 14 dimensions through 129,
including the 64/65 and 128/129 mask-width boundaries, with horizons 1/32:

```sh
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl preflight config/blade_index_oracle_preflight.toml /fresh/output/blade-index-oracle adapters/garamon_blade_index.jl
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl archive-audit config/blade_index_oracle_preflight.toml /fresh/output/blade-index-oracle
```

These are correctness and restart checks. They do not rank the two index
interfaces by speed.

Dense-global storage is checked against sparse storage on the same complete
products and an independent integer Clifford-word oracle. The grid has 264
cases over 11 dimensions (2–12), three diagonal signatures, basis/broad
supports, both storage formats and horizons 1/32. Broad support is fully
dense through dimension 6 and capped at 64 occupied masks above that, while
the dense container still allocates all 2^n coefficients. The explicit
dimension cap keeps the all-mask oracle and output within the preflight RAM
budget:

```sh
julia --startup-file=no --check-bounds=yes --threads=1,0 --project=. scripts/garamonbench.jl preflight config/dense_global_oracle_preflight.toml /fresh/output/dense-global-oracle adapters/garamon_dense_global.jl
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl archive-audit config/dense_global_oracle_preflight.toml /fresh/output/dense-global-oracle
```

Warm sample count is mandatory. BenchmarkTools' time limit can otherwise stop
a slow case before `samples` observations exist, so the per-case wall budget
sets its stopping deadline and incomplete sampling fails qualification. The
legacy `sample_seconds` field is retained in existing manifests but no longer
limits warm sampling in this adapter runner.

The default configurations use a real PerfChecker `FeatureSpec` and custom
executor, with BenchmarkTools samples attached to a `CheckerResult` carrying
the exact oracle qualification. Every archived warm sample is checked against
the returned PerfChecker table; feature status, campaign verdict and version
are archived per case. The optional `benchmarktools` backend is explicitly
labeled and never claims a PerfChecker verdict. Historical runs keep the backend
actually used. Existing external campaigns are not silently imported.

## Resources and cleanup

All generated code and compiled libraries belong in the callback's temporary
build directory. It is removed on success and exceptions; cleanup must release
native handles before removal. The archive permits text results and rejects
compiled/executable artifacts. Raw samples are CSV; metadata are TOML.
Source snapshots include only declared text extensions, not arbitrary data or
binary dependencies; the selected scope is recorded alongside every hash.

Current time/RSS/disk limits are checked between stages/cases; they are not hard
OS limits and disk observations are not a continuous peak. Native child RSS,
VRAM, transfers and GPU timings require adapter-specific measurements and must
not be filled with Julia controller metrics. The optional CUDA adapter archives
CUPTI traces and free-memory snapshots; those snapshots are not a peak-VRAM
measurement. No GPU is initialized by the metadata collector. GPU driver state
is queried only via `nvidia-smi`.

Machine records include CPU topology, affinity, thread environment, Julia and
tool versions, load/counters, memory, GPU state, and process names/CPU shares.
They intentionally omit full process command lines. Before sharing an archive,
remember it contains source code, Git remotes and local paths; publishing is a
separate action.

## Exact CUDA packed-product preflight

The optional `gpu/` environment pins CUDA and uses relative paths to the
GaramonBench and Garamon development checkouts under `~/.julia/dev`. On a host
with a functional CUDA device, the bounded preflight is:

```sh
julia --startup-file=no --project=gpu -e 'using Pkg; Pkg.instantiate()'
julia --startup-file=no --threads=1,0 --project=gpu scripts/garamonbench.jl resume config/gpu_packed_preflight_smoke.toml /fresh/output/gpu-preflight adapters/garamon_gpu_packed.jl
julia --startup-file=no --threads=1,0 --project=gpu scripts/garamonbench.jl resume-status config/gpu_packed_preflight_smoke.toml /fresh/output/gpu-preflight
```

The eight cases cross dimensions 8/65, horizons 1/32 and CPU packed/GPU
host-owned routes for the mixed-signature, higher-rank fixture. Each case has
three raw warm samples and the independent integer word oracle checks every
output coefficient. GPU cases archive CUDA/CUPTI traces for a resident kernel,
a resident result copied to a distinct host matrix, and a complete episode
that includes upload and download. Free device memory before/after each trace
is recorded as a snapshot. This preflight does not estimate a peak VRAM
allocation or establish an isolated speed ranking.

The same resumable per-case marker protects the traces: a changed trace causes
refusal and cannot silently trigger a rerun. The target-dependent tests are:

```sh
julia --startup-file=no --threads=1,0 --project=gpu test/gpu_packed_runtime.jl
CUDA_VISIBLE_DEVICES=-1 julia --startup-file=no --threads=1,0 --project=gpu test/gpu_absence_runtime.jl
```

The second command verifies explicit GPU refusal while retaining the CPU
route. Keep the source and environment fixed during a campaign; an intentional
code change requires a new output directory and new results.

## Matched C++/Julia packed-product preflight

The optional compiler-dependent adapter builds the upstream Garamon generator,
its EGA3 or EGA7 output and a matched packed C++ library in a disposable
directory for each C++ case. Its Julia route executes the identical packed
plan, input coefficients, ordering and owned Float64 output. Both routes are
checked coefficient by coefficient against an independent integer sign oracle.
The upstream `Mvec` route has a different strategy and is not included in this
comparison group. A fresh four-case smoke is:

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl resume config/cpp_packed_preflight_smoke.toml /fresh/output/cpp-packed-preflight adapters/garamon_cpp_packed.jl
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl archive-audit config/cpp_packed_preflight_smoke.toml /fresh/output/cpp-packed-preflight
julia --startup-file=no --threads=1,0 --project=. test/cpp_packed_runtime.jl
```

The grid crosses dimensions 3/7 and Julia/C++ packed paths at horizon 32,
with three warm samples per case. The runtime test checks both paths, resume
without reexecution, removal of generated binaries and refusal after a build
log is altered. A compiler and Eigen are needed only for this optional route.
Building anew for each case is deliberately conservative in the preflight;
an extensive run will need a shared, fingerprinted per-algebra build cache
whose artifacts are cleaned after that dimension is finished. No isolated
speed conclusion follows from the local smoke.

## Add an adapter

Load a file explicitly from the CLI, calling `register_adapter!` with a
`BenchmarkAdapter`. It receives the case dictionary, temporary directory and
seeded RNG. The runner invokes the independent oracle before and after hot
samples. The callback contract permits generation/build outside hot execution,
loading a compiled shared library, and batching identical inputs. See
`adapters/CONTRACT.md` for the C++ integration boundary.
An optional `diagnostics(state, case, directory)` callback runs after warm
samples in the resumable launcher. It must return a TOML-serializable dictionary
and may write text artifacts into the case staging directory. Every such file
is checksummed in the completion marker and reverified before a case is skipped.

## Primary documentation

The configuration expansion and naming follow the documented
[DrWatson grid](https://juliadynamics.github.io/DrWatson.jl/stable/run%26list/),
[naming](https://juliadynamics.github.io/DrWatson.jl/stable/name/) and
[Git tagging APIs](https://juliadynamics.github.io/DrWatson.jl/stable/save/).
The environment follows [Pkg project/manifest semantics](https://pkgdocs.julialang.org/v1/toml-files/)
and [package layout](https://pkgdocs.julialang.org/v1/creating-packages/).

## Run the existing paired C++/Julia campaign

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl cpp-matched config/cpp_matched.toml /path/to/results
```

This is a **fresh execution** of the packaged driver derived from the validated
`Garamon/perf/cpp_matched.jl`. Its controller is this package and its measurement
environment is the included `worker/` project. Clang, CMake, Ninja and Eigen
come from versioned Julia JLL packages; the generator source comes from the
pinned Pkg artifact. All extra C++ benchmark
sources are supplied under `adapters/cpp_matched/`; an upstream clone's local
`benchmark/` directory is deliberately removed from the temporary mirror.
The default smoke has
four features; setting `external_cpp.smoke=false` runs its complete 64-feature
corpus. This command compiles C++ and must receive a dedicated benchmark slot.

The orchestrator mirrors selected C++ sources into a temporary directory and
records the pinned source revision separately from the artifact's content hash.
The generator build,
generated algebras and libraries are cleaned afterwards. It verifies exact case
identities, raw sample counts/IDs, feature statuses and PerfChecker qualification
JSON, then archives the fresh CSV/JSON files with DrWatson provenance. It keeps
`cpp_upstream` in its original descriptive, unpaired group. No old result is
copied into a fresh-run verdict. The target driver's own guards remain active;
the wrapper does not claim an additional hard OS resource limit.

The exact modified Garamon.jl target is still required separately. The private
repository's public/base revision alone may lack the new APIs: share the
requested target checkout or the archived source snapshot and its Project/
Manifest. A GaramonBench Manifest cannot provide access rights or reconstruct
unpublished target modifications by itself. See `adapters/cpp_matched/PROVENANCE.md`.

## Coverage inventory

`config/campaigns.toml` distinguishes packaged campaigns from those requiring the
exact target's `perf/` files. `run-recipe` resolves and executes both categories
as documented below. The catalogue's argument vectors are illustrative native
commands; resolved commands, profile and parameters are saved for each fresh run.

## Executable recipe catalogue

### B1 compiler/bounds pilot

The dedicated `b1-plan` / `run-b1` commands prepare and measure the experimental
`perf/bounds_b1.jl` target without replacing Garamon's public prepared or packed
kernel. This pilot is separate from the recipe catalogue below. The target file
must already exist in `GARAMON_JULIA_ROOT`; no installation or source mutation is
performed. Its structural proof and tests remain required preflight evidence.

Minimal commands, from this repository, into a fresh results directory:

```sh
# Static manifest, no target load or measurements:
julia --startup-file=no --project=. scripts/garamonbench.jl b1-plan config/bounds_b1.toml

# Eight measured cases: one n=8/positive fixture, H1, both routes in two orders,
# with forced and normal bounds checking in separate Julia processes:
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl run-b1 config/bounds_b1.toml /path/to/new-b1-smoke

# Targeted configuration/source tests; no benchmark:
julia --startup-file=no --project=. test/bounds_b1.jl

# Functional integration and eight real option probes; exact B1 target required:
julia --startup-file=no --threads=1,0 --project=. test/bounds_b1_runtime.jl
```

The shipped config uses `check_bounds = ["yes", "auto"]`, `opt_levels = [2]` and
`cpu_targets = ["native"]`. Select `check_bounds = ["yes"]` for an explicit
bounds-forced smoke, then `auto` to exercise the local annotation. Lists may
cross `yes/auto`, `2/3` and `generic/native`. Global `--check-bounds=no`, arbitrary
CPU strings, fast-math and implicit thread increases are refused.

`config/bounds_b1_workspace.toml` adds `workspace`, which authenticates a
supplied plan against a canonical rebuild. `config/bounds_b1_workspace_native.toml`
also adds `workspace_native`, which builds its canonical plan directly from the
operands. Both use the same owned-output oracle and three measured phases;
their distinct preparation costs are included in complete episodes.
`config/bounds_b1_workspace_singlepass.toml` compares direct B1W with a
single-pass owned sparse-output materializer in two orders. Its 96 cases cover
2/8/65/128D, low/high support grades and H1/32/1024. The latter route remains
experimental in Garamon's `perf/` tree.
`config/bounds_b1_workspace_singlepass_12d.toml` extends the H1024 comparison
to 12 dimensions from 2 to 128, including the UInt64/UInt128 boundary at 64/65.

Changing `campaign.profile` to `"screen"` selects 12 dimensions
**2,3,4,6,8,12,16,32,64,65,96,128**, two bounded support families, three diagonal
metrics and **H=1/32/1024**. Both routes run in forward/reverse order: 864 cases
for one compiler configuration, or 6,912 for all eight explicit configurations.
Optional `dimensions`, `families`, `signatures`, `horizons` choose named subsets.
The full option cross is planned, not automatically admitted by the time budget.
Each dimension/compiler combination gets a fresh process; aggregate invocation
wall time, per-job wall time, process-tree RSS, temporary disk and archive size
are supervised. Stop/refusal reasons and not-qualified IDs remain explicit.

**Option propagation:** the launcher chooses the Julia executable from the 1.13
controller, strips inherited CLI switches, and supplies all worker arguments.
The worker verifies `Base.JLOptions()` for bounds mode, optimization level, CPU
target and disabled package images. It records those values, all process argv,
Julia/PerfChecker versions, CPU, system-image target and BLAS count. PerfChecker
uses a custom executor **inside that verified process**, so it cannot silently
spawn a measurement worker with different options. Package images are disabled;
existing module caches may be read (`--compiled-modules=existing`), and the
system image remains. These runs do not claim a fully cold disk cache or that
every system-image routine was rebuilt at the selected optimization level.
`native` is machine-specific, not a portable instruction-set identity. A target
rejected or reported differently by Julia causes failure, not silent fallback.
The process supervisor currently requires Linux `/proc`.
The catalogue names the minimal `worker/` environment for its interface contract;
the custom executor never launches it. Metadata explicitly records that fact and
the actual active GaramonBench project in which measurements take place.

**Measured contract:** checked/inbounds reuse the same prepared plan within a
fixture. Both pay the target's private copies and structural validations for
every product and retain H independent sparse outputs. Fixture generation and
the independent Int64 ordered-word oracle are outside timing. Three raw phases
are retained: plan construction, H calculations using the prepared plan, and
the directly executed construction-plus-H episode. The primary PerfChecker
table is the complete episode; no sum-of-medians verdict is synthesized.
The case corpus uses at most four support terms per operand and ±1/±2 integer
Float64 coefficients, which change in four phases. The oracle and output
ownership are checked before and after measurements. Each oracle coefficient
is bounded by 16 products of magnitude at most 4, so integer arithmetic is exact.

Artifacts include source snapshots of Garamon and GaramonBench, the complete
manifest, machine snapshots, command arguments, per-worker effective options,
first-observation times/compilation/recompilation/allocations, phase samples and
native PerfChecker qualification. First observations are **order-sensitive
diagnostics**: shared helpers may already be compiled when the second route
runs. They are not independent route cold-start comparisons. No performance
policy/baseline is evaluated, and passing exactness is not a speedup claim.
Worker partial archives remain available even if the aggregate run fails;
global completion is conservative and counts fully validated workers only.

**Current status:** Julia 1.13.0 checks passed: **816/816** configuration/source
assertions, **64/64** assertions across eight real option-probe processes, and
**1,449/1,449** functional integration assertions for oracle/ownership plus the
actual PerfChecker catalogue/custom-executor connection. The latter invokes a
functional executor returning no timing table, not a benchmark. The fixture
checks cover dimensions 2/64/65/128, both families, all three metrics, all five routes
and H1/32/1024. Source fixes include explicit module inclusion and
world-age-safe access in the integration test. The smoke manifest tests now
check both `yes` and `auto`. A first actual PerfChecker smoke qualified 8/8
cases and 168 raw observations at 8D/H1 under declared Etendue3D interference.
A second screen qualified 48/48 cases and 1,008 observations over 12 ambient
dimensions at H1 with low-grade positive fixtures; only two basis directions
are active. A third screen qualified another 48/48 cases and 1,008 observations
with input blades of grades n and n-1 on the same dimension grid. Plan building
costs more in this latter family, while complete-episode timings do not
establish a stable bounds-annotation gain. A fourth screen then qualified 96/96
cases and 2,016 observations across n=2/8/65/128, both support families and
H=1/32/1024. Two workspace screens then qualified 144/144 and 192/192 cases,
with 3,024 and 4,032 observations respectively. The directly built workspace
loses at H1/32 but wins 8/8 H1024 fixtures against the better baseline in its
own run, with fewer intermediate allocations; all timings remain exploratory.
The single-pass B1W screen qualifies another 96/96 cases and 2,016 observations.
It reduces H1024 episode allocation bytes by about 31–35% and improves 8/8
pooled fixture medians, but short horizons vary under external interference.
The 12-dimension H1024 follow-up qualifies 96/96 more cases, with 24/24 pooled
medians numerically favorable and 46/48 passage medians favorable; one pooled
cell is effectively a tie. Allocation bytes fall 30.1–34.8% in all 24 cells.
Central grades, other signatures, longer horizons on the other dimensions and
other compiler options remain unmeasured. Core B1/B1W tests passed 1,066/1,066
under both forced and normal bounds checks.
The 13 campaign recipes below retain their existing scope.

`config/campaigns.toml` now has **13 executable recipes**. Eleven delegate to the
exact Garamon target's `perf/` sources; the Julia-products and paired-C++ backends
are packaged. Integration does not mean that every full campaign was rerun.
Each invocation starts fresh measurements; no prior CSV is imported.

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl recipe-plan config/recipe.toml
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl run-recipe config/recipe.toml /path/to/results
```

Copy/edit the intrinsic TOML configuration to select `recipe.id`, `profile`
(`smoke` or `full`), condition, positive budgets and supported parameters. Unknown
fields are errors. Set `GARAMON_JULIA_ROOT` to the required Julia checkout;
`GARAMON_CPP_ROOT` is optional when using the packaged C++ artifact. The private
target with these exact `perf/` scripts and its
pinned `perf/controller`, `perf/runner` environments must already be usable.
The benchmark package Manifest alone cannot supply that private target. No
package installation is performed by the recipe orchestrator.

| Recipe ID | Smoke / parameters / qualification |
|---|---|
| `julia-products` | Current packaged 8 cases; `native_config` can select an existing native campaign TOML. Both profiles preserve that config's grid. |
| `cpp-matched` | 4-feature smoke / full native corpus; `reverse` boolean. Packaged benchmark sources; temporary upstream source mirror. |
| `continuous-dimensions` | Default smoke n=2; `max_dimension`, `dimensions`, `isolated_workers` (PerfChecker worker isolation, **not** machine isolation). |
| `workspace-small` | Explicit adapted smoke: n=2, cap12, preparation and H=1; full native grid otherwise. |
| `triplejoin` | Native smoke/full; kernels and requested-output oracle unchanged. |
| `pruning-recurrences` | Adapted smoke: n=2, positive, contracting, affine H=8, five methods; native error and restoration observations preserved. Passing the approximate method's qualification does not imply zero error. |
| `precompile-lifecycle` | Native smoke/full and all per-sample stage/session/build observations. Native exact/cache checks; **no PerfChecker verdict**. |
| `parallel-batches` | Sequential direct invocations of the native driver; `thread_counts`, `worker_counts`. Smoke defaults 1/2 each; full exploratory defaults 1/2/4 each. Full isolated defaults threads 1/2/4/8/16, workers 1/2/4/8. |
| `long-horizon` | Native smoke: 66D, stable inputs, H=32, generated/workspace; full native grid otherwise. |
| `selector-compare` | Native 6-route smoke/full; optional `reverse`. Matrix identities alone are not measurements; the current selector is analytical and unfitted. |
| `binary-rank` | Native `mode = "smoke"`, `"screen"`, `"episode_screen"` or `"full"`; smoke profile refuses larger modes. `episode_screen` executes 648 cases in two orders, timing the entire episode. Prototype integration is not a performance claim. |
| `n05-pfaffian` | Native 15-case smoke or bounded 23-case full slice, optional `reverse`; full plus explicit shard/range selects up to 32 of 36,480 stable identities. Coordinate-construction and preexisting-contraction contracts remain separate comparison groups. |
| `k1-binary-rank` | Four exact routes including prepared baseline; `decision_smoke` (12), `decision_screen` (936, two orders), or explicit `shards` over dimensions 2..128 (324 cases each). Fresh process per dimension, full 41,148-case manifest and coverage audit. |

Exploratory runs require an interference label and refuse any requested thread or
worker count above four. Most controllers require one Julia thread; the parallel
recipe owns its explicit lane grid. Process pools have the named workers **plus
one controller**. BLAS, OpenMP, GC and precompile parallelism are bounded by the
launcher. An `isolated` label is an operator declaration, not a certification;
machine snapshots record affinity, load and other processes before/after.

### K1v2: compact binary rank and workspace

`recipe.id = "k1-binary-rank"` requires the target's
`perf/binary_rank_compact_compare.jl`, companion kernels/cases and, for shards,
`perf/binary_rank_compact_audit.jl`. Four routes share the exact oracle and owned
output contract: prepared product, original rank plan, compact plan, compact plan
with workspace. Each timed episode constructs its plan/workspace and retains H
independent outputs for H=1/32/1024; build/hot observations remain separate.

The smoke profile defaults to `parameters.mode = "decision_smoke"`. The full
profile accepts `decision_screen` or defaults to `shards`, which **requires an
explicit nonempty `dimensions` list** of distinct integers 2..128. Dimensions
are sorted before execution. Dimension parameters are refused for smoke/screen;
native `--full` and preparation-only modes are not exposed as measured recipes.

Example selection (merge into a recipe configuration with suitable budgets):

```toml
[recipe]
id = "k1-binary-rank"
profile = "full"
threads = 1
condition = "exploratory_interference"
interference_label = "Etendue3D"

[parameters]
mode = "shards"
dimensions = [2]
```

Each invocation prepares a fresh full K1v2 manifest, starts a **fresh Julia
process for each selected dimension**, then runs the native coverage auditor in
another process. A dimension contains 324 cases: 3 support families × 3 metrics
× 3 horizons × 3 output queries × 4 routes. Across 127 dimensions, canonical
global indices cover 1..41,148. The packaged supervisor's wall/scratch/archive
budgets cover the **whole invocation**, not each dimension independently; the
native 900-second guard applies to each dimension. Prefer one dimension per
invocation for bounded restart and archived state. Selecting all 127 explicitly
requires budgets for all selected jobs, source snapshots and retained samples.

Native output is archived under `measurements/native`: the full manifest in
`manifest/`, selected dimension directories `n002`..`n128`, and `coverage.toml`.
The package checks condition/label/origin and fingerprint in every native
qualification, validates requested dimension indices and exact completion IDs,
and requires an audit without duplicate or incompatible archives. `partial`
coverage is valid for a requested subset and does not imply full-grid validation.
No prior result is imported by `run-recipe`.

For a global audit after separate invocations, supply one native manifest and
one successful native dimension directory per selected dimension explicitly:

```sh
julia --startup-file=no --threads=1,0 --project=. scripts/garamonbench.jl audit-k1 \
  /results/runA/measurements/native/manifest/k1-binary-rank-protocol.toml \
  /results/coverage-new.toml \
  /results/runA/measurements/native/n002 /results/runB/measurements/native/n003
```

This read-only archive check runs no benchmark and makes no new performance
qualification. It compares the immutable case identities, native fingerprint,
measurement condition and output contract, checks raw episode and summary IDs,
detects duplicate attempts, and lists missing global indices/dimensions. Use a
new output path; invalid coverage is saved for diagnosis and returns an error.
The target's native auditor remains a required dependency, with its hash saved.
An isolated replay needs its own condition-matching manifest and archives;
exploratory and isolated measurements are never combined into one coverage claim.

K1 recipe integration and 55 targeted source tests pass under Julia 1.13;
**a packaged K1 smoke has not yet been executed**. The earlier native 702/936
observations and n002 shard remain separate historical evidence. This recipe
does not implement automatic scheduling/resume, automatic machine-isolation
certification, parallel shard execution, ratio comparisons between campaigns,
or admission of the experimental kernels into Garamon's core.

To replay N01's direct episode screening through the recipe, set
`recipe.id = "binary-rank"`, `recipe.profile = "full"`, `recipe.threads = 1`
and `parameters.mode = "episode_screen"`. The resolved native argument is
`--episode_screen`; retain explicit condition/interference and resource budgets.
The mode was validated with configuration/argument assertions only. Its 648 cases
were not run through this package, and no previous smoke is requalified.

N05 uses `recipe.id = "n05-pfaffian"`, `recipe.profile = "smoke"` or `"full"`,
`recipe.threads = 1` and optional `parameters.reverse = true`. The general
exploratory cap remains four, while this native driver requires one thread.
Its guarded controller import/CLI and relative fixture include receive explicit,
archived adaptations. The common capture saves native PerfChecker evidence;
source snapshots include `perf/n05_protocol.toml`, and the native replay matrix,
diagnostics, environment and qualification files are archived as textual outputs.
The scalar group `coordinates_construction_included` starts from metric and
vector coordinates; `preexisting_contractions` starts with contractions already
available. Their timings must not be merged into one comparison group.
All recipe children now receive `GARAMONBENCH_CONDITION` and
`GARAMONBENCH_INTERFERENCE_LABEL`; isolated plans normalize the effective label
to an empty string and override inherited exploratory labels. The two forwarded
values are archived explicitly, without serializing the remaining environment.
N05's updated native condition parser consumes these declarations. Direct N05
calls without either declaration retain the native historical fallback; the
recipe launcher always supplies both. The historical N05 15/15 smoke was not executed
through `run-recipe` and receives no new qualification here. Only configuration,
argument, source-adapter and protocol-snapshot assertions were run for this addition.

### N05 manifest shards and coverage

With `recipe.profile = "full"`, set either both `parameters.shard_index` and
`parameters.shard_count`, or both `parameters.range_first` and
`parameters.range_last`. Shards use the native modulo selection
`case_id = index, index+count, ... <= 36480`; intervals are inclusive.
The launcher validates integer bounds, refuses mixed/incomplete selections,
limits each subset to 32 cases, and refuses manifest selection with `smoke`.
Without a selection, `full` still runs only the original 23-case slice.

```toml
[recipe]
id = "n05-pfaffian"
profile = "full"
threads = 1
condition = "exploratory_interference"
interference_label = "Etendue3D"
[parameters]
shard_index = 1
shard_count = 1140
reverse = false
```

Add the normal `schema_version = 1` and resource limits to this fragment.
`run-recipe` stores the requested IDs, the native selection CSV and completion
manifest, each native per-case qualification, and all per-case suite samples.
The separately included `n05_shards.jl` receives a checked capture adaptation;
its original/adapted hashes and executed source are archived too. Completion
requires selected IDs and completed IDs to match the request, with no failed
cases and the expected per-case qualification identities. A partial run remains
failed with its available evidence; it never becomes full-grid validation.

A complete repetition requires **1140 fresh invocations**, with indices 1..1140
and count 1140, then an audit. Keep forward and reverse repetitions, source
fingerprints and declared conditions separate. The native
`n05_audit_shards(root)` (from `perf/n05_shards.jl`, with `SHA` and `TOML` loaded)
expects immediate shard-directory children. Point a temporary audit directory's
symlinks at each archived `measurements/native/n05-shard-*` directory in one
repetition, call the native audit, retain its output, then remove the temporary
links. Require complete coverage of all 36,480 IDs with no missing/duplicate or
failed IDs, matching contexts, and present qualification/sample files. There is
no automatic multi-run scheduler or claim that this complete repetition ran.
Only bounded configuration, argument, adaptation and synthetic-evidence tests
were run for this addition; historical N05 data are unchanged.

### Exact source, samples and budgets

External scripts are read from the supplied checkout. The adapter validates
specific source anchors, wraps `run_suite` **after it returns** to save its native
JSON qualification and every table's raw timing/GC/allocation sample, and enables
guarded CLI entrypoints where needed. Workspace/pruning smoke filters are applied
after case admission, before constructing features. Their native full-grid skip
rows remain present and must not be counted as smoke features. Original source,
executed adapted source, adaptation descriptions and both hashes are archived.
A changed interface is refused instead of silently patched. Includes still
resolve from the original checkout; before/after fingerprints detect changes.

Every recipe saves its resolved TOML, exact argument vectors (never inherited
ENV), source snapshots/DrWatson identities, machine snapshots, native logs and
native evidence. A failed child preserves available text results and diagnostics
and marks the run failed. Native suite verdicts are not rewritten; in particular,
pruning and the unpaired upstream Mvec C++ strategy retain their own contracts.
The current external smoke produced 2 samples per feature under PerfChecker's
quick profile: the archive reports actual counts, not nominal driver options.

Linux `/proc` supervision polls the owned process tree every 0.2 s, records its
aggregate RSS and the temporary tree's size, and terminates tracked descendants
on wall/RSS/disk budget violation. These are sampled guards, not kernel-enforced
instantaneous memory caps; short-lived or reparented children can escape an
observation. The controller's own RSS and source archival time are separate from
the child campaign budget. GNU/Linux is currently required for this entrypoint.
Archive/source byte limits are checked independently. Refusals include unknown
parameters, missing sources, changed adapter anchors, unstable source hashes,
non-text artifacts and process-environment dumps. Diagnostics intentionally avoid
printing Julia Process objects.

`TMPDIR` is private per invocation, so generated entrypoints, lifecycle depots,
C++ source trees, libraries and executables are removed on success or failure.
Only intrinsic source snapshots, executed Julia adapter text and textual native
results are retained. The C++ backend still removes its own temporary build
mirror. No generated C++ code or binaries are accumulated in the archive.

Validation: 47 package assertions passed (including an actual timeout and real
PerfChecker harness cases); the 10 external source adapters were checked against
current scripts. A fresh long-horizon smoke is archived as
`20260927T125326_recipe_long-horizon_a5e42ce1`: 2/2 native validated features,
4 raw timing samples, 34.34 s child wall time, exploratory Etendue3D. This verifies
the external path; it does not validate every recipe, an isolated repetition or
a language/strategy speed ranking. Only this one recipe was run through the new
orchestrator; the other eleven received configuration/static integration checks in
this subtask. Older Julia/C++ backend runs retain their original provenance.
See the accompanying research output report.

## Profiling preflight and bounded capture (Julia 1.13, PerfChecker RC1)

This interface selects one exact case from `julia-products` or the dedicated
`profiling_b1w_cases.toml` grid. It preserves a DrWatson case identity, an
independent Int64 oracle, owned output and horizon. The Julia-products kernel
functions are shared by `adapters/garamon_julia.jl` and its profiling factory.
The B1W factory executes the experimental target in `perf/bounds_b1.jl` and
separates build, hot product and complete owned-output episode phases.

```sh
julia --startup-file=no --project=. scripts/garamonbench.jl profile-plan config/profiling.toml
julia --startup-file=no --project=. scripts/garamonbench.jl profile-preflight config/profiling.toml /fresh/output/preflight
# Actual execution, only in an allocated CPU slot:
julia --startup-file=no --project=. scripts/garamonbench.jl profile-capture config/profiling.toml /fresh/output/capture
```

`profile-plan` resolves an exact identity using either `[select]` or
`profiling.case_id`; ambiguous or unknown identities are refused.
`profile-preflight` archives the static plan, native ScenarioCatalog, source
snapshots, worker Project/Manifest and source fingerprints. It does **not**
instantiate packages, load Garamon, execute an oracle or certify compatibility.
The standard PerfChecker `preflight_suite` is deliberately not invoked here:
its dependency preparation can instantiate environments and run probes.

### Implemented routes and current limits

| Requested capability | Implemented path | Qualification boundary |
|---|---|---|
| `benchmark` | `ScenarioSpec` + `run_scenarios` | Fresh prepared state; same full-output oracle; operation timing excludes generation/preparation/verification. |
| `profile` | Native scenario CPU stack capture | `profile_repetitions` windows, each grouping `profile_episode_repetitions` exact owned outputs in one operation; all are verified outside the sample window. Empty usable stacks remain incomplete. These windows are not benchmark timings. |
| `profile_alloc` | Native scenario allocation stacks | Sampling rate is 1; `allocation_repetitions` cycles; no allocation types are serialized by this RC1 interface. |
| `wall_profile` | Native `FeatureSpec` + `run_suite` on the same case factory and independent oracle | RC1 ScenarioSpec excludes this collector. A separate FeatureSpec adapter archives the native suite JSON and folded wall stacks; it is not a benchmark timing. |
| `latency`, `gc`, `memory`, `heap` | `diagnose` in separate native workers | Source/first/warm lifecycle for latency; warmed operation counters for GC; retained/process memory and explicitly redacted heap. No speed verdict. |
| `jet`, `alloccheck` | Native PerfChecker diagnostic adapters | Declared and resolved in `worker/`; one exact Julia vector case passed their runtime capture. Findings still need review per method. |
| Type stability | Standalone `InteractiveUtils.code_warntype` worker | Exact argument type, oracle check and bounded text; no automatic stable/unstable judgment. |
| Flame graph data | Native bundles, folded stacks and Speedscope JSON | No Makie/HTML renderer or PProf dependency is added or claimed available. |

The supplied config requests all these capabilities and permits explicitly
unavailable tools. JET/AllocCheck are blocked if absent from the worker
Project/Manifest on a transferred machine. Set
`allow_unavailable=false` to refuse capture in that situation. Do not interpret
`captured_review_native_statuses` as a complete profiling suite: inspect native
records, capability counts and type-worker status. No unavailable capability
receives a passing result.

Captures use the repository's Linux process-tree supervisor, with wall time,
aggregate sampled RSS and scratch-disk limits. Defaults are one worker thread,
seven benchmark samples, 1,000 CPU-profile windows of 256 operations each,
one allocation-profile cycle,
120 seconds per native job and 600 seconds overall. At most four threads are
admitted. Limits are sampled/cooperative, not hard OS memory quotas. The outer
controller remains one thread. Native results, partial progress, diagnostics,
code text, exports and logs are archived even after a worker failure when
available. Temporary build/request directories are removed. A whole-process
heap snapshot can exhaust the disk budget; that becomes an incomplete capture.

The condition comes from the existing case campaign; isolated mode forwards an
empty interference label. Worker environments receive Pkg offline mode and
precompilation-auto disabled. No install/resolve command is issued. Imports may
still compile cached or missing code, which is why cold latency is a separate
record and never merged with warmed baseline samples. Garamon remains a local
external dependency loaded from `GARAMON_JULIA_ROOT`.

`test/profiling.jl` contains targeted identity, availability, limit, condition,
native catalogue and archival checks; it does not execute Garamon or a
scientific benchmark. The package suite passed under Julia 1.13 after the
wall-profile and crash-recovery changes.
The target-dependent test below and a bounded actual capture also passed under
Julia 1.13. The smoke configuration omits the separate heap diagnostic;
its native CPU, allocation, latency, GC and memory records are archived with
their original identities and qualifications.

Archival follows the RC1 writer's concrete RunBundle layout: `manifest.json`,
`measurement-definitions.json`, `observations.jsonl`, `diagnostics.jsonl`,
`artifacts.json`, `integrity.json`, and the `artifacts/` directory. Native JSONL
is accepted as text alongside TOML/CSV and profile exports; executable files,
symlinks, NUL/non-UTF8 data and process-environment dumps remain refused.
Targeted tests round-trip the catalogue and plan through TOML and round-trip a
synthetic native RunBundle through the archive with its integrity checks.

The default `worker_project="../worker"` resolves to the dedicated measurement
environment, where BenchmarkTools, JET and AllocCheck are declared/resolved.
PerfChecker resets a scenario worker's
initial load path to `@:@stdlib`. The intrinsic factory then explicitly places
`GARAMON_JULIA_ROOT` first **before** importing Garamon, so the target uses its
own project/dependency graph. The target-dependent check was run separately:

```sh
# Private Garamon checkout required; no timed benchmark:
julia --startup-file=no --threads=1,0 --project=. test/profiling_worker.jl
```

That check reproduces the restricted worker load path, imports BenchmarkTools,
loads the target factory, verifies the existing case's oracle and source path,
and checks that neither PerfChecker nor GaramonBench was loaded in the target
process. It is deliberately separate from portable package tests. It has been
executed under Julia 1.13 along with a repeated-output CPU episode check.

The wall and diagnostic preflight checks run on one exact Julia case and verify
that native PerfChecker evidence survives archival. They are separate from
`Pkg.test()` because they load Garamon and run real profiling workers:

```sh
julia --startup-file=no --threads=1,0 --project=. test/profiling_wall_runtime.jl
julia --startup-file=no --threads=1,0 --project=. test/profiling_diagnostics_runtime.jl
```
