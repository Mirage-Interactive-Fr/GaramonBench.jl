# Execute the packaged guarded PerfChecker campaign, never re-label old data.
# Its fixed unquoted CSV schema is validated before deriving identities.
function cpp_rows(path,expected_header)
    lines=readlines(path)
    !isempty(lines) && split(first(lines),',')==expected_header || error("external CSV schema changed: $path")
    [begin
         cells=split(line,','); length(cells)==length(expected_header) || error("external CSV width")
         Dict(expected_header[i]=>String(cells[i]) for i in eachindex(cells))
     end for line in lines[2:end] if !isempty(line)]
end

function cpp_expected_cases(smoke)
    [Dict{String,Any}("adapter"=>"external_cpp_matched","dimension"=>n,"family"=>family,
        "horizon"=>horizon,"strategy"=>strategy,"seed"=>0,
        "seed_policy"=>"deterministic_cm_value_formula_no_rng",
        "output_contract"=>"owned_all_structural_coefficients")
     for n in (smoke ? (3,) : (3,7))
     for family in (smoke ? ("mixed",) : ("mixed","vectors"))
     for horizon in (smoke ? (32,) : (1,32,1024,10000))
     for strategy in ("julia_jit","julia_precompile","cpp_packed","cpp_upstream")]
end

cpp_key(case)=(case["dimension"],case["family"],case["horizon"],case["strategy"])

function verify_cpp_artifacts(directory,cases)
    warm=cpp_rows(joinpath(directory,"cpp-matched-warm.csv"),
        ["dimension","corpus","horizon","strategy","comparison_group","status","median_ms","p95_ms","allocated_julia_bytes","samples"])
    samples=cpp_rows(joinpath(directory,"cpp-matched-samples.csv"),
        ["dimension","corpus","horizon","strategy","sample","time_ns","gc_time_ns","allocated_julia_bytes","julia_allocations"])
    key(row)=(parse(Int,row["dimension"]),row["corpus"],parse(Int,row["horizon"]),row["strategy"])
    Set(key.(warm))==Set(cpp_key.(cases)) || error("external corpus differs from requested cases")
    length(warm)==length(cases) || error("duplicate external case")
    mapping=Dict(cpp_key(case)=>case for case in cases)
    evidence=Dict{String,Any}[]
    for row in warm
        row["status"]=="pass" || error("external PerfChecker feature did not pass")
        raw=filter(sample->key(sample)==key(row),samples)
        length(raw)==parse(Int,row["samples"]) || error("external raw sample count differs")
        sort(parse.(Int,getindex.(raw,"sample")))==collect(1:length(raw)) || error("sample IDs incomplete")
        push!(evidence,Dict("case_id"=>case_id(mapping[key(row)]),
            "external_feature_id"=>"cpp_$(row["dimension"])_$(row["corpus"])_$(row["horizon"])_$(row["strategy"])",
            "external_comparison_key"=>"garamon/cpp/$(row["comparison_group"])/$(row["dimension"])/$(row["corpus"])/$(row["horizon"])",
            "comparison_group"=>row["comparison_group"],"status"=>row["status"],
            "samples"=>length(raw),"oracle_owner"=>"existing PerfChecker cpp_matched independent oracle"))
    end
    sum(e["samples"] for e in evidence)==length(samples) || error("extra raw sample cases")
    for n in unique(case["dimension"] for case in cases)
        path=joinpath(directory,"cpp-matched-qualification-d$n.json")
        isfile(path) || error("missing qualification JSON")
        qualification=JSON.parse(read(path,String))
        qualification["verdict"]=="validated" || error("external qualification not validated")
        runs=qualification["runs"]
        all(run["status"]=="pass" for run in runs) || error("external qualification has failures")
        expected=Set("cpp_$(case["dimension"])_$(case["family"])_$(case["horizon"])_$(case["strategy"])"
                     for case in cases if case["dimension"]==n)
        Set(run["feature"] for run in runs)==expected || error("qualification feature identities differ")
    end
    return evidence
end

"""Run the target repository's actual paired Julia/C++ campaign in a temporary
C++ source mirror. Binary build trees are removed, original checkouts untouched.
"""
function run_cpp_matched(config;output_root)
    roots=configured_repositories(config)
    all(haskey(roots,k) for k in ("julia","cpp")) || error("both target repositories are required")
    roots=Dict(k=>abspath(expanduser(v)) for (k,v) in roots)
    settings=get(config,"external_cpp",Dict())
    smoke=get(settings,"smoke",true)
    reverse_order=get(settings,"reverse",false)
    cases=cpp_expected_cases(smoke)
    driver=joinpath(dirname(@__DIR__),"adapters","cpp_matched","driver.jl")
    controller=dirname(@__DIR__)
    isfile(driver) || error("packaged C++ driver missing")
    condition=config["campaign"]["condition"]
    runid=Dates.format(now(UTC),dateformat"yyyymmddTHHMMSS")*"_cpp_"*condition*"_"*first(string(uuid4()),8)
    output=joinpath(abspath(output_root),runid); mkpath(output)
    metadata=Dict{String,Any}("schema_version"=>SCHEMA_VERSION,"run_id"=>runid,"status"=>"running",
        "benchmark_backend"=>"external_PerfChecker_fresh_execution",
        "condition"=>condition,"interference_label"=>get(config["campaign"],"interference_label",""),
        "isolation_status"=>"declared_by_operator_not_certified_by_snapshot",
        "cases_expected"=>length(cases),"cases_passed"=>0,"julia_packages"=>package_versions(),
        "seed_policy"=>"upstream deterministic cm_value formula; no RNG",
        "external_driver"=>driver,"external_driver_sha256"=>bytes2hex(open(sha256,driver)))
    identities=Dict{String,Any}()
    write_toml(joinpath(output,"configuration.toml"),config)
    write_toml(joinpath(output,"machine_before.toml"),machine_snapshot())
    try
        for (label,root) in roots
            identities[label]=repository_identity(root;snapshot=joinpath(output,"sources",label))
        end
        metadata["repositories"]=identities
        foreach(case->write_toml(joinpath(output,case_id(case)*".toml"),case),cases)
        with_build_directory() do temporary
            mirror=joinpath(temporary,"cpp"); mkpath(mirror)
            repository_identity(roots["cpp"];snapshot=mirror)
            # Prove that the local, untracked upstream benchmark/ is not needed.
            local_bench=joinpath(mirror,"benchmark")
            isdir(local_bench) && rm(local_bench;recursive=true)
            metadata["cpp_mirror_has_upstream_benchmark_directory"]=isdir(local_bench)
            metadata["native_benchmark_source"]="GaramonBench/adapters/cpp_matched"
            # The content-addressed source artifact has no .git. Pass its pinned
            # revision separately; the temporary mirror remains disposable.
            revision=cpp_source_revision(roots["cpp"])
            destination=joinpath(temporary,"measurements")
            arguments=String[]
            smoke && push!(arguments,"--smoke")
            reverse_order && push!(arguments,"--reverse")
            command=`$(Base.julia_cmd()) --startup-file=no --threads=1,0 --gcthreads=1 --project=$controller $driver $arguments $destination`
            command=addenv(command,"GARAMON_CPP_ROOT"=>mirror,
                           "GARAMON_CPP_REVISION"=>revision,"GARAMON_JULIA_ROOT"=>roots["julia"],
                           "OPENBLAS_NUM_THREADS"=>"1","OMP_NUM_THREADS"=>"1")
            metadata["command_arguments"]=collect(command)
            metadata["original_cpp_root"]=roots["cpp"]
            metadata["temporary_cpp_mirror"]=mirror
            write_toml(joinpath(output,"run.toml"),metadata)
            log=joinpath(temporary,"execution.txt")
            started=time()
            try
                open(log,"w") do io
                    run(pipeline(command;stdout=io,stderr=io))
                end
            catch error
                isfile(log) && archive_file!(log,joinpath(output,"execution.txt"))
                metadata["external_exit_codes"]=failure_exit_codes(error)
                metadata["diagnostic_log"]="execution.txt"
                # ProcessFailedException prints the inherited environment.
                # Preserve the useful child log, not the process object.
                throw(ErrorException("external C++ driver failed; see execution.txt"))
            end
            metadata["external_wall_seconds"]=time()-started
            metadata["case_verdicts"]=verify_cpp_artifacts(destination,cases)
            metadata["cases_passed"]=length(cases)
            artifacts=Dict{String,Any}[]
            for file in sort(readdir(destination))
                push!(artifacts,archive_file!(joinpath(destination,file),joinpath(output,"measurements",file)))
            end
            metadata["artifacts"]=artifacts
            archive_file!(log,joinpath(output,"execution.txt"))
            metadata["temporary_tree_bytes_before_cleanup"]=tree_bytes(temporary)
        end
        metadata["temporary_build_removed"]=true
        for (label,root) in roots
            repository_identity(root)["sha256"]==identities[label]["sha256"] || error("source changed: $label")
        end
        for file in ("Project.toml","Manifest.toml")
            archive_file!(joinpath(dirname(@__DIR__),file),joinpath(output,"environment",file))
        end
        metadata["status"]="passed"
    catch error
        metadata["status"]="failed"; metadata["failure"]=failure_message(error)
        rethrow()
    finally
        write_toml(joinpath(output,"machine_after.toml"),machine_snapshot())
        write_toml(joinpath(output,"run.toml"),metadata)
    end
    output
end
