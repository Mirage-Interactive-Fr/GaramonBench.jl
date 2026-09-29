const SCHEMA_VERSION = 1
const ADAPTERS = Dict{String,Any}()

"""Stage callbacks: generate(case,dir,rng), build(generated,case,dir),
prepare(built,case,dir), execute(state), oracle(state,result), cleanup(state).
`oracle` must check the full agreed result independently of the timed kernel.
"""
Base.@kwdef struct BenchmarkAdapter{G,B,P,E,O,V,C,D,K}
    name::String
    generate::G
    build::B = (generated,case,dir)->generated
    prepare::P = (built,case,dir)->built
    execute::E
    oracle::O
    preflight_evidence::V = (state,result)->Dict{String,Any}()
    cleanup::C = state->nothing
    diagnostics::D = (state,case,directory)->Dict{String,Any}()
    contract::String
    capabilities::K = Dict{String,Any}()
end

function register_adapter!(adapter::BenchmarkAdapter; replace=false)
    haskey(ADAPTERS,adapter.name) && !replace && error("adapter already registered: $(adapter.name)")
    ADAPTERS[adapter.name]=adapter
    return adapter
end

function load_config(path)
    config=TOML.parsefile(path)
    get(config,"schema_version",0)==SCHEMA_VERSION || error("unsupported schema")
    campaign=get(config,"campaign",Dict())
    get(campaign,"condition","") in ("exploratory_interference","isolated") ||
        error("campaign.condition must describe interference explicitly")
    if campaign["condition"]=="exploratory_interference"
        isempty(get(campaign,"interference_label","")) && error("interference_label is required")
    end
    haskey(config,"grid") || error("missing grid")
    config["config_path"]=abspath(path)
    return config
end

# Canonical TOML, rather than Julia's process-dependent hash(), is the identity.
function canonical_toml(value)
    io=IOBuffer(); TOML.print(io,value;sorted=true); return String(take!(io))
end

function case_id(case::AbstractDict)
    label=DrWatson.savename(Dict(k=>case[k] for k in ("dimension","family","strategy") if haskey(case,k)))
    label=replace(label,r"[^A-Za-z0-9_.=-]"=>"_")
    digest=bytes2hex(sha256(canonical_toml(case)))
    return first(label,min(100,length(label)))*"__"*first(digest,16)
end

function expand_cases(config)
    # DrWatson expands independent axes into a Cartesian parameter grid.
    cases=DrWatson.dict_list(config["grid"])
    length(cases)<=get(get(config,"limits",Dict()),"max_cases",256) || error("case budget")
    base=get(config,"case_defaults",Dict{String,Any}())
    result=Dict{String,Any}[]
    for item in cases
        case=merge(Dict{String,Any}(base),Dict{String,Any}(item))
        case["seed"]=get(case,"seed",get(config["campaign"],"seed",20260927))
        haskey(case,"adapter") || error("case needs an adapter")
        case["seed"] isa Integer || error("integer seed required")
        push!(result,case)
    end
    length(unique(case_id.(result)))==length(result) || error("duplicate case identities")
    return result
end

function write_toml(path,data)
    open(path,"w") do io
        TOML.print(io,data;sorted=true)
    end
end

function csv_value(value)
    text=string(value)
    return occursin(r"[,\"\n\r]",text) ? "\""*replace(text,"\""=>"\"\"")*"\"" : text
end

function write_csv(path,rows)
    isempty(rows) && return
    open(path,"w") do io
        println(io,join(string.(keys(first(rows))),','))
        for row in rows
            println(io,join(csv_value.(values(row)),','))
        end
    end
end
