-- Session-only quest observations feed the separate acquisition and planning services.
local core, planner = RikUI, RikUI.QuestPlanner
local schema = planner.Schema
local REFRESH_DELAY = 0.1
local EVENTS = { "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
    "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "GOSSIP_CLOSED",
    "QUEST_POI_UPDATE", "WAYPOINT_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "ZONE_CHANGED_NEW_AREA" }
local lastReason = "current quests"
local snapshot, pending, started = nil, false, false
local status = { state = "unavailable", reason = "not observed" }
local generation = 0

function planner.GetSnapshot()
    return schema.Clone(snapshot), schema.Clone(status)
end

function planner.Refresh()
    pending = false
    if not started or not planner.enabled then return end
    local nextSnapshot, reason = planner.Reader.Read()
    if not nextSnapshot then
        status = { state = snapshot and "stale" or "unavailable", reason = reason }
        if planner.Controller then planner.Controller.Update(snapshot,status,lastReason) end
        return
    end
    generation = generation + 1
    nextSnapshot.generation = generation
    snapshot = nextSnapshot
    local partial = snapshot.coverage ~= "log-complete" or snapshot.hasUnknown
    status = { state = partial and "partial" or "current" }
    if planner.Controller then planner.Controller.Update(snapshot,status,lastReason) end
end

function planner.Request()
    if not started or not planner.enabled or pending then return end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        status = { state = snapshot and "stale" or "unavailable", reason = "refresh timer unavailable" }
        return
    end
    pending = true
    local ok = pcall(C_Timer.After, REFRESH_DELAY, planner.Refresh)
    if not ok then
        pending = false
        status = { state = snapshot and "stale" or "unavailable", reason = "refresh scheduling failed" }
    end
end

function planner:Debug()
    local build = snapshot and snapshot.identity.build or "unknown"
    local observed = snapshot and snapshot.observedCount or 0
    local reported = snapshot and snapshot.reportedCount or 0
    local coverage = snapshot and snapshot.coverage or "unknown"
    core:Print("Quest observations build=" .. build .. " locale=" .. (snapshot and snapshot.identity.locale or "unknown") .. " state=" .. status.state
        .. " log=" .. observed .. "/" .. reported .. " coverage=" .. coverage)
    if status.reason then core:Print("Quest observations: " .. status.reason) end
    core:Print("Session-only log observations. /rik quests show opens guidance and its current uncertainty.")
end

local function onEvent(event,...)
    if planner.Journal then planner.Journal.Record(event,snapshot,...) end
    if planner.Controller and event~="QUEST_LOG_UPDATE" and event~="QUEST_POI_UPDATE" and event~="WAYPOINT_UPDATE" then
        planner.Controller.Invalidate()
    end
    lastReason=event=="PLAYER_LEVEL_UP" and "your level changed" or event=="QUEST_TURNED_IN" and "quest turned in"
        or event=="QUEST_ACCEPTED" and "quest accepted" or event=="ZONE_CHANGED_NEW_AREA" and "zone changed" or "quest state changed"
    planner.Request()
end

function planner:OnEnable()
    started = true
    if planner.Controller then planner.Controller.Start() end
    core:RegisterCommand("quests", function(args)
        if planner.Command then planner.Command(args) else planner:Debug() end
    end, "Quest planner: show, pin, skip, avoid, pause, map, export")
    if planner.Terrain then planner.Terrain.Start() end
    if planner.Navigation then planner.Navigation.Start() end
    for _, event in ipairs(EVENTS) do core:RegisterEvent(event, onEvent) end
    planner.Request()
end

core:RegisterModule("questplanner", planner)
