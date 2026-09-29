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

## Run and resume the EGA3 comparison

From Julia:

~~~julia
using GaramonBench
bench()
~~~

This runs an oracle preflight and then measures the same EGA3 vector-product
requests with Garamon.jl, GAL, and Versor. The resulting whole-library
comparison does not isolate a language effect because the internal
strategies differ. The run writes a CSV summary and a vector PDF chart.
A default run is marked exploratory; its timings do not populate the
article.

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

The article's empty figure slots are deliberate. A plot is published only
after its generating case set is qualified; old exploratory plots are never
inserted automatically into the manuscript.
