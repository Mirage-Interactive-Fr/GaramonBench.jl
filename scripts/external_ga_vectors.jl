using GaramonBench

function main(args)
    isolated = "--isolated" in args
    paths = filter(!=("--isolated"), args)
    length(paths) <= 1 || error("usage: external_ga_vectors.jl [--isolated] [RESULTS_DIRECTORY]")
    isempty(paths) ? bench(;isolated) : bench(;isolated, output=only(paths))
end

main(ARGS)
