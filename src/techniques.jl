const TECHNIQUE_STATES=Set(["implemented","prototype","research"])
const TECHNIQUE_CONTRACTS=Set(["exact","approximate","decision","orchestration"])
const COMPATIBILITY_CODES=Set(["O","?","X1","—"])

"""Read and check all 46 declared techniques without claiming runtime readiness."""
function technique_inventory(;benchmark_root=dirname(@__DIR__),
    julia_root=garamon_source_root())
    file=joinpath(benchmark_root,"config","techniques.toml")
    registry=TOML.parsefile(file)
    registry["schema_version"]==1 || error("technique registry schema")
    entries=registry["technique"]
    ids=getindex.(entries,"id")
    ids==[lpad(string(n),2,'0') for n in 1:46] ||
        error("technique registry must cover 01..46 exactly and in order")
    recipes=Set(getindex.(TOML.parsefile(joinpath(benchmark_root,"config","campaigns.toml"))["campaign"],"id"))
    rows=Dict{String,Any}[]
    for entry in entries
        entry["state"] in TECHNIQUE_STATES || error("unknown technique state: "*entry["id"])
        contract=get(entry,"contract","exact")
        contract in TECHNIQUE_CONTRACTS || error("unknown contract: "*entry["id"])
        source=entry["source"];test=entry["test"];campaign=entry["campaign"]
        entry["state"]=="research" && (!isempty(source) || !isempty(test)) &&
            error("research-only technique advertises existing implementation: "*entry["id"])
        !isempty(campaign) && !(campaign in recipes) &&
            error("technique refers to unknown recipe: "*entry["id"])
        preflight_config=get(entry,"preflight_config","")
        preflight_adapter=get(entry,"preflight_adapter","")
        preflight_environment=get(entry,"preflight_environment","")
        any(value->!isempty(value),(preflight_config,preflight_adapter,preflight_environment)) &&
            !(all(value->!isempty(value),(preflight_config,preflight_adapter,preflight_environment)) &&
              isfile(joinpath(benchmark_root,preflight_config)) &&
              isfile(joinpath(benchmark_root,preflight_adapter)) &&
              isfile(joinpath(benchmark_root,preflight_environment,"Project.toml"))) &&
            error("incomplete preflight registration: "*entry["id"])
        push!(rows,Dict{String,Any}("id"=>entry["id"],"name"=>entry["name"],
            "state"=>entry["state"],"contract"=>contract,
            "source"=>source,"source_present"=>!isempty(source) && isfile(joinpath(julia_root,source)),
            "test"=>test,"test_file_present"=>!isempty(test) && isfile(joinpath(julia_root,test)),
            "campaign"=>campaign,"recipe_declared"=>!isempty(campaign),
            "preflight_config"=>preflight_config,
            "preflight_adapter"=>preflight_adapter,
            "preflight_environment"=>preflight_environment,
            "preflight_registered"=>!isempty(preflight_config),
            "preflight_qualified"=>false,"perfchecker_profile_qualified"=>false))
    end
    combinations=get(registry,"combination",[])
    all(c->all(in(ids),c["techniques"]) && isfile(joinpath(julia_root,c["source"])) &&
        isfile(joinpath(julia_root,c["test"])),combinations) ||
        error("declared combination source or test is unavailable")
    matrix=compatibility_matrix(joinpath(benchmark_root,registry["compatibility_matrix"]))
    Set(keys(registry["compatibility_conditions"]))==Set("C"*string(n) for n in 1:20) ||
        error("compatibility conditions must define C1..C20")
    pairs=Dict{String,Any}[]
    for a in 1:45,b in a+1:46
        left=ids[a];right=ids[b];code=matrix[(left,right)]
        push!(pairs,Dict("left"=>left,"right"=>right,"compatibility"=>code,
            "implemented_combination"=>any(c->Set(c["techniques"])==Set([left,right]),combinations)))
    end
    Dict{String,Any}("schema_version"=>1,"registry_sha256"=>_resume_sha(file),
        "matrix_sha256"=>_resume_sha(joinpath(benchmark_root,registry["compatibility_matrix"])),
        "julia_root"=>abspath(julia_root),"techniques"=>rows,
        "technique_count"=>length(rows),"pairs"=>pairs,"pair_count"=>length(pairs),
        "source_present_count"=>count(r->r["source_present"],rows),
        "test_file_present_count"=>count(r->r["test_file_present"],rows),
        "preflight_registered_count"=>count(r->r["preflight_registered"],rows),
        "research_count"=>count(r->r["state"]=="research",rows),
        "note"=>"source/test file existence is only static evidence; no technique is promoted to preflight or profiling qualification")
end

"""Read the machine-readable contract matrix and require 46x46 symmetry."""
function compatibility_matrix(path::AbstractString)
    isfile(path) || error("compatibility matrix missing")
    matrix=Dict{Tuple{String,String},String}()
    ids=[lpad(string(i),2,'0') for i in 1:46]
    lines=readlines(path)
    length(lines)==47 || error("compatibility matrix must contain one header and 46 rows")
    split(first(lines),',')==vcat("id",ids) || error("compatibility matrix header invalid")
    for (index,line) in enumerate(lines[2:end])
        cells=split(line,',')
        length(cells)==47 && first(cells)==ids[index] ||
            error("compatibility matrix row invalid: $index")
        for (offset,code) in enumerate(cells[2:end])
            code in COMPATIBILITY_CODES || occursin(r"^C([1-9]|1[0-9]|20)$",code) ||
                error("unknown compatibility code "*code)
            key=(ids[index],ids[offset])
            haskey(matrix,key) && error("duplicate compatibility cell")
            matrix[key]=code
        end
    end
    length(matrix)==46*46 || error("compatibility matrix incomplete: $(length(matrix))/2116")
    for a in 1:46,b in 1:46
        left=lpad(string(a),2,'0');right=lpad(string(b),2,'0')
        matrix[(left,right)]==matrix[(right,left)] ||
            error("compatibility matrix asymmetric at $left/$right")
        (a==b)==(matrix[(left,right)]=="—") ||
            error("compatibility diagonal invalid at $left/$right")
    end
    matrix
end
