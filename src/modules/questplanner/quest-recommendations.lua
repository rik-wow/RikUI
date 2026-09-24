-- Cheap live recommendations; preference weights are not XP or completion-time estimates.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local recommendations={}
planner.Recommendations=recommendations
local MOVEMENT_CELL,MOVEMENT_DISTANCE,SWITCH_DISTANCE,SWITCH_FRACTION=25,40,40,.2
local TURNIN_BONUS,PROGRESS_BONUS,SHARED_BONUS=40,25,.15
local function eligible(row) return not row.skipped and not row.deferred and not row.groupBlocked and not row.avoided and not row.failed end
local function positioned(point)
    return point and schema.ID(point.mapID) and schema.Number(point.x,0,1) and schema.Number(point.y,0,1)
end
local function measured(position,frame)
    return positioned(position) and frame and schema.Number(frame.width,1,100000)
        and schema.Number(frame.height,1,100000)
        and frame.position and frame.position.mapID==position.mapID
end
function recommendations.PositionKey(position,frame)
    if not measured(position,frame) then return positioned(position) and tostring(position.mapID) or "unknown" end
    return string.format("%d:%d:%d",position.mapID,math.floor(position.x*frame.width/MOVEMENT_CELL),
        math.floor(position.y*frame.height/MOVEMENT_CELL))
end
local function distance(point,position,frame)
    if not positioned(point) or not measured(position,frame) or point.mapID~=position.mapID then return end
    return math.sqrt(((point.x-position.x)*frame.width)^2+((point.y-position.y)*frame.height)^2)
end
function recommendations.Moved(previous,position,frame)
    if not positioned(previous) or not positioned(position) then return false end
    if previous.mapID~=position.mapID then return true end
    local gap=distance(previous,position,frame)
    return gap and gap>=MOVEMENT_DISTANCE or false
end
local function progress(quest)
    local fulfilled,required=0,0
    for _,objective in ipairs(quest and quest.objectives or {}) do
        local count,total=objective.numFulfilled,objective.numRequired
        if schema.Number(total,1,1000000) and schema.Number(count,0,total) then
            fulfilled,required=fulfilled+count,required+total
        end
    end
    return required>0 and fulfilled/required or 0
end
local function sharedAreas(rows)
    local areas={}
    for _,row in ipairs(rows) do
        local key=eligible(row) and row.kind=="objective" and row.semantic and row.semantic.areaID
        if key then
            local set=areas[key] or {};areas[key]=set;set[row.questID]=true
        end
    end
    return areas
end
local function describe(row,shared,known)
    if row.pinned then return "Pinned by you" end
    if not known then return row.destination and "Travel between these locations is unknown" or "Quest location is unavailable" end
    if shared>0 then return "Shared area for "..(shared+1).." active quests" end
    return row.kind=="turnin" and "Nearby turn-in" or "Nearby objective"
end
local function annotate(row,index,snapshot,ctx,frame,areas)
    local gap=distance(row.destination,ctx.position,frame)
    local shared=0
    local set=row.semantic and areas[row.semantic.areaID]
    for id in pairs(set or {}) do if id~=row.questID then shared=shared+1 end end
    local bonus=row.kind=="turnin" and TURNIN_BONUS or PROGRESS_BONUS*progress(snapshot.quests[row.questID])
    local score=gap and math.max(0,gap-bonus)/(1+SHARED_BONUS*math.min(shared,2))
    row.recommendation={distance=gap,score=score,shared=shared,order=index,
        basis=gap and "map-distance estimate" or "travel unknown",
        text=describe(row,shared,gap~=nil)}
end
local function rank(row)
    if row.recommendation.score then return 0 end
    return positioned(row.destination) and 1 or 2
end
local function earlier(a,b)
    if eligible(a)~=eligible(b) then return eligible(a) end
    if a.pinned~=b.pinned then return a.pinned end
    if rank(a)~=rank(b) then return rank(a)<rank(b) end
    local left,right=a.recommendation,b.recommendation
    if left.score and left.score~=right.score then return left.score<right.score end
    return left.order<right.order
end
local function retain(current,best,prior)
    if not current or not best or not eligible(current) or current.pinned~=best.pinned then return false end
    if prior and (prior.kind~=current.kind or prior.stepID~=current.stepID) then return false end
    if rank(current)~=rank(best) then return false end
    local a,b=current.recommendation.score,best.recommendation.score
    return not a or a-b<math.max(SWITCH_DISTANCE,a*SWITCH_FRACTION)
end
function recommendations.Sort(rows,snapshot,ctx,previous,prior)
    local frame=planner.Context and planner.Context.Frame and planner.Context.Frame()
    local areas=sharedAreas(rows)
    local current
    for index,row in ipairs(rows) do
        annotate(row,index,snapshot,ctx,frame,areas)
        if row.questID==previous then current=row end
    end
    table.sort(rows,earlier)
    if current~=rows[1] and retain(current,rows[1],prior) then
        for index,row in ipairs(rows) do
            if row==current then table.remove(rows,index);table.insert(rows,1,row);break end
        end
        current.recommendation.retained=true
        current.recommendation.text=current.pinned and "Pinned by you" or "Continue the current step"
    end
    return rows
end

-- These are observations for choosing the next destination, never simulated rewards.
function recommendations.Capture(rows,state,policy,graph)
    local result,supported,byQuest={},{},{}
    for _,row in ipairs(rows or {}) do byQuest[row.questID]=row end
    for _,action in ipairs(graph and graph.actions or {}) do
        if not action.liveFallback and (action.kind=="objective" or action.kind=="turnin")
            and state and state.active[action.questID] then
            local live=state.live[action.questID]
            local row=byQuest[action.questID]
            local key=row and row.semantic and row.semantic.objectiveKey
            if action.kind==(live.objectivesComplete and "turnin" or "objective")
                and (not key or action.objectiveKey==key) then
                supported[action.questID]=supported[action.questID]==true or planner.PlanTransitions.Check(action,state,policy)==true
            end
        end
    end
    for _,row in ipairs(rows or {}) do
        if #result>=40 then break end
        local p=row.destination
        local point=p and {mapID=p.mapID,x=p.x,y=p.y,floor=p.floor,phase=p.phase,access=p.access}
        result[#result+1]={questID=row.questID,kind=row.kind,destination=point,
            blocked=(state and state.live[row.questID] and state.live[row.questID].hasPlanningRecord==true
                and supported[row.questID]~=true) or supported[row.questID]==false
                or row.step and row.step.state=="blocked" or false,
            distance=row.recommendation and row.recommendation.distance}
    end
    return result
end
local function liveEligible(row,state,policy)
    local id,point=row.questID,row.destination
    local live=state.live and state.live[id]
    if row.blocked or not live or state.active[id]~=true or state.failed[id] or not positioned(point) or point.access==false then return false end
    if row.kind~=(live.objectivesComplete and "turnin" or "objective") then return false end
    if policy.skips[id] or policy.defers[id] or policy.avoids[point.mapID] then return false end
    if live.dungeon and not policy.dungeons or live.groupRequiredUnknown then return false end
    if live.requiredParty and live.requiredParty>1
        and (policy.group=="solo" or not state.partySize or state.partySize<live.requiredParty) then return false end
    if point.phase and point.phase~=state.phase or point.floor and state.floor and point.floor~=state.floor then return false end
    if policy.travel=="localOnly" and state.position and point.mapID~=state.position.mapID then return false end
    local prefix=id..":"..row.kind..":"
    for key,count in pairs(state.failures or {}) do
        if count>=2 and (key==id..":live:"..row.kind or key==id..":"..row.kind or key:sub(1,#prefix)==prefix) then return false end
    end
    return true
end
-- Missing source data on an active quest must not hide a closer feasible pickup.
-- Dimensions are captured with the decision so offline replay uses the same distance.
function recommendations.CloserPickup(action,row,state,policy,mapSize)
    if not action or action.kind~="pickup" or not row or policy.pins[row.questID]
        or not mapSize or not schema.Number(row.distance,0,1000000) then return false end
    if planner.PlanTransitions.Check(action,state,policy)~=true then return false end
    local frame={position=state.position,width=mapSize[1],height=mapSize[2]}
    local gap=distance(action.destination,state.position,frame)
    local localScore=math.max(0,row.distance-(row.kind=="turnin" and TURNIN_BONUS or 0))
    return gap~=nil and gap<localScore
end
-- An unobserved pickup must not pull the player away from closer, feasible
-- active work solely because a speculative future chain scored well.
function recommendations.UnconfirmedPickupChoice(action,rows,state,policy,mapSize)
    if not state or not state.fresh or not action or action.kind~="pickup"
        or action.availability~="source-suggestion" or policy.pins[action.questID] or not mapSize then return end
    local offer=(state.questOffers or {})[action.questID]
    if offer and offer.offered==true and action.target and action.target.kind=="npc"
        and offer.npcID==action.target.id then return end
    local frame={position=state.position,width=mapSize[1],height=mapSize[2]}
    local gap=distance(action.destination,state.position,frame)
    if not gap then return end
    for _,row in ipairs(rows or {}) do
        if liveEligible(row,state,policy) and row.destination.mapID==state.position.mapID
            and schema.Number(row.distance,0,1000000)
            and gap-row.distance>=math.max(SWITCH_DISTANCE,gap*SWITCH_FRACTION) then
            return row,{mode="unconfirmed-pickup",distance=row.distance,pickupQuestID=action.questID}
        end
    end
end
function recommendations.LocalChoice(rows,state,policy)
    if not state or not state.fresh then return end
    local chosen,missing=nil,{}
    for _,row in ipairs(rows or {}) do
        if liveEligible(row,state,policy) then
            local measured=state.position and row.destination.mapID==state.position.mapID
                and schema.Number(row.distance,0,1000000)
            if not chosen and (measured or policy.pins[row.questID]) then chosen=row end
            if measured and state.live[row.questID].hasPlanningRecord==false then missing[#missing+1]=row.questID end
        end
    end
    if chosen and #missing>0 then return chosen,{missing=missing,mode="proximity",distance=chosen.distance} end
end

