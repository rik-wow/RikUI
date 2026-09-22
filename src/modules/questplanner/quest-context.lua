-- Guarded live context. API observations describe this character at this time only.
local planner, guard = RikUI.QuestPlanner, RikUI.Secret
local schema, context = planner.Schema, {}
planner.Context = context
local MAX_QUERIES, MAX_NUMBER = 40, 2147483647
local function call(fn, ...)
    if guard.IsSecret(fn) or type(fn) ~= "function" then return false end
    return guard.Read(fn, ...)
end
context.Call = call

local function scalar(fn, valid, ...)
    local ok, value = call(fn, ...)
    if ok and valid(value) then return value end
end
local function number(value) return schema.Number(value, 0, MAX_NUMBER) end
local function boolean(value) return not guard.IsSecret(value) and type(value) == "boolean" end
local function api(namespace, name)
    if schema.PlainTable(namespace) then return namespace[name] end
end
local function tupleID(fn)
    local ok, _, _, value = call(fn, "player")
    if ok and schema.ID(value) then return value end
end

function context.Position()
    local mapID = scalar(api(C_Map, "GetBestMapForUnit"), schema.ID, "player")
    if not mapID then return nil end
    local ok, vector = call(api(C_Map, "GetPlayerMapPosition"), mapID, "player")
    if not ok or guard.IsSecret(vector) or vector == nil then return nil end
    local read, x, y = pcall(function()
        if type(vector.GetXY) ~= "function" then return nil end
        return vector:GetXY()
    end)
    if read and schema.Number(x, 0, 1) and schema.Number(y, 0, 1) then return {mapID=mapID,x=x,y=y} end
end

function context.WorldPosition()
    local ok,x,y,z,mapID=call(UnitPosition,"player")
    if not ok or not schema.Number(x,-100000,100000) or not schema.Number(y,-100000,100000)
        or not schema.Integer(mapID,0,100000) then return nil end
    -- The third return is not established as usable Forever altitude. Keep the
    -- raw field for acquisition; horizontal-only grounding must remain unique.
    local result={x=y,z=x,mapID=mapID,api="UnitPosition(player)",verticalStatus="unestablished"}
    if schema.Number(z,-100000,100000) then result.rawReportedZ=z end
    return result
end

function context.RunSpeed()
    local ok,_,value=call(GetUnitSpeed,"player")
    if ok and schema.Number(value,.1,100) then return value end
end


-- One compact observation per render tick; API reads stay in their explicit systems.
local frameSnapshot,mapSizes
function context.Frame(force)
    local now=scalar(GetTime,number)
    if not force and now and frameSnapshot and frameSnapshot.time==now then return frameSnapshot end
    local position=context.Position()
    if not mapSizes or not mapSizes.width or mapSizes.mapID~=(position and position.mapID) then
        mapSizes={mapID=position and position.mapID}
        local ok,w,h=call(api(C_Map,"GetMapWorldSize"),mapSizes.mapID)
        if ok and schema.Number(w,1,100000) and schema.Number(h,1,100000) then mapSizes.width,mapSizes.height=w,h end
    end
    frameSnapshot={time=now,position=position,world=context.WorldPosition(),speed=context.RunSpeed(),
        facing=scalar(GetPlayerFacing,function(v) return schema.Number(v,0,math.pi*2) end),
        width=mapSizes.width,height=mapSizes.height}
    return frameSnapshot
end

local function attributes()
    return {class=tupleID(UnitClass),race=tupleID(UnitRace),
        faction=scalar(UnitFactionGroup,schema.Text,"player"),
        level=scalar(UnitLevel,schema.ID,"player"),xp=scalar(UnitXP,number,"player"),
        xpMax=scalar(UnitXPMax,schema.ID,"player"),
        logCapacity=scalar(api(C_QuestLog,"GetMaxNumQuestsCanAccept"),function(v) return schema.Integer(v,1,256) end)}
end

local function status(state, apiName, reason)
    return {state=state,api=apiName,reason=reason}
end

local function read(apiName, fn, ...)
    if guard.IsSecret(fn) then return status("rejected",apiName,"secret-function") end
    if type(fn) ~= "function" then return status("unavailable",apiName,"api-missing") end
    local ok, a, b, c = call(fn, ...)
    if not ok then return status("unavailable",apiName,"read-failed") end
    if guard.IsSecret(a) or guard.IsSecret(b) or guard.IsSecret(c) then
        return status("rejected",apiName,"secret-result")
    end
    return status("observed",apiName),a,b,c
end

local function destination(id)
    local apiName="C_QuestLog.GetNextWaypoint"
    local observed,mapID,x,y=read(apiName,api(C_QuestLog,"GetNextWaypoint"),id)
    if observed.state~="observed" then return nil,observed end
    if mapID==nil and x==nil and y==nil then
        return nil,status("no-result",apiName,"no-waypoint-returned")
    end
    if not schema.ID(mapID) or not schema.Number(x,0,1) or not schema.Number(y,0,1) then
        return nil,status("rejected",apiName,"invalid-waypoint")
    end
    return {mapID=mapID,x=x,y=y,api=apiName,scope="current-waypoint",
        text=scalar(api(C_QuestLog,"GetNextWaypointText"),schema.Text,id)},observed
end

local function queryIDs(snapshot, pins)
    local ids, seen = {}, {}
    for _, id in ipairs(snapshot.order) do if pins and pins[id] then ids[#ids+1]=id; seen[id]=true end end
    table.sort(ids)
    for _, id in ipairs(snapshot.order) do if not seen[id] then ids[#ids+1]=id end end
    return ids
end

-- GetQuestsOnMap coordinates are placed on the queried map by Blizzard's
-- QuestDataProvider. We additionally require an exact row map match and no child
-- depth, start flag or map-indicator flag before exposing a navigation target.
local function mapPOIs(snapshot, mapID)
    local apiName="C_QuestLog.GetQuestsOnMap"
    if not schema.ID(mapID) then return {},status("unavailable",apiName,"current-map-unavailable") end
    local observed,rows=read(apiName,api(C_QuestLog,"GetQuestsOnMap"),mapID)
    observed.mapID=mapID
    if observed.state~="observed" then return {},observed end
    if rows==nil then
        observed.state,observed.reason="no-result","no-map-result"
        return {},observed
    end
    local valid,count=schema.List(rows,256)
    if not valid then return {},status("rejected",apiName,"invalid-or-oversized-map-list") end
    observed.rows=count
    if count==0 then
        observed.state,observed.reason="no-result","empty-map-list"
        return {},observed
    end
    local matches={}
    for index=1,count do
        local row=rows[index]
        if not schema.PlainTable(row) or not schema.ID(row.questID) then
            return {},status("rejected",apiName,"invalid-map-row")
        end
        if snapshot.quests[row.questID] then
            local match=matches[row.questID]
            if match then
                match.count=match.count+1
                match.point=nil
                match.status=status("ambiguous",apiName,"multiple-active-quest-pois")
            else
                match={count=1}
                matches[row.questID]=match
                local depthKnown=not guard.IsSecret(row.childDepth)
                    and (row.childDepth==nil or schema.Integer(row.childDepth,0,256))
                if not schema.ID(row.mapID) or not schema.Number(row.x,0,1) or not schema.Number(row.y,0,1)
                    or not boolean(row.isQuestStart) or not boolean(row.isMapIndicatorQuest)
                    or not boolean(row.inProgress) or not depthKnown then
                    match.status=status("rejected",apiName,"invalid-active-quest-poi")
                elseif row.mapID~=mapID or (row.childDepth~=nil and row.childDepth~=0)
                    or row.isQuestStart or row.isMapIndicatorQuest then
                    match.status=status("rejected",apiName,"unsupported-poi-scope")
                else
                    match.point={mapID=mapID,x=row.x,y=row.y,sourceMapID=row.mapID,
                        api=apiName,scope="current-map-quest-poi",isQuestStart=false,
                        isMapIndicatorQuest=false,inProgress=row.inProgress,childDepth=row.childDepth}
                    match.status=status("observed",apiName)
                end
            end
        end
    end
    return matches,observed
end

local function rewards(result,snapshot,ids)
    local selectionAPI="C_QuestLog.GetSelectedQuest"
    local selectedStatus,selected=read(selectionAPI,api(C_QuestLog,"GetSelectedQuest"))
    local default=status("no-result","GetQuestLogRewardXP(selected)","quest-not-selected")
    if selectedStatus.state~="observed" then
        default=selectedStatus
    elseif selected==nil or selected==0 then
        default=status("no-result",selectionAPI,"no-selected-active-quest")
    elseif not schema.ID(selected) then
        default=status("rejected",selectionAPI,"invalid-selected-quest")
    elseif not snapshot.quests[selected] then
        default=status("no-result",selectionAPI,"selected-quest-not-in-observed-log")
    end
    for _,id in ipairs(ids) do result.rewardStatus[id]=schema.Clone(default) end
    if selectedStatus.state~="observed" or not schema.ID(selected) or not snapshot.quests[selected] then return end
    local xpStatus,xp=read("GetQuestLogRewardXP(selected)",GetQuestLogRewardXP)
    if xpStatus.state=="observed" then
        if xp==nil then
            xpStatus.state,xpStatus.reason="no-result","no-xp-returned"
        elseif not number(xp) then
            xpStatus.state,xpStatus.reason="rejected","invalid-xp"
        end
    end
    local afterStatus,after=read(selectionAPI,api(C_QuestLog,"GetSelectedQuest"))
    if afterStatus.state~="observed" or not schema.ID(after) or after~=selected then
        xpStatus=status("rejected","GetQuestLogRewardXP(selected)","selection-changed-or-unavailable")
    end
    result.rewardStatus[selected]=xpStatus
    if xpStatus.state=="observed" then
        result.rewards[selected]={xp=xp,level=result.attributes.level,api="GetQuestLogRewardXP(selected)",scope="character-level"}
    end
end

function context.Read(snapshot, pins)
    if not snapshot or not schema.Identity(snapshot.identity) then return nil end
    local position=context.Position()
    local result={identity=schema.Clone(snapshot.identity),attributes=attributes(),position=position,
        worldPosition=context.WorldPosition(),runSpeed=context.RunSpeed(),destinations={},history={},rewards={},
        targetStatus={},rewardStatus={},source="client-api-session-v1",origin="live",
        observedAt=scalar(GetTime,number),queries=0}
    local ids=queryIDs(snapshot,pins)
    local pois,mapStatus=mapPOIs(snapshot,position and position.mapID)
    result.mapPOIStatus=mapStatus
    for index,id in ipairs(ids) do
        if index>MAX_QUERIES then
            result.targetStatus[id]=status("query-limited","quest-context","quest-query-budget")
        else
            local point,waypointStatus=destination(id)
            local targetStatus=waypointStatus
            if not point then
                local match=pois[id]
                if match then
                    point,targetStatus=match.point,schema.Clone(match.status)
                elseif mapStatus.state=="observed" then
                    targetStatus=status("no-result","C_QuestLog.GetQuestsOnMap","quest-not-in-map-result")
                else
                    targetStatus=schema.Clone(mapStatus)
                end
                targetStatus.waypointState,targetStatus.waypointReason=waypointStatus.state,waypointStatus.reason
            end
            result.destinations[id],result.targetStatus[id]=point,targetStatus
            result.history[id]=scalar(api(C_QuestLog,"IsQuestFlaggedCompleted"),boolean,id)
            result.queries=result.queries+1
        end
    end
    result.queryLimited=#ids>MAX_QUERIES
    -- Read selected XP only; never change selection or assume an explicit-ID overload.
    rewards(result,snapshot,ids)
    return result
end

function context.Dialog(event)
    if event~="QUEST_DETAIL" and event~="QUEST_PROGRESS" and event~="QUEST_COMPLETE" then return nil end
    local id=scalar(GetQuestID,schema.ID)
    if not id then return nil end
    local value={questID=id,event=event,title=scalar(GetTitleText,schema.Text),
        position=context.Position(),observedAt=scalar(GetTime,number),
        level=scalar(UnitLevel,schema.ID,"player"),source="client-quest-dialog-v1"}
    local guid=scalar(UnitGUID,schema.Text,"npc")
    if guid then value.npcID=tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) end
    if event=="QUEST_COMPLETE" then value.xp=scalar(GetRewardXP,number) end
    return value
end

function context.History(ids)
    if not schema.List(ids,256) then return nil end
    local result={}
    for _,id in ipairs(ids) do
        if not schema.ID(id) then return nil end
        result[id]=scalar(api(C_QuestLog,"IsQuestFlaggedCompleted"),boolean,id)
    end
    return result
end
