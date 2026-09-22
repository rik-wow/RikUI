-- Explicit engineering priors and observed calibration; ranges are not confidence percentages.
local planner=RikUI.QuestPlanner
local schema,costs=planner.Schema,{}
planner.PlanCosts=costs
local function valid(value) return schema.Number(value,0,86400) end
function costs.Reward(action,state)
    if action.kind~="turnin" then
        if action.kind=="objective" and schema.Number(action.confirmedCombatXP,0,2147483647) then return action.confirmedCombatXP,"observed" end
        return 0,"not-applicable"
    end
    local live=state.live and state.live[action.questID]
    local observed=live and live.reward
    if observed and schema.Number(observed.xp,0,2147483647) then return observed.xp,"observed" end
    local reward=action.reward
    if not reward or not schema.Number(reward.baseXP,0,2147483647) then return nil,"unknown" end
    if reward.baseXP==0 then return 0,"source-reference" end
    if not schema.Number(reward.level,1,1000) or not schema.Number(state.level,1,1000) then return nil,"unknown" end
    local value=reward.baseXP*math.max(1,math.min(10,2*(reward.level-state.level)+20))/10
    if value<=100 then value=5*math.floor((value+2)/5)
    elseif value<=500 then value=10*math.floor((value+5)/10)
    elseif value<=1000 then value=25*math.floor((value+12)/25)
    else value=50*math.floor((value+25)/50) end
    if schema.Number(state.questXPMultiplier,0,100) then value=math.floor(value*state.questXPMultiplier) end
    return value,"source-estimate"
end
function costs.Context(action,state)
    return table.concat({state.identity.build,state.class or "?",state.level or "?",state.partySize or "?",
        action.zoneID or "?",action.target and action.target.id or action.questID,action.method or action.kind},":")
end
local function travel(action,state,environment)
    if not action.destination then return {seconds=0,lower=0,upper=0,status="not-applicable"} end
    if environment and environment.travel then
        local result=environment.travel(state.position,action.destination,state,action)
        if result and valid(result.seconds) and result.status~="unknown" then return result end
        if result and result.status=="inaccessible" then return result end
    end
    local from,to=state.position,action.destination
    if from and from.mapID==to.mapID and from.x==to.x and from.y==to.y and from.floor==to.floor then
        return {seconds=0,lower=0,upper=0,status="same-location"}
    end
    -- Coordinates are only a lower bound; without topology this remains qualified marker guidance.
    local distance
    if from and from.mapID==to.mapID then
        local sizes=environment and environment.mapSizes and environment.mapSizes[to.mapID]
        if sizes then distance=math.sqrt(((to.x-from.x)*sizes[1])^2+((to.y-from.y)*sizes[2])^2) end
    end
    local seconds=distance and distance/7 or (from and from.mapID==to.mapID and 90 or 600)
    return {seconds=seconds,lower=distance and seconds or 0,upper=math.max(120,seconds*3),status="unverified",
        reason="Travel time is an unverified estimate; connectivity is unknown"}
end
local function add(out,name,mean,low,high,authority,samples)
    out.components[name]={seconds=mean,lower=low,upper=high,authority=authority,samples=samples}
    out.seconds=out.seconds+mean;out.lower=out.lower+low;out.upper=out.upper+high
    if authority=="engineering-prior" then out.unknown=true end
end
function costs.Estimate(action,state,policy,environment)
    local out={seconds=0,lower=0,upper=0,components={},unknown=false,pressure=0}
    local route=travel(action,state,environment)
    if route.status=="inaccessible" then return nil,route.reason or "Travel inaccessible" end
    out.travel=route.seconds or 0;out.travelStatus=route.status;out.travelReason=route.reason
    add(out,"travel",out.travel,route.lower or out.travel,route.upper or out.travel,
        route.status=="unverified" and "engineering-prior" or route.status)
    local context=costs.Context(action,state)
    if action.kind=="objective" then
        local remaining=planner.PlanTransitions.Remaining(action,state)
        local kind=(action.method=="drop" or action.method=="loot") and "collection" or action.method=="kill" and "combat" or "interaction"
        local model=planner.PlanLearning and planner.PlanLearning.Estimate(kind,context)
        local count=remaining and remaining>=0 and remaining or nil
        if model and count then
            add(out,kind,model.mean*count,model.minimum*count,model.maximum*count,"observed-local",model.samples)
        elseif count then
            local work=count
            local rate=action.dropEstimate and action.dropEstimate.probability
            if action.method=="drop" and schema.Number(rate,0,1) then
                if rate==0 then return nil,"Source reports zero drop probability for this method" end
                work=count/rate
                out.drop={required=count,probability=rate,expectedAttempts=work,authority="source-estimate"}
            end
            local per=kind=="combat" and 25 or kind=="collection" and 30 or 10
            add(out,kind,work*per,work*math.min(5,per),work*per*3,"engineering-prior")
        else
            add(out,kind,180,30,900,"engineering-prior")
            out.quantityUnknown=true
        end
        add(out,"loot",kind=="combat" and (count or 1)*3 or 0,0,kind=="combat" and (count or 1)*8 or 0,"engineering-prior")
        add(out,"waiting",action.waitSeconds or 0,action.waitLower or 0,action.waitUpper or 120,
            action.waitSeconds and "source-estimate" or "engineering-prior")
        local recovery=planner.PlanLearning and planner.PlanLearning.Estimate("recovery",context)
        add(out,"recovery",recovery and recovery.mean or action.recoverySeconds or 15,
            recovery and recovery.minimum or 0,recovery and recovery.maximum or action.recoveryUpper or 90,
            recovery and "observed-local" or "engineering-prior",recovery and recovery.samples)
        add(out,"death",action.deathSeconds or 0,0,action.deathUpper or 180,
            action.deathSeconds and "observed-local" or "engineering-prior")
        if action.method=="escort" or action.method=="defend" then
            out.commitment=true
            add(out,"event",action.eventSeconds or 300,action.eventLower or 60,action.eventUpper or 900,"engineering-prior")
        end
    elseif action.kind=="pickup" or action.kind=="turnin" then
        add(out,"interaction",5,2,20,"engineering-prior")
        add(out,"reading",policy.readingSeconds,policy.readingSeconds,policy.readingSeconds,"preference")
    elseif action.kind=="service" then
        add(out,"service",action.serviceSeconds or 30,10,120,"engineering-prior")
    elseif action.kind=="explore" then add(out,"exploration",action.exploreSeconds or 120,30,300,"engineering-prior") end
    if action.cost and valid(action.cost.seconds) then
        -- Validated observed/authored durations, also used by replay cases.
        out.seconds=out.travel+action.cost.seconds;out.lower=(route.lower or out.travel)+(action.cost.lower or action.cost.seconds)
        out.upper=(route.upper or out.travel)+(action.cost.upper or action.cost.seconds)
        out.unknown=action.cost.authority~="observed" and action.cost.authority~="authored"
        out.components.work={seconds=action.cost.seconds,authority=action.cost.authority}
    end
    out.xp,out.xpAuthority=costs.Reward(action,state)
    out.variance=math.max(0,out.upper-out.lower)
    -- Encounter level is a feature, never sufficient to certify capability.
    local difficulty=action.encounter and (action.encounter.minLevel or action.encounter.level)
    out.difficulty=difficulty and state.level and difficulty-state.level or nil
    out.pressure=out.variance/600+(action.requiredParty and action.requiredParty>1 and 1 or 0)
        +(action.rank and action.rank>0 and 1 or 0)
    out.capabilityKnown=state.capabilities and state.capabilities.combat~=nil
    return out
end
