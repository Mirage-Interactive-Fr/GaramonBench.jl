# Exact selected coefficients of (a*b)*c, with a word-level oracle independent
# of Garamon products, plan construction, and the reusable join workspace.
pushfirst!(LOAD_PATH,get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random

function tj_indices(mask,n)
    [i for i in 1:n if !iszero(mask & (big(1) << (i-1)))]
end

function tj_pair(mask_a,mask_b,diagonal)
    ai=tj_indices(mask_a,length(diagonal))
    bi=tj_indices(mask_b,length(diagonal))
    sign=isodd(count(i>j for i in ai for j in bi)) ? Int64(-1) : Int64(1)
    for i in intersect(ai,bi)
        sign*=diagonal[i]
    end
    xor(mask_a,mask_b),sign
end

function tj_generate(case,directory,rng)
    n=case["dimension"]
    2<=n<=129 || error("triple-join dimension budget")
    horizon=case["horizon"]
    1<=horizon<=1024 || error("triple-join horizon budget")
    signature=case["signature"]
    signature in ("positive","mixed","degenerate") || error("triple-join signature")
    diagonal=signature=="positive" ? ones(Int64,n) :
        signature=="mixed" ? Int64[iseven(i) ? -1 : 1 for i in 1:n] :
        Int64[i%3==0 ? 0 : iseven(i) ? -1 : 2 for i in 1:n]
    low=big(1)
    high=big(1) << (n-1)
    near=big(1) << (n-2)
    supports=(unique(BigInt[0,low,high,low|high]),
              unique(BigInt[0,high,low|high]),
              unique(BigInt[0,low,high,near]))
    targets=unique(BigInt[0,low,high,low|high,near])
    positions=Dict(mask=>i for (i,mask) in enumerate(targets))
    coefficients=[ntuple(k->rand(rng,Int64(1):Int64(3),length(supports[k])),3)
                  for _ in 1:horizon]
    expected=zeros(Int64,length(targets),horizon)
    for t in 1:horizon
        values=coefficients[t]
        for (ia,amask) in enumerate(supports[1]),
            (ib,bmask) in enumerate(supports[2]),
            (ic,cmask) in enumerate(supports[3])
            intermediate,first_factor=tj_pair(amask,bmask,diagonal)
            output,second_factor=tj_pair(intermediate,cmask,diagonal)
            row=get(positions,output,0)
            iszero(row) && continue
            expected[row,t]+=first_factor*second_factor*
                values[1][ia]*values[2][ib]*values[3][ic]
        end
    end
    (;n,horizon,signature,diagonal,supports,targets,coefficients,expected,
      strategy=case["strategy"])
end

function tj_prepare(fixture,case,directory)
    ga=if fixture.signature=="positive"
        algebra(fixture.n,:ega)
    else
        metric=zeros(Int64,fixture.n,fixture.n)
        for i in 1:fixture.n
            metric[i,i]=fixture.diagonal[i]
        end
        algebra(metric)
    end
    inputs=[ntuple(k->multivector(ga,
        Dict(mask=>Float64(values[k][i]) for (i,mask) in enumerate(fixture.supports[k]));
        storage=:sparse),3) for values in fixture.coefficients]
    outputs=[tj_indices(mask,fixture.n) for mask in fixture.targets]
    if fixture.strategy=="join_workspace"
        plan=prepare_triple_join(inputs[1]...,outputs;
            max_probes=1<<20,max_paths=1<<16)
        workspace=TripleJoinWorkspace(plan,inputs[1]...)
        positions=[something(findfirst(==(mask),plan.output_masks))
                   for mask in fixture.targets]
        return (;fixture,inputs,plan,workspace,positions,plans=nothing,outputs)
    elseif fixture.strategy in ("recursive","recursive_grades","join3")
        plans=[begin
            a,b,c=operands
            prepare_expression(@ga (a*b)*c)
        end for operands in inputs]
        return (;fixture,inputs,plan=nothing,workspace=nothing,
            positions=Int[],plans,outputs)
    end
    fixture.strategy=="direct" || error("triple-join strategy")
    (;fixture,inputs,plan=nothing,workspace=nothing,
      positions=Int[],plans=nothing,outputs)
end

function tj_execute(state)
    fixture=state.fixture
    output=Matrix{Float64}(undef,length(fixture.targets),fixture.horizon)
    for t in 1:fixture.horizon
        operands=state.inputs[t]
        if fixture.strategy=="direct"
            result=(operands[1]*operands[2])*operands[3]
            for (i,mask) in enumerate(fixture.targets)
                output[i,t]=coefficient_mask(result,mask)
            end
        elseif fixture.strategy=="join_workspace"
            values=run_triple_join_values!(state.workspace,operands...)
            for (i,position) in enumerate(state.positions)
                output[i,t]=values[position]
            end
        else
            values=evaluate(state.plans[t];outputs=state.outputs,
                strategy=Symbol(fixture.strategy))
            for i in eachindex(fixture.targets)
                output[i,t]=values[i]
            end
        end
    end
    output
end

register_adapter!(BenchmarkAdapter(name="garamon_triple_join",
    generate=tj_generate,prepare=tj_prepare,execute=tj_execute,
    oracle=(state,result)->size(result)==size(state.fixture.expected) &&
        result==state.fixture.expected,
    contract="owned Float64 matrix of selected (a*b)*c coefficients, fixed mask order",
    capabilities=Dict("exact_oracle"=>"independent Int64 Clifford-word inversions",
        "signatures"=>"positive,mixed,degenerate diagonal",
        "strategies"=>"direct,join_workspace",
        "generation_includes_oracle"=>true,"gpu_kernel"=>false));replace=true)
