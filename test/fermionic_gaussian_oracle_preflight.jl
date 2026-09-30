using Test, Random
include(joinpath(@__DIR__,"..","adapters","garamon_fermionic_gaussian.jl"))

@testset "fermionic Gaussian factorization and overlap oracle" begin
    for n in (3,4,129),mode in ("factored","materialized"),
        particles in (2,3),shears in (1,4,16),
        relation in ("same","shifted")
        case=Dict{String,Any}("dimension"=>n,"mode"=>mode,
            "particles"=>particles,"shear_count"=>shears,
            "orbital_support"=>2,"target_relation"=>relation,
            "horizon"=>n==4 ? 32 : 1)
        fixture=fg_generate(case,"",MersenneTwister(3701))
        state=fg_prepare(fixture,case,"")
        result=fg_execute(state)
        @test fg_check(state,result)
        @test (state.plan.matrix===nothing)==(mode=="factored")
    end
end
