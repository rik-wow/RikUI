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

local function attributes()
    return {class=tupleID(UnitClass),race=tupleID(UnitRace),
        faction=scalar(UnitFactionGroup,schema.Text,"player"),
        level=scalar(UnitLevel,schema.ID,"player"),xp=scalar(UnitXP,number,"player"),
        xpMax=scalar(UnitXPMax,schema.ID,"player"),
        logCapacity=scalar(api(C_QuestLog,"GetMaxNumQuestsCanAccept"),function(v) return schema.Integer(v,1,256) end)}
end

local function destination(id)
    local ok, mapID, x, y = call(api(C_QuestLog,"GetNextWaypoint"),id)
    if not ok or not schema.ID(mapID) or not schema.Number(x,0,1) or not schema.Number(y,0,1) then return nil end
    return {mapID=mapID,x=x,y=y,api="C_QuestLog.GetNextWaypoint",scope="current-waypoint",
        text=scalar(api(C_QuestLog,"GetNextWaypointText"),schema.Text,id)}
end

local function queryIDs(snapshot, pins)
    local ids, seen = {}, {}
    for _, id in ipairs(snapshot.order) do if pins and pins[id] then ids[#ids+1]=id; seen[id]=true end end
    table.sort(ids)
    for _, id in ipairs(snapshot.order) do if not seen[id] then ids[#ids+1]=id end end
    return ids
end

function context.Read(snapshot, pins)
    if not snapshot or not schema.Identity(snapshot.identity) then return nil end
    local result = {identity=schema.Clone(snapshot.identity),attributes=attributes(),position=context.Position(),
        destinations={},history={},rewards={},source="client-api-session-v1",origin="live",
        observedAt=scalar(GetTime,number),queries=0}
    local ids = queryIDs(snapshot,pins)
    for index=1,math.min(#ids,MAX_QUERIES) do
        local id=ids[index]
        result.destinations[id]=destination(id)
        result.history[id]=scalar(api(C_QuestLog,"IsQuestFlaggedCompleted"),boolean,id)
        result.queries=result.queries+1
    end
    result.queryLimited=#ids>MAX_QUERIES
    -- No selection mutation and no assumption that an explicit-ID XP overload works.
    local selected=scalar(api(C_QuestLog,"GetSelectedQuest"),schema.ID)
    if selected and snapshot.quests[selected] then
        local xp=scalar(GetQuestLogRewardXP,number)
        local after=scalar(api(C_QuestLog,"GetSelectedQuest"),schema.ID)
        if after==selected and xp~=nil then
            result.rewards[selected]={xp=xp,level=result.attributes.level,api="GetQuestLogRewardXP(selected)",scope="character-level"}
        end
    end
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
