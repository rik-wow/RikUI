-- Installed-corpus regression for the reported Muren Stormpike switch.
-- Usage: lua tests/quest-plan-switch-replay.lua <AddOns root> <RIKP packet>
-- Archived observations plus a synthetic rewind/walk; not native gameplay evidence.
local root=assert(arg[1],"AddOns root required"):gsub("\\","/"):gsub("/$","")
RikUI={CharDB={},Changed=function() end};RikUI["Secret"]={IsSecret=function() return false end}
GetTime=function() return 0 end
for _,name in ipairs({"schema","objectives","transfer","steps","step-bindings","guide-data","observed-steps","hunts","targets",
    "optimizer","area-optimizer","semantic-data","waypoints","objective-guide","semantic-guidance","recommendations","guidance","preferences",
    "plan-state","plan-graph","plan-transitions","plan-learning","plan-costs","plan-search","plan-rewards",
    "roads","road-travel","travel-estimate","plan-runtime"}) do
    dofile("src/modules/questplanner/quest-"..name..".lua")
end
local p=RikUI.QuestPlanner
local f=assert(io.open(assert(arg[2],"RIKP packet required"),"rb"))
local wire=f:read("*a"):gsub("%s+$","");f:close()
local trace=assert(p.Transfer.DecodePlan(wire))
local current={searchRevision=p.PlanSearch.REVISION,corpusRevision=trace.source.corpusRevision,identity=trace.source.identity}
if trace.source.searchRevision~=p.PlanSearch.REVISION then
    local rejected=p.PlanRuntime.RerunReplay(trace,current)
    assert(rejected.status=="rejected" and rejected.reason=="source_mismatch")
    print("ARCHIVED REPLAY SKIPPED: source_mismatch; "..trace.source.searchRevision.." -> "..p.PlanSearch.REVISION)
else
    -- Current-revision exports also require their actual travel index.
    dofile("tests/generated_stub.lua").Load(dofile("tests/generated_stub.lua").Base(root),{"roads"})
    local result=p.PlanRuntime.RerunReplay(trace,current)
    assert(result.status=="match","current-revision replay: "..tostring(result.reason or result.phase))
    print("ARCHIVED REPLAY MATCH")
end
local state=p.Schema.Clone(trace.state);state.fresh=true
state.active[1678]=nil;state.live[1678]=nil;state.progress[1678]=nil;state.objectiveInfo[1678]=nil
state.failed[1678]=nil;state.objectivesComplete[1678]=nil;state.completed[1678]=false
state.active[1679]=true;state.completed[1679]=false;state.failed[1679]=false;state.objectivesComplete[1679]=true
state.progress[1679]={};state.objectiveInfo[1679]={};state.xp=state.xp-85
state.live[1679]={id=1679,title="Muren Stormpike",level=10,objectivesComplete=true,objectives={}}
-- 1537 in source action IDs is AreaTable Ironforge; its UI map is 1455.
state.position={mapID=1455,x=.528,y=.825}
local snapshot={identity=state.identity,order={},quests=state.live,coverage="log-complete"}
for id,active in pairs(state.active) do if active then snapshot.order[#snapshot.order+1]=id end end
table.sort(snapshot.order);state.logCount=#snapshot.order
local ctx={origin="live",identity=state.identity,characterKey="switch-regression",position=state.position,
    attributes={level=state.level,class=state.class,race=state.race,faction=state.faction,xp=state.xp,xpMax=state.xpMax},
    history=state.completed,destinations={}}
p.Context={Call=function(fn,...) if type(fn)=="function" then return pcall(fn,...) end return false end,
    History=function(ids) local out={};for _,id in ipairs(ids) do out[id]=state.completed[id] end;return out end}
local generated=dofile("tests/generated_stub.lua")
if not RikUIQuestCorpusCatalog then generated.Load(generated.Base(root),{"corpus"}) end
if not p.Roads.HasWorld(0) then generated.Load(generated.Base(root),{"roads"}) end
C_AddOns={LoadAddOn=generated.PatchLoader(root)}
assert(RikUIQuestCorpusCatalog,"installed corpus catalog required")
p.SemanticData.Ensure(snapshot,ctx)
local records
for _=1,32 do
    records=p.SemanticData.Records(snapshot,ctx,trace.constraints)
    for _=1,64 do p.SemanticData.Step(64);p.SemanticData.StepHistory() end
end
records=p.SemanticData.Records(snapshot,ctx,trace.constraints)
assert(records[1679] and records[1679].planning,"installed Muren record missing")
assert(records[1679].planning.breadcrumbFor==1678,"Muren breadcrumb must come from actual corpus")
state.sourceRevision=RikUIQuestCorpusCatalog.revision
local policy=p.Schema.Clone(trace.constraints)
assert(not policy.pins[1679],"regression must not depend on a Muren pin")
local function graphAt(s,previousID)
    local job=assert(p.PlanGraph.Begin(s,records,{},policy,previousID))
    for _=1,50000 do local graph=job:Step(64);if graph then assert(graph.status=="ready");return graph end end
    error("source graph did not settle")
end
local initialGraph=graphAt(state)
local muren
for _,action in ipairs(initialGraph.byQuest[1679] or {}) do
    if action.kind=="turnin" and action.destination and action.destination.mapID==1455 then muren=action;break end
end
assert(muren and muren.breadcrumbFor==1678,"actual Muren turn-in missing breadcrumb")
assert(p.PlanTransitions.Check(muren,state,policy)==true,"rewound Muren must be feasible")
assert(p.PlanCosts.Reward(muren,state)==85,"rewind XP must match source reward")
local prior={actionID=muren.id,actionIDs={muren.id},flavor=policy.flavor,
    selected={questID=1679,title=muren.title,planAction=muren}}
RikUIDB={planSwitches={}}
local firstReplay,maxSeconds,totalWork=nil,0,0
for i=0,10 do
    local s=p.Schema.Clone(state);local t=i/10
    s.position={mapID=1455,x=.528+(.7077-.528)*t,y=.825+(.9027-.825)*t}
    ctx.position=s.position;ctx.observedAt=i
    local graph=graphAt(s,prior.actionID)
    local began=os.clock()
    local ok,model=p.PlanLearning.WithSnapshot(trace.learning,function()
        local travelModel=p.TravelEstimate.Capture(s,trace.environment.mapSizes)
        local env={previousID=prior.actionID,incumbent=prior.actionIDs,travelModel=travelModel,
            previousAction={id=muren.id,questID=1679,kind="turnin"},mapSizes=trace.environment.mapSizes}
        local replayEnvironment=p.Schema.Clone(env)
        env.travel=assert(p.TravelEstimate.Open(travelModel))
        local job=assert(p.PlanSearch.Begin(graph,s,policy,env))
        local raw
        for _=1,1000 do raw=job:Step(64);if raw then break end end
        assert(raw and raw.status=="ready","search failed")
        raw.adaptive=true;raw.stateKey=p.PlanState.Key(s);raw.replayState=s
        raw.replayGraph={version=graph.version,status=graph.status,identity=graph.identity,revision=graph.revision,
            coverage=graph.coverage,actions=graph.actions}
        raw.replayEnvironment=replayEnvironment;raw.replayLearning=p.PlanLearning.Export();raw.candidateIDs={}
        for _,a in ipairs(graph.actions) do raw.candidateIDs[#raw.candidateIDs+1]=a.id end
        local result=p.PlanRuntime.Result(raw,{},ctx,policy,prior,s)
        assert(result.selected and result.selected.questID==1679 and result.selected.kind=="turnin",
            "Muren abandoned at "..i..": "..tostring(result.actionID))
        assert(result.actionID==prior.actionID,"first step changed during the walk")
        p.PlanRuntime.RecordSwitch(prior,result,ctx)
        totalWork=totalWork+raw.metrics.work
        if i==0 then firstReplay=assert(p.PlanRuntime.Replay()) end
        return result
    end)
    assert(ok,model)
    local seconds=os.clock()-began;maxSeconds=math.max(maxSeconds,seconds)
    print(string.format("WALK %3d%% first=%s rate=%.4f retained=%s cpu=%.3fs",i*10,model.actionID,model.score,tostring(model.retained),seconds))
    prior=model
end
assert(#p.PlanRuntime.Switches()==0,"walk recorded an unexpected plan switch")
local exported=assert(p.Transfer.EncodePlan(firstReplay))
local reproduced=p.PlanRuntime.RerunReplay(assert(p.Transfer.DecodePlan(exported)),firstReplay.source)
assert(reproduced.status=="match","fresh actual-corpus replay differs: "..tostring(reproduced.reason or reproduced.phase))
print(string.format("MUREN_SWITCH_OK: 11/11 actual-corpus turn-ins, zero switches; fresh replay match; max search %.3fs; work %d; road network loads %d",
    maxSeconds,totalWork,p.Roads.Stats().loads))
