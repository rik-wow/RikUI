-- Corpus-to-action graph. References describe opportunities, never observed completion.
local planner=RikUI.QuestPlanner
local schema,graphModel=planner.Schema,{}
planner.PlanGraph=graphModel
local MAX_QUESTS,MAX_ACTIONS,MAX_METHODS,MAX_AREAS=96,768,6,12
-- QuestieDB baa0998d src/corrections/enum/constants.lua; categories, not quest IDs.
-- Retain this check for installed corpus pages compiled before availability metadata.
local SEASONAL_SORTS={[-21]=true,[-22]=true,[-41]=true,[-364]=true,[-366]=true,
    [-369]=true,[-370]=true,[-374]=true,[-375]=true,[-376]=true,[-378]=true,[-402]=true,[-404]=true}
local VERBS={kill="Defeat",drop="Collect from",loot="Loot",talk="Talk to",interact="Interact with",
    ["use-item"]="Use the quest item at",explore="Explore",escort="Escort",defend="Defend",
    deliver="Deliver to",craft="Craft",vendor="Purchase from",herb="Gather",mine="Mine",fish="Fish at",
    event="Follow the quest instructions at",unknown="Check the quest instructions at"}
local function point(area)
    if not area or not schema.ID(area.mapID) or not schema.Number(area.x,0,1) or not schema.Number(area.y,0,1) then return end
    return {mapID=area.mapID,x=area.x,y=area.y,floor=area.floor,phase=area.phase,areaID=area.id,
        floorKnown=area.floorKnown,access=area.access,source=area.source or "source-reference",scope="semantic-objective-area",api="QuestieDB"}
end
local function usable(area,state,policy)
    if not point(area) or policy.avoids[area.mapID] then return false end
    if area.access==false or area.reachable==false then return false end
    if area.phase and area.phase~=state.phase then return false end
    if area.floor and state.floor and area.mapID==(state.position and state.position.mapID) and area.floor~=state.floor
        and not area.entrance then return false end
    return true
end
local function nearestAreas(method,state,policy)
    local areas={}
    for n,area in ipairs(method.areas or {}) do
        if n>MAX_AREAS then break end
        if usable(area,state,policy) then areas[#areas+1]=area end
    end
    local origin=state.position
    table.sort(areas,function(a,b)
        local da=origin and origin.mapID==a.mapID and (a.x-origin.x)^2+(a.y-origin.y)^2 or math.huge
        local db=origin and origin.mapID==b.mapID and (b.x-origin.x)^2+(b.y-origin.y)^2 or math.huge
        if da~=db then return da<db end
        return tostring(a.id or "")<tostring(b.id or "")
    end)
    return areas
end
local function append(graph,action)
    local reserve=graph.previousID and action.id~=graph.previousID and not graph.byID[graph.previousID] and 1 or 0
    if #graph.actions>=MAX_ACTIONS-reserve then graph.limited=true;return end
    if graph.byID[action.id] then return end
    graph.actions[#graph.actions+1],graph.byID[action.id]=action,action
    graph.byQuest[action.questID]=graph.byQuest[action.questID] or {}
    local rows=graph.byQuest[action.questID];rows[#rows+1]=action
end
local function baseAction(record,kind,key)
    local rules=record.planning or {}
    return {id=record.id..":"..kind..":"..key,questID=record.id,title=record.title,kind=kind,
        prerequisite=kind=="pickup" and rules.requirements or nil,
        excludes=kind=="pickup" and rules.blockedBy or nil,
        branchExcludes=kind=="pickup" and (rules.exclusiveWith or {}) or nil,
        forbiddenAfter=kind=="pickup" and rules.forbiddenAfter or nil,
        activeBreadcrumbs=rules.activeBreadcrumbs,blockedWhileActive=rules.blockedWhileActive,breadcrumbFor=rules.breadcrumbFor,
        unsupportedRequirements=kind=="pickup" and rules.unsupportedRequirements or nil,
        seasonal=kind=="pickup" and (rules.seasonalCategory~=nil or rules.seasonalEvent~=nil or SEASONAL_SORTS[record.zoneOrSort]) or nil,
        repeatable=rules.repeatable,reset=rules.reset,authority="reference",
        provenance=record.provenance,sourceRevision=record.provenance and record.provenance.revision,
        level=record.eligibility and record.eligibility.questLevel,minLevel=record.eligibility and record.eligibility.requiredLevel,
        interaction=kind,completionEvidence=kind=="pickup" and "Quest appears in the live log"
            or kind=="turnin" and "QUEST_TURNED_IN or live completed history"
            or "Live objective progress or completion",
        recovery="If unavailable, retry once, then choose another action"}
end
local function locate(action,method,area)
    action.destination=point(area);action.zoneID=area.mapID
    action.target={kind=method.targetKind,id=method.targetID,name=method.name}
    action.method=method.kind;action.dropEstimate=method.dropEstimate
    action.viaItemID=method.viaItemID;action.acquisition=method.acquisition
    action.encounter=method.eligibility;action.rank=method.rank
    action.dispositionKnown=method.dispositionKnown;action.friendlyToFaction=method.friendlyToFaction
    action.npcFlags=method.npcFlags
    action.topologyKey=table.concat({area.mapID,tostring(area.floor or "?"),tostring(area.phase or "?"),
        tostring(area.entrance or area.id or "?")},":")
    action.travelStatus=area.access==true and "supported" or "unverified"
    action.clusterKey=action.topologyKey
end
local function relationship(graph,record,kind,state,policy)
    local methods=kind=="pickup" and record.starts or record.ends
    local added=0
    for n,method in ipairs(methods or {}) do
        if n>MAX_METHODS then break end
        for index,area in ipairs(nearestAreas(method,state,policy)) do
            local key=n..":"..tostring(area.id or (area.x..","..area.y))
            if index<=2 or graph.previousID==record.id..":"..kind..":"..key then
                local action=baseAction(record,kind,key)
                locate(action,method,area)
                action.instruction=(kind=="pickup" and "Check for "..record.title.." with " or "Turn in "..record.title.." to ")..(method.name or "the quest giver")
                if kind=="pickup" then
                    action.gains=record.providedItemID and {{itemID=record.providedItemID,count=1,source=true}} or nil
                    action.initialProgress={}
                    for _,objective in ipairs(record.objectives or {}) do
                        action.initialProgress[objective.id]=objective.required or -1
                    end
                    action.availability="source-suggestion"
                else
                    action.reward=record.reward;action.consumes={};action.unknownConsumeItems={}
                    for _,objective in ipairs(record.objectives or {}) do
                        local info=state.objectiveInfo[record.id] and state.objectiveInfo[record.id][objective.id]
                        if objective.type=="item" then
                            local required=info and info.required or objective.required
                            if required then action.consumes[#action.consumes+1]={itemID=objective.targetID,count=required}
                            else action.unknownConsumeItems[#action.unknownConsumeItems+1]=objective.targetID end
                        end
                    end
                end
                if planner.PlanRewards then planner.PlanRewards.Attach(action,record,state,policy) end
                append(graph,action);added=added+1
            end
        end
    end
    if added==0 then graph.excluded[#graph.excluded+1]={questID=record.id,kind=kind,reason="No supported location; live instructions retained"} end
end
local function objectiveAction(record,objective,method,area,state,key)
    local action=baseAction(record,"objective",key)
    locate(action,method,area)
    action.objectiveKey=objective.id
    local info=state.objectiveInfo[record.id] and state.objectiveInfo[record.id][objective.id]
    action.objectiveTarget=objective.targetID
    if objective.type=="item" then action.itemID=objective.targetID end
    action.count=info and math.max(0,info.required-info.fulfilled) or objective.required
    action.countUnknown=action.count==nil
    action.objectiveType=(objective.type=="monster" or objective.type=="kill-credit") and method.kind=="kill" and "kill" or objective.type
    action.activity=method.kind
    action.instruction=(VERBS[method.kind] or VERBS.unknown).." "..(method.name or objective.name or record.title)
    action.progressText=info and info.text
    if method.viaItemID then
        action.stages={{interaction=method.kind,targetID=method.targetID},{interaction="open-container",itemID=method.viaItemID}}
        action.instruction=action.instruction.."; open the collected container and check its contents"
        action.mechanicUncertain=true
    end
    if objective.sourceItemID then
        action.preconditions={{op="item",itemID=objective.sourceItemID,count=1}}
        if method.kind=="use-item" then action.cooldownKey="item:"..objective.sourceItemID end
    end
    if objective.type=="item" and action.count then
        action.gains={{itemID=objective.targetID,count=action.count}}
        action.itemID=objective.targetID
        action.requiredCount=info and info.required or objective.required
    end
    if method.kind=="vendor" then action.moneyCost=method.price;action.priceUnknown=method.price==nil end
    if method.kind=="quest-reward" then action.prerequisite={op="completed",questID=method.targetID} end
    if action.objectiveType=="kill" then action.sharedCredit="kill:"..method.targetID..":"..action.topologyKey end
    return action
end
local function objectives(graph,record,state,policy)
    for objectiveIndex,objective in ipairs(record.objectives or {}) do
        if objectiveIndex>32 then graph.limited=true;break end
        local made=0
        for n,method in ipairs(objective.methods or {}) do
            if n>MAX_METHODS then break end
            for index,area in ipairs(nearestAreas(method,state,policy)) do
                local key=objective.id..":"..n..":"..tostring(area.id or (area.x..","..area.y))
                if index<=2 or graph.previousID==record.id..":objective:"..key then
                    append(graph,objectiveAction(record,objective,method,area,state,key))
                    made=made+1
                end
            end
        end
        if made==0 then graph.excluded[#graph.excluded+1]={questID=record.id,objective=objective.id,reason="Objective mechanic/location unresolved"} end
    end
    local action=baseAction(record,"complete","milestone")
    action.instruction="Finish the quest objectives";action.completionEvidence="All live objectives complete"
    append(graph,action)
end
local function liveFallback(graph,state,id,row)
    local live=state.live[id]
    if not live then return end
    local kind=live.objectivesComplete and "turnin" or "objective"
    local action={id=id..":live:"..kind,questID=id,title=live.title,kind=kind,authority="live",liveFallback=true,
        destination=row and row.destination or live.destination,detail=row and row.detail,
        instruction=row and row.detail or (kind=="turnin" and "Turn in this quest" or "Follow the live quest instructions"),
        completionEvidence="Live progress or QUEST_TURNED_IN; proximity never completes",
        recovery="Check the quest log or choose an alternative",countUnknown=true}
    action.zoneID=action.destination and action.destination.mapID
    append(graph,action)
end
local function addQuest(graph,state,id,record,policy,rows)
    if not record or (record.known and record.known.semanticRecord==false) then
        graph.coverage.liveOnly=graph.coverage.liveOnly+1;liveFallback(graph,state,id,rows[id]);return
    end
    if record.id~=id or not schema.Text(record.title) or not schema.List(record.objectives or {},32) then
        graph.excluded[#graph.excluded+1]={questID=id,reason="Invalid source record"};liveFallback(graph,state,id,rows[id]);return
    end
    graph.quests[id]=record
    graph.coverage.semantic=graph.coverage.semantic+1
    if record.planning and record.planning.version==1 then
        relationship(graph,record,"pickup",state,policy);graph.coverage.future=graph.coverage.future+1
    end
    objectives(graph,record,state,policy)
    relationship(graph,record,"turnin",state,policy)
    -- A contradictory or unbound source objective cannot replace live instructions.
    if state.active[id] then liveFallback(graph,state,id,rows[id]) end
end
local function finalize(graph,state,policy)
    local credits={}
    for _,action in ipairs(graph.actions) do
        if action.sharedCredit and action.objectiveType=="kill" then
            local list=credits[action.sharedCredit] or {};credits[action.sharedCredit]=list
            list[#list+1]={questID=action.questID,key=action.objectiveKey}
        end
        local live=state.live[action.questID]
        if live then action.requiredParty=live.requiredParty;action.dungeon=live.dungeon;action.groupRequiredUnknown=live.groupRequiredUnknown end
        local rules=graph.quests[action.questID] and graph.quests[action.questID].planning
        if rules then
            local predecessors={}
            local function walk(rule,depth)
                if not rule or depth>10 then return end
                if rule.op=="completed" then predecessors[rule.questID]=true end
                for _,child in ipairs(rule.args or {}) do walk(child,depth+1) end
            end
            walk(rules.requirements,0);action.chainPredecessors=predecessors
        end
    end
    for _,action in ipairs(graph.actions) do if action.sharedCredit then action.credits=credits[action.sharedCredit] end end
    for _,offer in ipairs(state.explorationOffers or {}) do
        if offer.supported and offer.discoveryNode and offer.destination and usable(offer.destination,state,policy) then
            append(graph,schema.Clone(offer))
        end
    end
    -- A future quest trigger is not an exploration attraction.
    -- Quest exploration stays attached to its actual eligibility and live objectives.
    for index,service in ipairs(state.services or {}) do
        if index>16 then break end
        if service.supported==true and schema.Text(service.id) and service.destination and usable(service.destination,state,policy) then
            local action=schema.Clone(service)
            action.kind="service";action.id="service:"..service.id;action.questID=service.questID or 0
            action.zoneID=service.destination.mapID
            action.instruction=service.instruction or "Use the observed service"
            action.completionEvidence="Live currency, capacity or capability change"
            action.recovery="Leave this optional stop or choose another action"
            append(graph,action)
        end
    end
end
function graphModel.Begin(state,records,observed,policy,previousID)
    if not state or not state.fresh then return nil,"Live state required" end
    local graph={version=1,identity=state.identity,revision=state.sourceRevision,actions={},byID={},byQuest={},quests={},
        excluded={},coverage={semantic=0,future=0,liveOnly=0},limited=false,
        previousID=schema.Text(previousID) and #previousID<=160 and previousID or nil}
    local ids,seen,rows={},{},{}
    for id in pairs(state.live) do ids[#ids+1]=id;seen[id]=true end
    table.sort(ids)
    local future={}
    for id in pairs(records or {}) do if not seen[id] then future[#future+1]=id end end
    table.sort(future)
    for _,id in ipairs(future) do if #ids<MAX_QUESTS then ids[#ids+1]=id else graph.limited=true end end
    for _,row in ipairs(observed or {}) do rows[row.questID]=row end
    local at,cancelled=1,false
    return {Cancel=function() cancelled=true end,Step=function(_,budget)
        if cancelled then return {status="cancelled"} end
        for _=1,math.min(4,budget or 1) do
            local id=ids[at]
            if not id then finalize(graph,state,policy);graph.status="ready";return graph end
            addQuest(graph,state,id,records[id],policy,rows);at=at+1
        end
    end}
end
