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

local function readyFirst(list)
    if not core.Profile.questtracker.readyFirst then return list end
    local result = {}
    for _, quest in ipairs(list) do
        if quest.complete and not quest.failed then result[#result + 1] = quest end
    end
    for _, quest in ipairs(list) do
        if not quest.complete or quest.failed then result[#result + 1] = quest end
    end
    return result
end

local function validQuestID(id)
    return not core.Secret.IsSecret(id) and type(id) == "number"
        and id > 0 and id <= 1000000000 and id % 1 == 0
end

function tracker.IsPinned(id)
    if not validQuestID(id) then return false end
    local source = core.Profile.questtracker.pins or ""
    return ("," .. source .. ","):find("," .. id .. ",", 1, true) ~= nil
end

function tracker.TogglePin(id)
    if not validQuestID(id) then return end
    local pinned, ids = tracker.IsPinned(id), {}
    for token in (core.Profile.questtracker.pins or ""):gmatch("%d+") do
        if tonumber(token) ~= id then ids[#ids + 1] = token end
    end
    if not pinned and #ids >= 50 then core:Print("Keep at most 50 pinned quests."); return end
    if not pinned then ids[#ids + 1] = tostring(id) end
    core.Profile.questtracker.pins = table.concat(ids, ",")
    core:Changed()
    tracker.Refresh()
end

local function pinnedFirst(list)
    local result = {}
    for _, quest in ipairs(list) do
        quest.pinned = tracker.IsPinned(quest.id)
        if quest.pinned then result[#result + 1] = quest end
    end
    for _, quest in ipairs(list) do
        if not quest.pinned then result[#result + 1] = quest end
    end
    return result
end

local function readWatched()
    local list = {}
    for index = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
        local quest = questID and readQuest(questID) or nil
        if quest then list[#list + 1] = quest end
    end
    return pinnedFirst(readyFirst(list))
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
        if validQuestID(block.questID) then core.Combat.Cancel("questtracker:watch:" .. block.questID) end
        if type(C_QuestLog.RemoveQuestWatch) == "function" then C_QuestLog.RemoveQuestWatch(block.questID) end
        return
    end
    if type(IsControlKeyDown) == "function" then
        local ok, pressed = pcall(IsControlKeyDown)
        if ok and not core.Secret.IsSecret(pressed) and pressed == true then tracker.TogglePin(block.questID); return end
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
    layout.Register(holder, KEY, DEFAULTS, { label = "Quest tracker", grow = "DOWN", onLimit = tracker.SetRoom,
        onApply = tracker.Refresh })
    tracker.Holder = holder
    tracker.Refresh()
    parkStock()
end

local function watchAccepted(_, first, second)
    if core.Secret.IsSecret(second) then return end
    local questID = second ~= nil and second or first
    if core.Profile.questtracker.autoWatch ~= true or not validQuestID(questID) then return end
    local profile = core.Profile
    core.Combat.Queue(function()
        if core.Profile ~= profile or profile.questtracker.autoWatch ~= true then return end
        if type(C_QuestLog.AddQuestWatch) ~= "function" then
            warn("auto watch", "automatic tracking unavailable"); return
        end
        local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
        if not ok or not validQuestID(index) then return end
        local added, result = pcall(C_QuestLog.AddQuestWatch, questID)
        if not added or core.Secret.IsSecret(result) or result ~= true then
            warn("auto watch", "Client could not track the accepted quest; use the quest log.")
        end
        tracker.Request()
    end, "questtracker:watch:" .. questID)
end

function tracker:OnEnable()
    if not available() then return core:Print("Quest tracker unavailable: the quest log API is missing.") end
    core.Combat.Queue(build)
    for _, event in ipairs(EVENTS) do core:RegisterEvent(event, tracker.Request) end
    core:RegisterEvent("QUEST_ACCEPTED", watchAccepted)
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
    { type = "checkbox", key = "hideCompleted", label = "Hide completed objectives",
        description = "Keep unfinished steps in the list. Hover a quest to see every objective.",
        get = function() return core.Profile.questtracker.hideCompleted == true end,
        set = function(value) core.Profile.questtracker.hideCompleted = value == true; tracker.Refresh() end },
    { type = "slider", key = "maxVisible", label = "Maximum visible quests (0 = all)",
        description = "Keep the tracker short without untracking quests. Pinned quests appear first; hidden quests remain in the quest log.",
        min = 0, max = 25, step = 1,
        get = function() return core.Profile.questtracker.maxVisible end,
        set = function(value)
            if type(value) ~= "number" or value ~= value or value < 0 or value > 25 or value % 1 ~= 0 then return end
            core.Profile.questtracker.maxVisible = value
            tracker.Refresh()
        end },
    { type = "checkbox", key = "autoWatch", label = "Track newly accepted quests",
        description = "Add accepted quests to the native watch list. Existing quests and manual untracking are unchanged.",
        get = function() return core.Profile.questtracker.autoWatch == true end,
        set = function(value) core.Profile.questtracker.autoWatch = value == true end },
    { type = "checkbox", key = "readyFirst", label = "Ready quests first",
        description = "Show turn-ins at the top. Keep the original watch order within each group.",
        get = function() return core.Profile.questtracker.readyFirst == true end,
        set = function(value) core.Profile.questtracker.readyFirst = value == true; tracker.Refresh() end },
} }

core:RegisterModule("questtracker", tracker)
