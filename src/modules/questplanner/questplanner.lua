-- Session-only quest observations. The catalogue and future optimizer remain separate consumers.
local core, planner = RikUI, RikUI.QuestPlanner
local schema = planner.Schema
local REFRESH_DELAY = 0.1
local EVENTS = { "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }
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
        return
    end
    generation = generation + 1
    nextSnapshot.generation = generation
    snapshot = nextSnapshot
    local partial = snapshot.coverage ~= "log-complete" or snapshot.hasUnknown
    status = { state = partial and "partial" or "current" }
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
    core:Print("Session only. Current character log; world coverage, prerequisites, XP and routes are not established.")
end

function planner:OnEnable()
    started = true
    core:RegisterCommand("quests", function() planner:Debug() end, "Inspect current quest observations")
    for _, event in ipairs(EVENTS) do core:RegisterEvent(event, planner.Request) end
    planner.Request()
end

core:RegisterModule("questplanner", planner)
