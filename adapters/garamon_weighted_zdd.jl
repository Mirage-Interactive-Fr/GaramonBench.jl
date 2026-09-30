# Weighted coefficient ZDD product, with an independent exact blade-word
# oracle. The production product recurses through ZDD nodes and does not call
# Garamon's multivector product.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

function wz20_oracle(a,b,g)
    Q=Rational{BigInt}
    n=length(g)
    output=Dict{BigInt,Q}()
    for (am,av) in a,(bm,bv) in b
        ai=[i for i in 1:n if !iszero(am & (big(1)<<(i-1)))]
        bi=[i for i in 1:n if !iszero(bm & (big(1)<<(i-1)))]
        factor=isodd(sum((i>j for i in ai for j in bi);init=0)) ? -one(Q) : one(Q)
        for i in intersect(ai,bi);factor*=g[i];end
        mask=xor(am,bm)
        output[mask]=get(output,mask,zero(Q))+factor*av*bv
    end
    filter!(kv->!iszero(last(kv)),output)
end

function wz20_generate(case,directory,rng)
    case["dimension"]==4 && case["signature"]=="signed_degenerate" &&
        case["strategy"]=="weighted_zdd_product" ||
        throw(ArgumentError("outside bounded weighted ZDD preflight case"))
    Q=Rational{BigInt}
    g=Q[2,-1,0,3]
    a=Dict{BigInt,Q}(0=>1,1=>2,2=>-1,3=>1,8=>2,9=>-2,12=>1)
    b=Dict{BigInt,Q}(0=>-1,1=>3,2=>2,3=>-1,4=>1,8=>1,10=>-2)
    expected=wz20_oracle(a,b,g)
    (;g,a,b,expected)
end

function wz20_prepare(fixture,case,directory)
    left=weighted_zdd(4,fixture.a;max_nodes=4096,max_work=10_000)
    right=weighted_zdd(4,fixture.b;max_nodes=4096,max_work=10_000)
    weighted_zdd_terms(left)==fixture.a && weighted_zdd_terms(right)==fixture.b ||
        error("weighted ZDD input encoding disagrees")
    (;fixture,left,right)
end

function wz20_execute(state)
    product=weighted_zdd_product(state.left,state.right,state.fixture.g;
        max_nodes=4096,max_work=10_000)
    weighted_zdd_terms(product;max_terms=16)
end

register_adapter!(BenchmarkAdapter(name="garamon_weighted_zdd",
    generate=wz20_generate,prepare=wz20_prepare,execute=wz20_execute,
    baseline_prepare=state->begin
        f=state.fixture
        gram=zeros(eltype(f.g),length(f.g),length(f.g))
        for i in eachindex(f.g)
            gram[i,i]=f.g[i]
        end
        ga=algebra(gram)
        (;fixture=f,
            left=multivector(ga,f.a;storage=:sparse),
            right=multivector(ga,f.b;storage=:sparse))
    end,
    baseline_execute=state->begin
        product=geometric_product(state.left,state.right)
        Q=Rational{BigInt}
        result=Dict{BigInt,Q}()
        for mask in 0:(1<<length(state.fixture.g))-1
            value=Q(coefficient_mask(product,mask))
            iszero(value) || (result[BigInt(mask)]=value)
        end
        result
    end,
    baseline_name="garamon_julia_sparse_direct_product",
    oracle=(state,result)->result isa Dict{BigInt,Rational{BigInt}} &&
        result==state.fixture.expected,
    contract="owned exact rational complete product extracted from a coefficient ZDD",
    capabilities=Dict("exact_oracle"=>"independent ambient Clifford-word inversions",
        "algorithm"=>"memoized ZDD branch product with signed metric factors",
        "metric"=>"diagonal rational, signed and degenerate",
        "input_nodes"=>"canonical coefficient terminals and zero-suppressed nodes",
        "gpu_kernel"=>false));replace=true)
