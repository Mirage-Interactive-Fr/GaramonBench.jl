pushfirst!(LOAD_PATH, get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")))
using Garamon, GaramonBench, Random, SHA

const K4Scalar = Rational{BigInt}

function k4_generate(case,directory,rng)
    n, horizon = case["dimension"], case["horizon"]
    3 <= n <= 8 && 1 <= horizon <= 32 || error("K4 fixture budget")
    normals = K4Scalar.(rand(rng,1:3,n,2))
    rotations = [(1,2,3//5,4//5),(2,n,5//13,12//13)]
    factors = [K4Scalar.(rand(rng,-3:3,n,2)) for _ in 1:horizon]
    indices = [(i,j) for i in 1:n-1 for j in i+1:n]
    masks = [(UInt64(1)<<(i-1)) | (UInt64(1)<<(j-1)) for (i,j) in indices]
    expected = Matrix{K4Scalar}(undef,length(indices),horizon)
    for (t,input) in enumerate(factors)
        transformed = copy(input)
        for col in axes(input,2)
            v = view(transformed,:,col)
            for normal in eachcol(normals)
                v .-= (2*sum(v.*normal)/sum(abs2,normal)).*normal
            end
            for (i,j,c,s) in rotations
                x,y = v[i],v[j]
                v[i],v[j] = c*x-s*y, s*x+c*y
            end
        end
        for (k,(i,j)) in enumerate(indices)
            expected[k,t] = transformed[i,1]*transformed[j,2] -
                transformed[j,1]*transformed[i,2]
        end
    end
    (;n,horizon,normals,rotations,factors,masks,expected)
end

function k4_vector(ga,coordinates,storage)
    multivector(ga,Dict(UInt64(1)<<(i-1)=>v for (i,v) in enumerate(coordinates));
        storage)
end

function k4_prepare(fixture,scenario)
    f = fixture
    storage = occursin('D',scenario) ? :dense : :sparse
    use_workspace = occursin('W',scenario)
    factored = occursin('R',scenario)
    givens = occursin('G',scenario)
    ga = algebra(K4Scalar[i==j for i in 1:f.n,j in 1:f.n])
    chain = factored ? ReflectionChain(ga,f.normals) : nothing
    inputs = factored ? [FactorizedBlade(ga,uv) for uv in f.factors] :
        [Tuple(k4_vector(ga,v,storage) for v in eachcol(uv)) for uv in f.factors]
    normals = factored ? nothing :
        [(k4_vector(ga,u,storage),k4_vector(ga,u./sum(abs2,u),storage))
            for u in eachcol(f.normals)]
    plan = givens ? prepare_givens_basis_change(ga,f.rotations) : nothing
    matrix = if givens
        nothing
    else
        q = K4Scalar[i==j for i in 1:f.n,j in 1:f.n]
        for (i,j,c,s) in f.rotations
            rotation = K4Scalar[a==b for a in 1:f.n,b in 1:f.n]
            rotation[i,i] = rotation[j,j] = c
            rotation[i,j],rotation[j,i] = -s,s
            q = rotation*q
        end
        q
    end
    # One reusable buffer per product step, so a sandwich can consume a
    # borrowed result while writing into a different workspace.
    slots = use_workspace ?
        Matrix{Union{Nothing,ProductWorkspace}}(nothing,factored ? 1 : 5,f.horizon) : nothing
    (;fixture,ga,storage,chain,inputs,normals,plan,matrix,slots)
end

function k4_store(value,storage)
    storage==:dense && !(value isa DenseMultiVector) ? dense(value) : value
end

function k4_product(state,step,request,a,b,operation)
    if isnothing(state.slots)
        value = operation==:wedge ? wedge(a,b) : geometric_product(a,b)
    else
        workspace = state.slots[step,request]
        if isnothing(workspace)
            plan = prepare_product(a,b;operation)
            workspace = ProductWorkspace(plan,a,b)
            state.slots[step,request] = workspace
        end
        value = run_product!(workspace,a,b)
    end
    k4_store(value,state.storage)
end

function k4_execute(state)
    f = state.fixture
    output = Matrix{K4Scalar}(undef,length(f.masks),f.horizon)
    for t in 1:f.horizon
        if isnothing(state.chain)
            value = k4_product(state,1,t,state.inputs[t]...,:wedge)
            for (i,(normal,inverse)) in enumerate(state.normals)
                left = k4_product(state,2*i,t,normal,value,:geometric)
                value = k4_product(state,2*i+1,t,left,inverse,:geometric)
            end
            value = isnothing(state.plan) ? outermorphism(state.matrix,value,state.ga) :
                run_givens_basis_change(state.plan,value)
        else
            blade = versor_action(state.chain,state.inputs[t])
            vectors = if isnothing(state.plan)
                Tuple(k4_vector(state.ga,state.matrix*v,state.storage) for v in eachcol(blade.factors))
            else
                Tuple(k4_store(run_givens_basis_change(state.plan,
                    k4_vector(state.ga,v,state.storage)),state.storage) for v in eachcol(blade.factors))
            end
            value = k4_product(state,1,t,vectors...,:wedge)
        end
        value = k4_store(value,state.storage)
        for (i,mask) in enumerate(f.masks)
            output[i,t] = coefficient_mask(value,mask)
        end
    end
    output
end

register_adapter!(BenchmarkAdapter(
    name="garamon_k4_interactions",
    generate=k4_generate,
    prepare=(fixture,case,directory)->k4_prepare(fixture,case["scenario"]),
    execute=k4_execute,
    oracle=(state,result)->result==state.fixture.expected,
    baseline_prepare=state->k4_prepare(state.fixture,"reference"),
    baseline_execute=k4_execute,
    baseline_name="Garamon.jl sparse expanded bivector, direct products, matrix rotation",
    baseline_scenario=(state,case)->Dict("dimension"=>case["dimension"],
        "horizon"=>case["horizon"],"seed"=>case["seed"]),
    baseline_output_identity=result->bytes2hex(sha256(join(vec(result),","))),
    contract="owned exact coefficients of a grade-two blade after two reflections and two rotations",
    capabilities=Dict("oracle"=>"independent rational vector reflections, plane rotations, and minors",
        "workspaces"=>"one per product step and repeated request support")); replace=true)
