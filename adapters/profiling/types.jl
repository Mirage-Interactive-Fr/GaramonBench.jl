# Standalone worker: no GaramonBench or PerfChecker load in the target process.
using TOML, InteractiveUtils
request=TOML.parsefile(ARGS[1]);output=ARGS[2]
owner=Module(:GaramonBenchTypeProbe)
Base.include(owner,request["source"])
case=Base.invokelatest(getfield(owner,:make_case),Dict("case"=>request["case"],
    "adapter_source"=>get(request,"adapter_source","")))
state=Base.invokelatest(case.prepare)
try
    result=Base.invokelatest(case.operation,state)
    Base.invokelatest(case.verify,state,result)===true || error("type probe oracle failed")
    signature=Tuple{typeof(state)}
    io=IOBuffer();InteractiveUtils.code_warntype(io,case.operation,signature;debuginfo=:source)
    text=String(take!(io));limit=request["type_text_bytes"]
    truncated=ncodeunits(text)>limit
    # Prefix is shortened by characters, preserving UTF-8; byte cap is checked again.
    while ncodeunits(text)>limit;text=first(text,length(text)÷2);end
    write(output,text)
    open(output*".toml","w") do sink
        TOML.print(sink,Dict("status"=>"complete","oracle_passed"=>true,"argument_type"=>string(signature),
            "truncated"=>truncated,"scope"=>"InteractiveUtils.code_warntype; diagnostic text, not a universal type-stability or speed verdict"))
    end
finally
    Base.invokelatest(case.cleanup,state)
end
