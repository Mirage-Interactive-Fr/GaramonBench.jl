using Test, Random
include(joinpath(@__DIR__,"..","adapters","garamon_givens.jl"))

@testset "factored and materialized Givens adapter oracle" begin
    for n in (2,4,129), mode in ("factored","materialized"),
        grade in (1,2), angle in ("3-4-5","5-12-13")
        case=Dict{String,Any}("dimension"=>n,"mode"=>mode,
            "rotation_count"=>2,"support"=>4,"grade"=>grade,
            "angle"=>angle,"horizon"=>1)
        fixture=givens_bench_generate(case,"",MersenneTwister(3801))
        state=givens_bench_prepare(fixture,case,"")
        result=givens_bench_execute(state)
        @test givens_bench_oracle(state,result)
    end
end

