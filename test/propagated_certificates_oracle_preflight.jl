using Test, Random
include(joinpath(@__DIR__,"..","adapters",
    "garamon_propagated_certificates.jl"))

@testset "propagated certificate regimes and independent oracle" begin
    for n in (2,4,129), mode in ("certified","direct"),
        regime in ("stable","cancellation","support_change","metric_change"),
        support in (2,3)
        case=Dict{String,Any}("dimension"=>n,"mode"=>mode,
            "regime"=>regime,"signature"=>"positive",
            "support"=>support,"horizon"=>n==4 ? 32 : 1)
        fixture=pc_generate(case,"",MersenneTwister(4601))
        state=pc_prepare(fixture,case,"")
        output=pc_execute(state)
        @test pc_oracle(state,output)
        if mode=="certified" && n==4
            if regime in ("support_change","metric_change")
                @test state.fallbacks[]==31
            else
                @test state.fallbacks[]==0
            end
        end
    end
end

