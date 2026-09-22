-- Feasibility and copy-on-write rollout state; never mutates observations.
local planner=RikUI.QuestPlanner
local schema,transitions=planner.Schema,{}
planner.PlanTransitions=transitions
local function membership(state,key,id)
    local value=(state[key] or {})[id]
    if value~=nil then return value end
    if key=="active" and state.logComplete then return false end
end
local function maskHas(mask,value)
    if not schema.Integer(mask,0,2147483647) or not schema.Integer(value,1,2147483647) then return end
    return math.floor(mask/value)%2==1
end
local function condition(rule,state,depth)
    if rule==nil then return true end
    depth=(depth or 0)+1
    if depth>12 or type(rule)~="table" then return nil,"Invalid requirement" end
    local op=rule.op
    if op=="all" or op=="any" then
        if not schema.List(rule.args,64) then return nil,"Invalid requirement list" end
        local unknown
        for _,child in ipairs(rule.args) do
            local result=condition(child,state,depth)
            if op=="all" and result==false then return false end
            if op=="any" and result==true then return true end
            if result==nil then unknown=true end
        end
        if unknown then return nil,"Requirement not observed" end
        return op=="all"
    end
    if op=="not" then local result=condition(rule.arg,state,depth);if result~=nil then return not result end;return end
    if op=="always" then return true end
    if op=="never" then return false end
    if op=="active" or op=="completed" then return membership(state,op,rule.questID) end
    local actual,wanted
    if op=="minLevel" or op=="maxLevel" then actual,wanted=state.level,rule.value
    elseif op=="classMask" or op=="raceMask" then return maskHas(rule.value,state[op])
    elseif op=="reputationMin" or op=="reputationMax" then actual,wanted=(state.reputation or {})[rule.id or rule.factionID],rule.value
    elseif op=="skill" then actual,wanted=(state.skills or {})[rule.id or rule.skillID],rule.value
    elseif op=="spell" then
        local value=(state.spells or {})[rule.id or rule.spellID]
        if value==nil then return end
        return value==(rule.value~=false)
    elseif op=="item" then actual,wanted=(state.inventory or {})[rule.itemID],rule.count
        if actual==nil and (state.inventoryLower or {})[rule.itemID] and state.inventoryLower[rule.itemID]>=wanted then actual=state.inventoryLower[rule.itemID] end
    elseif op=="capability" then return (state.capabilities or {})[rule.value]
    else return nil,"Unsupported requirement: "..tostring(op) end
    if not schema.Number(actual,-2147483647,2147483647) or not schema.Number(wanted,-2147483647,2147483647) then return end
    if op=="maxLevel" then return actual<=wanted end
    if op=="reputationMax" then return actual<wanted end
    return actual>=wanted
end
transitions.Condition=condition
local function remaining(action,state)
    local progress=state.progress[action.questID]
    local value=progress and progress[action.objectiveKey]
    if action.itemID and action.requiredCount then
        local owned=state.inventory[action.itemID]
        if owned~=nil then return math.max(value or 0,action.requiredCount-owned,0) end
    end
    return value
end
transitions.Remaining=remaining
local function resources(list,state)
    local totals={}
    for _,row in ipairs(list or {}) do
        if not schema.ID(row.itemID) or not schema.Integer(row.count,0,2147483647) then return nil,"Item quantity unknown" end
        totals[row.itemID]=(totals[row.itemID] or 0)+row.count
    end
    for id,count in pairs(totals) do
        local owned=state.inventory[id]
        if owned==nil and (state.inventoryLower or {})[id] and state.inventoryLower[id]>=count then owned=state.inventoryLower[id] end
        if owned==nil then return nil,"Carried item quantity unknown" end
        if owned<count then return false,"Required carried items missing" end
    end
    return true
end
local function objectivesDone(state,id)
    if state.objectivesComplete[id] then return true end
    local progress=state.progress[id]
    if not progress then return nil end
    if state.live and state.live[id] and not (state.simulatedWork or {})[id] then return nil end
    local conditional=state.conditionalObjectives and state.conditionalObjectives[id] or {}
    for key,count in pairs(progress) do
        if count~=0 and not (count==-1 and conditional[key]) then return false end
    end
    return true
end
local function blocked(ids,state,activeOnly,completedOnly)
    for _,id in ipairs(ids or {}) do
        local active,done=membership(state,"active",id),membership(state,"completed",id)
        if not completedOnly and active==true or not activeOnly and done==true then return true end
        if not completedOnly and active==nil or not activeOnly and done==nil then return nil end
    end
    return false
end
-- Allocate observed partial-stack space by item, then generic slots. No shared capacity credit.
local function capacity(action,state)
    if action.bagSlots then return action.bagSlots,{} end
    local incoming,unknown={},false
    for _,gain in ipairs(action.gains or {}) do
        local amount=gain.count
        if action.kind=="objective" and action.itemID==gain.itemID then amount=remaining(action,state) end
        if not schema.Integer(amount,0,2147483647) then unknown=true
        else
            if gain.source then amount=math.max(0,amount-(state.inventory[gain.itemID] or 0)) end
            incoming[gain.itemID]=(incoming[gain.itemID] or 0)+amount
        end
    end
    if action.itemID and not action.gains then unknown=true end
    local slots,rooms=0,{}
    for id,amount in pairs(incoming) do
        if amount>0 then
            local room=(state.stackRoom or {})[id] or 0
            local size=(state.stackSizes or {})[id]
            if amount<=room then rooms[id]=room-amount
            elseif size and size>0 then
                local needed=math.ceil((amount-room)/size)
                slots=slots+needed;rooms[id]=needed*size-(amount-room)
            else unknown=true end
        end
    end
    if unknown then return nil,rooms end
    return slots,rooms
end
transitions.Capacity=capacity
function transitions.Check(action,state,policy)
    if not action or not state or not state.fresh then return false,"Stale planner state" end
    policy=policy or state.policy
    local id=action.questID
    if action.liveFallback then return false,"Live guidance only" end
    if policy.skips[id] then return false,"Skipped quest" end
    if policy.defers[id] then return false,"Deferred for this session" end
    if action.zoneID and policy.avoids[action.zoneID] then return false,"Avoided area" end
    if state.failed[id] then return false,"Quest failed; live recovery required" end
    if state.applied[action.id] then return false,"Already simulated" end
    if (state.failures or {})[action.id] and state.failures[action.id]>=2 then return false,"Unavailable after bounded retry" end
    if action.inaccessible or action.destination and action.destination.access==false then return false,"Access unavailable" end
    local destination=action.destination
    if destination then
        if destination.phase and state.phase~=destination.phase then return nil,"Phase access unresolved" end
        if destination.floor and state.floor and destination.floor~=state.floor and not action.verifiedTravel then return nil,"Floor access unresolved" end
        if policy.travel=="localOnly" and state.position and state.position.mapID~=destination.mapID then return false,"Local travel only" end
    end
    if action.dispositionKnown then
        local friendly=action.friendlyToFaction
        local faction=state.faction=="Alliance" and "A" or state.faction=="Horde" and "H"
        local interaction=action.method=="vendor" or action.method=="talk" or action.method=="interact"
            or action.method=="start" or action.method=="finish"
        if interaction and not faction then return nil,"Faction interaction unknown" end
        if interaction and friendly~="AH" and friendly~=faction then return false,"Target does not support this faction interaction" end
        if (action.method=="kill" or action.method=="drop") and (friendly=="AH" or faction and friendly==faction) then
            return false,"Target is friendly to this faction"
        end
    end
    local slots=capacity(action,state)
    if slots and state.bagFree and slots>state.bagFree then return false,"Bags full; use observed stacking capacity or a service" end
    if slots==nil and state.bagFree==0 and not action.fitsExistingStack then return false,"Bags full; stacking capacity unresolved" end
    if action.dungeon and not policy.dungeons then return false,"Dungeon content disabled" end
    if action.groupRequiredUnknown then
        if policy.group=="solo" then return false,"Group content disabled" end
        return nil,"Required party size is not observed"
    end
    if action.requiredParty and action.requiredParty>1 then
        if policy.group=="solo" then return false,"Group content disabled" end
        if state.partySize==nil then return nil,"Party availability unknown" end
        if state.partySize<action.requiredParty then return false,"Required party unavailable" end
    end
    for _,rule in ipairs(action.preconditions or {}) do
        local ok=condition(rule,state)
        if ok~=true then return ok,"Resource or capability prerequisite unmet" end
    end
    local eligible=condition(action.prerequisite,state)
    if eligible~=true then return eligible,"Quest prerequisite unmet or unknown" end
    if action.unsupportedRequirements and next(action.unsupportedRequirements) then return nil,"Source requirement unresolved" end
    if action.kind=="pickup" then
        local active,done=membership(state,"active",id),membership(state,"completed",id)
        if active then return false,"Quest already active" end
        if state.branchLocks[id] then return false,"Incompatible branch already selected" end
        if done and not action.resetAvailable then return false,"Already completed; reset not observed" end
        if active==nil or done==nil then return nil,"Quest history incomplete" end
        for _,pair in ipairs({{action.excludes,false,false},{action.forbiddenAfter,false,true},
            {action.activeBreadcrumbs,true,false},{action.blockedWhileActive,true,false}}) do
            local conflict=blocked(pair[1],state,pair[2],pair[3])
            if conflict==true then return false,"Exclusive or breadcrumb availability blocked" end
            if conflict==nil then return nil,"Exclusive or breadcrumb availability unknown" end
        end
        if state.logCount==nil or state.logCapacity==nil then return nil,"Quest log capacity unknown" end
        if state.logCount>=state.logCapacity then return false,"Quest log full; finish or release a quest" end
    elseif action.kind=="objective" then
        if state.active[id]~=true then return false,"Accept quest first" end
        local value=remaining(action,state)
        if value==nil then return nil,"Source objective is not bound to live progress" end
        if value==0 or value==-1 and ((state.conditionalObjectives or {})[id] or {})[action.objectiveKey] then return false,"Objective already planned complete" end
    elseif action.kind=="complete" then
        if state.active[id]~=true then return false,"Quest is not active" end
        if objectivesDone(state,id)~=true then return false,"Objectives remain" end
    elseif action.kind=="turnin" then
        if state.active[id]~=true then return false,"Quest is not active" end
        if objectivesDone(state,id)~=true then return false,"Objectives remain" end
    elseif action.kind=="service" then
        if not policy.services or not action.supported then return false,"Service not supported or disabled" end
        for _,slot in ipairs(action.saleSlots or {}) do if (state.soldSlots or {})[slot] then return false,"Sale already planned" end end
        for itemID,count in pairs(action.saleInventory or {}) do
            if state.inventory[itemID]~=count then return nil,"Inventory changed; recheck the merchant offer" end
        end
    elseif action.kind=="explore" then
        if policy.explorationMinutes<=0 then return false,"Exploration declined" end
    else return nil,"Unsupported action mechanic" end
    if action.moneyCost then
        if state.money==nil then return nil,"Currency unknown" end
        if state.money<action.moneyCost then return false,"Insufficient currency" end
    elseif action.priceUnknown then return nil,"Purchase price unknown" end
    local available,reason=resources(action.consumes,state)
    if available~=true then return available,reason end
    if action.bagSlots and action.bagSlots>0 then
        if state.bagFree==nil then return nil,"Bag capacity unknown" end
        if state.bagFree<action.bagSlots then return false,"Bags full; use a supported service or finish a turn-in" end
    end
    if action.cooldownKey then
        local ready=(state.cooldowns or {})[action.cooldownKey]
        if ready==nil then return nil,"Cooldown unknown" end
        if ready>state.elapsed then return false,"Cooldown not ready" end
    end
    return true
end
-- Source graph/observed metadata are immutable and shared. Only rollout fields copy.
local MAPS={"active","completed","failed","objectivesComplete","applied","branchLocks","inventory","skills",
    "capabilities","spells","cooldowns","visited","credited","conditionalCompleted","inventoryLower","simulatedWork","stackRoom","genericStacks","soldSlots"}
local NESTED={"progress","conditionalObjectives"}
function transitions.Fork(state)
    local result={}
    for key,value in pairs(state) do result[key]=value end
    for _,key in ipairs(MAPS) do
        result[key]={};for id,value in pairs(state[key] or {}) do result[key][id]=value end
    end
    for _,key in ipairs(NESTED) do
        result[key]={}
        for id,values in pairs(state[key] or {}) do
            local copy={};for index,value in pairs(values) do copy[index]=value end
            result[key][id]=copy
        end
    end
    result.projectedRewards=schema.Clone(state.projectedRewards)
    result.assumptions={};for _,value in ipairs(state.assumptions or {}) do result.assumptions[#result.assumptions+1]=value end
    result.recent={};for _,value in ipairs(state.recent or {}) do result.recent[#result.recent+1]=value end
    return result
end
local function assume(state,text)
    if #state.assumptions<32 then state.assumptions[#state.assumptions+1]=text end
    state.conditional=true
end
local function levelXP(state,xp)
    state.xpGained=(state.xpGained or 0)+xp
    if state.xp==nil or state.xpMax==nil or state.level==nil then return end
    state.xp=state.xp+xp
    for _=1,20 do
        if not state.xpMax or state.xp<state.xpMax then break end
        state.xp=state.xp-state.xpMax;state.level=state.level+1
        state.xpMax=(state.xpThresholds or {})[state.level]
    end
end
function transitions.Apply(action,state,policy,cost)
    local ok,reason=transitions.Check(action,state,policy)
    if ok~=true then return nil,reason end
    local result=transitions.Fork(state)
    local id=action.questID
    result.applied[action.id]=true
    result.elapsed=(state.elapsed or 0)+(cost and cost.seconds or 0)
    result.upperElapsed=(state.upperElapsed or 0)+(cost and cost.upper or 0)
    result.travelSeconds=(state.travelSeconds or 0)+(cost and cost.travel or 0)
    if cost and cost.unknown then assume(result,"Cost includes an uncalibrated estimate") end
    if action.mechanicUncertain then assume(result,"Compound acquisition depends on unobserved container contents") end
    if action.destination then result.position=action.destination;result.floor=action.destination.floor end
    if action.kind=="pickup" then
        result.active[id]=true;result.logCount=result.logCount+1
        result.progress[id]={}
        for key,count in pairs(action.initialProgress or {}) do result.progress[id][key]=count end
        result.conditionalObjectives[id]={}
        if action.availability=="source-suggestion" then assume(result,"Availability is a source suggestion; confirm at the giver") end
        for _,other in ipairs(action.branchExcludes or action.excludes or {}) do result.branchLocks[other]=id end
    elseif action.kind=="objective" then
        result.simulatedWork[id]=true
        local count=remaining(action,state)
        if count==-1 or action.countUnknown then
            result.conditionalObjectives[id]=result.conditionalObjectives[id] or {}
            result.conditionalObjectives[id][action.objectiveKey]=true
            assume(result,"Future objective quantity unknown; completion and follow-ups are conditional")
            if action.objectiveType=="item" then result.bagFree=nil end
        else
            result.progress[id][action.objectiveKey]=0
            if action.sharedCredit then
                local seen={}
                for _,credit in ipairs(action.credits or {}) do
                    local key=tostring(credit.questID)..":"..credit.key
                    local values=result.progress[credit.questID]
                    if not seen[key] and result.active[credit.questID] and values and values[credit.key] and values[credit.key]>0 then
                        values[credit.key]=math.max(0,values[credit.key]-count)
                        result.simulatedWork[credit.questID]=true
                        seen[key]=true
                    end
                end
            end
        end
    elseif action.kind=="complete" then
        result.objectivesComplete[id]=true
        return result -- Validation milestone cannot manufacture rewards or resource effects.
    elseif action.kind=="turnin" then
        result.active[id]=false;result.completed[id]=true;result.logCount=math.max(0,result.logCount-1)
        result.finished=(state.finished or 0)+1
        local reward=action.typedRewards
        if reward then
            result.projectedRewards=result.projectedRewards or {money=0,reputation={},spells={}}
            local projection=result.projectedRewards
            if reward.money then
                projection.money=projection.money+reward.money
                if result.money~=nil then result.money=result.money+reward.money end
            end
            for _,rep in ipairs(reward.reputation) do
                projection.reputation[rep.factionID]=(projection.reputation[rep.factionID] or 0)+rep.value
                assume(result,"Reputation is a source estimate; live standing must confirm unlocks")
            end
            for _,spellID in ipairs(reward.spells) do
                projection.spells[spellID]=true;result.spells[spellID]=true
                assume(result,"Confirm the offered learned spell after turn-in")
            end
            if reward.choiceItemID then assume(result,"Choose reward item "..reward.choiceItemID.." for this plan") end
        end
        if result.conditional then result.conditionalCompleted[id]=true end
        for _,itemID in ipairs(action.unknownConsumeItems or {}) do
            result.inventory[itemID]=nil;result.inventoryLower[itemID]=nil;assume(result,"Turn-in consumes an unresolved item quantity")
        end
    elseif action.kind=="service" then
        if action.conditionalService then assume(result,"Optional service benefits require your action and live confirmation") end
        if action.freesSlots then result.bagFree=result.bagFree and result.bagFree+action.freesSlots end
        for _,sold in ipairs(action.discardStackRoom or {}) do result.stackRoom[sold.itemID]=nil;result.genericStacks[sold.itemID]=nil end
        for _,slot in ipairs(action.saleSlots or {}) do result.soldSlots[slot]=true end
        for skill,value in pairs(action.skillGains or {}) do result.skills[skill]=value end
        for key,value in pairs(action.capabilityGains or {}) do result.capabilities[key]=value end
    elseif action.kind=="explore" then result.explorationSeconds=(state.explorationSeconds or 0)+(cost and cost.seconds or 0) end
    local consumed={}
    for _,row in ipairs(action.consumes or {}) do consumed[row.itemID]=(consumed[row.itemID] or 0)+row.count end
    for itemID,count in pairs(consumed) do
        if result.inventory[itemID]==count then
            local freed=result.genericStacks[itemID]
            if freed and not action.freesSlots then result.bagFree=result.bagFree and result.bagFree+freed end
            result.genericStacks[itemID]=nil;result.stackRoom[itemID]=nil
        end
    end
    for _,row in ipairs(action.consumes or {}) do
        if result.inventory[row.itemID]~=nil then result.inventory[row.itemID]=result.inventory[row.itemID]-row.count end
        if result.inventoryLower[row.itemID]~=nil then result.inventoryLower[row.itemID]=math.max(0,result.inventoryLower[row.itemID]-row.count) end
    end
    for _,row in ipairs(action.gains or {}) do
        local owned=result.inventory[row.itemID]
        local amount=row.count
        if action.kind=="objective" and action.itemID==row.itemID then amount=math.max(0,remaining(action,state) or 0) end
        if owned~=nil then result.inventory[row.itemID]=row.source and math.max(owned,amount) or owned+amount
        else
            local lower=result.inventoryLower[row.itemID] or 0
            result.inventoryLower[row.itemID]=row.source and math.max(lower,amount) or lower+amount
            assume(result,"Carried quantity has a known lower bound only")
        end
    end
    if action.moneyCost then result.money=result.money-action.moneyCost end
    local slots,rooms=capacity(action,state)
    if slots then
        result.bagFree=result.bagFree and result.bagFree-slots
        for itemID,room in pairs(rooms) do result.stackRoom[itemID]=room end
    else
        result.bagFree=nil;result.stackRoom={}
        assume(result,"Collection capacity is unresolved; check bags before proceeding")
    end
    if cost and cost.xp~=nil then
        levelXP(result,cost.xp)
        if cost.xp>0 and cost.xpAuthority~="observed" then assume(result,"XP and level progression are estimates") end
    elseif action.kind=="turnin" then result.unknownXP=(state.unknownXP or 0)+1 end
    local activity=action.activity or action.kind
    result.recent[#result.recent+1]=activity
    if #result.recent>12 then table.remove(result.recent,1) end
    if action.zoneID and result.visited[action.zoneID]==false then
        result.discoveries=(state.discoveries or 0)+1
        result.visited[action.zoneID]=true
    end
    if action.storyArc and action.storyArc==state.storyArc then result.storySteps=(state.storySteps or 0)+1 end
    if action.storyArc then result.storyArc=action.storyArc end
    return result
end
