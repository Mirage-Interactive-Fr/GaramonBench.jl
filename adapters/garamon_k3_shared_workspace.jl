# K3: shared Pfaffian contractions and a retained workspace. The oracle in
# n05_pfaffian.jl expands the Clifford word with Chevalley vector action.
module GaramonBenchK3
include(joinpath(get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")),"perf","n05_shared_workspace.jl"))

const Q=Rational{BigInt}

function generate(case,directory,rng)
    case["dimension"]==3 && case["strategy"]=="shared_cached" &&
        case["horizon"]==3 || error("outside K3 minimal case")
    G=Q[1 1 0;1 -1 0;0 0 0]
    U1=Q[1 2 0 1;2 1 1 -1;1 0 2 1]
    U2=copy(U1);U2[1,1]+=1
    chains=[[1,2,3,4],[4,3,2,1],[1,1,2,2]]
    pools=[U1,U1,U2]
    expected=hcat((n05_shared_oracle(G,U,chains) for U in pools)...)
    (;G,pools,chains,expected)
end

function prepare(fixture,case,directory)
    plan=n05_shared_plan(3,4,fixture.chains)
    workspace=n05_shared_workspace(plan,fixture.G,first(fixture.pools);
        policy=:check_inputs)
    (;fixture,plan,workspace)
end

function execute(state)
    f=state.fixture
    output=Matrix{Q}(undef,length(f.chains),length(f.pools))
    for (t,U) in enumerate(f.pools)
        output[:,t]=n05_shared_owned!(state.workspace,f.G,U)
    end
    output
end

function oracle(state,result)
    result==state.fixture.expected &&
        state.workspace.contraction_builds>=2 &&
        length(state.plan.pairs)<sum(length(c)*(length(c)-1)÷2 for c in state.fixture.chains)
end
end

using GaramonBench
register_adapter!(BenchmarkAdapter(name="garamon_k3_shared_workspace",
    generate=GaramonBenchK3.generate,prepare=GaramonBenchK3.prepare,
    execute=GaramonBenchK3.execute,oracle=GaramonBenchK3.oracle,
    contract="owned exact rational scalar chain matrix with shared contractions",
    capabilities=Dict("exact_oracle"=>"independent Chevalley Clifford-word scalar expansion",
        "combination"=>"K3: Pfaffian, shared contraction DAG, retained workspace",
        "reuse"=>"three calls include one unchanged and one changed input",
        "gpu_kernel"=>false));replace=true)
