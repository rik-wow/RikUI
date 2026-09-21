-- Hypothetical effects only. Never writes live state or world evidence.
local planner=RikUI.QuestPlanner
local schema,actions=planner.Schema,planner.Actions
local function complete(counters)
    if not schema.PlainTable(counters) or next(counters)==nil then return false end
    for _,remaining in pairs(counters) do if remaining~=0 then return false end end
    return true
end

local function initial(raw)
    local state,reason=schema.CopyLimited(raw,4096,65536,12)
    if not state or not schema.Identity(state.identity) or not schema.PlainTable(state.travel)
        or not schema.Identity(state.travel.identity) then return nil,reason or "invalid simulation state" end
    for _,key in ipairs({"product","build","locale"}) do
        if state.identity[key]~=state.travel.identity[key] then return nil,"travel identity mismatch" end
    end
    for _,key in ipairs({"active","failed","objectivesComplete","turnedIn","objectives","inventory","completedActions","pinsDone"}) do
        state[key]=state[key] or {}
        if not schema.PlainTable(state[key]) then return nil,"invalid state map" end
    end
    for _,key in ipairs({"elapsed","gainedXP","unknownXP","risk","uncertainty"}) do
        state[key]=state[key] or 0
        if not schema.Number(state[key],0,2147483647) then return nil,"invalid state counter" end
    end
    return state
end

local function preflight(row,state,policy,book)
    if row.source.authority~="verified" or state.fresh~=true or state.origin=="imported-untrusted" then return nil,"unverified action or state" end
    if state.completedActions[row.id] then return nil,"action already applied" end
    if policy.skips and policy.skips[row.questID] then return nil,"quest skipped" end
    if policy.avoids and policy.avoids[row.zoneID] then return nil,"zone avoided" end
    if row.category=="dungeon" and policy.dungeons~=true then return nil,"dungeon disabled" end
    if row.kind=="unlock" then
        if planner.Eligibility.Condition(row.requirement,state)~="true" then return nil,"unlock requirement unknown or blocked" end
        local target=row.unlock.kind=="flight" and state.travel.flights or state.flags
        if target and target[row.unlock.key]==true then return nil,"already unlocked" end
    elseif planner.Eligibility.Evaluate(row,state,book).status~="eligible" then return nil,"action not eligible" end
    return true
end

local function totals(row,state,leg,policy)
    if not leg or (leg.status~="known" and leg.status~="budget-exhausted")
        or not schema.Number(leg.seconds,0,86400) or not schema.Number(leg.risk,0,100)
        or not schema.Number(leg.uncertainty,0,100) then return nil,"travel not feasible" end
    local duration=0
    for _,key in ipairs({"combat","looting","interaction","downtime"}) do duration=duration+row.duration[key] end
    state.elapsed=state.elapsed+leg.seconds+duration
    state.risk,state.uncertainty=state.risk+leg.risk+row.risk,state.uncertainty+leg.uncertainty+row.uncertainty
    if state.elapsed>policy.maxSeconds or state.risk>policy.maxRisk or state.uncertainty>policy.maxUncertainty then return nil,"route limits" end
    if not schema.Number(state.travel.departure,0,2147483647) then return nil,"travel clock unknown" end
    state.travel.departure=state.travel.departure+leg.seconds+duration
    if leg.hearthUsed then state.travel.hearthDisabled=true end
    return true
end

local function award(state,row)
    if row.xp==nil or (row.xpLevel and (state.levelProgressUnknown or row.xpLevel~=state.level)) then
        state.unknownXP,state.levelProgressUnknown=state.unknownXP+1,true
        return
    end
    state.gainedXP=state.gainedXP+row.xp
    if state.levelProgressUnknown then return end
    if not schema.Number(state.xp,0,2147483647) or not schema.Number(state.xpMax,1,2147483647)
        or not schema.Integer(state.level,1,1000) then state.levelProgressUnknown=true; return end
    state.xp=state.xp+row.xp
    for _=1,256 do
        if state.xp<state.xpMax then return end
        state.xp,state.level=state.xp-state.xpMax,state.level+1
        local threshold=state.xpThresholds and state.xpThresholds[state.level]
        if not schema.Number(threshold,1,2147483647) then state.xpMax=nil; state.levelProgressUnknown=true; return end
        state.xpMax=threshold
    end
    state.levelProgressUnknown=true
end

local function pickup(state,row)
    local id=row.questID
    state.active[id],state.failed[id],state.objectivesComplete[id]=true,false,false
    state.objectives[id]=nil
    if row.requiredObjectives and #row.requiredObjectives>0 then
        local counters={}
        for _,objective in ipairs(row.requiredObjectives) do counters[objective.key]=objective.remaining end
        state.objectives[id],state.objectivesComplete[id]=counters,complete(counters)
    end
    state.logCount=state.logCount+1
    return true
end

local function progress(state,row)
    local id,key=row.questID,row.sharedKey or row.id
    local counters=state.objectives[id]
    local remaining=counters and counters[key]
    if remaining==nil then
        if row.completeQuest and not row.sharedKey and (not counters or next(counters)==nil) then state.objectivesComplete[id]=true; return true end
        return nil,"objective counters unknown"
    end
    if not schema.Number(remaining,1,2147483647) then return nil,"objective already complete or invalid" end
    counters[key]=math.max(0,remaining-(row.progress or 1))
    if row.sharedKey then
        for otherID,other in pairs(state.objectives) do
            if otherID~=id and state.active[otherID]==true and state.failed[otherID]==false and schema.PlainTable(other)
                and schema.Number(other[key],0,2147483647) then
                other[key]=math.max(0,other[key]-(row.progress or 1))
                state.objectivesComplete[otherID]=complete(other)
            end
        end
    end
    state.objectivesComplete[id]=complete(counters)
    return true
end

local function turnin(state,row)
    if not schema.Integer(state.logCount,1,256) then return nil,"unknown active log count" end
    for _,item in ipairs(row.consumes or {}) do
        local count=state.inventory[item.itemID]
        if not schema.Integer(count,item.count,2147483647) then return nil,"turn-in items unavailable or unknown" end
    end
    for _,item in ipairs(row.consumes or {}) do state.inventory[item.itemID]=state.inventory[item.itemID]-item.count end
    state.active[row.questID],state.turnedIn[row.questID]=false,true
    state.objectives[row.questID],state.logCount=nil,state.logCount-1
    if state.repeatReady then state.repeatReady[row.questID]=false end
    award(state,row)
    return true
end

local function apply(row,raw,leg,book,policy)
    local state,reason=initial(raw)
    if not state then return nil,reason end
    row,reason=actions.Validate(row,state.identity)
    if not row then return nil,reason end
    local ok
    ok,reason=preflight(row,state,policy,book)
    if not ok then return nil,reason end
    ok,reason=totals(row,state,leg,policy)
    if not ok then return nil,reason end
    if row.kind=="pickup" then ok,reason=pickup(state,row)
    elseif row.kind=="objective" then ok,reason=progress(state,row)
    elseif row.kind=="turnin" then ok,reason=turnin(state,row)
    else
        state.travel.flights,state.flags=state.travel.flights or {},state.flags or {}
        local target=row.unlock.kind=="flight" and state.travel.flights or state.flags
        target[row.unlock.key],ok=true,true
    end
    if not ok then return nil,reason end
    if row.kind=="objective" then state.objectiveWork=(state.objectiveWork or 0)+1 end
    state.node,state.completedActions[row.id]=row.node,true
    if row.kind=="turnin" then state.pinsDone[row.questID]=true end
    return state
end

function actions.Apply(...)
    local ok,state,reason=pcall(apply,...)
    if ok then return state,reason end
    return nil,"invalid simulation input"
end
