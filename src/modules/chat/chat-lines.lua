-- What a chat line looks like. Each feature uses the narrowest hook 69913 offers:
--   class colours  the client's chatClassColorOverride setting; no code on the message path
--   mentions       a message filter; Blizzard runs filters through securecallfunction and never
--   repeats        hands them a secret argument
--   short tags     an AddMessage wrapper per window. The tag is composed after the filters run and
--                  only exists in the final text, and a shorter channel argument would make the
--                  handler drop the line. The event name arrives as AddMessage's eighth argument.
-- The wrapper is the one piece that replaces a Blizzard method, so it is only installed while short
-- tags are on; once installed it stays until a reload and passes text through when switched off.
local core = RikUI
local chat = core.Chat

local CLASS_CVAR, CLASS_ON = "chatClassColorOverride", "0"
local TAGS = { CHAT_MSG_GUILD = "G", CHAT_MSG_OFFICER = "O", CHAT_MSG_PARTY = "P", CHAT_MSG_PARTY_LEADER = "PL",
    CHAT_MSG_RAID = "R", CHAT_MSG_RAID_LEADER = "RL", CHAT_MSG_RAID_WARNING = "RW", CHAT_MSG_INSTANCE_CHAT = "I",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "IL" }
local CHANNEL_EVENT = "CHAT_MSG_CHANNEL"
local GROUP_TAG, NUMBERED_TAG = "(|Hchannel:[^|]-|h)%[[^%]]-%](|h)", "(|Hchannel:channel:(%d+)|h)%[[^%]]-%](|h)"
local MENTION_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_CHANNEL" }
-- Blizzard already plays its own sound for these.
local SILENT_EVENTS = { CHAT_MSG_WHISPER = true, CHAT_MSG_BN_WHISPER = true }
local REPEAT_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" }
local HIGHLIGHT, RESET = "|cffffd24d", "|r"
local SOUND_COOLDOWN, REPEAT_WINDOW, REPEAT_LIMIT = 5, 10, 200
-- Position of the line id among the filter arguments that follow the message and the sender.
local LINE_ID_AFTER_SENDER = 9
local originals, recent, recentCount = {}, {}, 0
local mentionPattern, lastSound, lastSoundLine = nil, nil, nil

local function usable(value)
    return not core.Secret.IsSecret(value) and type(value) == "string"
end

local function readCVar(name)
    if type(C_CVar) ~= "table" or type(C_CVar.GetCVar) ~= "function" then return nil end
    local ok, value = pcall(C_CVar.GetCVar, name)
    return ok and type(value) == "string" and value or nil
end

local function writeCVar(name, value)
    local ok, accepted = pcall(C_CVar.SetCVar, name, value)
    if not ok or accepted == false then chat.Warn("class colours", ok and "setting rejected" or accepted) end
end

-- Off only undoes our own write: a player who already had class colours on keeps them.
function chat.ApplyClassColors()
    local settings, current = chat.Settings(), readCVar(CLASS_CVAR)
    if current == nil or type(C_CVar.SetCVar) ~= "function" then
        chat.Warn("class colours", CLASS_CVAR .. " unavailable on this client")
        return
    end
    if settings.classColors ~= false then
        if current == CLASS_ON then return end
        settings.classColorsBefore = current
        writeCVar(CLASS_CVAR, CLASS_ON)
    elseif current == CLASS_ON and type(settings.classColorsBefore) == "string" then
        writeCVar(CLASS_CVAR, settings.classColorsBefore)
        settings.classColorsBefore = nil
    end
end

function chat.ShortenTag(text, event)
    if event == CHANNEL_EVENT then return (text:gsub(NUMBERED_TAG, "%1[%2]%3", 1)) end
    local tag = TAGS[event]
    if not tag then return text end
    return (text:gsub(GROUP_TAG, "%1[" .. tag .. "]%2", 1))
end

local function shortened(text, event)
    if chat.Settings().shortTags == false or not usable(text) or not usable(event) then return text end
    local ok, short = pcall(chat.ShortenTag, text, event)
    return ok and short or text
end

local function wrap(frame)
    if originals[frame] or type(frame.AddMessage) ~= "function" then return end
    local original = frame.AddMessage
    originals[frame] = original
    frame.AddMessage = function(self, text, r, g, b, id, accessID, typeID, event, ...)
        return original(self, shortened(text, event), r, g, b, id, accessID, typeID, event, ...)
    end
end

-- Blizzard's own AddMessage for a window, for callers that must not go through the wrapper.
function chat.RawAddMessage(frame) return originals[frame] or frame.AddMessage end

local function applyShortTags()
    if chat.Settings().shortTags == false then return end
    for frame in pairs(chat.Frames) do wrap(frame) end
end

local function playerName()
    local ok, name = pcall(UnitName, "player")
    return ok and usable(name) and name ~= "" and name or nil
end

-- One character class per letter, so "probey" and "PROBEY" both match; other bytes match themselves.
local function caseless(name)
    return (name:gsub(".", function(char)
        if char:match("%a") then return "[" .. char:lower() .. char:upper() .. "]" end
        return char:gsub("%p", "%%%0")
    end))
end

function chat.PhraseList(value)
    local phrases = {}
    if not usable(value) or #value > 256 or value:find("[%c|]") then return phrases end
    for phrase in value:gmatch("[^,]+") do
        phrase = phrase:match("^%s*(.-)%s*$")
        if phrase ~= "" and #phrases < 16 then phrases[#phrases + 1] = phrase:lower() end
    end
    return phrases
end

function chat.PhraseSetting(key, label, description)
    return { type = "text", key = key, label = label, description = description,
        get = function() return chat.Settings()[key] or "" end,
        set = function(value)
            if not usable(value) or #value > 256 or value:find("[%c|]") then
                return nil, "Use at most 256 characters without markup or control characters."
            end
            local count = 0
            for _ in value:gmatch("[^,]+") do count = count + 1 end
            if count > 16 then return nil, "Use at most 16 comma-separated phrases." end
            chat.Settings()[key] = value
            return true
        end }
end

local function markPlain(text, phrases)
    local lower, parts, position, count = text:lower(), {}, 1, 0
    while position <= #text do
        local first, last
        if mentionPattern then first, last = text:find(mentionPattern, position) end
        for _, phrase in ipairs(phrases) do
            local start, stop = lower:find(phrase, position, true)
            if start and (not first or start < first or start == first and stop > last) then first, last = start, stop end
        end
        if not first then parts[#parts + 1] = text:sub(position); break end
        parts[#parts + 1] = text:sub(position, first - 1) .. HIGHLIGHT .. text:sub(first, last) .. RESET
        position, count = last + 1, count + 1
    end
    return table.concat(parts), count
end

local function markWithoutMarkup(text, phrases)
    local parts, position, count = {}, 1, 0
    while position <= #text do
        local pipe = text:find("|", position, true)
        local marked, hits = markPlain(text:sub(position, pipe and pipe - 1 or #text), phrases)
        parts[#parts + 1], count = marked, count + hits
        if not pipe then break end
        local tail = text:sub(pipe)
        local token = tail:match("^|c%x%x%x%x%x%x%x%x") or tail:match("^|T.-|t")
            or tail:match("^|A.-|a") or tail:match("^|[rR]") or tail:match("^||") or "|"
        parts[#parts + 1], position = token, pipe + #token
    end
    return table.concat(parts), count
end

function chat.MarkMentions(text)
    if not usable(text) then return text, 0 end
    local name = chat.Settings().mentions ~= false and playerName() or nil
    mentionPattern = name and ("%f[%a]" .. caseless(name) .. "%f[%A]") or nil
    local phrases, total = chat.PhraseList(chat.Settings().highlightWords), 0
    local marked = chat.MapPlain(text, function(plain)
        local rewritten, count = markWithoutMarkup(plain, phrases)
        total = total + count
        return rewritten
    end)
    return marked, total
end

local function isSelf(sender)
    local name = playerName()
    return name ~= nil and usable(sender) and sender:match("^[^-]+") == name
end

-- A filter runs once per window showing the line; the line id keeps that to one sound.
local function mentionSound(event, lineID)
    if SILENT_EVENTS[event] or (lineID ~= nil and lineID == lastSoundLine) then return end
    local now = GetTime()
    if lastSound and now - lastSound < SOUND_COOLDOWN then return end
    lastSound, lastSoundLine = now, lineID
    if type(PlaySound) == "function" and type(SOUNDKIT) == "table" and SOUNDKIT.TELL_MESSAGE then
        pcall(PlaySound, SOUNDKIT.TELL_MESSAGE)
    end
end

local function mentionFilter(_, event, message, sender, ...)
    if not usable(message) or isSelf(sender) then return false end
    local marked, count = chat.MarkMentions(message)
    if count == 0 then return false end
    mentionSound(event, (select(LINE_ID_AFTER_SENDER, ...)))
    return false, marked, sender, ...
end

local function prune(now)
    if recentCount < REPEAT_LIMIT then return end
    for key, entry in pairs(recent) do
        if now - entry.time >= REPEAT_WINDOW then recent[key] = nil; recentCount = recentCount - 1 end
    end
end

-- The same line id is the same line reaching another window, not a repeat. The window does not
-- slide, so a line repeated forever still shows once every ten seconds.
local function repeatFilter(_, _, message, sender, ...)
    if chat.Settings().collapseRepeats == false or not usable(message) or not usable(sender) then return false end
    local lineID = select(LINE_ID_AFTER_SENDER, ...)
    if type(lineID) ~= "number" or isSelf(sender) then return false end
    local key, now = sender .. "\n" .. message, GetTime()
    local entry = recent[key]
    if entry and now - entry.time < REPEAT_WINDOW then return entry.line ~= lineID end
    if not entry then recentCount = recentCount + 1 end
    recent[key] = { time = now, line = lineID }
    prune(now)
    return false
end

local function registerFilters()
    local add = chat.FilterAdder and chat.FilterAdder() or nil
    if not add then return end
    for _, event in ipairs(REPEAT_EVENTS) do add(event, repeatFilter) end
    for _, event in ipairs(MENTION_EVENTS) do add(event, mentionFilter) end
end

function chat.EnableLines()
    chat.ApplyClassColors()
    applyShortTags()
    registerFilters()
end

local function toggle(key, apply)
    return function(enabled)
        chat.Settings()[key] = enabled == true
        if apply then apply() end
        return true
    end
end

local function checkbox(key, label, apply)
    table.insert(chat.Options.settings, { type = "checkbox", key = key, label = label,
        get = function() return chat.Settings()[key] ~= false end, set = toggle(key, apply) })
end

checkbox("classColors", "Class-coloured names", chat.ApplyClassColors)
checkbox("shortTags", "Short channel tags", applyShortTags)
checkbox("mentions", "Highlight my name", nil)
table.insert(chat.Options.settings, chat.PhraseSetting("highlightWords", "Highlight words and phrases",
    "Up to 16 comma-separated literal phrases, 256 characters total. Leave empty to disable. Name highlighting is independent."))
checkbox("collapseRepeats", "Collapse repeated public lines", nil)
