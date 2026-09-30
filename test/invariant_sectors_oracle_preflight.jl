using Test, Random
include(joinpath(@__DIR__,"..","adapters","garamon_invariant_sectors.jl"))

@testset "invariant sector parity, fallback and independent oracle" begin
    for n in (2,4,129), mode in ("prepared","direct"),
        parity in ("all","even","odd"),
        regime in ("stable","support_change","metric_change")
        case=Dict{String,Any}("dimension"=>n,"mode"=>mode,
            "output_parity"=>parity,"regime"=>regime,
            "signature"=>"mixed","support"=>3,
            "horizon"=>n==4 ? 32 : 1)
        fixture=ps_generate(case,"",MersenneTwister(3201))
        state=ps_prepare(fixture,case,"")
        result=ps_execute(state)
        @test ps_check(state,result)
        if mode=="prepared" && n==4
            @test state.fallbacks[]==(regime=="stable" ? 0 : 31)
        end
    end
end
