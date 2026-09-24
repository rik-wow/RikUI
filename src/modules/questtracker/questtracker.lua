-- Compact list of watched quests replacing the stock objective tracker. This file reads the quest
-- log, coalesces the client's bursts of quest events into one render, routes clicks and parks
-- ObjectiveTrackerFrame once the list exists; src/modules/questtracker/questtracker-blocks.lua draws it. The frames are
-- unprotected, so the list shows, hides and resizes in combat.
local core, layout = RikUI, RikUI.Layout
local tracker = { View = {} }
core.QuestTracker = tracker

local HOLDER_NAME, KEY = "RikUIQuestTracker", "questtracker"
local DEFAULTS = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -126, y = -260 }
local REFRESH_DELAY = 0.1
local REQUIRED = { "GetNumQuestWatches", "GetQuestIDForQuestWatchIndex", "GetLogIndexForQuestID", "IsComplete" }
local EVENTS = { "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "PLAYER_ENTERING_WORLD" }
local STOCK = "ObjectiveTrackerFrame"
local holder, warnings, pending, quests = nil, {}, false, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Quest tracker " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetParent) == "function"
end

local function available()
    if type(C_QuestLog) ~= "table" then return false end
    for _, name in ipairs(REQUIRED) do
        if type(C_QuestLog[name]) ~= "function" then return false end
    end
    return type(GetNumQuestLeaderBoards) == "function" and type(GetQuestLogLeaderBoard) == "function"
end

local function readObjectives(logIndex)
    local objectives = {}
    for index = 1, GetNumQuestLeaderBoards(logIndex) do
        local text, _, finished = GetQuestLogLeaderBoard(index, logIndex, true)
        if type(text) == "string" then objectives[#objectives + 1] = { text = text, finished = finished == true } end
    end
    return objectives
end

local function readInfo(questID, logIndex)
    local info = type(C_QuestLog.GetInfo) == "function" and C_QuestLog.GetInfo(logIndex) or nil
    if type(info) == "table" then return info.title, info.level end
    return type(C_QuestLog.GetTitleForQuestID) == "function" and C_QuestLog.GetTitleForQuestID(questID) or nil
end

local function readQuest(questID)
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if not logIndex then return nil end
    local title, level = readInfo(questID, logIndex)
    return {
        id = questID, title = type(title) == "string" and title or "?", level = type(level) == "number" and level or nil,
        complete = C_QuestLog.IsComplete(questID) == true,
        failed = type(C_QuestLog.IsFailed) == "function" and C_QuestLog.IsFailed(questID) == true,
        objectives = readObjectives(logIndex),
    }
end

local function readWatched()
    local list = {}
    for index = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
        local quest = questID and readQuest(questID) or nil
        if quest then list[#list + 1] = quest end
    end
    return list
end

local combatCollapsed
local function automaticCollapse()
    return core.Profile.questtracker.collapseInCombat == true and InCombatLockdown()
end

local function collapsed()
    if automaticCollapse() then
        if combatCollapsed ~= nil then return combatCollapsed end
        return true
    end
    return core.Profile.questtracker.collapsed == true
end

local function combatChanged()
    combatCollapsed = nil
    if holder then tracker.View.Render(holder, quests, collapsed()) end
end

-- A failed read keeps the last good list on screen.
function tracker.Refresh()
    pending = false
    if not holder then return end
    local ok, list = pcall(readWatched)
    if ok then quests = list else warn("read", list) end
    tracker.View.Render(holder, quests, collapsed())
end

-- room is how much further the list may grow; nil when the client reports no screen size.
function tracker.SetRoom(room)
    local limit = type(room) == "number" and holder and holder:GetHeight() + room or nil
    local view = tracker.View
    if limit == view.Limit or (limit and view.Limit and math.abs(limit - view.Limit) < 0.5) then return end
    view.Limit = limit
    view.Render(holder, quests, collapsed())
end

function tracker.Request()
    if pending or not holder then return end
    pending = true
    C_Timer.After(REFRESH_DELAY, tracker.Refresh)
end

function tracker.ToggleCollapsed()
    if automaticCollapse() then combatCollapsed = not collapsed()
    else core.Profile.questtracker.collapsed = not collapsed() end
    tracker.View.Render(holder, quests, collapsed(), not collapsed())
end

function tracker.Click(block)
    if IsShiftKeyDown() then
        if type(C_QuestLog.RemoveQuestWatch) == "function" then C_QuestLog.RemoveQuestWatch(block.questID) end
        return
    end
    if type(QuestMapFrame_OpenToQuestDetails) ~= "function" then return warn("open", "quest map unavailable") end
    local ok, reason = pcall(QuestMapFrame_OpenToQuestDetails, block.questID)
    if not ok then warn("open", reason) end
end

-- The tracker's events stay registered, so a restore after a reload-free toggle is current.
local function parkStock()
    local frame = _G[STOCK]
    if not isFrame(frame) then return end
    core.Tutorials.Acknowledge(LE_FRAME_TUTORIAL_HOW_TO_SUPERTRACK)
    core.Hide.Frame(frame, true)
end

local function build()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    tracker.View.Build(holder)
    -- The list grows downward; the arrangement system reports the room down to the next frame and the
    -- list caps itself there, so it can never grow into a neighbour.
    layout.Register(holder, KEY, DEFAULTS, { label = "Quest tracker", grow = "DOWN", onLimit = tracker.SetRoom })
    tracker.Holder = holder
    tracker.Refresh()
    parkStock()
end

function tracker:OnEnable()
    if not available() then return core:Print("Quest tracker unavailable: the quest log API is missing.") end
    core.Combat.Queue(build)
    for _, event in ipairs(EVENTS) do core:RegisterEvent(event, tracker.Request) end
    core:RegisterEvent("PLAYER_REGEN_DISABLED", combatChanged)
    core:RegisterEvent("PLAYER_REGEN_ENABLED", combatChanged)
end

function tracker:Debug()
    core:Print("Quest tracker holder=" .. tostring(holder ~= nil) .. " quests=" .. #quests
        .. " collapsed=" .. tostring(core.Profile ~= nil and collapsed()))
end

tracker.Options = { title = "Quest tracker", group = "Gameplay", settings = {
    { type = "checkbox", key = "collapseInCombat", label = "Collapse objectives in combat",
        description = "Keep the header visible. Click it to reveal quests temporarily; restore your preference after combat.",
        get = function() return core.Profile.questtracker.collapseInCombat == true end,
        set = function(value) core.Profile.questtracker.collapseInCombat = value == true; combatChanged() end },
} }

core:RegisterModule("questtracker", tracker)
