-- Explicit actions and evidence-driven progression, separate from route arrival.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local steps={}
planner.Steps=steps
local KINDS={travel="arrival",interaction="interaction",objective="objective",item="item",turnin="turned-in",transport="transport"}
local function key(v) return schema.ID(v) or (schema.Text(v) and #v>0 and #v<=128) end
local function same(a,b)
    return schema.Identity(a) and schema.Identity(b) and a.product==b.product and a.build==b.build and a.locale==b.locale
end
local function location(v)
    return schema.PlainTable(v) and v.coordinateSystem=="normalized-map" and schema.ID(v.mapID)
        and schema.Integer(v.instanceID,0,2147483647) and schema.Number(v.x,0,1) and schema.Number(v.y,0,1)
        and (v.floor==nil or key(v.floor) or v.floor==0) and (v.anchorID==nil or key(v.anchorID))
end
local function condition(v)
    if not schema.PlainTable(v) then return false end
    local k=v.kind
    if k=="quest-active" or k=="quest-ready" or k=="turned-in" then return schema.ID(v.questID) end
    if k=="objective" then return schema.ID(v.questID) and key(v.objectiveID)
        and (v.count==nil or schema.Integer(v.count,1,1000000)) end
    if k=="item" then return schema.ID(v.itemID) and schema.Integer(v.count,1,1000000) end
    if k=="interaction" then return key(v.outcome) end
    if k=="arrival" or k=="transport" then return schema.Number(v.radius,0,100) end
    if k=="access" or k=="cooldown" then return key(v.key) end
    return false
end
local function validStep(step,identity)
    if not schema.PlainTable(step) or not key(step.id) or not KINDS[step.kind] then return false end
    if step.questID~=nil and not schema.ID(step.questID) then return false end
    if step.objectiveID~=nil and not key(step.objectiveID) then return false end
    if step.location~=nil and not location(step.location) then return false end
    if step.target~=nil and (not schema.PlainTable(step.target) or not key(step.target.kind)
        or (step.target.id~=nil and not key(step.target.id))) then return false end
    if step.source~=nil and (not schema.Source(step.source) or not same(step.source,identity)) then return false end
    if step.kind=="transport" and (not key(step.legID) or not key(step.fromAnchorID)) then return false end
    if step.accessAnchors~=nil then
        if not schema.List(step.accessAnchors,32) then return false end
        for _,anchor in ipairs(step.accessAnchors) do if not location(anchor) then return false end end
    end
    if step.prerequisites==nil then step.prerequisites={} end
    if not schema.List(step.prerequisites,32) or not schema.List(step.completion,32) or #step.completion==0 then return false end
    for _,v in ipairs(step.prerequisites) do if not condition(v) then return false end end
    for _,v in ipairs(step.completion) do
        if not condition(v) then return false end
        local expected=KINDS[step.kind]
        local matched=expected=="interaction" and v.kind=="objective" and v.questID==step.questID and v.objectiveID==step.objectiveID
        if v.kind~=expected and not matched then return false end
        if v.questID~=nil and v.questID~=step.questID then return false end
        if expected=="objective" and v.objectiveID~=step.objectiveID then return false end
    end
    return true
end
function steps.Validate(identity,definitions)
    local data,reason=schema.Copy({identity=identity,definitions=definitions})
    if not data or not schema.Identity(data.identity) or not schema.List(data.definitions,128) then return nil,reason or "invalid-step-sequence" end
    local seen={}
    for _,step in ipairs(data.definitions) do
        if not validStep(step,data.identity) or seen[step.id] then return nil,"invalid-step" end
        seen[step.id]=true
    end
    return data
end
local function get(t,id) return type(t)=="table" and t[id] or nil end
local function boolean(t,id)
    if type(t)=="table" and type(t[id])=="boolean" then return t[id] end
end
local function arrival(step,p,e)
    local target,observed=step.location,get(e.arrivals,step.id)
    if not target or type(observed)~="table" or target.floor==nil or target.anchorID==nil
        or observed.floor==nil or observed.anchorID==nil or observed.instanceID==nil or observed.mapID==nil then return nil end
    if target.mapID~=observed.mapID or target.instanceID~=observed.instanceID or target.floor~=observed.floor
        or target.anchorID~=observed.anchorID or observed.connected==false or observed.partial==true then return false end
    if observed.connected~=true or not schema.Number(observed.distance,0,1000000) then return nil end
    return observed.distance<=p.radius
end
local function evaluate(step,p,e)
    local k=p.kind
    if k=="quest-active" then return boolean(e.activeQuests,p.questID) end
    if k=="quest-ready" then return boolean(e.questReady,p.questID) end
    if k=="turned-in" then return boolean(e.turnedIn,p.questID) end
    if k=="access" then return boolean(e.access,p.key) end
    if k=="cooldown" then
        local v=get(e.cooldowns,p.key)
        if type(v)~="table" or not schema.Number(v.readyAt,0,2147483647) or not schema.Number(e.now,0,2147483647) then return end
        return e.now>=v.readyAt
    end
    if k=="item" then local count=get(e.items,p.itemID)
        if schema.Integer(count,0,1000000) then return count>=p.count end;return end
    if k=="objective" then
        local v=get(get(e.objectives,p.questID),p.objectiveID)
        if type(v)~="table" then return end
        if v.finished==true then return true end
        if p.count and schema.Integer(v.count,0,1000000) then return v.count>=p.count end
        if v.finished==false then return false end
        return nil
    end
    if k=="interaction" then
        local target,v=step.target,get(e.interactions,step.id)
        if not target or target.id==nil or type(v)~="table" or v.targetKind~=target.kind
            or v.targetID~=target.id or v.outcome==nil then return end
        return v.outcome==p.outcome
    end
    if k=="arrival" then return arrival(step,p,e) end
    local v=get(e.transports,step.id)
    if type(v)~="table" or v.legID~=step.legID or v.fromAnchorID~=step.fromAnchorID then return end
    if v.boarded==false or v.exited==false then return false end
    if v.boarded~=true or v.exited~=true then return end
    return arrival(step,p,e)
end
local function all(step,conditions,evidence)
    local unknown=false
    for _,p in ipairs(conditions) do
        local value=evaluate(step,p,evidence)
        if value==false then return false end
        if value==nil then unknown=true end
    end
    if not unknown then return true end
end
local function phase(step,e)
    if step.kind~="transport" then return end
    local v=get(e.transports,step.id)
    if type(v)~="table" or v.legID~=step.legID or v.fromAnchorID~=step.fromAnchorID then return "waiting" end
    if v.boarded==true then return v.exited==true and "exiting" or "riding" end
    return v.boarding==true and "boarding" or "waiting"
end
function steps.New(identity,definitions)
    local data,reason=steps.Validate(identity,definitions)
    if not data then return nil,reason end
    return {Evaluate=function(_,raw)
        local evidence=schema.Copy(raw)
        if not schema.PlainTable(evidence) or not same(data.identity,evidence.identity) or evidence.origin=="imported-untrusted" then
            return {state="unknown",reason="evidence-identity-or-origin"} end
        for _,step in ipairs(data.definitions) do
            if step.source and step.source.authority~="verified" then
                return {state="unknown",stepID=step.id,active=schema.Clone(step),reason="reference-step"} end
            local done=all(step,step.completion,evidence)
            if done~=true then
                local ready=all(step,step.prerequisites,evidence)
                local state,issue="active",nil
                if ready==false then state,issue="blocked","prerequisite-unsatisfied"
                elseif ready==nil then state,issue="unknown","prerequisite-unobserved"
                elseif done==nil then state,issue="unknown","completion-unobserved" end
                return {state=state,reason=issue,stepID=step.id,active=schema.Clone(step),phase=phase(step,evidence),
                    completion=done==false and "incomplete" or "unknown"}
            end
        end
        return {state="completed"}
    end}
end
