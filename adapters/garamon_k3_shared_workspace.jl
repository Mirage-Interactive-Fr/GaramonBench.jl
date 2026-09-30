# K3: shared Pfaffian contractions and a retained workspace. The oracle in
# n05_pfaffian.jl expands the Clifford word with Chevalley vector action.
module GaramonBenchK3
include(joinpath(get(ENV,"GARAMON_JULIA_ROOT",
    joinpath(homedir(),".julia","dev","Garamon")),"perf","n05_shared_workspace.jl"))

const Q=Rational{BigInt}

function generate(case,directory,rng)
    n=case["dimension"];H=case["horizon"]
    3<=n<=129 && case["strategy"]=="shared_cached" &&
        3<=H<=32 || error("outside K3 campaign domain")
    G=zeros(Q,n,n);G[1,1]=1;G[1,2]=G[2,1]=1;G[2,2]=-1
    for i in 3:n-1;G[i,i]=1;end
    U1=zeros(Q,n,4);U1[[1,2,n],:]=Q[1 2 0 1;2 1 1 -1;1 0 2 1]
    U2=copy(U1);U2[1,1]+=1
    chains=[[1,2,3,4],[4,3,2,1],[1,1,2,2]]
    pools=[t%3==0 ? U2 : U1 for t in 1:H]
    expected=hcat((n05_shared_oracle(G,U,chains) for U in pools)...)
    (;G,pools,chains,expected)
end

function prepare(fixture,case,directory)
    plan=n05_shared_plan(size(fixture.G,1),4,fixture.chains)
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
    baseline_prepare=state->(;fixture=state.fixture,
        ga=GaramonBenchK3.algebra(state.fixture.G)),
    baseline_execute=state->begin
        f=state.fixture
        output=Matrix{GaramonBenchK3.Q}(undef,length(f.chains),length(f.pools))
        for (t,pool) in enumerate(f.pools),(i,chain) in enumerate(f.chains)
            output[i,t]=GaramonBenchK3.n05_garamon(state.ga,pool[:,chain],:full)
        end
        output
    end,
    baseline_name="garamon_julia_full_vector_chain",
    contract="owned exact rational scalar chain matrix with shared contractions",
    capabilities=Dict("exact_oracle"=>"independent Chevalley Clifford-word scalar expansion",
        "combination"=>"K3: Pfaffian, shared contraction DAG, retained workspace",
        "reuse"=>"episodes cycle unchanged and changed pools with exact cache invalidation",
        "gpu_kernel"=>false));replace=true)
