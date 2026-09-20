-- Longer scrollback, and the last lines of every chat window brought back after a reload or relog.
-- Lines are saved per character at logout and only when they are readable strings. SetMaxLines
-- clears a window, so scrollback is raised before anything is restored. Restored lines go through
-- Blizzard's own AddMessage, past the tag wrapper and the unread counter, dimmed and followed by a
-- separator. Saved entries keep their original colours in memory so a second reload does not dim
-- them twice. The combat log window is left alone.
local core = RikUI
local chat = core.Chat

local MAX_LINES, KEEP, DIM, COMBAT_LOG_ID = 1000, 200, 0.6, 2
local SEPARATOR, SEPARATOR_COLOR = "- earlier messages -", { 0.5, 0.5, 0.5 }
local restored = {}

local function usable(value)
    return not core.Secret.IsSecret(value) and type(value) == "string"
end

local function channel(value)
    return not core.Secret.IsSecret(value) and type(value) == "number" and value or 1
end

local function enabled() return chat.Settings().history ~= false end

local function kept(frame)
    return type(frame.GetID) == "function" and frame:GetID() ~= COMBAT_LOG_ID
end

local function raiseScrollback(frame)
    if type(frame.GetMaxLines) ~= "function" or type(frame.SetMaxLines) ~= "function" then return end
    local current = frame:GetMaxLines()
    if type(current) == "number" and current < MAX_LINES then frame:SetMaxLines(MAX_LINES) end
end

local function restore(frame)
    local store = core.CharDB.chatHistory
    local lines = type(store) == "table" and store[frame:GetID()] or nil
    if type(lines) ~= "table" or #lines == 0 then return end
    local add = chat.RawAddMessage and chat.RawAddMessage(frame) or frame.AddMessage
    for _, line in ipairs(lines) do
        if usable(line.text) then add(frame, line.text, channel(line.r) * DIM, channel(line.g) * DIM, channel(line.b) * DIM) end
    end
    add(frame, SEPARATOR, unpack(SEPARATOR_COLOR))
    restored[frame] = lines
end

-- Lines that arrived this session: everything after the restored block and its separator. A full
-- window has scrolled the restored block out, and a cleared one has nothing of it left.
local function firstNewIndex(frame, total)
    local old = restored[frame]
    if not old or total >= MAX_LINES or total < #old + 1 then return 1, nil end
    return #old + 2, old
end

local function collect(frame)
    local total = frame:GetNumMessages()
    local first, old = firstNewIndex(frame, total)
    local lines = {}
    for _, line in ipairs(old or {}) do lines[#lines + 1] = line end
    for index = first, total do
        local text, r, g, b = frame:GetMessageInfo(index)
        if usable(text) then lines[#lines + 1] = { text = text, r = channel(r), g = channel(g), b = channel(b) } end
    end
    local recent = {}
    for index = math.max(1, #lines - KEEP + 1), #lines do recent[#recent + 1] = lines[index] end
    return recent
end

local function save()
    if not enabled() then core.CharDB.chatHistory = nil; return end
    local store = {}
    for frame in pairs(chat.Frames) do
        if kept(frame) then
            local ok, lines = pcall(collect, frame)
            if ok and #lines > 0 then store[frame:GetID()] = lines elseif not ok then chat.Warn("history", lines) end
        end
    end
    core.CharDB.chatHistory = store
end

function chat.SetHistory(value)
    chat.Settings().history = value == true
    if value ~= true then core.CharDB.chatHistory = nil end
    return true
end

function chat.EnableHistory()
    for frame in pairs(chat.Frames) do
        if kept(frame) then
            raiseScrollback(frame)
            if enabled() then restore(frame) end
        end
    end
    core:RegisterEvent("PLAYER_LOGOUT", save)
end

table.insert(chat.Options.settings, { type = "checkbox", key = "history", label = "Restore chat after a reload",
    get = enabled, set = chat.SetHistory })
