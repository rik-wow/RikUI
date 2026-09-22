-- Full installed corpus integrity and source-driven host replay. Not native gameplay evidence.
local root=assert(arg[1],"addon directory required"):gsub("\\","/"):gsub("/$","")
RikUI={Secret={IsSecret=function() return false end}}
for _,name in ipairs({"schema","objectives","transfer","optimizer","area-optimizer","steps","step-bindings","guide-data",
    "observed-steps","semantic-data","semantic-guidance","hunts","targets","guidance","preferences","plan-state","plan-graph"}) do
    dofile("src/modules/questplanner/quest-"..name..".lua")
end
local p=RikUI.QuestPlanner
local loads,peak,total=0,0,0
C_AddOns={LoadAddOn=function(name)
    assert(name=="RikUIQuestCorpus" or name:match("^RikUIQuestCorpus_P%d+_S%d+$") or name:match("^RikUIQuestCorpus_P%d+$"))
    local begin=os.clock()
    local toc=assert(io.open(root.."/"..name.."/"..name..".toc"))
    for line in toc:lines() do
        line=line:gsub("\r",""):match("^%s*(.-)%s*$")
        if line~="" and line:sub(1,1)~="#" then
            assert(line:match("^[%w_-]+%.lua$"),"unsafe compiled file path")
            assert(loadfile(root.."/"..name.."/"..line))()
        end
    end
    toc:close()
    local elapsed=(os.clock()-begin)*1000
    loads=loads+1;peak=math.max(peak,elapsed);total=total+elapsed
    return true
end}
assert(C_AddOns.LoadAddOn("RikUIQuestCorpus"))
local catalog=assert(RikUIQuestCorpusCatalog)
local identity=catalog.identity
assert(catalog.eventMemberships and catalog.eventMemberships.sourceMemberships==1006,
    "pinned active holiday memberships must be installed")
local context={identity=identity,origin="live",attributes={class=1,faction="Alliance"},position={mapID=1426,x=.5,y=.5},
    destinations={},rewards={},history={},observedAt=1}
p.Context={Frame=function() return {position=context.position,width=1000,height=1000} end}
local policy={pins={},skips={},avoids={}}
local snapshot={identity=identity,order={},quests={}}
local buckets={}
for bucket in pairs(catalog.partitions) do buckets[#buckets+1]=bucket end
table.sort(buckets)
collectgarbage("collect");local before=collectgarbage("count")
for _,bucket in ipairs(buckets) do
    snapshot.order={bucket*catalog.partitionSize+1}
    p.SemanticData.Ensure(snapshot,context)
    local limit=0
    repeat p.SemanticData.Step();limit=limit+1;assert(limit<513,"partition exceeded slice limit")
    until p.SemanticData.Status().queuedPartitions==0
end
assert(p.SemanticData.Status().loadedPartitions==#buckets,p.SemanticData.Status().reason)
for _,case in ipairs({{8653,"LunarFestival"},{172,"ChildrensWeek"},{7905,"DarkmoonFaire"}}) do
    local quest=assert(p.SemanticData.Quest(identity,case[1]),"required seasonal source record")
    assert(quest.planning.seasonalEvent==case[2],"seasonal membership missing: "..case[1])
    assert(quest.planning.seasonalProvenance.revision=="454b9d072965ee8f1a881429260fcf1fac8d60f7")
end
collectgarbage("collect")
local retained=collectgarbage("count")-before
local records,objectives,matched,located,zones,methods=0,0,0,0,{},{}
local callbackTimes={}
local plannerRecords,plannerActions,plannerFuture=0,0,0
local plannerPolicy=assert(p.Preferences.Normalize({}))
local function admitPlan(record)
    local state={fresh=true,identity=identity,sourceRevision=catalog.revision,live={},active={},
        objectiveInfo={},position=context.position,progress={}}
    local job=assert(p.PlanGraph.Begin(state,{[record.id]=record},{},plannerPolicy))
    local graph
    for _=1,4 do graph=job:Step(1);if graph then break end end
    assert(graph and graph.status=="ready","bounded graph admission did not finish")
    assert(#graph.actions<=768,"action cap")
    for _,action in ipairs(graph.actions) do
        assert(action.questID==record.id and action.completionEvidence and action.recovery)
        assert(action.authority=="reference","source graph cannot become live proof")
        if action.kind=="objective" then assert(action.countUnknown or action.count~=nil) end
    end
    plannerRecords=plannerRecords+1;plannerActions=plannerActions+#graph.actions
    plannerFuture=plannerFuture+graph.coverage.future
end
for _,bucket in ipairs(buckets) do
    for id=math.max(1,bucket*catalog.partitionSize),(bucket+1)*catalog.partitionSize-1 do
        local record=p.SemanticData.Quest(identity,id)
        if record then
            records=records+1
            admitPlan(record)
            local observed={}
            local first
            for _,objective in ipairs(record.objectives or {}) do
                if #observed<32 and objective.name and objective.name~="" then
                    local label=objective.name
                    local kind=objective.type=="kill-credit" and "monster" or objective.type
                    if kind=="monster" then label=label.." slain" end
                    observed[#observed+1]={text="0/2 "..label,type=kind,numFulfilled=0,numRequired=2,finished=false}
                    objectives=objectives+1
                    for _,method in ipairs(objective.methods or {}) do
                        methods[method.kind]=(methods[method.kind] or 0)+1
                        for _,area in ipairs(method.areas or {}) do
                            if area.mapID and not first and not area.phase then first=area end
                        end
                    end
                end
            end
            if #observed>0 then
                snapshot={identity=identity,order={id},quests={[id]={id=id,title=record.title,objectives=observed,objectivesComplete=false}}}
                if first then context.position={mapID=first.mapID,x=first.x,y=first.y} end
                local begin=os.clock()
                p.SemanticGuidance.Observe(snapshot,context,policy)
                local binding=p.StepBindings.Match(snapshot,id)
                if binding and binding.semantic then for _ in pairs(binding.semantic) do matched=matched+1 end end
                local rows=p.Guidance.Observed(snapshot,context,policy)
                local row=rows[1]
                if row and row.semantic and row.destination then
                    located=located+1;zones[row.destination.mapID]=true
                    assert(row.semantic.authority=="reference")
                    assert(row.step and row.step.state~="completed","proximity completed sourced objective")
                end
                callbackTimes[#callbackTimes+1]=(os.clock()-begin)*1000
            end
        end
    end
end
local zoneCount=0;for _ in pairs(zones) do zoneCount=zoneCount+1 end
assert(records>7000,"expected full provider plus exact client membership universe")
assert(matched>1000 and located>1000 and zoneCount>20,"semantic integration too narrow")
table.sort(callbackTimes)
print(string.format("INSTALLED CORPUS: %d records, %d partitions; %d synthetic source-derived objectives, %d matched; %d located quests across %d maps; all-page retained %.1f KiB; load total/max %.3f/%.3f ms; admission p99/max %.3f/%.3f ms",
    records,#buckets,objectives,matched,located,zoneCount,retained,total,peak,
    callbackTimes[math.max(1,math.ceil(#callbackTimes*.99))],callbackTimes[#callbackTimes]))
for method,count in pairs(methods) do print("SOURCE METHOD",method,count) end
assert(plannerRecords==records,"all records must pass production graph admission")
if catalog.planning then assert(plannerFuture>4000,"future planning corpus missing") end
print("PLANNER GRAPH",plannerRecords,"records",plannerFuture,"future records",plannerActions,"action transitions")
for _,persona in ipairs({{class=8,faction="Horde"},{class=2,faction="Alliance"},{class=11,faction="Horde"}}) do
    context.attributes=persona;p.SemanticData.Ensure(snapshot,context)
    for _,id in ipairs({2,287,310,315,384,638,1462,6564,96608}) do
        local record=p.SemanticData.Quest(identity,id)
        if record then admitPlan(record) end
    end
end
context.attributes={class=1,faction="Alliance"};p.SemanticData.Ensure(snapshot,context)
if arg[2] then
    local file=assert(io.open(arg[2],"rb"));local wire=file:read("*a");file:close()
    snapshot=assert(p.Transfer.Decode(wire:gsub("[\r\n]+$","")))
    context=snapshot.context
    snapshot.origin=nil;context.origin="live" -- archived host replay, never runtime import admission
    p.Context.Frame=function() return {position=context.position,width=5100,height=3400} end
    p.SemanticData.Ensure(snapshot,context)
    p.SemanticGuidance.Observe(snapshot,context,policy)
    local rows=p.Guidance.Observed(snapshot,context,policy)
    local seen={}
    for _,row in ipairs(rows) do
        seen[row.questID]=row
        print("ARCHIVED HOST",row.questID,row.title,row.semantic and row.semantic.method or "live/reviewed",
            row.destination and row.destination.mapID or "unknown",row.step and row.step.state)
    end
    assert(seen[310] and seen[310].targetHint,"Bitter Rivals reviewed basement binding must survive")
    assert(seen[313] and seen[313].step.state~="completed","collection progress remains live")
    assert(seen[287] and seen[287].step.state~="completed","hunting/exploration progress remains live")
end

