-- Revisioned character state. Unknown facts remain absent; simulation owns its copy.
local planner=RikUI.QuestPlanner
local schema,stateModel=planner.Schema,{}
planner.PlanState=stateModel
local MAX_QUESTS,MAX_ITEMS=96,128
local function same(a,b)
    return a and b and a.product==b.product and a.build==b.build and a.locale==b.locale
end
stateModel.SameIdentity=same
local function numberMap(raw,maximum,minimum)
    local result,count={},0
    for id,value in pairs(schema.PlainTable(raw) and raw or {}) do
        count=count+1
        if count>maximum then break end
        if schema.ID(id) and schema.Number(value,minimum or 0,2147483647) then result[id]=value end
    end
    return result
end
local function completed(snapshot,ctx,records)
    local result,ids,seen={},{},{}
    local function add(id)
        if schema.ID(id) and not seen[id] and #ids<256 then ids[#ids+1]=id;seen[id]=true end
    end
    local function rule(value,depth)
        if not value or depth>10 then return end
        add(value.questID)
        if value.arg then rule(value.arg,depth+1) end
        for _,child in ipairs(value.args or {}) do rule(child,depth+1) end
    end
    local sorted={};for id in pairs(records or {}) do if schema.ID(id) then sorted[#sorted+1]=id end end;table.sort(sorted)
    for _,id in ipairs(sorted) do add(id) end
    for _,id in ipairs(sorted) do
        local plan=records[id].planning or {}
        rule(plan.requirements,0)
        for _,field in ipairs({"blockedBy","forbiddenAfter","activeBreadcrumbs","blockedWhileActive"}) do
            for _,other in ipairs(plan[field] or {}) do add(other) end
        end
    end
    table.sort(ids)
    local observed=planner.Context and planner.Context.History and planner.Context.History(ids) or {}
    for _,id in ipairs(ids) do
        local value=observed and observed[id]
        if type(value)=="boolean" then result[id]=value end
        if planner.Journal and planner.Journal.TurnedIn(id,snapshot.identity) then result[id]=true end
    end
    for id,value in pairs(ctx.history or {}) do if schema.ID(id) and type(value)=="boolean" then result[id]=value end end
    return result
end
local function inventory(ctx,records)
    local carried,seen,count=numberMap(ctx.inventory,MAX_ITEMS),{},0
    local function add(id)
        if not schema.ID(id) or seen[id] or count>=MAX_ITEMS then return end
        seen[id],count=true,count+1
        if carried[id]~=nil then return end
        local value=planner.Context and planner.Context.ItemCount and planner.Context.ItemCount(id)
        if schema.Number(value,0,2147483647) then carried[id]=value end
    end
    for _,record in pairs(records or {}) do
        add(record.providedItemID)
        for _,item in ipairs(record.requiredItems or {}) do add(item.itemID) end
        for _,objective in ipairs(record.objectives or {}) do
            if objective.type=="item" then add(objective.targetID) end
            add(objective.sourceItemID)
        end
    end
    return carried,count
end
local function addLive(state,snapshot,ctx,id)
    local quest=snapshot.quests[id]
    local binding=planner.StepBindings and planner.StepBindings.Match(snapshot,id)
    state.active[id],state.failed[id]=true,quest.failed
    state.objectivesComplete[id]=quest.objectivesComplete
    state.live[id]={title=quest.title,level=quest.level,objectivesComplete=quest.objectivesComplete,
        destination=schema.Clone(ctx.destinations and ctx.destinations[id]),reward=schema.Clone(ctx.rewards and ctx.rewards[id])}
    if not quest.objectives then return end
    state.progress[id],state.objectiveInfo[id]={},{}
    for index,objective in ipairs(quest.objectives) do
        local key=binding and binding.ids[index] or "live:"..index
        local remaining=math.max(0,objective.numRequired-objective.numFulfilled)
        state.progress[id][key]=objective.finished and 0 or remaining
        state.objectiveInfo[id][key]={index=index,type=objective.type,text=objective.text,
            required=objective.numRequired,fulfilled=objective.numFulfilled,bound=binding~=nil,finished=objective.finished}
    end
end
local function attributes(state,ctx)
    local values=ctx.attributes or {}
    for _,key in ipairs({"level","xp","xpMax","class","race","faction","logCapacity","questXPMultiplier"}) do state[key]=values[key] end
    state.classMask=schema.Integer(state.class,1,32) and 2^(state.class-1) or nil
    state.raceMask=schema.Integer(state.race,1,32) and 2^(state.race-1) or nil
    for _,key in ipairs({"partySize","money","bagFree","floor","phase","characterKey"}) do state[key]=ctx[key] end
    state.reputation=numberMap(ctx.reputation,64,-42000);state.skills=numberMap(ctx.skills,64)
    state.spells=schema.Clone(ctx.spells or {});state.capabilities=schema.Clone(ctx.capabilities or {})
    state.bank=numberMap(ctx.bank,MAX_ITEMS);state.equipped=numberMap(ctx.equipped,MAX_ITEMS)
    state.xpThresholds=numberMap(ctx.xpThresholds,128)
end
function stateModel.Build(snapshot,status,ctx,records,policy)
    if not snapshot or not schema.Identity(snapshot.identity) or not ctx or ctx.origin~="live"
        or snapshot.origin=="imported-untrusted" or not status or (status.state~="current" and status.state~="partial") then
        return nil,"Current live character state required"
    end
    if not schema.List(snapshot.order,256) or not schema.PlainTable(snapshot.quests) then return nil,"Invalid live log" end
    local state={version=1,identity=schema.Clone(snapshot.identity),generation=snapshot.generation,
        sourceRevision=planner.SemanticData and planner.SemanticData.Status().revision,
        fresh=true,logComplete=snapshot.coverage=="log-complete",logCount=snapshot.reportedCount,
        active={},failed={},progress={},objectiveInfo={},objectivesComplete={},live={},applied={},branchLocks={},
        completed=completed(snapshot,ctx,records),position=schema.Clone(ctx.position),
        observedAt=ctx.observedAt,elapsed=0,xpGained=0,unknownXP=0,assumptions={},evidence={},
        policy=schema.Clone(policy),bank={},equipped={},conditionalObjectives={},conditionalCompleted={},
        visited=schema.Clone(ctx.visited or {}),recent=schema.Clone(ctx.recent or {}),failures=schema.Clone(ctx.failures or {}),
        cooldowns=schema.Clone(ctx.cooldowns or {}),services=schema.Clone(ctx.services or {})}
    attributes(state,ctx)
    state.inventory,state.inventoryQueries=inventory(ctx,records)
    for _,id in ipairs(snapshot.order) do addLive(state,snapshot,ctx,id) end
    for _,key in ipairs({"level","xp","xpMax","money","bagFree","partySize","characterKey"}) do
        state.evidence[key]={status=state[key]~=nil and "observed" or "unknown",source="live-client"}
    end
    state.evidence.completed={status="partial",source="live-client-and-turnin-events"}
    state.evidence.inventory={status="partial",source="carried-item-query",count=state.inventoryQueries}
    return state
end
function stateModel.Key(state)
    local out={state.identity.product,state.identity.build,state.identity.locale,state.characterKey or "?",
        tostring(state.sourceRevision),tostring(state.generation),tostring(state.level),tostring(state.money),
        tostring(state.bagFree),tostring(state.partySize),tostring(state.floor),tostring(state.phase)}
    return table.concat(out,":")
end
