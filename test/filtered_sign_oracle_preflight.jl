using Test, Random
include(joinpath(@__DIR__,"..","adapters","garamon_filtered_sign.jl"))

@testset "filtered sign modes, cancellation and fallback oracle" begin
    for n in (2,4,129), mode in ("prepared","oneshot","direct_bigint"),
        cancellation in ("ordinary","near_zero","exact_zero"),
        bits in (8,128)
        case=Dict{String,Any}("dimension"=>n,"mode"=>mode,
            "signature"=>"mixed","cancellation"=>cancellation,
            "coefficient_bits"=>bits,"horizon"=>n==4 ? 64 : 1)
        fixture=fs_generate(case,"",MersenneTwister(4501))
        state=fs_prepare(fixture,case,"")
        output=fs_execute(state)
        @test fs_oracle(state,output)
        cancellation=="exact_zero" && @test all(iszero,output)
        cancellation=="near_zero" && @test all(==(Int8(1)),output)
        if mode!="direct_bigint" && bits==128
            @test state.fallbacks[]>0
        end
    end
end

