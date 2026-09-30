# One bounded trie wedge with an independent integer Clifford-word oracle.
pushfirst!(LOAD_PATH, get(ENV, "GARAMON_JULIA_ROOT",
    joinpath(homedir(), ".julia", "dev", "Garamon")))
using Garamon, GaramonBench, Random

function mt21_word(left::UInt64, right::UInt64, n::Int)
    iszero(left & right) || return xor(left, right), Int64(0)
    inversions = 0
    for i in 1:n
        iszero(left & (UInt64(1) << (i - 1))) && continue
        for j in 1:i-1
            inversions += !iszero(right & (UInt64(1) << (j - 1)))
        end
    end
    left | right, isodd(inversions) ? Int64(-1) : Int64(1)
end

function mt21_generate(case, directory, rng)
    n = case["dimension"]
    6<=n<=64 && case["operation"] == "wedge" || error("trie wedge dimension/operation budget")
    left = Dict{UInt64,Int64}(0x03=>2, 0x05=>-1, 0x12=>3, 0x28=>2)
    right = Dict{UInt64,Int64}(0x0c=>3, 0x09=>-2, 0x30=>1, 0x06=>4)
    coordinates=[1,2,3,4,n-1,n]
    embed(mask)=sum((UInt64(1)<<(coordinates[i]-1) for i in 1:6
        if !iszero(mask & (UInt64(1)<<(i-1))));init=UInt64(0))
    left=Dict(embed(mask)=>value for (mask,value) in left)
    right=Dict(embed(mask)=>value for (mask,value) in right)
    horizon=get(case,"horizon",1)
    1<=horizon<=32 || error("trie episode horizon budget")
    if haskey(case,"horizon")
        left=Dict(mask=>value*rand(rng,(-1,1)) for (mask,value) in sort!(collect(left);by=first))
        right=Dict(mask=>value*rand(rng,(-1,1)) for (mask,value) in sort!(collect(right);by=first))
    end
    targets=n==6 ? UInt64.(0:63) :
        sort!(unique(UInt64[xor(a,b) for a in keys(left) for b in keys(right)]))
    positions=Dict(mask=>i for (i,mask) in enumerate(targets))
    expected = zeros(Int64, length(targets))
    for (amask, avalue) in left, (bmask, bvalue) in right
        output, sign = mt21_word(amask, bmask, n)
        expected[positions[output]] += sign * avalue * bvalue
    end
    (; n, left, right, expected,targets,horizon)
end

function mt21_prepare(fixture, case, directory)
    ga = algebra(fixture.n, :ega)
    left = multivector(ga, Dict(mask=>Float64(value) for (mask,value) in fixture.left);
        storage=:sparse)
    right = multivector(ga, Dict(mask=>Float64(value) for (mask,value) in fixture.right);
        storage=:sparse)
    left_trie = build_trie(left, fixture.n)
    right_trie = build_trie(right, fixture.n)
    (; fixture, left_trie, right_trie)
end

function mt21_once(state)
    terms = trie_wedge(state.left_trie, state.right_trie, state.fixture.n)
    Float64[get(terms,mask,0.0) for mask in state.fixture.targets]
end

mt21_execute(state)=state.fixture.horizon==1 ? mt21_once(state) :
    [mt21_once(state) for _ in 1:state.fixture.horizon]

function mt21_baseline_once(state)
    product=wedge(state.left,state.right)
    Float64[coefficient_mask(product,mask) for mask in state.fixture.targets]
end

register_adapter!(BenchmarkAdapter(name="garamon_materialized_trie",
    generate=mt21_generate, prepare=mt21_prepare, execute=mt21_execute,
    baseline_prepare=state->begin
        f=state.fixture
        ga=algebra(f.n,:ega)
        (;fixture=f,
            left=multivector(ga,Dict(mask=>Float64(value)
                for (mask,value) in f.left);storage=:sparse),
            right=multivector(ga,Dict(mask=>Float64(value)
                for (mask,value) in f.right);storage=:sparse))
    end,
    baseline_execute=state->state.fixture.horizon==1 ? mt21_baseline_once(state) :
        [mt21_baseline_once(state) for _ in 1:state.fixture.horizon],
    baseline_name="garamon_julia_sparse_direct_wedge",
    oracle=(state,result)->state.fixture.horizon==1 ? result==state.fixture.expected :
        length(result)==state.fixture.horizon && all(==(state.fixture.expected),result),
    contract="owned exact Float64 coefficients; all 6D masks or all reachable high-dimensional masks",
    capabilities=Dict("exact_oracle"=>"independent Int64 mask-pair disjointness and inversion parity",
        "operation"=>"materialized-trie wedge, construction in preparation",
        "coefficient_domain"=>"small integer inputs exactly representable in Float64",
        "generation_includes_oracle"=>true, "gpu_kernel"=>false)); replace=true)
