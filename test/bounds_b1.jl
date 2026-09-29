using Test,GaramonBench,TOML

@testset "B1 bounded manifest and explicit measurement-process options" begin
    path=joinpath(@__DIR__,"..","config","bounds_b1.toml")
    raw=TOML.parsefile(path);smoke=b1_plan(raw)
    @test smoke["case_count"]==8
    @test length(smoke["jobs"])==2
    @test [j["check_bounds"] for j in smoke["jobs"]]==["yes","auto"]
    @test all([c["route"] for c in j["cases"]]==["checked","inbounds","inbounds","checked"] for j in smoke["jobs"])
    @test smoke["horizons"]==[1]
    workspace=b1_plan(joinpath(@__DIR__,"..","config","bounds_b1_workspace.toml"))
    @test workspace["case_count"]==144
    @test length(workspace["jobs"])==4
    @test workspace["routes"]==["checked","inbounds","workspace"]
    @test [c["route"] for c in first(workspace["jobs"])["cases"][1:3]]==
        ["checked","inbounds","workspace"]
    @test [c["route"] for c in last(first(workspace["jobs"])["cases"],3)]==
        ["workspace","inbounds","checked"]
    native_workspace=b1_plan(joinpath(@__DIR__,"..","config","bounds_b1_workspace_native.toml"))
    @test native_workspace["case_count"]==192
    @test native_workspace["routes"]==["checked","inbounds","workspace","workspace_native"]
    singlepass=b1_plan(joinpath(@__DIR__,"..","config","bounds_b1_workspace_singlepass.toml"))
    @test singlepass["case_count"]==96
    @test singlepass["routes"]==["workspace_native","workspace_native_singlepass"]
    singlepass_12d=b1_plan(joinpath(@__DIR__,"..","config","bounds_b1_workspace_singlepass_12d.toml"))
    @test singlepass_12d["dimensions"]==[2,3,4,6,8,12,16,32,64,65,96,128]
    @test singlepass_12d["case_count"]==96
    @test singlepass_12d["horizons"]==[1024]
    screen=deepcopy(raw);screen["campaign"]["profile"]="screen"
    planned=b1_plan(screen)
    @test length(planned["dimensions"])>=10
    @test all(n->n in planned["dimensions"],(64,65,128))
    @test planned["horizons"]==[1,32,1024]
    @test planned["case_count"]==1728
    @test length(planned["jobs"])==24
    @test allunique([c["id"] for j in planned["jobs"] for c in j["cases"]])
    for (section,key,value) in (("compiler","check_bounds",["no"]),("compiler","opt_levels",[1]),
        ("compiler","cpu_targets",["unknown"]),("compiler","opt_levels",[true]),
        ("campaign","dimensions",[1]),("campaign","dimensions",[129]),("campaign","dimensions",[8,8]),
        ("campaign","horizons",[10000]),("campaign","interference_label","\nlabel"),
        ("limits","samples",0),("limits","job_seconds",Inf))
        bad=deepcopy(raw);bad[section][key]=value
        @test_throws ErrorException b1_plan(bad)
    end
    bad=deepcopy(raw);bad["campaign"]["condition"]="isolated"
    @test_throws ErrorException b1_plan(bad)
    bad["campaign"]["interference_label"]=""
    @test b1_plan(bad)["condition"]=="isolated"
    allopts=deepcopy(screen)
    allopts["compiler"]=Dict("check_bounds"=>["yes","auto"],"opt_levels"=>[2,3],"cpu_targets"=>["generic","native"])
    grid=b1_plan(allopts)
    @test length(grid["jobs"])==96
    @test grid["case_count"]==6912
    @test allunique([j["id"] for j in grid["jobs"]])
    for job in grid["jobs"]
        args=collect(GaramonBench.b1_command(grid,job,"/request.toml","/output";executable="/julia-1.13"))
        @test args[1]=="/julia-1.13"
        @test "--check-bounds="*job["check_bounds"] in args
        @test "-O"*string(job["opt_level"]) in args
        @test "--cpu-target="*job["cpu_target"] in args
        @test "--pkgimages=no" in args
        @test "--math-mode=ieee" in args
        @test "--threads=1,0" in args
        @test last(args,2)==["/request.toml","/output"]
    end
    source=read(joinpath(@__DIR__,"..","adapters","bounds_b1","worker.jl"),String)
    @test occursin("options.check_bounds==",source)
    @test occursin("options.opt_level==",source)
    @test occursin("cpu==job[\"cpu_target\"]",source)
    @test occursin("run_suite(suite;profile=:quick,strict=false,executor)",source)
    @test occursin("b1_word_oracle",source)
    @test occursin("b1_exact_owned",source)
    @test occursin("private validation/copies paid on every product",source)
    @test occursin("b1_workspace_product!",source)
    @test occursin("b1_workspace_product_singlepass!",source)
end
