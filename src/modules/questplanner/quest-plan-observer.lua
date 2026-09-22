-- Evidence episodes: refresh frequency is not work duration; only confirmed progress trains.
local planner=RikUI.QuestPlanner
local schema,observer=planner.Schema,{}
planner.PlanObserver=observer
local episode,lastContext,phase
local function now()
    local ok,value=planner.Context.Call(GetTime)
    if ok and schema.Number(value,0,2147483647) then return value end
end
local function matchesTarget(ctx)
    return episode and episode.action.target and ctx and ctx.targetNPC==episode.action.target.id
end
local function advance(at)
    if not episode or not at or not episode.at then return end
    local dt=at-episode.at
    if dt<0 or dt>120 or at-episode.started>1200 then episode=nil;phase=nil;return end
    if phase and dt>0 then episode.buckets[phase]=(episode.buckets[phase] or 0)+dt end
    episode.at=at
end
local function fulfilled(snapshot,action)
    local row=snapshot.quests[action.questID]
    local objective=row and row.objectives and row.objectives[action.liveIndex or 0]
    return objective and objective.numFulfilled
end
local function commit(units)
    if not episode or not schema.Number(units,1,10000) then return end
    local b=episode.buckets;local action=episode.action
    local kind=action.kind~="objective" and "interaction" or action.method=="kill" and "combat"
        or (action.method=="drop" or action.method=="loot") and "collection" or "interaction"
    local duration=kind=="collection" and (b.combat or 0)+(b.interaction or 0) or b[kind]
    if duration and duration>0 then planner.PlanLearning.Observe(kind,episode.context,duration,units) end
    for _,component in ipairs({"waiting","recovery","death"}) do
        if b[component] and b[component]>0 then planner.PlanLearning.Observe(component,episode.context,b[component],units) end
    end
    episode.buckets={}
end
function observer.Reset() episode,lastContext,phase=nil,nil,nil end
function observer.Observe(snapshot,ctx,policy,action)
    local at=ctx.observedAt
    local key=action and planner.PlanCosts.Context(action,{identity=snapshot.identity,class=ctx.attributes.class,
        level=ctx.attributes.level,partySize=ctx.partySize,equipmentKey=ctx.equipmentKey,xpRested=ctx.xpRested})
    local interrupted=policy.paused or ctx.afk or not at or not action
        or lastContext and (lastContext.characterKey~=ctx.characterKey or lastContext.position and ctx.position
            and lastContext.position.mapID~=ctx.position.mapID)
    if interrupted then observer.Reset();lastContext=ctx;return end
    if not episode or episode.action.id~=action.id or episode.context~=key then
        episode={action=action,context=key,started=at,at=at,buckets={},fulfilled=fulfilled(snapshot,action)}
        phase=nil
    else
        advance(at)
        if episode then
            local count=fulfilled(snapshot,action)
            if count and episode.fulfilled and count>episode.fulfilled then
                commit(count-episode.fulfilled);episode.fulfilled=count
                planner.PlanLearning.Activity(action.activity or action.method or action.kind)
                planner.PlanLearning.Failure(action.id,false)
            elseif count and episode.fulfilled and count<episode.fulfilled then observer.Reset() end
        end
    end
    if episode then
        if ctx.dead then phase="death"
        elseif phase=="death" then phase=nil end
        if phase=="combat" and (not ctx.inCombat or not matchesTarget(ctx)) then phase=nil end
        if ctx.inCombat and matchesTarget(ctx) then phase="combat" end
    end
    lastContext=ctx
end
function observer.OnEvent(event,...)
    if event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_LEAVING_WORLD" or event=="ZONE_CHANGED_NEW_AREA" then observer.Reset();return end
    if not episode or not lastContext or lastContext.afk then return end
    advance(now());if not episode then return end
    if event=="PLAYER_DEAD" then phase="death"
    elseif event=="PLAYER_REGEN_DISABLED" then phase=matchesTarget(lastContext) and "combat" or nil
    elseif event=="PLAYER_TARGET_CHANGED" then
        if phase=="combat" then phase=nil end
    elseif event=="PLAYER_REGEN_ENABLED" then if phase=="combat" then phase=nil end
    elseif event=="QUEST_DETAIL" or event=="QUEST_PROGRESS" or event=="QUEST_COMPLETE" then
        local ok,id=planner.Context.Call(GetQuestID)
        if ok and id==episode.action.questID then phase="interaction" end
    elseif event=="GOSSIP_SHOW" or event=="LOOT_OPENED" then
        if matchesTarget(lastContext) then phase="interaction" end
    elseif event=="QUEST_FINISHED" or event=="GOSSIP_CLOSED" or event=="LOOT_CLOSED" then
        if phase=="interaction" then phase=nil end
    elseif event=="QUEST_ACCEPTED" or event=="QUEST_TURNED_IN" then
        local id=select(event=="QUEST_ACCEPTED" and 2 or 1,...)
        if id==episode.action.questID then commit(1);observer.Reset() end
    end
end
function observer.Feedback(kind)
    if not episode then return nil,"No current action to time" end
    advance(now());if not episode then return nil,"Timing episode expired" end
    if kind=="waiting" then phase=phase=="waiting" and nil or "waiting";return true
    elseif kind=="recovery" then phase=phase=="recovery" and nil or "recovery";return true end
    return nil,"Unknown timing feedback"
end
function observer.Status() return {active=episode~=nil,phase=phase,actionID=episode and episode.action.id} end
