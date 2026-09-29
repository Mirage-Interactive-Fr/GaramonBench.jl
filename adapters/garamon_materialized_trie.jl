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
    n == 6 && case["operation"] == "wedge" || error("trie wedge smoke contract")
    left = Dict{UInt64,Int64}(0x03=>2, 0x05=>-1, 0x12=>3, 0x28=>2)
    right = Dict{UInt64,Int64}(0x0c=>3, 0x09=>-2, 0x30=>1, 0x06=>4)
    expected = zeros(Int64, 1 << n)
    for (amask, avalue) in left, (bmask, bvalue) in right
        output, sign = mt21_word(amask, bmask, n)
        expected[Int(output) + 1] += sign * avalue * bvalue
    end
    (; n, left, right, expected)
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

function mt21_execute(state)
    terms = trie_wedge(state.left_trie, state.right_trie, state.fixture.n)
    Float64[get(terms, UInt64(mask), 0.0) for mask in 0:(1 << state.fixture.n)-1]
end

register_adapter!(BenchmarkAdapter(name="garamon_materialized_trie",
    generate=mt21_generate, prepare=mt21_prepare, execute=mt21_execute,
    oracle=(state,result)->result == state.fixture.expected,
    contract="owned Float64 vector of every 6D ordered-blade coefficient",
    capabilities=Dict("exact_oracle"=>"independent Int64 mask-pair disjointness and inversion parity",
        "operation"=>"materialized-trie wedge, construction in preparation",
        "coefficient_domain"=>"small integer inputs exactly representable in Float64",
        "generation_includes_oracle"=>true, "gpu_kernel"=>false)); replace=true)
