# Full exact recurrence using ordinary Garamon.jl multivector operations.
# The adapter oracle remains the independent ambient-word implementation.
using Garamon

function standard_pruning_history(fixture)
    Q=Rational{BigInt}
    gram=zeros(Q,fixture.n,fixture.n)
    for i in 1:fixture.n
        gram[i,i]=fixture.diagonal[i]
    end
    ga=algebra(gram)
    x=multivector(ga,Dict(mask=>Q(value)
        for (mask,value) in zip(fixture.masks,fixture.initial));storage=:sparse)
    history=[Q[coefficient_mask(x,mask) for mask in fixture.masks]]
    for step in 1:fixture.horizon
        if fixture.recurrence==:affine
            j=mod1(step,fixture.k)
            if fixture.regime==:neutral
                coefficient=fixture.diagonal[trailing_zeros(fixture.masks[2^ (j-1)+1])+1]==0 ?
                    Dict(UInt128(0)=>one(Q)) :
                    Dict(fixture.masks[2^(j-1)+1]=>one(Q))
            else
                coefficient=Dict(UInt128(0)=>Q(3//4),
                    fixture.masks[2^(j-1)+1]=>Q(1//4))
            end
            a=multivector(ga,coefficient;storage=:sparse)
            x=Q(fixture.rho)*geometric_product(a,x)+Q(1//65_536)
        else
            x=Q(fixture.rho)*x+geometric_product(x,x)/32
        end
        push!(history,Q[coefficient_mask(x,mask) for mask in fixture.masks])
    end
    history
end
