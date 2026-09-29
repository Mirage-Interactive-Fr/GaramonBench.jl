# Boundary for matched Julia/C++ campaigns

Do not move the existing `Garamon/perf/cpp_matched*.jl` files automatically.
First validate a fresh adapter against the same fixture and oracle. Distinguish:
upstream generated C++ Mvec products, the matched packed C++ loop, Julia packed
products, Julia direct products, and Julia workspaces. They are separate
strategies with distinct preparation and generation costs.

Each adapter stage must return data needed by the next stage:

1. `generate(case, temporary_directory, rng)` creates exact inputs, output-mask
   order, independent oracle and any generator input. It records all seeds.
2. `build(generated, case, temporary_directory)` invokes the generator/compiler
   in that directory, records full argument vectors and flags, tool versions,
   generated source hashes and native resource measurements. No shell string
   assembled from case values, and no persistent compiled library cache.
3. `prepare(built, case, temporary_directory)` packs coefficients, creates
   native contexts or Julia workspaces, and loads compiled code.
4. `execute(state)` returns the same fully materialized, owned output for all
   compared strategies. A checksum-only API is a different contract.
5. `oracle(state, result)` compares every requested coefficient and checks
   completeness of output masks. Integer/dyadic fixtures allow exact checks;
   approximate arithmetic requires declared tolerances and an independent bound.
6. `cleanup(state)` releases C pointers and library handles. The harness then
   removes the temporary build tree, including generated binaries.

External child metrics cannot be inferred from `@timed`: add explicit native
wall time, peak RSS, disk monitoring and exit-code observations to the adapter.
Likewise record CUDA synchronization, transfer bytes, active/pooled VRAM and
kernel compilation only once an actual GPU adapter exists.

The present callback runner executes real PerfChecker features but does not yet
provide continuous subprocess guards or an external `CheckerResult` importer.
Keep the existing guarded C++ runner
and its PerfChecker verdict until these integrations are implemented and tested.
Text CSV/TOML artifacts may be copied with `archive_file!`; their original
backend, source fingerprint, output contract, sample schema and interference
condition must remain attached. Never relabel an imported pass as a newly run
GaramonBench or PerfChecker validation.
