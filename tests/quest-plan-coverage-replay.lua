-- Replay the reported Shimmer Stout decision using captured graph/state and installed travel data.
-- Usage: lua5.1 tests/quest-plan-coverage-replay.lua <RIKP packet> <AddOns root>
-- Use the exporting client's Lua 5.1 number parsing: LuaJIT can differ in travel-index fingerprints.
-- Offline replay of real observations; does not assert native gameplay acceptance.
local packet=assert(arg[1],"RIKP packet required")
local root=assert(arg[2],"AddOns root required"):gsub("\\","/"):gsub("/$","")
RikUI={CharDB={}};RikUI["Secret"]={IsSecret=function() return false end}
for _,name in ipairs({"schema","preferences","recommendations","guidance","plan-transitions",
    "plan-state","plan-learning","plan-rewards","plan-costs","plan-search","roads","road-travel","travel-estimate","plan-runtime","transfer"}) do
    dofile("src/modules/questplanner/quest-"..name..".lua")
end
local p=RikUI.QuestPlanner
local file=assert(io.open(packet,"rb"))
local wire=file:read("*a"):match("(RIKP1:[a-f0-9]+:[a-f0-9]+)");file:close()
local archived=assert(p.Transfer.DecodePlan(assert(wire)))
assert(loadfile(root.."/RikUIQuestRoads/index.lua"))()
local state=p.Schema.Clone(archived.state);state.fresh=true
local graph=p.Schema.Clone(archived.graph);graph.byID={};graph.byQuest={}
-- The old packet predates the explicit coverage bit; recover it from its actual action graph.
for _,live in pairs(state.live) do live.hasPlanningRecord=false end
for _,action in ipairs(graph.actions) do
    graph.byID[action.id]=action
    local rows=graph.byQuest[action.questID] or {};graph.byQuest[action.questID]=rows;rows[#rows+1]=action
    if state.live[action.questID] and not action.liveFallback then state.live[action.questID].hasPlanningRecord=true end
end
local snapshot={identity=state.identity,quests={},order={}}
local ctx={position=state.position,destinations={},rewards={},attributes={},questTags={},history=state.completed}
for id,live in pairs(state.live) do
    local row=p.Schema.Clone(live);row.id=id;row.objectives={}
    for _,info in pairs(state.objectiveInfo[id] or {}) do
        row.objectives[info.index]={text=info.text,type=info.type,numFulfilled=info.fulfilled,numRequired=info.required,finished=info.finished}
    end
    snapshot.quests[id]=row;snapshot.order[#snapshot.order+1]=id
    ctx.destinations[id]=live.destination;ctx.rewards[id]=live.reward
    ctx.questTags[id]={dungeon=live.dungeon,group=live.groupRequiredUnknown or (live.requiredParty or 1)>1,requiredParty=live.requiredParty}
end
table.sort(snapshot.order)
local size=assert(archived.environment.mapSizes[state.position.mapID])
p.Context={Frame=function() return {position=state.position,width=size[1],height=size[2]} end}
local observed=p.Guidance.Observed(snapshot,ctx,archived.constraints)
local before=archived.displayed.selected.questID
assert(before==413 and archived.retained,"Expected the reported retained Shimmer Stout decision")
local result,model,trace
local ok,why=p.PlanLearning.WithSnapshot(archived.learning,function()
    local environment=p.Schema.Clone(archived.environment)
    environment.travel=assert(p.TravelEstimate.Open(environment.travelModel))
    local job=assert(p.PlanSearch.Begin(graph,state,archived.constraints,environment))
    for _=1,50000 do result=job:Step(1);if result then break end end
    assert(result and result.status=="ready","Search failed to settle")
    result.replayGraph={version=graph.version,status=graph.status,identity=graph.identity,revision=graph.revision,
        coverage=graph.coverage,actions=graph.actions}
    result.replayState=state;result.replayEnvironment=archived.environment;result.replayLearning=archived.learning
    result.candidateIDs={};for _,action in ipairs(graph.actions) do result.candidateIDs[#result.candidateIDs+1]=action.id end
    model=p.PlanRuntime.Result(result,observed,ctx,archived.constraints,archived.replayPrior,state)
    assert(model.localGuidance and model.selected.questID==412,"Nearby Operation Recombobulation must win")
    assert(#model.localCoverage.missing==3,"Expected three eligible navigable coverage gaps")
    assert(model.score==nil and model.estimate.xp==nil and model.estimate.seconds==nil and #model.upNext==0)
    assert(not model.selected.planAction and state.active[412] and not state.objectivesComplete[412])
    trace=assert(p.PlanRuntime.Replay())
end)
assert(ok,why)
local exported=assert(p.Transfer.EncodePlan(trace))
local decoded=assert(p.Transfer.DecodePlan(exported))
local replay=p.PlanRuntime.RerunReplay(decoded,trace.source)
assert(replay.status=="match","Fresh export replay failed: "..tostring(replay.reason or replay.phase))
print("Reported decision: Shimmer Stout (413), retained")
print("Corrected decision: "..model.selected.title.." ("..model.selected.questID.."), "..model.reason)
print(string.format("Current target: map %d, %.2f / %.2f",model.selected.destination.mapID,
    model.selected.destination.x*100,model.selected.destination.y*100))
for _,id in ipairs(model.localCoverage.missing) do print("Partial planning data: "..state.live[id].title.." ("..id..")") end
print("No projected XP, fabricated completion, or inherited future rollout; fresh decision export replays exactly")
print("Search work: "..result.metrics.work.."; limited: "..tostring(result.limited))
