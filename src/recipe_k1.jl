"""K1v2 parameters never implicitly launch the 127-dimension replay."""
function recipe_k1_parameters!(parameters,profile,recipe)
    mode=get(parameters,"mode",profile=="smoke" ? "decision_smoke" : "shards")
    mode in ("decision_smoke","decision_screen","shards") || error("K1 mode must be decision_smoke, decision_screen or shards")
    profile=="smoke" && mode!="decision_smoke" && error("K1 smoke profile cannot request a larger campaign")
    label=recipe["interference_label"]
    label isa AbstractString && length(label)<=256 && !any(iscntrl,label) || error("K1 interference_label must be a printable line of at most 256 characters")
    recipe["condition"]=="exploratory_interference" && isempty(strip(label)) && error("K1 exploratory label must not be blank")
    recipe["interference_label"]=strip(label)
    if mode=="shards"
        dimensions=get(parameters,"dimensions",nothing)
        dimensions isa Vector && !isempty(dimensions) &&
            all(n->n isa Integer && !(n isa Bool) && 2<=n<=128,dimensions) || error("K1 shards require explicit dimensions in 2..128")
        length(unique(dimensions))==length(dimensions) || error("duplicate K1 dimensions")
        parameters["dimensions"]=sort(collect(Int,dimensions))
    else
        haskey(parameters,"dimensions") && error("K1 dimensions apply only to shards")
    end
    parameters["mode"]=mode
    parameters
end

function recipe_k1_jobs(plan,root,destination)
    output=joinpath(destination,"native"); mkpath(output)
    controller=joinpath(root,"perf","binary_rank_compact_compare.jl")
    project=joinpath(root,"perf","controller")
    isfile(controller) || error("exact K1v2 target controller required")
    mode=plan["parameters"]["mode"]
    job(name,args;measured=true,script=controller,adaptation_id="k1-binary-rank")=
        (;script,project,threads=1,name,args,measured,adaptation_id)
    mode!="shards" && return [job("k1-"*mode,["--"*mode,joinpath(output,mode)])]
    auditor=joinpath(root,"perf","binary_rank_compact_audit.jl")
    isfile(auditor) || error("exact K1v2 coverage auditor required")
    manifest=joinpath(output,"manifest")
    jobs=[job("k1-manifest",["--prepare",manifest];measured=false)]
    shards=String[]
    for dimension in plan["parameters"]["dimensions"]
        shard="n"*lpad(string(dimension),3,'0'); directory=joinpath(output,shard)
        push!(shards,directory)
        push!(jobs,job("k1-"*shard,["--shard",string(dimension),directory]))
    end
    push!(jobs,job("k1-coverage",vcat([joinpath(manifest,"k1-binary-rank-protocol.toml"),joinpath(output,"coverage.toml")],shards);
        measured=false,script=auditor,adaptation_id="k1-audit"))
    jobs
end

function recipe_k1_verify_protocol(directory,plan,expected_count)
    protocol=TOML.parsefile(joinpath(directory,"k1-binary-rank-protocol.toml"))
    recipe=plan["recipe"]
    protocol["grid_version"]=="K1v2" && protocol["case_count"]==expected_count || error("K1 grid or case count changed")
    protocol["measurement_condition"]==recipe["condition"] && protocol["interference_label"]==recipe["interference_label"] || error("K1 native condition differs from recipe")
    protocol["condition_declaration"]=="environment" || error("K1 native condition was not explicitly forwarded")
    protocol["completed"] && protocol["source_unchanged"] && protocol["execution_state"]=="completed" || error("K1 native execution incomplete or source changed")
    expected=[c["execution_id"] for c in protocol["cases"]]
    length(unique(expected))==expected_count || error("K1 duplicate execution IDs")
    all(protocol[key]==expected for key in ("started_execution_ids","measured_execution_ids","passed_execution_ids")) || error("K1 completion IDs differ from planned IDs")
    isempty(protocol["failed_execution_ids"]) && isempty(protocol["not_started_execution_ids"]) || error("K1 incomplete cases")
    evidence=JSON.parse(read(joinpath(directory,"k1-binary-rank-qualification.json"),String))
    evidence["passed"] && length(evidence["runs"])==expected_count || error("K1 qualification count or verdict differs")
    for run in evidence["runs"]
        q=run["qualification"]
        run["status"]=="pass" && q["measurement_condition"]==recipe["condition"] &&
            q["interference_label"]==recipe["interference_label"] && q["condition_declaration"]=="environment" &&
            q["source_fingerprint"]==protocol["source_sha256"] || error("K1 qualification provenance differs")
        q["execution"]["threads"]==1 && q["execution"]["measurement_condition"]==recipe["condition"] &&
            q["execution"]["interference_label"]==recipe["interference_label"] || error("K1 execution provenance differs")
    end
    protocol
end

function recipe_verify_k1(results,plan)
    native=joinpath(results,"native"); mode=plan["parameters"]["mode"]
    if mode!="shards"
        count=mode=="decision_smoke" ? 12 : 936
        p=recipe_k1_verify_protocol(joinpath(native,mode),plan,count)
        p["mode"]==mode || error("K1 native mode differs")
        return Dict("mode"=>mode,"executed_cases"=>count,"source_sha256"=>p["source_sha256"],
            "coverage_scope"=>"native smoke or paired screen only; not exhaustive replay")
    end
    manifest=TOML.parsefile(joinpath(native,"manifest","k1-binary-rank-protocol.toml"))
    manifest["grid_version"]=="K1v2" && manifest["case_count"]==41148 && length(manifest["shards"])==127 || error("K1 full manifest changed")
    dimensions=plan["parameters"]["dimensions"]
    for n in dimensions
        shard="n"*lpad(string(n),3,'0')
        p=recipe_k1_verify_protocol(joinpath(native,shard),plan,324)
        p["selected_shard"]==shard && p["mode"]=="shard" || error("K1 shard differs")
        p["measured_global_indices"]==collect((n-2)*324+1:(n-1)*324) || error("K1 shard indices differ")
    end
    audit=TOML.parsefile(joinpath(native,"coverage.toml"))
    isempty(audit["issues"]) && isempty(audit["duplicate_measured_index_ranges"]) || error("K1 coverage audit found incompatible or duplicate archives")
    expected_count=324length(dimensions)
    all(audit[k]==expected_count for k in ("distinct_started","distinct_measured","distinct_qualified")) || error("K1 audited count differs")
    audit["expected_cases"]==41148 && audit["missing_cases"]==41148-expected_count || error("K1 audited full coverage differs")
    audit["status"]==(length(dimensions)==127 ? "complete" : "partial") || error("K1 coverage status differs")
    Dict("mode"=>mode,"dimensions"=>dimensions,"executed_cases"=>expected_count,"grid_cases"=>41148,
        "coverage_status"=>audit["status"],"missing_cases"=>audit["missing_cases"],"source_sha256"=>manifest["source_sha256"],
        "coverage_scope"=>"selected dimension shards only; archive measurements/native/coverage.toml records global gaps")
end

"""Read-only coverage audit of explicitly supplied archives; no measurements run.

Uses the target's frozen-contract native auditor and records its source hash.
Archive paths may come from multiple recipe runs with the same native manifest
fingerprint and condition. This is coverage verification, not timing comparison.
"""
function audit_k1(manifest,output,archives;root=abspath(expanduser(get(ENV,"GARAMON_JULIA_ROOT","~/.julia/dev/Garamon"))))
    isempty(archives) && error("supply at least one K1 dimension archive")
    ispath(output) && error("use a fresh coverage output path")
    source=joinpath(root,"perf","binary_rank_compact_audit.jl")
    isfile(source) || error("exact K1v2 native coverage auditor required")
    identity=bytes2hex(sha256(read(source)))
    sandbox=Module(gensym(:K1Coverage))
    Base.include(sandbox,source)
    auditor=Base.invokelatest(getfield,sandbox,:compact_coverage_audit)
    report=Base.invokelatest(auditor,abspath(manifest),abspath.(archives))
    bytes2hex(sha256(read(source)))==identity && report["auditor_sha256"]==identity || error("K1 auditor source changed")
    report["expected_cases"]==41148 || error("not the full K1v2 manifest")
    report["operation"]="coverage audit only; no new performance qualification or measurements"
    write_toml(output,report)
    report["status"]!="invalid" || error("K1 audit found incompatible or duplicate archives; see saved report")
    report
end
