using Test, Random
include(joinpath(@__DIR__,"..","adapters","garamon_signed_disjoint.jl"))

@testset "signed disjoint campaign modes and exact oracle" begin
    for n in (2,4,11), mode in ("prepared","oneshot","pairwise"),
        density in (0.01,0.25,1.0)
        case=Dict{String,Any}("dimension"=>n,"mode"=>mode,
            "density"=>density,"coefficient_bits"=>8,
            "horizon"=>n==4 ? 32 : 1)
        fixture=sd_generate(case,"",MersenneTwister(3901))
        state=sd_prepare(fixture,case,"")
        @test sd_oracle(state,sd_execute(state))
    end
end

