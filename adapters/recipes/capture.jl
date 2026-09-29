# Loaded by the temporary external entrypoint, under the target's pinned environment.
module GaramonRecipeCapture
using PerfChecker, TOML, SHA
const COUNTER = Ref(0)
function include_n05_shards(path)
    source=read(path,String)
    length(findall("run_suite(",source))==1 || error("N05 shard interface changed; expected one run_suite call")
    adapted=replace(source,"run_suite("=>"GaramonRecipeCapture.run_suite(")
    directory=ENV["GARAMONBENCH_CAPTURE"];mkpath(directory)
    write(joinpath(directory,"n05-shards-adapted.txt"),adapted)
    open(joinpath(directory,"n05-shards-adapter.toml"),"w") do io
        TOML.print(io,Dict("original_path"=>path,"original_sha256"=>bytes2hex(sha256(source)),
            "adapted_sha256"=>bytes2hex(sha256(adapted)),
            "adaptation"=>"capture each native per-case suite after return; preserve selection, oracle and comparison keys"))
    end
    Base.include_string(Main,adapted,path)
end
quoted(value) = "\"" * replace(string(value), "\"" => "\"\"") * "\""
function run_suite(args...; kwargs...)
    result = PerfChecker.run_suite(args...; kwargs...)
    COUNTER[] += 1
    directory = ENV["GARAMONBENCH_CAPTURE"]
    mkpath(directory)
    prefix = joinpath(directory, "suite-$(COUNTER[])")
    PerfChecker.write_suite_json(result, prefix * ".json")
    samples = 0
    open(prefix * "-samples.csv", "w") do io
        println(io, "feature,comparison_key,table,sample,time_ns,gc_time_ns,allocated_bytes,allocations")
        for run in result.runs
            run.result isa PerfChecker.CheckerResult || continue
            for (table_id, table) in enumerate(run.result.tables), i in eachindex(table.times)
                # Preserve native arrays, never reconstruct samples from summaries.
                values = (run.planned.feature.id, run.planned.comparison_key, table_id, i,
                          table.times[i], table.gctimes[i], table.memory[i], table.allocs[i])
                println(io, join(quoted.(values), ',')); samples += 1
            end
        end
    end
    open(prefix * "-capture.toml", "w") do io
        TOML.print(io, Dict("perfchecker_version" => string(pkgversion(PerfChecker)),
            "features" => length(result.runs), "samples" => samples,
            "passed" => PerfChecker.suite_passed(result),
            "verdict" => string(PerfChecker.suite_verdict(result)),
            "capture_phase" => "after run_suite returns; outside measurement"))
    end
    return result
end
end
