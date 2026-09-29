# Correctness-only preflight for the diagonal direct-product path.
# This test deliberately does not load or run PerfChecker.
using Test
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon

function independent_diagonal_product(left,right,diagonal,operation)
    output=Dict{BigInt,Int64}()
    n=length(diagonal)
    indices(mask)=[i for i in 1:n if !iszero(mask & (big(1)<<(i-1)))]
    for (amask,avalue) in left, (bmask,bvalue) in right
        ai=indices(amask);bi=indices(bmask)
        ra,rb=length(ai),length(bi)
        common=intersect(ai,bi)
        operation==:wedge && !isempty(common) && continue
        outmask=xor(amask,bmask)
        grade=length(indices(outmask))
        selected=operation==:geometric || operation==:wedge ? true :
            operation==:left ? ra<=rb && grade==rb-ra :
            operation==:right ? rb<=ra && grade==ra-rb :
            operation==:inner ? ra>0 && rb>0 && grade==abs(ra-rb) :
            operation==:dot ? grade==abs(ra-rb) :
            operation==:scalar ? ra==rb && grade==0 : error("operation")
        selected || continue
        inversions=count(i>j for i in ai for j in bi)
        factor=isodd(inversions) ? -Int64(1) : Int64(1)
        if operation!=:wedge
            for i in common
                factor*=diagonal[i]
            end
        end
        value=factor*avalue*bvalue
        newvalue=get(output,outmask,Int64(0))+value
        if iszero(newvalue)
            delete!(output,outmask)
        else
            output[outmask]=newvalue
        end
    end
    output
end

@testset "independent diagonal-product oracle across 14 dimensions" begin
    dimensions=(2,3,4,5,6,7,8,16,32,64,65,96,128,129)
    operations=Dict(:geometric=>geometric_product,:wedge=>wedge,
        :left=>left_contraction,:right=>right_contraction,
        :inner=>inner_product,:dot=>dot_product,:scalar=>scalar_product)
    for n in dimensions
        diagonal=Int64[i%3==0 ? 0 : iseven(i) ? -1 : 2 for i in 1:n]
        metric=zeros(Int64,n,n)
        for i in 1:n
            metric[i,i]=diagonal[i]
        end
        ga=algebra(metric)
        low=big(1);high=big(1)<<(n-1);near=big(1)<<(n-2)
        left=Dict{BigInt,Int64}(0=>2,low=>-3,low|high=>1)
        right=Dict{BigInt,Int64}(0=>-1,high=>2,low|high=>-2)
        if n>=3
            left[near]=3
            right[low|near]=1
        end
        for storage in (n<=5 ? (:sparse,:dense) : (:sparse,))
            a=multivector(ga,left;storage)
            b=multivector(ga,right;storage)
            for (operation,apply) in operations
                expected=independent_diagonal_product(left,right,diagonal,operation)
                actual=sparse(apply(a,b))
                observed=Dict{BigInt,Int64}(BigInt(mask)=>Int64(value)
                    for (mask,value) in actual.values)
                @test observed==expected
            end
        end
    end
end
