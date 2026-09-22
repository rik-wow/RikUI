-- Coalesced planning with cancellable jobs and publication revision checks.
local core,planner=RikUI,RikUI.QuestPlanner
local schema,controller=planner.Schema,{}
planner.Controller=controller
local MAX_FLAGS,FRAME_CALLS,FRAME_MS=32,64,1
local policy={pins={},avoids={},skips={},paused=false,arrow=false,dungeons=false}
local view={status="unavailable",detail="Reading the quest log",quests={}}
local revision,signature,data,job,context=0,nil,nil,nil,nil
local stats={replans=0,published=0,cancelled=0,maxSliceMS=0,timingSamples=0,frameCalls=0}
local worker,manualQuest,journeyState
local function notify()
    if core.QuestTracker and core.QuestTracker.Request then core.QuestTracker.Request() end
    if planner.View and planner.View.Refresh then planner.View.Refresh() end
end
local function publish(value)
    if journeyState and journeyState.boundModel~=value then planner.JourneyLive.Detach(journeyState) end
    if journeyState and value.selected and journeyState.base.questID~=value.selected.questID then journeyState=nil end
    view=value; stats.published=stats.published+1
    notify()
end
local function cancel()
    if job then job.search:Cancel(); job=nil; stats.cancelled=stats.cancelled+1 end
end
function controller.Invalidate(retainJourney)
    if journeyState then
        if retainJourney then planner.JourneyLive.Detach(journeyState) else journeyState=nil end
    end
    if planner.Terrain then planner.Terrain.Invalidate() end
    revision=revision+1; signature=nil; cancel()
    view={status="updating",detail="Updating quest guidance",quests={}}
    notify()
end
-- Borrowed views are private read-only values for presentation/frame consumers.
function controller.Peek() return view end
function controller.Refresh()
    revision=revision+1;signature=nil;cancel()
end
function controller.Get() return schema.Clone(view) end
function controller.Quests()
    local snapshot,status=planner.GetSnapshot()
    if not snapshot or not context or status.state=="stale" or status.state=="unavailable" then return {} end
    return planner.Guidance.Observed(snapshot,context,policy,view.selected and view.selected.questID,true)
end
function controller.Policy() return schema.Clone(policy) end
function controller.ArrowEnabled() return policy.arrow end
function controller.Stats() return schema.Clone(stats) end
function controller.Context() return schema.Clone(context) end
local function flagMap(raw)
    local result,count={},0
    if not schema.PlainTable(raw) then return result end
    for id,value in pairs(raw) do
        if schema.ID(id) and value==true then count=count+1; if count>MAX_FLAGS then return {} end; result[id]=true end
    end
    return result
end
function controller.Restore()
    local saved=core.CharDB and core.CharDB.questPolicy
    if not schema.PlainTable(saved) then return end
    for _,name in ipairs({"pins","avoids","skips"}) do policy[name]=flagMap(saved[name]) end
    for _,name in ipairs({"paused","arrow","dungeons"}) do policy[name]=saved[name]==true end
end
function controller.Set(name,value)
    if name~="paused" and name~="arrow" and name~="dungeons" then return nil,"unknown setting" end
    if type(value)~="boolean" then return nil,"invalid setting" end
    if policy[name]==value then return true end
    policy[name]=value
    if core.CharDB then core.CharDB.questPolicy=schema.Clone(policy); core:Changed() end
    if name=="arrow" then
        notify()
        if planner.Navigation then planner.Navigation.Refresh() end
    else controller.Invalidate(name=="paused"); planner.Request() end
    return true
end
function controller.Toggle(name,id)
    if (name~="pins" and name~="avoids" and name~="skips") or not schema.ID(id) then return nil,"invalid constraint" end
    local values=policy[name]
    if values[id] then values[id]=nil
    else
        local count=0; for _ in pairs(values) do count=count+1 end
        if count>=MAX_FLAGS then return nil,"constraint limit reached" end
        values[id]=true
    end
    if core.CharDB then core.CharDB.questPolicy=schema.Clone(policy); core:Changed() end
    controller.Invalidate(); planner.Request()
    return true
end
function controller.Select(id)
    if id~=nil then
        local eligible=false
        for _,row in ipairs(controller.Quests()) do
            if row.questID==id and row.destination and not row.skipped and not row.avoided and not row.failed then eligible=true;break end
        end
        if not eligible then return nil,"Choose an available quest with a map location; restore any skip or avoided area first" end
    end
    if manualQuest==id then return true end
    manualQuest=id
    controller.Invalidate();planner.Request()
    return true
end
function controller.Clear()
    policy.pins,policy.avoids,policy.skips={},{},{}
    if core.CharDB then core.CharDB.questPolicy=schema.Clone(policy); core:Changed() end
    controller.Invalidate(); planner.Request()
end
function controller.Install(raw)
    local ok,value,reason=pcall(planner.Dataset.New,raw)
    if not ok or not value then return nil,reason or "invalid compiled dataset" end
    data=value
    controller.Invalidate(); planner.Request()
    return true
end
function controller.Coverage()
    return data and data:Coverage() or {catalogued=0,denominator="unknown",fields={}}
end
local function clock()
    local ok,value=planner.Context.Call(debugprofilestop)
    if ok and schema.Number(value,0,2147483647) then return value end
end
local function expired(value)
    if not value.validUntil then return false end
    local ok,now=planner.Context.Call(GetTime)
    return not ok or not schema.Number(now,0,2147483647) or now>value.validUntil
end
local function finish(current,result)
    if job~=current or current.revision~=revision or not planner.enabled or policy.paused then return end
    local prior=view.selected and view.selected.questID
    local value=planner.Guidance.Result(result,current.observed,context,data,current.reason,policy)
    if expired(value) then controller.Invalidate(); planner.Request(); return end
    value.actionID=result.actions and result.actions[1] and result.actions[1].id
    if planner.JourneyLive then
        journeyState=planner.JourneyLive.Attach(value,result,data,context,current.originNode,journeyState)
        if journeyState then planner.JourneyLive.Tick(journeyState,value,policy.paused) end
    end
    if prior and value.selected and prior~=value.selected.questID then value.change="Next action changed: "..current.reason end
    job=nil; publish(value)
end
function controller.Step()
    if planner.enabled and planner.Enrichment then planner.Enrichment.Tick() end
    if planner.enabled and planner.SemanticData then planner.SemanticData.Step() end
    if planner.enabled and planner.SemanticGuidance then planner.SemanticGuidance.Step() end
    if planner.enabled and journeyState and planner.JourneyLive.Tick(journeyState,view,policy.paused) then notify() end
    if not planner.enabled or policy.paused then cancel(); return end
    if expired(view) then controller.Invalidate(); planner.Request(); return end
    if not job then return end
    local current,start,count=job,clock(),0
    repeat
        local result= current.search:Step(1)
        count=count+1
        if result then finish(current,result); break end
        local now=clock()
        if start and now and now-start>=FRAME_MS then break end
    until count>=FRAME_CALLS or job~=current
    local ended=clock()
    if start and ended then stats.maxSliceMS=math.max(stats.maxSliceMS,ended-start); stats.timingSamples=stats.timingSamples+1 end
    stats.frameCalls=math.max(stats.frameCalls,count)
end
local function manualView(observed,ctx)
    if not manualQuest then return end
    for _,row in ipairs(observed) do
        if row.questID==manualQuest and row.destination then
            local value=planner.Guidance.Result({actions={},status="insufficient-data"},observed,ctx,nil,"Selected by you",policy)
            if value.status~="constraint-conflict" then
                value.selected=schema.Clone(row);value.stops={schema.Clone(row)}
                value.manual=true;value.detail="Selected by you; walking route unverified"
            end
            return value
        end
    end
    manualQuest=nil
end
local function begin(snapshot,status,ctx,dialog,observed,reason)
    local chosen=manualView(observed,ctx)
    if chosen then publish(chosen);return end
    local input,problem
    if data then input,problem=data:Prepare(snapshot,status,ctx,dialog) end
    if not input then input=planner.Guidance.DialogInput(snapshot,status,ctx,dialog) end
    if not input then
        publish(planner.Guidance.Result({actions={},status="insufficient-data"},observed,ctx,data,problem or reason,policy))
        return
    end
    local options=schema.Clone(policy)
    options.depth,options.width,options.maxTransitions,options.maxTravelWork=6,16,1200,12000
    options.previousID=view.actionID; options.reason=reason
    local search,issue=planner.Optimizer.Begin(input.actions,input.state,input.book,input.graph,options)
    if not search then
        publish({status="unavailable",detail=issue,quests=observed}); return
    end
    job={search=search,revision=revision,observed=observed,reason=reason,originNode=input.originNode}
    stats.replans=stats.replans+1
    local pending={}
    for key,value in pairs(view) do pending[key]=value end
    pending.status,pending.detail="calculating","Calculating quest sequence"
    view=pending;notify()
end
function controller.Update(snapshot,status,reason)
    if not planner.enabled then cancel(); return end
    if not snapshot or status.state=="stale" or status.state=="unavailable" then
        if planner.Hunts then planner.Hunts.Suspend() end
        controller.Invalidate(true); publish({status=status.state,detail="Current quest data is unavailable",quests={}}); return
    end
    local ctx=planner.Context.Read(snapshot,policy.pins)
    if not ctx then controller.Invalidate(true); return end
    if planner.SemanticData then planner.SemanticData.Ensure(snapshot,ctx) end
    if planner.SemanticGuidance then planner.SemanticGuidance.Observe(snapshot,ctx,policy,view.selected and view.selected.questID) end
    if planner.Hunts then planner.Hunts.Observe(snapshot,ctx) end
    local dialog=planner.Journal.Dialog()
    local nextSignature,signatureProblem=planner.Guidance.Signature(snapshot,status,ctx,dialog)
    context=ctx
    if not nextSignature then
        controller.Invalidate();publish({status="unavailable",detail=signatureProblem,quests={}});return
    end
    if signature==nextSignature then return end
    cancel(); revision=revision+1; signature=nextSignature
    local observed=planner.Guidance.Observed(snapshot,ctx,policy,view.selected and view.selected.questID)
    if policy.paused then publish({status="paused",detail="Quest guidance paused",quests=observed}); return end
    begin(snapshot,status,ctx,dialog,observed,reason or "quest state changed")
end
function controller.Start()
    controller.Restore()
    worker=CreateFrame("Frame")
    worker:SetScript("OnUpdate",function() controller.Step() end)
end
