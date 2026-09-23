-- Deterministic anytime search over ordinary corpus actions, with recursive continuations.
local planner=RikUI.QuestPlanner
local schema,search=planner.Schema,{}
planner.PlanSearch=search
search.REVISION="adaptive-8"
local MAX_WORK,MAX_ACTIONS,MAX_DEPTH,WIDTH=48000,128,64,16
local function copyList(values)
    local result={};for _,value in ipairs(values or {}) do result[#result+1]=value end;return result
end
local function features(node,initial,policy)
    local state=node.state
    local scale=initial.xpMax and math.max(100,initial.xpMax) or 1000
    local progress=(state.xpGained or 0)/scale
    local minutes=math.max(1,(state.elapsed or 0)/60) -- One-minute evaluation floor prevents instant-reward rate spikes.
    local efficiency=progress/minutes
    local variety,seen=0,{}
    local previous=initial.recent and initial.recent[#initial.recent]
    local chain,goals,pressure,challenge,work,repetition,breadcrumbs=0,0,0,0,0,0,0
    local pressureExposures=0
    local priorID
    for index,action in ipairs(node.actions) do
        local activity=action.activity
        if activity and activity==previous then repetition=repetition+1 end
        if activity and not seen[activity] then
            seen[activity]=true
            if activity~=previous then variety=variety+1 end
        end
        if action.kind=="turnin" then
            if schema.ID(action.breadcrumbFor) then breadcrumbs=breadcrumbs+1 end
            if policy.questGoals[action.questID] or policy.zoneGoals[action.zoneID] then goals=goals+1 end
            if priorID and action.chainPredecessors and action.chainPredecessors[priorID] then chain=chain+1 end
            priorID=action.questID
        end
        if action.kind=="objective" then work=work+1 end
        local cost=node.costs[index]
        if action.kind~="complete" and not action.optionalExploration then
            pressure=pressure+(cost.pressure or 0);pressureExposures=pressureExposures+1
        end
        if cost.difficulty and cost.capabilityKnown then
            local desired=policy.difficulty=="hard" and 2 or policy.difficulty=="easy" and -2 or 0
            challenge=challenge+math.max(0,1-math.abs(cost.difficulty-desired)/5)
        end
    end
    local discoveries=state.discoveries or 0
    local rewardValue=0
    if planner.PlanRewards then for _,action in ipairs(node.actions) do rewardValue=rewardValue+planner.PlanRewards.Value(action,policy) end end
    return {efficiency=efficiency,progress=progress,minutes=minutes,variety=math.min(3,variety),chain=math.min(6,chain),
        breadcrumbs=math.min(3,breadcrumbs),discoveries=math.min(3,discoveries),goals=goals,pressure=pressure/math.max(1,pressureExposures),
        challenge=challenge/math.max(1,work),finished=state.finished or 0,work=work,
        conditional=state.conditional==true,unknownXP=state.unknownXP or 0,repetition=math.min(6,repetition),
        optionalInterest=math.min(3,state.optionalInterest or 0),rewardValue=math.max(-8,math.min(8,rewardValue)),pinned=node.actions[1] and policy.pins[node.actions[1].questID] or false}
end
function search.Score(node,initial,policy)
    local f=features(node,initial,policy)
    -- One bonus point is 2% of a level. Travel and work time dilute every
    -- benefit equally; a distant breadcrumb cannot keep a fixed score bonus.
    local scale=initial.xpMax and math.max(100,initial.xpMax) or 1000
    local points=f.finished*.5+policy.variety*f.variety*1.5+policy.continuity*(f.chain*3+f.breadcrumbs*6)
        +policy.discovery*(f.discoveries*3+f.optionalInterest*.75)+f.goals*3+f.rewardValue*6
        +f.challenge*(policy.difficulty=="hard" and 3 or 1)
    if f.finished==0 and f.progress==0 then points=points+math.min(2,f.work)*.05 end
    local value=math.max(0,(node.state.xpGained or 0)+points*.02*scale)
    local pressure=1+policy.pressure*f.pressure*.3
    local repetition=1+f.repetition*(policy.grind=="low" and .04 or policy.grind=="medium" and .01 or 0)
    local utility=value/scale*60/f.minutes/pressure/repetition
    return utility+(f.pinned and 1000000 or 0),f
end
local function completed(action,state)
    if not action then return false end
    local id=action.questID
    return (state.applied or {})[action.id]==true or (id>0 and state.completed[id]==true)
        or action.kind=="pickup" and state.active[id]==true
        or action.kind=="objective" and (state.objectivesComplete[id]==true
            or ((state.progress or {})[id] or {})[action.objectiveKey]==0)
        or action.kind=="complete" and state.objectivesComplete[id]==true
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
    local byID={};for _,action in ipairs(graph.actions) do byID[action.id]=action end
    local previous=byID[environment.previousID]
    local previousStatus
    if environment.previousID then
        if completed(previous or environment.previousAction,initial) then previousStatus="completed"
        elseif previous and planner.PlanTransitions.Check(previous,initial,policy)==true then previousStatus="feasible"
        else previousStatus="invalid" end
    end
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
            if first~=environment.previousID and (not worst or better(bestByFirst[worst],value)) then worst=first end
        end
        if count>96 and worst then bestByFirst[worst]=nil end
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
    -- Hub bundles preserve low-immediate-value pickups before their shared excursion.
    -- Every step still passes the same resource, branch, travel and time checks.
    local function sameHub(a,b)
        return a and b and a.mapID==b.mapID and a.x==b.x and a.y==b.y and a.floor==b.floor and a.phase==b.phase
    end
    local function cluster(node,first)
        local hub=first.destination
        if not hub then return end
        node=extend(node,first);if not node then return end
        local selected,ids={[first.questID]=true},{first.questID}
        for _,action in ipairs(graph.actions) do
            if #ids>=8 then break end
            if action.kind=="pickup" and not selected[action.questID] and sameHub(hub,action.destination) then
                local candidate=extend(node,action)
                if candidate then node=candidate;selected[action.questID]=true;ids[#ids+1]=action.questID end
            end
        end
        if #ids<2 then return end
        for _=1,64 do
            local best
            for _,id in ipairs(ids) do
                for _,action in ipairs(graph.byQuest[id] or {}) do
                    if action.kind=="objective" then
                        local candidate=extend(node,action)
                        if candidate and (not best or candidate.state.elapsed<best.state.elapsed
                            or candidate.state.elapsed==best.state.elapsed and candidate.key<best.key) then best=candidate end
                    end
                end
            end
            if not best then break end
            node=best
        end
        for _,id in ipairs(ids) do
            local complete=chooseAction(node,graph.byQuest[id],function(a) return a.kind=="complete" end)
            if complete then node=complete end
        end
        for _=1,#ids do
            local best
            for _,id in ipairs(ids) do
                local candidate=chooseAction(node,graph.byQuest[id],function(a) return a.kind=="turnin" end)
                if candidate and (not best or candidate.state.elapsed<best.state.elapsed
                    or candidate.state.elapsed==best.state.elapsed and candidate.key<best.key) then best=candidate end
            end
            if not best then break end
            node=best;retain(node)
        end
        return node
    end
    local co=coroutine.create(function()
        -- Primitive first actions yield a useful incumbent before deeper continuations.
        local beam={}
        -- Reprice the prior rollout before ordinary expansion. Protect every feasible
        -- prefix so cancellation or the 96-first-step cap cannot erase its comparison.
        local seeded,seen=root,{}
        local function seed(action)
            if not action or seen[action.id] then return end
            seen[action.id]=true
            local node=extend(seeded,action)
            if node then seeded=node;retain(node) end
        end
        if previousStatus=="feasible" then seed(previous) end
        for i,id in ipairs(environment.incumbent or {}) do
            if i>MAX_ACTIONS then break end
            seed(byID[id])
        end
        metrics.seeded=#seeded.actions
        if #seeded.actions>0 then beam[#beam+1]=seeded end
        for _,action in ipairs(graph.actions) do
            local node=extend(root,action)
            if node then retain(node);beam[#beam+1]=node end
        end
        local clustered=0
        for _,action in ipairs(graph.actions) do
            if action.kind=="pickup" and sameHub(initial.position,action.destination) and clustered<8 then
                local node=cluster(root,action);clustered=clustered+1
                if node then retain(node);beam[#beam+1]=node end
            end
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
            reason=REASONS[policy.flavor],baselineEfficiency=baseline,detourAllowance=policy.detour,previousStatus=previousStatus}
        local commitment=environment.previousID and bestByFirst[environment.previousID]
        if commitment then
            output.commitment={actions=commitment.actions,costs=commitment.costs,score=commitment.score,features=commitment.features,
                seconds=commitment.state.elapsed,upperSeconds=commitment.state.upperElapsed,xp=commitment.state.xpGained,
                unknownXP=commitment.state.unknownXP,unknownCombatXP=commitment.state.unknownCombatXP,conditional=commitment.state.conditional,assumptions=commitment.state.assumptions}
        end
        if best then
            output.actions=best.actions;output.costs=best.costs;output.score=best.score;output.features=best.features
            output.seconds=best.state.elapsed;output.upperSeconds=best.state.upperElapsed
            output.xp=best.state.xpGained;output.unknownXP=best.state.unknownXP;output.unknownCombatXP=best.state.unknownCombatXP;output.conditional=best.state.conditional
            output.assumptions=best.state.assumptions
            if policy.rewardFocus and policy.rewardFocus~="xp" then output.reason=output.reason.."; prefer "..policy.rewardFocus.." rewards within your detour allowance" end
            if best.features.breadcrumbs>0 then output.reason=output.reason.."; preserve a missable quest step before its follow-up" end
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
