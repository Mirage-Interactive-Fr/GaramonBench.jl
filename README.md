# GaramonBench.jl

GaramonBench.jl is a reproducible benchmark harness for geometric algebra
workloads. It records inputs, seeds, source revisions, machine information,
correctness checks, raw samples, and derived plots through DrWatson. The
package includes Garamon.jl strategies and matched C++/Julia routes. Other
GA libraries are added only for mathematical workloads they can implement
and validate.

The accompanying article is a methods manuscript. It contains empty result
slots and no preliminary timing claims. Qualified results from the dedicated
benchmark machine will fill those slots.

## Install

Use Julia 1.13:

~~~julia
using Pkg
Pkg.develop(url="https://github.com/Mirage-Interactive-Fr/GaramonBench.jl.git")
using GaramonBench
~~~

The package pins the Garamon C++ source and optional third-party GA sources
as Julia artifacts. CMake, Clang, Ninja, and Eigen come through Julia binary
dependencies. A manual C++ clone is unnecessary for the packaged workflows.
The resolved Manifest.toml should accompany a shared campaign.

Garamon.jl and GaramonBench.jl development checkouts belong under
~/.julia/dev. Set GARAMON_JULIA_ROOT only when a different local Garamon.jl
checkout is intentionally used.

## Launch the complete technique campaign

On the dedicated machine, use Julia 1.13 and launch the controller with
automatic threads:

~~~sh
julia --startup-file=no -t auto --project="$HOME/.julia/dev/GaramonBench"
~~~

Then:

~~~julia
using GaramonBench
bench(campaign=:techniques, isolated=true,
      output="/data/garamonbench/run-001")
~~~

The controller selects native environments and thread counts automatically.
The current registry uses one thread for ordinary routes, four threads for
route 27, and the CUDA environment for route 29. The controller's `-t auto`
does not change these declared measurement protocols. Groups run sequentially
to avoid competing benchmark workloads. BLAS and OpenMP subprocesses use one
thread. Each archive records the actual Julia threads, worker identity, machine
and environment. The process route creates and removes its own Julia worker.

`gpu=:auto` checks CUDA and explicitly records a skipped GPU route if no
functional device is present. Use `gpu=:required` to require GPU coverage,
or `gpu=:off` for a CPU-only campaign. Optional GPU dependencies are installed
before measuring any group. No manual activation of the CUDA environment is
needed. Inspect `technique_launch_plan()` to see the groups without running.

For a correctness-only screen of the launcher:

~~~julia
run_technique_campaign("/data/garamonbench/preflight-001";
                       phase=:preflight, ids=["01", "27", "29"])
~~~

The complete benchmark performs a minimal preflight first. It does not repeat
the preparation machine's PerfChecker optimization pass. `phase=:profiles`
is available separately when profiling is explicitly requested.

Press Ctrl-C to stop. Repeat the same `bench` call with the same output path
to resume; validated cases and shared baselines are checked and skipped.
ProgressMeter displays each active route's count and ETA. The controller
records stage completion in `launch-progress.toml`; each route retains its
own detailed checkpoint. Keep the same sources, settings and machine when
resuming. By default all raw data are retained. Qualified figures and the
article update after each completed route; `article_every_cases=100` enables
intermediate updates during longer routes.

## Run and resume the EGA3 comparison

From Julia:

~~~julia
using GaramonBench
bench()
~~~

`bench()` without `campaign=:techniques` retains the separate EGA3
whole-library comparison described here.

This runs an oracle preflight and then measures the same EGA3 vector-product
requests with Garamon.jl, GAL, and Versor. The resulting whole-library
comparison does not isolate a language effect because the internal
strategies differ. The run writes a CSV summary and a vector PDF chart.
A default run is marked exploratory; its timings do not populate the
article.
ProgressMeter.jl shows separate preflight and benchmark bars
with counts and an ETA. Repeating the same call after an interruption starts
the bars at the number of validated cases in the archive. The ETA uses cases
finished since this launch, so it is approximate when case sizes differ.
Use `show_progress=false` to suppress the bars in redirected logs.

On the dedicated machine, after confirming it has no competing workload:

~~~julia
bench(isolated=true)
~~~

The isolation flag records the operator's declaration; it cannot reserve
the machine automatically. Once all cases pass, the qualified EGA3 plot
replaces its article placeholder. Other article slots remain empty until
their own campaigns provide qualified data.

To place data on a dedicated volume:

~~~julia
bench(output="/data/garamonbench/run-001", isolated=true)
~~~

`bench()` keeps every raw sample, source snapshot, preflight archive and
intermediate by default. To remove only unfinished staging contents after a
completed run, use `bench(output="/data/garamonbench/run-001",
isolated=true, cleanup=:temporary)`. To retain only the verified CSV summary,
figure, article PDF and their hashes, use `cleanup=:paper`. The same option
can be supplied when resuming an already completed run; completed cases are
checked and skipped before cleanup. A later call on a compacted directory
returns its verified final results without trying to recreate deleted cases.

The cleanup operation is also available separately:

~~~julia
cleanup_bench_data("/data/garamonbench/run-001"; mode=:paper)
~~~

`:paper` removes the preflight and benchmark archives only after checking the
completed campaign, the CSV, the figure, the article PDF, and their hashes.
The detailed samples and source snapshots cannot be audited after this
compaction. Use a new output directory to measure again. The package's
technique campaigns remain fully retained until their own figures and article
outputs are qualified; this cleanup function does not delete them.

Raw campaigns, exploratory outputs, profiling captures, and temporary build
products under `data/garamonbench` remain ignored by Git. A complete isolated
run also copies its qualified article table and provenance to
`data/processed/garamonbench/external-ga-vectors/<signature>/<archive-id>/`.
These processed CSV and TOML files are **not ignored** and can be committed
with the article. Generated PDFs remain ignored, as required by the repository
policy. The processed table is written only after every library route passes
its oracle and the article artifacts are verified.

Resume an interrupted run by repeating the same call with the same output
path, project, sources, configuration, and machine. Completed cases are
rechecked and skipped; incomplete cases are rerun. A new machine or source
revision needs a new results directory. The campaign uses a recorded common
seed. Preparation and compilation are separated from product timing.

The default DrWatson layout is:

~~~text
data/garamonbench/external-ga-vectors/<condition>/
    preflight/
    benchmark/cases/<case-id>/samples.csv
    summary.csv
    report.toml
plots/garamonbench/external-ga-vectors/<condition>/<signature>/<archive-id>/
    ega3_vector_libraries.pdf
    qualified_ega3_vector_libraries.pdf  (completed isolated run only)
papers/garamonbench/external-ga-vectors/<condition>/<signature>/<archive-id>/
    Garamon_research_article_2026-09-27_en.pdf
papers/Garamon_research_article_2026-09-27_en.tex
papers/Garamon_research_article_2026-09-27_en.pdf
~~~

The last PDF is the current canonical article build. An isolated completed
run updates it. LaTeX compilation requires TeX Live and latexmk. Generated
PDFs and the data and plot directories are ignored by Git.

## Other strategies

The technique registry is in config/techniques.toml. It distinguishes
implemented routes, prototypes, and research proposals. The pairwise
mathematical composition matrix is in config/compatibility_matrix.csv;
its conditions are in the same TOML registry. Neither file asserts a
performance ranking.

The registered technique workflow uses the same DrWatson archive structure.
Choose a campaign name once and reuse it when resuming:

~~~julia
using GaramonBench, DrWatson
root = DrWatson.datadir("garamonbench", "techniques-dedicated-001")
preflight = joinpath(root, "preflight")
run_technique_smoke(preflight)
run_technique_profiles(preflight, joinpath(root, "profiles"))
run_technique_bench(preflight, joinpath(root, "benchmark"))
~~~

`run_technique_bench` shows a ProgressMeter.jl bar for each active route.
On restart, each bar starts at that route's validated case count;
fully completed routes are skipped. The ETA is recalculated from the current
run and may change substantially as dimensions and strategies vary. Pass
`show_progress=false` to disable the bars.

The smoke run checks one oracle case per registered route. A passed case
creates a vector validation card beside that method in the article, with no
timing or speed claim. Profiling captures
bounded PerfChecker diagnostics on that case. The benchmark runs the full
parameter grid only after a matching smoke archive exists. Each route has its
own resumable directory; completed cases are verified and skipped when the
benchmark call is repeated. An incomplete PerfChecker capture requires a new
profile output directory. Use `ids=["12", "13"]` on any of these functions to
select routes. Run CPU routes from the package environment with their
registered thread count; GPU routes require the package's `gpu/` environment.
When running from `gpu/`, keep the same archive in the main project's
DrWatson data directory:

~~~julia
root = DrWatson.datadir(joinpath(pkgdir(GaramonBench), "data",
    "garamonbench", "techniques-dedicated-001"))
preflight = joinpath(root, "preflight")
run_technique_smoke(preflight; ids=["29"])
run_technique_profiles(preflight, joinpath(root, "profiles"); ids=["29"])
run_technique_bench(preflight, joinpath(root, "benchmark"); ids=["29"])
~~~

Routes that declare the same exact generated inputs share one measured
Garamon.jl baseline. Its samples are stored under `benchmark/_baselines/` and
referenced by later route cases, so the baseline is not measured again. Resume
and archive audit verify the reference and its content hash. Transfer the
complete `benchmark/` directory, including `_baselines/`, to preserve these
references. Routes without a proved common input identity retain separate
baseline measurements.
Inspect `technique_bench_plan()` for route case counts before starting a large
campaign. The article currently has 48 figure slots, one per registry entry.
Preflight cards fill empty slots temporarily; only qualified completed
performance data from the dedicated machine may replace them with benchmark
figures.

After each completed technique, `run_technique_bench` exports its paired
timing summary to `data/processed/garamonbench/techniques/`, with a parameter
table and provenance. It renders an XKCDMakie vector PDF in the method's
existing article slot and compiles the article. Each point compares the
strategy with its Garamon.jl baseline on the same inputs; triangles mark
times above 10× baseline. The CSV retains the uncapped ratios.
Pass `article_every_cases=100` to refresh during a long route using only its
completed, oracle-validated cases. The plot title reports partial coverage.
Pass `update_article=false` to postpone rendering. A completed campaign can
be called again to regenerate its article artifacts without rerunning cases.

The configurations under config/ and adapters under adapters/ define
oracle preflights, CPU and GPU routes, matched C++/Julia kernels, cache
policies, sparse and dense storage, targeted outputs, workspaces, and
structured special cases. Use the supplied CLI to inspect or run a chosen
configuration from the package root:

~~~sh
julia --startup-file=no --threads=1 --project=. scripts/garamonbench.jl list config/julia_products.toml
julia --startup-file=no --threads=1 --project=. scripts/garamonbench.jl run config/smoke.toml /path/to/results
~~~

The full campaigns are intended for a dedicated machine. Every strategy
is first checked against its declared output contract and independent
oracle. PerfChecker diagnostics and extensive crossed benchmarks follow
qualification. Sparse high-dimensional requests, dense small algebras,
stable and changing supports, general metrics, reuse horizons, CPU thread
counts, and GPU residency are separate workload axes. A C++/Julia speed
comparison is made only for matched algorithms and outputs.

## Provenance and integrity

A campaign records its configuration, seed, machine snapshot, Julia
environment, source identity, case status, oracle verdict, and raw samples.
The archive audit can detect a changed source or incomplete case. Removing
archived source snapshots prevents a full historical integrity check, even
when timing CSV files remain. Do not reuse timing samples from a different
machine as if they were local measurements.

The article's unqualified performance slots are deliberate. Preflight cards
report oracle coverage without timings. A performance plot is published only
after its generating case set is qualified; exploratory timings are never
inserted automatically into the manuscript.

CPU and GPU article artifacts use the package's `plots/` and `papers/`
DrWatson directories, regardless of the active Julia environment. Each LaTeX
build compiles in a private temporary directory, then atomically publishes
the completed PDF. Independent preflights can therefore refresh the article
concurrently without sharing compiler output files.

## V50: registered campaign coverage

Every registry entry has executable code, an independent bounded oracle gate, a resumable parameter grid and its own article figure slot. These gates do not assert a performance ranking or correctness of every future parameter combination. Native PerfChecker probes recorded on earlier revisions remain historical evidence; captures used to qualify a run must match the archived source identity.

The dedicated campaign schedules 56351 cases before optional user restrictions. `benchmark_grid` overrides extend the one-case preflight without changing its case identity. The full rational sandwich at high ambient dimension is reserved for the dedicated machine and has an explicit expansion budget.

| ID | Route | Code | Oracle | Scheduled cases | Figure slot |
|---|---|---|---|---:|---|
| 01 | dense-global | implemented | bounded | 132 | 01 |
| 02 | sparse-supports | implemented | bounded | 78 | 02 |
| 03 | grade-blocks | implemented | bounded | 168 | 03 |
| 04 | targeted-recursion | implemented | bounded | 84 | 04 |
| 05 | exact-grade-filter | implemented | bounded | 84 | 05 |
| 06 | xor-join | implemented | bounded | 84 | 06 |
| 07 | join-three | implemented | bounded | 84 | 07 |
| 08 | prepared-plans | implemented | bounded | 78 | 08 |
| 09 | workspaces | implemented | bounded | 78 | 09 |
| 10 | lru-plan-cache | implemented | bounded | 504 | 10 |
| 11 | roulette-plan-eviction | implemented | bounded | 12600 | 11 |
| 12 | tinylfu-plan-admission | prototype | bounded | 1512 | 12 |
| 13 | sieve-plan-eviction | prototype | bounded | 504 | 13 |
| 14 | jit-code-generation | implemented | bounded | 60 | 14 |
| 15 | precompilation-catalogue | prototype | bounded | 21 | 15 |
| 16 | dag-subexpression-sharing | implemented | bounded | 4 | 16 |
| 17 | factorized-blades-versors | implemented | bounded | 288 | 17 |
| 18 | active-coordinate-subspace | implemented | bounded | 2 | 18 |
| 19 | exact-tensor-train | prototype | bounded | 42 | 19 |
| 20 | weighted-zdd | prototype | bounded | 72 | 20 |
| 21 | materialized-trie | prototype | bounded | 60 | 21 |
| 22 | clifford-matrix-gfft | prototype | bounded | 348 | 22 |
| 23 | egraph-rewriting | prototype | bounded | 680 | 23 |
| 24 | deferred-exact-replay | prototype | bounded | 648 | 24 |
| 25 | approximate-pruning-roulette | prototype | bounded | 35 | 25 |
| 26 | analytic-triple-selector | prototype | bounded | 78 | 26 |
| 27 | cpu-threads-simd-batches | implemented | bounded | 2 | 27 |
| 28 | cpu-processes | prototype | bounded | 288 | 28 |
| 29 | gpu-kernels-transfers | prototype | bounded | 4 | 29 |
| 30 | blade-masks-combinatorial-index | implemented | bounded | 28 | 30 |
| 31 | binary-support-rank | prototype | bounded | 168 | 31 |
| 32 | invariant-sectors | prototype | bounded | 3240 | 32 |
| 33 | radical-nilpotence | prototype | bounded | 432 | 33 |
| 34 | short-polynomial-identity | prototype | bounded | 5376 | 34 |
| 35 | pfaffian-scalar-chain | prototype | bounded | 216 | 35 |
| 36 | cross-gram-rank | prototype | bounded | 4320 | 36 |
| 37 | fermionic-gaussian-operators | prototype | bounded | 1440 | 37 |
| 38 | givens-basis-change | prototype | bounded | 2880 | 38 |
| 39 | signed-disjoint-convolution | prototype | bounded | 540 | 39 |
| 40 | bilinear-kernel-synthesis | prototype | bounded | 360 | 40 |
| 41 | verified-superoptimization | prototype | bounded | 1080 | 41 |
| 42 | wavefront-recursion | prototype | bounded | 8064 | 42 |
| 43 | adaptive-radix-tree | prototype | bounded | 1008 | 43 |
| 44 | multimodular-crt | prototype | bounded | 4590 | 44 |
| 45 | filtered-adaptive-precision | prototype | bounded | 2430 | 45 |
| 46 | propagated-structural-certificates | prototype | bounded | 1440 | 46 |
| K1 | K1 | prototype | bounded | 78 | K1 |
| K3 | K3 | prototype | bounded | 39 | K3 |

Dimension limits follow the output contract, mask representation and oracle budget. Catalogue requests cover the trained EGA3 algebra and untrained/changing 4D contexts; they are not a general-dimension catalogue. The full-coefficient tensor-train grid is restricted to dimensions 2–8 because its independent oracle enumerates all blade pairs. The materialized trie uses UInt64 masks up to dimension 64. Large ambient-dimensional Pfaffian chains keep the active vector span small so the full-output oracle remains tractable.

The radical-inverse route varies ambient dimension, radical size, active nonradical coordinates, metric and coefficient phase. Ordinary Garamon.jl general `inv` is limited to five coordinates. Above that ambient dimension its baseline operates in the exactly isomorphic active coordinate subalgebra of at most five axes and embeds the complete inverse back. This restriction is explicit; no general high-dimensional inverse performance claim is implied.

Run the boundary gates without timing samples using `julia --project=. --threads=1 test/campaign_variants.jl`. Optional subsets are selected with `GARAMONBENCH_VARIANT_IDS`; values `28` and `15` exercise real workers and native catalogue reloads respectively. These remain correctness gates, not benchmarks.
