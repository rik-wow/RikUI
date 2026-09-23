-- Coalesced planning with cancellable jobs and publication revision checks.
local core,planner=RikUI,RikUI.QuestPlanner
local schema,controller=planner.Schema,{}
planner.Controller=controller
local MAX_FLAGS,FRAME_CALLS,FRAME_MS=32,64,1
local policy=planner.Preferences and planner.Preferences.Normalize({}) or {pins={},avoids={},skips={},dungeons=false}
policy.paused,policy.arrow=false,false
local view={status="unavailable",detail="Reading the quest log",quests={}}
local revision,signature,data,job,context=0,nil,nil,nil,nil
local stats={replans=0,published=0,cancelled=0,maxSliceMS=0,timingSamples=0,frameCalls=0}
local worker,manualQuest,journeyState,recommendationPosition
local adaptiveRecords,manualRow,incumbent
local function notify()
    if core.QuestTracker and core.QuestTracker.Request then core.QuestTracker.Request() end
    if planner.View and planner.View.Refresh then planner.View.Refresh() end
end
local function publish(value)
    if not value.adaptive and planner.PlanRuntime then planner.PlanRuntime.ClearReplay() end
    if journeyState and journeyState.boundModel~=value then planner.JourneyLive.Detach(journeyState) end
    if journeyState and value.selected and journeyState.base.questID~=value.selected.questID then journeyState=nil end
    if value.adaptive and value.actionID and planner.PlanRuntime then
        planner.PlanRuntime.RecordSwitch(incumbent,value,context)
        incumbent=value
    end
    view=value; stats.published=stats.published+1
    notify()
end
local function cancel()
    if job then job.search:Cancel(); job=nil; stats.cancelled=stats.cancelled+1 end
end
function controller.Invalidate(retainJourney)
    if planner.PlanRuntime then planner.PlanRuntime.ClearReplay() end
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
-- Invalidating presentation must not erase the plan used by the next search.
-- The new state still revalidates and reprices this borrowed incumbent.
function controller.Incumbent() return incumbent or view end
function controller.Refresh()
    revision=revision+1;signature=nil;cancel()
end
function controller.Get() return schema.Clone(view) end
function controller.Quests()
    local snapshot,status=planner.GetSnapshot()
    if not snapshot or not context or status.state=="stale" or status.state=="unavailable" then return {} end
    local rows=planner.Guidance.Observed(snapshot,context,policy,view.selected and view.selected.questID,true,view.selected)
    local seen={};for _,row in ipairs(rows) do seen[row.questID]=true end
    for _,list in ipairs({view.upNext or {},view.alternatives or {},view.selected and {view.selected} or {}}) do
        for _,row in ipairs(list) do
            if not seen[row.questID] and #rows<96 then rows[#rows+1]=schema.Clone(row);seen[row.questID]=true end
        end
    end
    return rows
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
    if planner.Preferences then
        local restored=planner.Preferences.Normalize(saved)
        if restored then policy=restored end
    end
    for _,name in ipairs({"pins","avoids","skips"}) do policy[name]=flagMap(saved[name]) end
    for _,name in ipairs({"paused","arrow","dungeons"}) do policy[name]=saved[name]==true end
end
function controller.Preference(name,value)
    if not planner.Preferences then return nil,"Adaptive controls unavailable" end
    local raw=schema.Clone(policy);raw[name]=value
    if name=="flavor" then raw.difficulty,raw.grind,raw.readingSeconds,raw.explorationMinutes=nil,nil,nil,nil end
    local nextPolicy,reason=planner.Preferences.Normalize(raw)
    if not nextPolicy then return nil,reason end
    nextPolicy.paused,nextPolicy.arrow=policy.paused,policy.arrow
    policy=nextPolicy
    if core.CharDB then core.CharDB.questPolicy=schema.Clone(policy);core:Changed() end
    controller.Refresh();planner.Request();notify()
    return true
end
function controller.Feedback(kind)
    if not planner.PlanRuntime then return nil,"Adaptive feedback unavailable" end
    local ok,reason=planner.PlanRuntime.Feedback(kind,view.actionID)
    if ok then controller.Refresh();planner.Request() end
    return ok,reason
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
    if (name~="pins" and name~="avoids" and name~="skips" and name~="defers" and name~="questGoals" and name~="zoneGoals") or not schema.ID(id) then return nil,"invalid constraint" end
    local values=policy[name]
    if not values then return nil,"Constraint unavailable" end
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
            if row.questID==id and row.destination and not row.skipped and not row.deferred and not row.groupBlocked and not row.avoided and not row.failed then
                if not row.planAction or not planner.PlanRuntime or planner.PlanRuntime.Valid(row.planAction,policy) then eligible=true;manualRow=schema.Clone(row) end
                break
            end
        end
        if not eligible then return nil,"Choose an available quest with a map location; restore any skip or avoided area first" end
    end
    if manualQuest==id then return true end
    manualQuest=id
    if not id then manualRow=nil end
    controller.Invalidate();planner.Request()
    return true
end
function controller.Clear()
    policy.pins,policy.avoids,policy.skips,policy.defers,policy.questGoals,policy.zoneGoals={},{},{},{},{},{}
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
    if result.status=="cancelled" then job=nil;return end
    local value
    if result.adaptive then
        value=planner.PlanRuntime.Result(result,current.observed,context,policy,controller.Incumbent(),current.search.state)
    else value=planner.Guidance.Result(result,current.observed,context,data,current.reason,policy) end
    if expired(value) then controller.Invalidate(); planner.Request(); return end
    if not result.adaptive then value.actionID=result.actions and result.actions[1] and result.actions[1].id end
    if planner.JourneyLive and not result.adaptive then
        journeyState=planner.JourneyLive.Attach(value,result,data,context,current.originNode,journeyState)
        if journeyState then planner.JourneyLive.Tick(journeyState,value,policy.paused) end
    end
    if prior and value.selected and prior~=value.selected.questID then value.change="Next action changed: "..current.reason end
    job=nil; publish(value)
end
local function refreshPosition()
    if not planner.enabled or policy.paused or manualQuest or not context or not planner.Recommendations then return end
    local frame=planner.Context.Frame()
    local position=frame and frame.position
    if not position then return end
    if not recommendationPosition or planner.Recommendations.Moved(recommendationPosition,position,frame) then
        local changed=recommendationPosition~=nil
        local elapsed=changed and frame.time and recommendationPosition.time and frame.time-recommendationPosition.time
        local teleported=changed and recommendationPosition.mapID~=position.mapID
        if changed and elapsed and elapsed>0 and frame.width and frame.height and not frame.taxi then
            local distance=math.sqrt(((position.x-recommendationPosition.x)*frame.width)^2+((position.y-recommendationPosition.y)*frame.height)^2)
            teleported=teleported or distance>math.max(100,elapsed*(frame.speed or 7)*2+30)
        end
        recommendationPosition={mapID=position.mapID,x=position.x,y=position.y,time=frame.time}
        if teleported then controller.Invalidate(true) end
        if changed and planner.Request then planner.Request() end
    end
end
function controller.Step()
    local callbackStart=clock()
    local function remaining()
        local now=clock()
        return not callbackStart or not now or now-callbackStart<FRAME_MS
    end
    local function record()
        local ended=clock()
        if callbackStart and ended then stats.maxCallbackMS=math.max(stats.maxCallbackMS or 0,ended-callbackStart) end
    end
    refreshPosition()
    if planner.enabled and remaining() and planner.PlanXP then
        local ok,at=planner.Context.Call(GetTime);if ok then planner.PlanXP.Tick(at) end
    end
    if planner.enabled and remaining() and planner.BagScan then planner.BagScan.Step(16) end
    if planner.enabled and planner.Enrichment then planner.Enrichment.Tick() end
    local loadStart=clock()
    if planner.enabled and planner.SemanticData then planner.SemanticData.Step() end
    local loadEnd=clock()
    if loadStart and loadEnd then stats.maxLoadMS=math.max(stats.maxLoadMS or 0,loadEnd-loadStart) end
    if planner.enabled and remaining() and planner.SemanticData and planner.SemanticData.StepHistory then planner.SemanticData.StepHistory() end
    if planner.enabled and remaining() and planner.SemanticGuidance then planner.SemanticGuidance.Step() end
    if planner.enabled and journeyState and planner.JourneyLive.Tick(journeyState,view,policy.paused) then notify() end
    if not planner.enabled or policy.paused then cancel();record();return end
    if expired(view) then controller.Invalidate();planner.Request();record();return end
    if not job or not remaining() then record();return end
    local current,start,count=job,clock(),0
    repeat
        local result=current.search:Step(1)
        count=count+1
        if result then finish(current,result);break end
        if current.adaptive then
            current.steps=current.steps+1
            if current.steps%128==0 and current.search.Peek and current.revision==revision then
                local partial=current.search:Peek()
                if partial and partial.actions and #partial.actions>0
                    and not (view.selected and view.selected.planAction
                        and planner.PlanTransitions.Check(view.selected.planAction,current.search.state,policy)==true) then
                    publish(planner.PlanRuntime.Result(partial,current.observed,context,policy,controller.Incumbent(),current.search.state))
                end
            end
        end
        if not remaining() then break end
    until count>=FRAME_CALLS or job~=current
    local ended=clock()
    if start and ended then stats.maxSliceMS=math.max(stats.maxSliceMS,ended-start);stats.timingSamples=stats.timingSamples+1 end
    stats.frameCalls=math.max(stats.frameCalls,count)
    record()
end
local function manualView(observed,ctx,snapshot,status)
    if not manualQuest then return end
    local candidates=observed
    if manualRow and manualRow.planAction and planner.PlanState then
        local state=planner.PlanState.Build(snapshot,status,ctx,adaptiveRecords or {},policy)
        if not state or planner.PlanTransitions.Check(manualRow.planAction,state,policy)~=true then manualQuest,manualRow=nil,nil;return end
        candidates={manualRow}
    end
    for _,row in ipairs(candidates) do
        if row.questID==manualQuest and row.destination and not row.skipped and not row.deferred and not row.groupBlocked and not row.avoided and not row.failed then
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
    local chosen=manualView(observed,ctx,snapshot,status)
    if chosen then publish(chosen);return end
    local input,problem
    if data then input,problem=data:Prepare(snapshot,status,ctx,dialog) end
    if not input and planner.PlanRuntime then
        local search,issue=planner.PlanRuntime.Begin(snapshot,status,ctx,adaptiveRecords or {},observed,policy)
        if search then
            local prior=controller.Incumbent()
            job={search=search,revision=revision,observed=observed,reason=reason,adaptive=true,steps=0}
            stats.replans=stats.replans+1
            local fallback=planner.PlanRuntime.Result({actions={},status="refining",decisionKind="fallback",
                reason="Refining future quest options"},observed,ctx,policy,prior,search.state)
            if fallback.status=="observed" then fallback.detail=policy.flavor..": refining future quest options" end
            if prior.adaptive and prior.selected and prior.selected.planAction
                and planner.PlanTransitions.Check(prior.selected.planAction,search.state,policy)==true then
                fallback=planner.PlanRuntime.Result({actions={prior.selected.planAction},status="refining",decisionKind="continuity",
                    reason="Continue while future options are updated"},observed,ctx,policy,prior,search.state)
            end
            publish(fallback)
            return
        end
        problem=issue
    end
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
    if planner.SemanticData then
        planner.SemanticData.Ensure(snapshot,ctx)
        adaptiveRecords=planner.SemanticData.Records and planner.SemanticData.Records(snapshot,ctx,policy) or {}
    end
    if planner.PlanContext then planner.PlanContext.Enrich(ctx,snapshot,adaptiveRecords or {}) end
    if planner.PlanRuntime then planner.PlanRuntime.Observe(snapshot,ctx,policy) end
    if planner.SemanticGuidance then planner.SemanticGuidance.Observe(snapshot,ctx,policy,view.selected and view.selected.questID) end
    if planner.Hunts then planner.Hunts.Observe(snapshot,ctx) end
    local dialog=planner.Journal.Dialog()
    local nextSignature,signatureProblem=planner.Guidance.Signature(snapshot,status,ctx,dialog)
    if nextSignature and planner.PlanContext then nextSignature=nextSignature.."|"..planner.PlanContext.Signature(ctx) end
    context=ctx
    if not nextSignature then
        controller.Invalidate();publish({status="unavailable",detail=signatureProblem,quests={}});return
    end
    if signature==nextSignature then return end
    cancel(); revision=revision+1; signature=nextSignature
    local observed=planner.Guidance.Observed(snapshot,ctx,policy,view.selected and view.selected.questID,false,view.selected)
    if policy.paused then publish({status="paused",detail="Quest guidance paused",quests=observed}); return end
    begin(snapshot,status,ctx,dialog,observed,reason or "quest state changed")
end
function controller.Start()
    controller.Restore()
    worker=CreateFrame("Frame")
    worker:SetScript("OnUpdate",function() controller.Step() end)
end
