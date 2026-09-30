using Test, Random
include(joinpath(@__DIR__,"..","adapters","garamon_cross_gram.jl"))

@testset "cross-Gram rank, invalidation and independent determinant" begin
    for n in (3,4,129),mode in ("prepared","direct"),
        signature in ("positive","mixed","degenerate"),
        k in (2,3),regime in ("generic","dependent"),
        mutation in ("stable","vector_change","metric_change")
        case=Dict{String,Any}("dimension"=>n,"mode"=>mode,
            "signature"=>signature,"grade"=>k,"rank_regime"=>regime,
            "vector_support"=>2,"mutation"=>mutation,
            "horizon"=>n==4 ? 32 : 1)
        fixture=cg_generate(case,"",MersenneTwister(3601))
        state=cg_prepare(fixture,case,"")
        result=cg_execute(state)
        @test cg_check(state,result)
        if mode=="prepared" && n==4
            @test state.fallbacks[]==(mutation=="stable" ? 0 : 31)
        end
        if regime=="dependent" && mode=="prepared"
            @test state.plan.rank<k
            @test iszero(state.plan.determinant)
        end
    end
end
