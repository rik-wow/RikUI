-- Deterministic anytime search over ordinary corpus actions, with recursive continuations.
local planner=RikUI.QuestPlanner
local schema,search=planner.Schema,{}
planner.PlanSearch=search
local MAX_WORK,MAX_ACTIONS,MAX_DEPTH,WIDTH=48000,128,64,16
local function copyList(values)
    local result={};for _,value in ipairs(values or {}) do result[#result+1]=value end;return result
end
local function features(node,initial,policy)
    local state=node.state
    local scale=initial.xpMax and math.max(100,initial.xpMax) or 1000
    local progress=(state.xpGained or 0)/scale
    local minutes=math.max(1,(state.elapsed or 0)/60)
    local efficiency=progress/minutes
    local variety,seen=0,{}
    local previous=initial.recent and initial.recent[#initial.recent]
    local chain,goals,pressure,challenge,work,repetition=0,0,0,0,0,0
    local priorID
    for index,action in ipairs(node.actions) do
        local activity=action.activity
        if activity and activity==previous then repetition=repetition+1 end
        if activity and not seen[activity] then
            seen[activity]=true
            if activity~=previous then variety=variety+1 end
        end
        if action.kind=="turnin" then
            if policy.questGoals[action.questID] or policy.zoneGoals[action.zoneID] then goals=goals+1 end
            if priorID and action.chainPredecessors and action.chainPredecessors[priorID] then chain=chain+1 end
            priorID=action.questID
        end
        if action.kind=="objective" then work=work+1 end
        local cost=node.costs[index]
        pressure=pressure+(cost.pressure or 0)
        if cost.difficulty and cost.capabilityKnown then
            local desired=policy.difficulty=="hard" and 2 or policy.difficulty=="easy" and -2 or 0
            challenge=challenge+math.max(0,1-math.abs(cost.difficulty-desired)/5)
        end
    end
    local discoveries=state.discoveries or 0
    return {efficiency=efficiency,progress=progress,minutes=minutes,variety=math.min(3,variety),chain=math.min(6,chain),
        discoveries=math.min(3,discoveries),goals=goals,pressure=pressure/math.max(1,#node.actions),
        challenge=challenge/math.max(1,work),finished=state.finished or 0,work=work,
        conditional=state.conditional==true,unknownXP=state.unknownXP or 0,repetition=math.min(6,repetition),
        pinned=node.actions[1] and policy.pins[node.actions[1].questID] or false}
end
function search.Score(node,initial,policy)
    local f=features(node,initial,policy)
    -- Fixed scales, never normalized to the current candidate set.
    local utility=f.efficiency*100+f.progress*.5+f.finished*.5
        +policy.variety*f.variety*1.5+policy.continuity*f.chain*3
        +policy.discovery*f.discoveries*3+f.goals*3
        -policy.pressure*f.pressure*3+f.challenge*(policy.difficulty=="hard" and 3 or 1)
        -f.repetition*(policy.grind=="low" and .4 or policy.grind=="medium" and .1 or 0)+(f.pinned and 10 or 0)
    if f.finished==0 and f.progress==0 then utility=utility+math.min(2,f.work)*.05 end
    return utility,f
end
local REASONS={
    Balanced="Reliable progress with local continuity and variety",
    Efficient="Best supported XP efficiency within the same constraints",
    Story="Useful quest-chain continuity within your detour allowance",
    Explorer="Optional discovery and variety within your exploration allowance",
    Relaxed="Predictable progress with less waiting and pressure",
    Challenge="Preferred difficulty within your available capabilities",
}
function search.Begin(graph,initial,policy,environment)
    if not graph or graph.status~="ready" or not initial or not initial.fresh then return nil,"Ready graph and live state required" end
    environment=environment or {}
    local cancelled,done,limited=false,false,false
    local metrics={work=0,transitions=0,macros=0,depth=0,retained=0}
    local exclusions,excludedCount={},0
    local bestByFirst={}
    local baseline=0
    local root={state=planner.PlanTransitions.Fork(initial),actions={},costs={}}
    local function pause()
        metrics.work=metrics.work+1
        coroutine.yield()
        if cancelled then error("cancelled") end
        if metrics.work>=MAX_WORK then limited=true;error("budget") end
    end
    local function exclude(action,reason)
        if reason and excludedCount<128 and not exclusions[action.id] then exclusions[action.id]=reason;excludedCount=excludedCount+1 end
    end
    local function extend(node,action)
        pause()
        if #node.actions>=MAX_ACTIONS then limited=true;return end
        local feasible,reason=planner.PlanTransitions.Check(action,node.state,policy)
        if feasible~=true then exclude(action,reason);return end
        local cost,problem=planner.PlanCosts.Estimate(action,node.state,policy,environment)
        if not cost then exclude(action,problem);return end
        if policy.strictSession and (node.state.upperElapsed or 0)+cost.upper>policy.maxSeconds then
            exclude(action,"Cannot finish within the strict session budget");return
        end
        if action.kind=="explore" and (node.state.explorationSeconds or 0)+cost.upper>policy.explorationMinutes*60 then
            exclude(action,"Exploration allowance exhausted");return
        end
        local state=planner.PlanTransitions.Apply(action,node.state,policy,cost)
        if not state then return end
        local nextNode={state=state,actions=copyList(node.actions),costs=copyList(node.costs)}
        nextNode.actions[#nextNode.actions+1]=action;nextNode.costs[#nextNode.costs+1]=cost
        nextNode.score,nextNode.features=search.Score(nextNode,initial,policy)
        nextNode.first=nextNode.actions[1].id
        nextNode.key=(node.key or "").."|"..action.id
        metrics.transitions=metrics.transitions+1
        return nextNode
    end
    local function better(a,b)
        if not b then return true end
        if a.score~=b.score then return a.score>b.score end
        if a.features.progress~=b.features.progress then return a.features.progress>b.features.progress end
        if a.state.elapsed~=b.state.elapsed then return a.state.elapsed<b.state.elapsed end
        return a.key<b.key
    end
    local function retain(node)
        if not node or #node.actions==0 then return end
        -- Advisory sessions prefer complete, timely milestones; overruns stay visible.
        node.overrun=node.state.upperElapsed>policy.maxSeconds
        local f=node.features
        if f.finished>0 and node.state.elapsed<=policy.maxSeconds then baseline=math.max(baseline,f.efficiency) end
        local prior=bestByFirst[node.first]
        local timely=node.state.elapsed<=policy.maxSeconds
        if not prior or timely and prior.state.elapsed>policy.maxSeconds
            or (timely==(prior.state.elapsed<=policy.maxSeconds) and better(node,prior)) then bestByFirst[node.first]=node end
        local count,worst=0,nil
        for first,value in pairs(bestByFirst) do
            count=count+1
            if not worst or better(bestByFirst[worst],value) then worst=first end
        end
        if count>96 then bestByFirst[worst]=nil end
    end
    local finishQuest,ensure
    local function chooseAction(node,actions,predicate)
        local best
        for _,action in ipairs(actions or {}) do
            if predicate(action) then
                local candidate=extend(node,action)
                if candidate and (not best or candidate.state.elapsed<best.state.elapsed
                    or candidate.state.elapsed==best.state.elapsed and candidate.key<best.key) then best=candidate end
            end
        end
        return best
    end
    ensure=function(rule,node,visiting,depth)
        if planner.PlanTransitions.Condition(rule,node.state)==true then return node end
        if not rule or depth>24 then return end
        if rule.op=="completed" then return finishQuest(rule.questID,node,visiting,depth+1) end
        if rule.op=="active" then
            return chooseAction(node,graph.byQuest[rule.questID],function(a) return a.kind=="pickup" end)
        end
        if rule.op=="all" then
            for _,child in ipairs(rule.args or {}) do node=ensure(child,node,visiting,depth);if not node then return end end
            return node
        end
        if rule.op=="any" then
            local best
            for _,child in ipairs(rule.args or {}) do
                local candidate=ensure(child,node,visiting,depth)
                if candidate and (not best or candidate.state.elapsed<best.state.elapsed) then best=candidate end
            end
            return best
        end
    end
    finishQuest=function(id,node,visiting,depth)
        if node.state.completed[id]==true then return node end
        if depth>24 or visiting[id] then return end
        visiting[id]=true
        local function finish(value) visiting[id]=nil;return value end
        local actions=graph.byQuest[id]
        if not actions then return finish(nil) end
        if not node.state.active[id] then
            local best
            for _,action in ipairs(actions) do
                if action.kind=="pickup" then
                    local prepared=ensure(action.prerequisite,node,visiting,depth)
                    local candidate=prepared and extend(prepared,action)
                    if candidate and (not best or candidate.state.elapsed<best.state.elapsed) then best=candidate end
                end
            end
            node=best;if not node then return finish(nil) end
        end
        for _=1,32 do
            local progress=node.state.progress[id] or {}
            local conditional=node.state.conditionalObjectives[id] or {}
            local keys={}
            for objective,value in pairs(progress) do if value~=0 and not conditional[objective] then keys[#keys+1]=objective end end
            table.sort(keys)
            if #keys==0 or node.state.objectivesComplete[id] then break end
            local nextNode=chooseAction(node,actions,function(action) return action.kind=="objective" and action.objectiveKey==keys[1] end)
            if not nextNode then return finish(nil) end
            node=nextNode
        end
        local complete=chooseAction(node,actions,function(action) return action.kind=="complete" end)
        if complete then node=complete end
        return finish(chooseAction(node,actions,function(action) return action.kind=="turnin" end))
    end
    local co=coroutine.create(function()
        -- Primitive first actions yield a useful incumbent before deeper continuations.
        local beam={}
        for _,action in ipairs(graph.actions) do
            local node=extend(root,action)
            if node then retain(node);beam[#beam+1]=node end
        end
        local ids={};for id in pairs(graph.byQuest) do ids[#ids+1]=id end;table.sort(ids)
        for _,id in ipairs(ids) do
            local node=finishQuest(id,root,{},0)
            metrics.macros=metrics.macros+1
            if node and #node.actions>0 then retain(node);beam[#beam+1]=node end
        end
        local depthLimit=math.min(MAX_DEPTH,math.max(12,#ids*4))
        for depth=1,depthLimit do
            metrics.depth=depth
            table.sort(beam,better)
            local narrowed,seenFirst={},{}
            -- Half the beam protects distinct first decisions; the rest competes on utility.
            for _,node in ipairs(beam) do
                if not seenFirst[node.first] and #narrowed<WIDTH/2 then
                    narrowed[#narrowed+1]=node;seenFirst[node.first]=true
                end
            end
            local seen={}
            for _,node in ipairs(narrowed) do seen[node.key]=true end
            for _,node in ipairs(beam) do
                if not seen[node.key] and #narrowed<WIDTH then narrowed[#narrowed+1]=node;seen[node.key]=true end
            end
            metrics.retained=#narrowed
            local nextBeam={}
            for _,node in ipairs(narrowed) do
                if node.state.elapsed<=policy.maxSeconds then
                    for _,action in ipairs(graph.actions) do
                        local child=extend(node,action)
                        if child then retain(child);nextBeam[#nextBeam+1]=child end
                        if #nextBeam>=256 then table.sort(nextBeam,better);for index=#nextBeam,WIDTH*4+1,-1 do nextBeam[index]=nil end end
                    end
                    -- Continue a promising branch through whole future quests beyond primitive depth.
                    if depth<=3 then
                        for _,id in ipairs(ids) do
                            if not node.state.completed[id] then
                                local child=finishQuest(id,node,{},0)
                                if child and #child.actions>#node.actions then retain(child);nextBeam[#nextBeam+1]=child end
                                if #nextBeam>=256 then table.sort(nextBeam,better);for index=#nextBeam,WIDTH*4+1,-1 do nextBeam[index]=nil end end
                            end
                        end
                    end
                end
            end
            if #nextBeam==0 then break end
            beam=nextBeam
        end
    end)
    local function result(status)
        local rows={}
        for _,node in pairs(bestByFirst) do rows[#rows+1]=node end
        table.sort(rows,better)
        local best,relaxed
        for _,node in ipairs(rows) do
            local within=node.features.pinned or node.features.efficiency>=baseline/(1+policy.detour) or baseline==0 or node.features.progress==0 and node.features.unknownXP>0
            if within and (node.state.elapsed<=policy.maxSeconds or not best) then
                if not best or (best.state.elapsed>policy.maxSeconds and node.state.elapsed<=policy.maxSeconds) or better(node,best) then best=node end
            end
            if not relaxed or better(node,relaxed) then relaxed=node end
        end
        best=best or relaxed
        local alternatives={}
        for _,node in ipairs(rows) do
            if node~=best and #alternatives<3 then alternatives[#alternatives+1]={action=node.actions[1],score=node.score,
                seconds=node.state.elapsed,xp=node.state.xpGained,conditional=node.state.conditional,overrun=node.overrun} end
        end
        local output={status=status,metrics=schema.Clone(metrics),limited=limited,revision=graph.revision,generation=initial.generation,
            alternatives=alternatives,excluded=schema.Clone(exclusions),coverage=graph.coverage,flavor=policy.flavor,
            reason=REASONS[policy.flavor],baselineEfficiency=baseline,detourAllowance=policy.detour}
        local commitment=environment.previousID and bestByFirst[environment.previousID]
        if commitment then
            output.commitment={actions=commitment.actions,costs=commitment.costs,score=commitment.score,features=commitment.features,
                seconds=commitment.state.elapsed,upperSeconds=commitment.state.upperElapsed,xp=commitment.state.xpGained,
                unknownXP=commitment.state.unknownXP,conditional=commitment.state.conditional,assumptions=commitment.state.assumptions}
        end
        if best then
            output.actions=best.actions;output.costs=best.costs;output.score=best.score;output.features=best.features
            output.seconds=best.state.elapsed;output.upperSeconds=best.state.upperElapsed
            output.xp=best.state.xpGained;output.unknownXP=best.state.unknownXP;output.conditional=best.state.conditional
            output.assumptions=best.state.assumptions
            output.efficiencyCost=baseline>0 and math.max(0,1-best.features.efficiency/baseline) or nil
            output.stoppingPoint=best.features.finished>0 and "Finish a quest segment" or "Complete the current objective"
        else output.actions={};output.reason="No supported feasible plan; live guidance remains available" end
        return output
    end
    return {Cancel=function() cancelled=true end,Peek=function() return result(done and "ready" or "refining") end,
        Step=function(_,budget)
            if cancelled then return {status="cancelled"} end
            if done then return result("ready") end
            for _=1,math.min(64,budget or 1) do
                local ok,reason=coroutine.resume(co)
                if not ok then
                    done=true
                    if tostring(reason):find("budget",1,true) then limited=true
                    elseif tostring(reason):find("cancelled",1,true) then return {status="cancelled"}
                    else return {status="error",reason=tostring(reason),metrics=metrics} end
                elseif coroutine.status(co)=="dead" then done=true end
                if done then return result("ready") end
            end
        end}
end
