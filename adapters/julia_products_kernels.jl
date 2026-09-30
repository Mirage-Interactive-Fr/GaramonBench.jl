function gb_generate_vectors(case,directory,rng)
    n=case["dimension"]; 2<=n<=128 || error("dimension budget")
    horizon=case["horizon"]; 1<=horizon<=1024 || error("horizon budget")
    signature=get(case,"signature","positive")
    signature in ("positive","mixed","degenerate") || error("signature budget")
    diagonal=signature=="positive" ? ones(Int64,n) :
        signature=="mixed" ? Int64[iseven(i) ? -1 : 1 for i in 1:n] :
        Int64[i%3==0 ? 0 : iseven(i) ? -1 : 1 for i in 1:n]
    K=n<=64 ? UInt64 : UInt128
    masks=[K(1)<<(i-1) for i in 1:n]
    output_masks=sort!(unique([xor(a,b) for a in masks for b in masks]))
    positions=Dict(mask=>i for (i,mask) in enumerate(output_masks))
    coefficients=[(rand(rng,1:3,n),rand(rng,1:3,n)) for _ in 1:horizon]
    expected=zeros(Int64,length(output_masks),horizon)
    for t in 1:horizon, i in 1:n, j in 1:n
        # Explicit vector-basis inversion; no Garamon sign/product helper.
        expected[positions[xor(masks[i],masks[j])],t]+=
            (i>j ? -1 : 1)*(i==j ? diagonal[i] : 1)*
            coefficients[t][1][i]*coefficients[t][2][j]
    end
    (;n,horizon,masks,output_masks,coefficients,expected,diagonal,signature,
        strategy=case["strategy"])
end

function gb_prepare_vectors(fixture,case,directory)
    ga=if fixture.signature=="positive"
        algebra(fixture.n,:ega)
    else
        metric=zeros(Int64,fixture.n,fixture.n)
        for i in 1:fixture.n
            metric[i,i]=fixture.diagonal[i]
        end
        algebra(metric)
    end
    inputs=[map(c->multivector(ga,Dict(mask=>Float64(c[i]) for (i,mask) in enumerate(fixture.masks));
                               storage=:sparse),pair) for pair in fixture.coefficients]
    if fixture.strategy in ("workspace","prepared","packed")
        plan=prepare_product(inputs[1]...;max_paths=16384)
        workspace=fixture.strategy=="workspace" ? ProductWorkspace(plan,inputs[1]...) : nothing
        batch=fixture.strategy=="packed" ?
            pack_product_batch(plan,first.(inputs),last.(inputs)) : nothing
        positions=[something(findfirst(==(mask),plan.output_masks)) for mask in fixture.output_masks]
        return (;fixture,inputs,plan,workspace,batch,positions)
    end
    fixture.strategy=="direct" || error("unknown strategy")
    return (;fixture,inputs,plan=nothing,workspace=nothing,batch=nothing,positions=Int[])
end

function gb_copy_coefficients!(output, column, masks, result::AbstractMultiVector)
    for i in eachindex(masks)
        output[i,column]=coefficient_mask(result,masks[i])
    end
    output
end

function gb_execute_vectors(state)
    f=state.fixture
    output=Matrix{Float64}(undef,length(f.output_masks),f.horizon)
    if f.strategy=="packed"
        values=run_packed_batch(state.batch)
        for t in 1:f.horizon, i in eachindex(state.positions)
            output[i,t]=values[state.positions[i],t]
        end
        return output
    end
    if f.strategy=="direct"
        for t in 1:f.horizon
            result=state.inputs[t][1]*state.inputs[t][2]
            gb_copy_coefficients!(output,t,f.output_masks,result)
        end
    elseif f.strategy=="prepared"
        for t in 1:f.horizon
            result=run_product(state.plan,state.inputs[t]...)
            gb_copy_coefficients!(output,t,f.output_masks,result)
        end
    elseif f.strategy=="workspace"
        for t in 1:f.horizon
            values=run_product_values!(state.workspace,state.inputs[t]...)
            for i in eachindex(state.positions)
                output[i,t]=values[state.positions[i]]
            end
        end
    else
        error("unknown strategy")
    end
    output
end

function gb_execute_vectors_baseline(state)
    fixture=state.fixture
    output=Matrix{Float64}(undef,length(fixture.output_masks),fixture.horizon)
    for t in 1:fixture.horizon
        result=geometric_product(state.inputs[t]...)
        gb_copy_coefficients!(output,t,fixture.output_masks,result)
    end
    output
end
