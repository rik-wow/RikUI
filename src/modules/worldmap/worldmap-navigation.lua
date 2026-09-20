-- Readable quest snapshots and guarded navigation; native providers own pins.
local core, map = RikUI, RikUI.WorldMap
local nav = {}
map.Navigation = nav
local function readable(value, kind) return not core.Secret.IsSecret(value) and type(value) == kind end
local function number(value)
    return readable(value, "number") and value == value and value > -math.huge and value < math.huge
end
function nav.Call(reader, ...)
    if type(reader) ~= "function" then return nil end
    local ok, value = pcall(reader, ...)
    if ok and not core.Secret.IsSecret(value) then return value end
end
local function coordinate(value) return number(value) and value >= 0 and value <= 1 end
local function locations(mapID)
    local result = {}
    local list = C_QuestLog and nav.Call(C_QuestLog.GetQuestsOnMap, mapID)
    if not readable(list, "table") then return result end
    for _, info in ipairs(list) do
        if readable(info, "table") and number(info.questID) and coordinate(info.x) and coordinate(info.y) then
            result[info.questID] = { x = info.x, y = info.y }
        end
    end
    return result
end
local function quest(info, points)
    if not readable(info, "table") or not number(info.questID) or info.questID <= 0
        or not readable(info.title, "string") or core.Secret.IsSecret(info.isHeader) or info.isHeader then return end
    local id, point = info.questID, points[info.questID]
    return { id = id, title = info.title, point = point,
        location = point and string.format("%.1f, %.1f", point.x * 100, point.y * 100) or "Location unavailable on this map",
        complete = nav.Call(C_QuestLog.IsComplete, id) == true,
        watched = nav.Call(C_QuestLog.GetQuestWatchType, id) ~= nil }
end
function nav.Quests(mapID, zoneOnly)
    if not number(mapID) or not C_QuestLog then return {}, "Quest locations unavailable" end
    local count = nav.Call(C_QuestLog.GetNumQuestLogEntries)
    if not number(count) then return {}, "Quest log unavailable" end
    local points, rows = locations(mapID), {}
    for index = 1, math.min(count, 500) do
        local row = quest(nav.Call(C_QuestLog.GetInfo, index), points)
        if row and (not zoneOnly or row.point) then rows[#rows + 1] = row end
    end
    table.sort(rows, function(a, b)
        if a.complete ~= b.complete then return a.complete end
        if a.watched ~= b.watched then return a.watched end
        if a.title ~= b.title then return a.title < b.title end
        return a.id < b.id
    end)
    return rows, #rows == 0 and (zoneOnly and "No locations here. Try All quests." or "Your quest log is empty.") or nil
end
function nav.Run(action)
    if InCombatLockdown() then core:Print("World map: this action is available after combat."); return false end
    local ok, reason = pcall(action)
    if not ok then core:Print("World map: " .. tostring(reason)) end
    return ok
end
function nav.Player(frame)
    return nav.Run(function()
        local id = C_Map and nav.Call(C_Map.GetBestMapForUnit, "player")
        if not number(id) or id <= 0 then error("Player location unavailable.", 0) end
        frame:SetMapID(id)
    end)
end
function nav.Parent(frame)
    return nav.Run(function()
        local id = nav.Call(frame.GetMapID, frame)
        local info = C_Map and nav.Call(C_Map.GetMapInfo, id)
        if not readable(info, "table") or not number(info.parentMapID) or info.parentMapID <= 0 then return end
        frame:SetMapID(info.parentMapID)
    end)
end
function nav.Select(row)
    return nav.Run(function()
        if type(QuestMapFrame_OpenToQuestDetails) ~= "function" then error("Quest details unavailable.", 0) end
        if C_SuperTrack and type(C_SuperTrack.SetSuperTrackedQuestID) == "function" then
            C_SuperTrack.SetSuperTrackedQuestID(row.id)
        end
        QuestMapFrame_OpenToQuestDetails(row.id)
    end)
end
function nav.Watch(row)
    return nav.Run(function()
        local api = C_QuestLog and (row.watched and C_QuestLog.RemoveQuestWatch or C_QuestLog.AddQuestWatch)
        if type(api) ~= "function" then error("Quest tracking unavailable.", 0) end
        api(row.id)
    end)
end
function nav.Markers()
    return nav.Call(C_CVar and C_CVar.GetCVarBool or GetCVarBool, "questPOI")
end
function nav.ToggleMarkers()
    return nav.Run(function()
        local current, setter = nav.Markers(), C_CVar and C_CVar.SetCVar or SetCVar
        if type(current) ~= "boolean" or type(setter) ~= "function" then error("Quest markers unavailable.", 0) end
        setter("questPOI", current and "0" or "1")
    end)
end
function nav.Coordinates(frame)
    local id = nav.Call(frame.GetMapID, frame)
    if not number(id) or not C_Map then return "Player: --" end
    local point = nav.Call(C_Map.GetPlayerMapPosition, id, "player")
    if not point or type(point.GetXY) ~= "function" then return "Player: --" end
    local ok, x, y = pcall(point.GetXY, point)
    if not ok or not coordinate(x) or not coordinate(y) then return "Player: --" end
    return string.format("Player: %.1f, %.1f", x * 100, y * 100)
end
