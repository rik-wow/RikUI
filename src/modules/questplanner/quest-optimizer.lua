-- Bounded deterministic lookahead. Costs and policy weights are models, not world facts.
local planner = RikUI.QuestPlanner
local schema, optimizer = planner.Schema, {}
planner.Optimizer = optimizer
local MAX_TRANSITIONS, MAX_TRAVEL_WORK = 5000, 50000

local function policy(raw)
    local p = schema.Copy(raw or {})
    if not p then return nil, "invalid planner policy" end
    local defaults = {depth=6,width=24,maxTransitions=MAX_TRANSITIONS,maxTravelWork=MAX_TRAVEL_WORK,
        maxSeconds=1800,maxRisk=.5,maxUncertainty=.5,classValue=60,unlockValue=60,switchThreshold=.15}
    for key, value in pairs(defaults) do if p[key] == nil then p[key] = value end end
    for key, maximum in pairs({depth=8,width=24,maxTransitions=MAX_TRANSITIONS,maxTravelWork=MAX_TRAVEL_WORK}) do
        if not schema.Integer(p[key],1,maximum) then return nil, "invalid planner budget" end
    end
    for _, key in ipairs({"maxSeconds","maxRisk","maxUncertainty","classValue","unlockValue","switchThreshold"}) do
        if not schema.Number(p[key],0,86400) then return nil, "invalid planner weight" end
    end
    for _, key in ipairs({"pins","avoids","skips"}) do
        p[key] = p[key] or {}
        if not schema.PlainTable(p[key]) then return nil, "invalid planner constraints" end
        for id, value in pairs(p[key]) do if not schema.ID(id) or type(value)~="boolean" then return nil,"invalid constraint" end end
    end
    return p
end

local function initialState(raw)
    local state, reason = schema.CopyLimited(raw,4096,65536,12)
    if not state or not schema.Identity(state.identity) or not schema.Text(state.node)
        or state.fresh ~= true or state.origin == "imported-untrusted" then return nil, reason or "unavailable current state" end
    state.elapsed, state.gainedXP, state.unknownXP = 0, 0, 0
    state.risk, state.uncertainty, state.bonus = 0, 0, 0
    state.completedActions, state.pinsDone, state.objectiveWork = {}, {}, 0
    for _, key in ipairs({"active","failed","objectivesComplete","turnedIn","objectives","inventory"}) do
        state[key] = state[key] or {}
        if not schema.PlainTable(state[key]) then return nil, "invalid planner state" end
    end
    if not schema.PlainTable(state.travel) then return nil, "travel state unavailable" end
    return state
end

local function pinCount(state, p)
    local count = 0
    for id, pinned in pairs(p.pins) do if pinned and state.pinsDone[id] == true then count = count + 1 end end
    return count
end

function optimizer.Score(state)
    return ((state.gainedXP or 0)+(state.bonus or 0))/math.max(1,state.elapsed or 0)
        - (state.risk or 0)*.1 - (state.uncertainty or 0)*.05
end

local function rank(node, p)
    node.pins, node.pinProgress = pinCount(node.state,p), 0
    for _, action in ipairs(node.sequence) do if p.pins[action.questID] then node.pinProgress=node.pinProgress+1 end end
    node.score = optimizer.Score(node.state)
    node.rewardTier = node.state.gainedXP+node.state.bonus>0 and 1 or 0
    node.finished = 0
    for _, done in pairs(node.state.pinsDone) do if done then node.finished = node.finished + 1 end end
    return node
end

local function better(a,b)
    if not b then return true end
    if a.pins ~= b.pins then return a.pins > b.pins end
    if a.pinProgress ~= b.pinProgress then return a.pinProgress > b.pinProgress end
    -- With no known reward/value, finish feasible work instead of stopping at a zero-value pickup.
    if a.rewardTier~=b.rewardTier then return a.rewardTier>b.rewardTier end
    if a.rewardTier==0 then
        if a.finished~=b.finished then return a.finished>b.finished end
        if a.state.objectiveWork~=b.state.objectiveWork then return a.state.objectiveWork>b.state.objectiveWork end
    end
    if math.abs(a.score-b.score)>0.000000001 then return a.score>b.score end
    if a.state.elapsed~=b.state.elapsed then return a.state.elapsed<b.state.elapsed end
    return a.key<b.key
end

local function keep(beam,node,width)
    local at=#beam+1
    for index,old in ipairs(beam) do if better(node,old) then at=index; break end end
    if at>width then return end
    table.insert(beam,at,node)
    if #beam>width then table.remove(beam) end
end

local function omitted(job,reason)
    job.omitted[reason]=(job.omitted[reason] or 0)+1
end

local function allowed(job,action,state)
    if state.completedActions[action.id] or job.policy.skips[action.questID] or job.policy.avoids[action.zoneID] then return false end
    if action.category=="dungeon" and job.policy.dungeons~=true then return false end
    if action.source.authority~="verified" then omitted(job,"unverified action"); return false end
    if action.kind=="unlock" then return planner.Eligibility.Condition(action.requirement,state)=="true" end
    local result=planner.Eligibility.Evaluate(action,state,job.book)
    if result.status~="eligible" then omitted(job,result.status.." eligibility"); return false end
    return true
end

local function leg(job,node,action)
    if node.state.node==action.node then return {status="known",seconds=0,risk=0,uncertainty=0,path={},metrics={work=0}} end
    if not job.graph then omitted(job,"missing travel graph"); return nil end
    local remaining=job.policy.maxTravelWork-job.metrics.travelWork
    if remaining<1 then job.limited=true; return nil end
    local search,reason=job.graph:Begin(node.state.node,action.node,node.state.travel,{
        maxSeconds=math.max(0,job.policy.maxSeconds-node.state.elapsed),
        maxRisk=math.max(0,job.policy.maxRisk-node.state.risk), maxUncertainty=math.max(0,job.policy.maxUncertainty-node.state.uncertainty),
        avoids=job.policy.avoids,maxWork=math.min(8192,remaining)})
    if not search then omitted(job,reason or "unknown travel"); return nil end
    local result,charged= nil,0
    repeat
        result=search:Step(32)
        charged=charged+32
        coroutine.yield(32)
    until result
    local actual=result.metrics and result.metrics.work or charged
    job.metrics.travelWork=job.metrics.travelWork+actual
    if result.status=="budget-exhausted" then job.limited=true end
    if result.seconds==nil then omitted(job,result.status); return nil end
    return result
end

local function transition(job,node,action)
    local path=leg(job,node,action)
    if not path then return nil end
    local state,reason=planner.Actions.Apply(action,node.state,path,job.book,job.policy)
    if not state then omitted(job,reason or "infeasible action"); return nil end
    if action.kind=="turnin" and action.category=="class" then state.bonus=(state.bonus or 0)+job.policy.classValue end
    if action.kind=="unlock" or (action.kind=="turnin" and action.category=="travel") then
        state.bonus=(state.bonus or 0)+job.policy.unlockValue
    end
    local sequence={}
    for index,value in ipairs(node.sequence) do sequence[index]=value end
    sequence[#sequence+1]={id=action.id,questID=action.questID,kind=action.kind,node=action.node,
        zoneID=action.zoneID,title=action.title,travel=path}
    return rank({state=state,sequence=sequence,key=node.key.."/"..action.id},job.policy)
end

local function search(job)
    local beam={rank({state=job.initial,sequence={},key=""},job.policy)}
    for _=1,job.policy.depth do
        local nextBeam={}
        for _,node in ipairs(beam) do
            for _,action in ipairs(job.rows) do
                if job.metrics.transitions>=job.policy.maxTransitions or job.metrics.travelWork>=job.policy.maxTravelWork then
                    job.limited=true; return
                end
                job.metrics.considered=job.metrics.considered+1
                if allowed(job,action,node.state) then
                    job.metrics.transitions=job.metrics.transitions+1
                    local candidate=transition(job,node,action)
                    if candidate then
                        if better(candidate,job.best) then job.best=candidate end
                        if candidate.sequence[1].id==job.policy.previousID and better(candidate,job.old) then job.old=candidate end
                        keep(nextBeam,candidate,job.policy.width)
                    end
                end
                coroutine.yield(1)
            end
        end
        if #nextBeam==0 then return end
        beam=nextBeam
    end
end

local function deferred(node,p)
    local ids={}
    for id,pinned in pairs(p.pins) do if pinned and (not node or node.state.pinsDone[id]~=true) then ids[#ids+1]=id end end
    table.sort(ids)
    return ids
end

local function result(job)
    local best,retained=job.best,false
    if job.old and best and job.old.pins==best.pins and job.old.pinProgress==best.pinProgress and job.old.finished==best.finished
        and job.old.rewardTier==best.rewardTier and job.old.state.objectiveWork==best.state.objectiveWork
        and best.score-job.old.score<=math.max(math.abs(best.score),.01)*job.policy.switchThreshold then
        best,retained=job.old,job.old.sequence[1].id~=best.sequence[1].id
    end
    local state=best and best.state or job.initial
    local pending=deferred(best,job.policy)
    return {status=not best and "insufficient-data" or ((state.unknownXP>0 or #pending>0) and "uncertain" or "ready"),
        actions=best and schema.Clone(best.sequence) or {},state=schema.Clone(state),seconds=state.elapsed,
        gainedXP=state.gainedXP,unknownXP=state.unknownXP,score=best and best.score or 0,
        limited=job.limited or false,globalOptimal=false,retained=retained,deferredPins=pending,
        metrics=schema.Clone(job.metrics),omitted=schema.Clone(job.omitted),generation=job.initial.generation,
        graphRevision=job.graph and job.graph:Revision() or "missing",
        reason=retained and "current action remains competitive" or job.policy.reason or "calculated from current state"}
end

local function conflict(rows,p)
    local byQuest={}
    for _,action in ipairs(rows) do
        byQuest[action.questID]=byQuest[action.questID] or {avoided=true}
        if not p.avoids[action.zoneID] then byQuest[action.questID].avoided=false end
    end
    for id,pinned in pairs(p.pins) do
        if pinned and (p.skips[id] or (byQuest[id] and byQuest[id].avoided)) then return true end
    end
    return false
end

function optimizer.Begin(actions,rawState,book,graph,rawPolicy)
    local p,reason=policy(rawPolicy)
    if not p then return nil,reason end
    local initial,problem=initialState(rawState)
    if not initial then return nil,problem end
    local rows=actions:List()
    if not schema.List(rows,40) then return nil,"candidate limit" end
    table.sort(rows,function(a,b) return a.id<b.id end)
    local job={initial=initial,rows=rows,book=book,graph=graph,policy=p,omitted={},
        metrics={transitions=0,travelWork=0,considered=0,slices=0}}
    if conflict(rows,p) then job.output={status="constraint-conflict",actions={},deferredPins=deferred(nil,p),reason="pin conflicts with skip or avoided area"} end
    local worker=coroutine.create(function() search(job) end)
    return {
        Cancel=function() job.cancelled=true end,
        Step=function(_,budget)
            if job.cancelled then return {status="cancelled",actions={}} end
            if job.output then return schema.Clone(job.output) end
            if not schema.Integer(budget or 128,1,512) then return nil,"invalid planner slice" end
            local used=0; job.metrics.slices=job.metrics.slices+1
            repeat
                local ok,work=coroutine.resume(worker)
                if not ok then job.output={status="invalid",actions={},reason=tostring(work)}; return schema.Clone(job.output) end
                used=used+(work or 1)
                if coroutine.status(worker)=="dead" then job.output=result(job); return schema.Clone(job.output) end
            until used >= (budget or 128)
        end,
    }
end

function optimizer.Plan(...)
    local job,reason=optimizer.Begin(...)
    if not job then return {status="invalid",reason=reason,actions={}} end
    while true do local result=job:Step(512); if result then return result end end
end
