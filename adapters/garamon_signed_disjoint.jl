pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random, LinearAlgebra

function sd_generate(case,directory,rng)
    n=case["dimension"]
    n in 2:11 || error("signed disjoint dimension budget")
    mode=case["mode"]
    mode in ("prepared","oneshot","pairwise") || error("mode")
    density=case["density"]
    density in (0.01,0.25,1.0) || error("density")
    bits=case["coefficient_bits"]
    bits in (8,64) || error("coefficient bits")
    horizon=case["horizon"]
    horizon in (1,32,256) || error("horizon")
    count=max(1,ceil(Int,density*(1<<n)))
    masks=sort!(UInt64.(randperm(rng,1<<n)[1:count].-1))
    left=Vector{Vector{BigInt}}(undef,horizon)
    right=Vector{Vector{BigInt}}(undef,horizon)
    for t in 1:horizon
        left[t]=BigInt[(BigInt(rand(rng,1:127))<<(bits-7))*
            (isodd(t+i) ? -1 : 1) for i in 1:count]
        right[t]=BigInt[(BigInt(rand(rng,1:127))<<(bits-7))*
            (isodd(t+2i) ? -1 : 1) for i in 1:count]
    end
    (;n,mode,density,bits,horizon,masks,left,right)
end

function sd_prepare(f,case,directory)
    ga=algebra(Matrix{BigInt}(I,f.n,f.n))
    inputs=[(multivector(ga,Dict(mask=>f.left[t][i]
                for (i,mask) in enumerate(f.masks));storage=:sparse),
             multivector(ga,Dict(mask=>f.right[t][i]
                for (i,mask) in enumerate(f.masks));storage=:sparse))
        for t in 1:f.horizon]
    plan=f.mode=="prepared" ? prepare_signed_disjoint_convolution(
        inputs[1]...) : nothing
    (;fixture=f,inputs,plan)
end

function sd_execute(state)
    f=state.fixture
    if f.mode=="prepared"
        return [run_signed_disjoint_convolution(state.plan,a,b).values
            for (a,b) in state.inputs]
    elseif f.mode=="oneshot"
        return [signed_disjoint_convolution(a,b).values
            for (a,b) in state.inputs]
    end
    [wedge(a,b).values for (a,b) in state.inputs]
end

function sd_oracle(state,result)
    expected=state.fixture.mode=="pairwise" ?
        [signed_disjoint_convolution(a,b).values for (a,b) in state.inputs] :
        [wedge(a,b).values for (a,b) in state.inputs]
    result==expected
end

register_adapter!(BenchmarkAdapter(name="garamon_signed_disjoint",
    generate=sd_generate,prepare=sd_prepare,execute=sd_execute,oracle=sd_oracle,
    baseline_execute=state->[wedge(a,b).values for (a,b) in state.inputs],
    baseline_name="garamon_julia_direct_wedge",
    preflight_evidence=(state,result)->Dict{String,Any}(
        "mode"=>state.fixture.mode,"density"=>state.fixture.density,
        "coefficient_bits"=>state.fixture.bits,
        "support"=>length(state.fixture.masks)),
    contract="owned sequence of all exact integer exterior-product coefficients; no term omitted",
    capabilities=Dict(
        "exact_oracle"=>"target partition sum cross-checked against pairwise wedge",
        "domains"=>"integer coefficients, dimension 2 through 11 in the campaign",
        "modes"=>"prepared,oneshot,pairwise",
        "generation_includes_oracle"=>false));replace=true)
