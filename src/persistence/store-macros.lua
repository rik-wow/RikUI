-- The settings store's second tier. Measured with RikProbe on 69913 (2026-09-20): a CVar an addon
-- registers survives /reload but comes back empty after a client restart; an account macro survives
-- both. So what differs from the defaults is also written to account macros named "RikUI data N",
-- each a single comment line ("#rikui i/n <checksum> <text>") that does nothing when pressed. Only the
-- difference is kept, so one or two macros usually do. Macros cannot be written in combat; the ticker
-- tries again. src/core/core.lua asks for this tier at login, only when neither saved variables nor the CVar
-- tier had anything. The undo snapshot and the chat history are not kept across a restart.
local core, store = RikUI, RikUI.Store

local NAME, HEADER, ICON = "RikUI data ", "#rikui ", "INV_Misc_QuestionMark"
local BODY_LIMIT, MAX_MACROS, TICK_SECONDS = 255, 12, 5
-- Left out of this tier: copies kept for undo and the chat history are large and only conveniences.
local SKIP = { undo = true, chatHistory = true, layoutUndo = true }
local FULL = "the account macro list is full, so settings cannot be kept across a client restart"
local DAMAGED = "RikUI's macros are damaged (edited or partly deleted); settings were not restored from them."
local state = { data = nil, lastText = nil, used = 0, complained = {}, restored = false, learningReduced = 0 }
local MAX_TEXT = MAX_MACROS * (BODY_LIMIT - #(HEADER .. MAX_MACROS .. "/" .. MAX_MACROS .. " 4294967295 "))
function store.MacroStatus() return { used=state.used, restored=state.restored, learningReduced=state.learningReduced, failure=state.failure } end

function store.MacrosAvailable()
    return type(GetMacroInfo) == "function" and type(CreateMacro) == "function" and type(EditMacro) == "function"
        and type(DeleteMacro) == "function"
end

local function complain(message)
    state.failure = message
    if state.complained[message] then return end
    state.complained[message] = true
    core:Print("Settings store: " .. message)
end

local MAX_PRUNE_DEPTH, MAX_PRUNE_NODES = 32, 8192
local function pruneTable(value, defaults, isModules, context, depth)
    if depth > MAX_PRUNE_DEPTH then error("settings nesting exceeds limit", 0) end
    if context.active[value] then error("cyclic settings table", 0) end
    context.active[value] = true
    local result = {}
    for key, entry in pairs(value) do
        context.nodes = context.nodes + 1
        if context.nodes > MAX_PRUNE_NODES then error("too many settings entries", 0) end
        local default = nil
        if type(defaults) == "table" then default = defaults[key] end
        local kept
        if SKIP[key] then kept = nil
        elseif type(entry) == "table" then kept = pruneTable(entry, default, key == "modules", context, depth + 1)
        elseif entry ~= default and not (isModules and entry == true) then kept = entry end
        if kept ~= nil then result[key] = kept end
    end
    context.active[value] = nil
    return next(result) ~= nil and result or nil
end

-- nil alone means no differences; nil with a reason means input validation failed.
function store.Prune(value, defaults)
    if type(value) ~= "table" then return nil end
    local ok, result = pcall(pruneTable, value, defaults, false, { active = {}, nodes = 0 }, 1)
    if not ok then return nil, tostring(result) end
    return result
end

local function samePlace(a, b)
    return a.point == b.point and a.relativePoint == b.relativePoint and math.abs((a.x or 0) - (b.x or 0)) < 0.01
        and math.abs((a.y or 0) - (b.y or 0)) < 0.01
end

-- What it takes to describe positions starting from a preset: the frames that stand elsewhere, and
-- false for the frames the preset places but the player never had a saved place for.
local function differences(positions, preset)
    local moved, cost = {}, 0
    for key, wanted in pairs(preset) do
        local saved = positions[key]
        if type(saved) ~= "table" then moved[key], cost = false, cost + 1
        elseif not samePlace(saved, wanted) then moved[key], cost = saved, cost + 1 end
    end
    for key, saved in pairs(positions) do
        if preset[key] == nil then moved[key], cost = saved, cost + 1 end
    end
    return moved, cost
end

-- A whole layout is thirty-five positions, and it is almost always a preset with a few frames moved.
-- The cheapest description wins; without the layouts, or when no preset helps, positions stay as they are.
local function packPositions(profile)
    local layout, positions = core.Layout, profile.positions
    if type(positions) ~= "table" or not (layout and layout.PresetPositions and core.Layouts) then return end
    local best, bestCost, bestName = nil, 0, nil
    for _ in pairs(positions) do bestCost = bestCost + 1 end
    for _, name in ipairs(core.Layouts.Order) do
        local moved, cost = differences(positions, layout.PresetPositions(name))
        if cost < bestCost then best, bestCost, bestName = moved, cost, name end
    end
    if not bestName then return end
    profile.positions = nil
    profile.layoutPacked = { base = bestName, moved = next(best) ~= nil and best or nil }
end

local function unpackPositions(profile)
    local packed, layout = profile.layoutPacked, core.Layout
    profile.layoutPacked = nil
    if type(packed) ~= "table" or not (layout and layout.PresetPositions) then return end
    local positions = layout.PresetPositions(packed.base)
    if not positions then return end
    for key, place in pairs(packed.moved or {}) do
        if place == false then positions[key] = nil else positions[key] = place end
    end
    profile.positions = positions
end

local function pruneAccount(db)
    local result = { profiles = {} }
    for name, profile in pairs(db.profiles or {}) do
        if type(profile) ~= "table" then error("invalid stored profile", 0) end
        local pruned, reason = store.Prune(profile, core.Defaults.profile)
        if reason then error(reason, 0) end
        if pruned then packPositions(pruned) end
        -- A profile name is a choice even when all its settings match defaults.
        result.profiles[name] = pruned or {}
    end
    if next(result.profiles) == nil then result.profiles = nil end
    -- Preset definitions are user data; empty slot tables and exact macro text matter.
    if type(db.community) == "table" and next(db.community) then result.community = db.community end
    return next(result) ~= nil and result or nil
end

local function checksum(text)
    local a, b = 1, 0
    for index = 1, #text do
        a = (a + text:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

local function body(name)
    local _, _, text = GetMacroInfo(name)
    if type(text) ~= "string" then return nil end
    return (text:gsub("[\r\n]+$", ""))
end

-- The text the macros hold, or nil plus whether macros were there at all.
local function readText()
    local first = body(NAME .. 1)
    if not first then return nil, false end
    local total, sum = first:match("^#rikui 1/(%d+) (%d+) ")
    total = tonumber(total)
    if not total or total > MAX_MACROS then return nil, true end
    local parts = {}
    for index = 1, total do
        local text = body(NAME .. index)
        local chunk = text and text:match("^#rikui " .. index .. "/" .. total .. " " .. sum .. " (.*)$")
        if not chunk then return nil, true end
        parts[index] = chunk
    end
    local text = table.concat(parts)
    if checksum(text) ~= tonumber(sum) then return nil, true end
    state.used = total
    return text, true
end

local function writeMacro(name, text)
    local written
    if body(name) ~= nil then written = EditMacro(name, name, nil, text)
    else written = CreateMacro(name, ICON, text, false) end
    if written == nil or written == false then return false, FULL end
    if body(name) ~= text then return false, "the client did not retain the restart backup macro" end
    return true
end

local function writeText(text)
    local sum = checksum(text)
    local room = BODY_LIMIT - #(HEADER .. MAX_MACROS .. "/" .. MAX_MACROS .. " " .. sum .. " ")
    local total = math.max(1, math.ceil(#text / room))
    if total > MAX_MACROS then return false, "the settings are too large for the macro store" end
    for index = 1, total do
        local chunk = text:sub((index - 1) * room + 1, index * room)
        local ok, written, reason = pcall(writeMacro, NAME .. index, HEADER .. index .. "/" .. total .. " " .. sum .. " " .. chunk)
        if not ok then return false, "restart backup write failed: " .. tostring(written) end
        if not written then return false, reason end
    end
    for index = total + 1, math.max(state.used, total) do pcall(DeleteMacro, NAME .. index) end
    state.used = total
    return true
end

-- User choices get the whole budget first. Learning remains complete in the
-- reload/SavedVariables tiers; the small restart tier keeps what fits.
local function characterSettings(value)
    local settings={}
    for key,entry in pairs(value or {}) do if key~="questPlanMemory" then settings[key]=entry end end
    local own,reason=store.Prune(settings,core.Defaults.character)
    if reason then error(reason,0) end
    return own
end
local function snapshot()
    local characters,memories={},{}
    for name,settings in pairs(state.data and state.data.characters or {}) do
        characters[name]=characterSettings(settings);memories[name]=settings.questPlanMemory
    end
    local name=store.CharacterKey()
    characters[name]=characterSettings(core.CharDB);memories[name]=core.CharDB.questPlanMemory
    return {account=pruneAccount(core.DB),characters=characters},memories
end
local function historyMemory(raw)
    local completed={}
    if type(raw.completed)=="table" then
        for index=math.max(1,#raw.completed-63),#raw.completed do completed[#completed+1]=raw.completed[index] end
    end
    return {version=raw.version,identity=raw.identity,models={},order={},recent={},completed=completed,
        visits={},failures={},places={}}
end
local function encodeSnapshot(data,memories)
    local text,reason=store.Encode(data)
    if not text then return nil,reason end
    if #text>MAX_TEXT then return nil,"the settings are too large for the macro store" end
    local names={};local own=store.CharacterKey()
    for name in pairs(memories) do if name~=own then names[#names+1]=name end end
    table.sort(names);table.insert(names,1,own)
    state.learningReduced=0
    for _,name in ipairs(names) do
        local raw=memories[name]
        if type(raw)=="table" then
            local settings=data.characters[name] or {};data.characters[name]=settings
            local kept=false
            for index,choice in ipairs({raw,historyMemory(raw)}) do
                settings.questPlanMemory=choice
                local candidate=store.Encode(data)
                if candidate and #candidate<=MAX_TEXT then
                    text=candidate;kept=true
                    if index>1 then state.learningReduced=state.learningReduced+1 end
                    break
                end
            end
            if not kept then
                settings.questPlanMemory=nil
                if not next(settings) then data.characters[name]=nil end
                state.learningReduced=state.learningReduced+1
            end
        end
    end
    return text
end

function store.FlushMacros()
    if not store.MacrosAvailable() or not core.DB or InCombatLockdown() then return end
    local built, data, memories = pcall(snapshot)
    if not built then complain(tostring(data)); return end
    local text, reason = encodeSnapshot(data, memories)
    if not text then complain(reason); return end
    if text == state.lastText and not state.failure then return end
    local ok, failure = writeText(text)
    if ok then state.lastText, state.data, state.failure = text, data, nil else complain(failure) end
end

local function overlay(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            overlay(target[key], value)
        else
            target[key] = value
        end
    end
end

-- Called by src/core/core.lua at login, before modules start. True when settings were put back, so the core
-- merges defaults and binds the profile again.
function store.RestoreLate()
    local status = store.Status()
    local accountMissing = not (status.loadedAccount or status.restored.account)
    local characterMissing = not (status.loadedCharacter or status.restored.character)
    if not store.MacrosAvailable() or not (accountMissing or characterMissing) then return false end
    local text, present = readText()
    local data = text and store.Decode(text) or nil
    if type(data) ~= "table" then
        if present then complain(DAMAGED) end
        return false
    end
    state.data, state.lastText = data, text
    if accountMissing and type(data.account) == "table" then
        overlay(RikUIDB, data.account)
        for _, profile in pairs(RikUIDB.profiles or {}) do unpackPositions(profile) end
    end
    local own = type(data.characters) == "table" and data.characters[store.CharacterKey()] or nil
    if characterMissing and type(own) == "table" then overlay(RikUICharDB, own) end
    state.restored = (accountMissing and type(data.account) == "table") or (characterMissing and type(own) == "table")
    return state.restored
end

core:RegisterEvent("PLAYER_LOGIN", function()
    if not store.MacrosAvailable() then return end
    if not state.data then
        -- Other characters' entries must survive this character's first save.
        local text = readText()
        local data = text and store.Decode(text) or nil
        if type(data) == "table" then state.data = data end
    end
    if type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then C_Timer.NewTicker(TICK_SECONDS, store.FlushMacros) end
end)
core:RegisterEvent("PLAYER_LOGOUT", store.FlushMacros)
