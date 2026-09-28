-- Per-class lists the player may edit for any class, not only the one being played: the cooldown
-- strip's class list and the three class effect groups. The shipped tables (data/class-cooldowns-*.lua,
-- data/class-auras-*.lua) are the defaults; a profile override replaces a list wholesale, so a reset
-- is a deletion. Names are validated against RikUI's spell catalogue for that class.
local core = RikUI
local settings = { Kinds = {}, Order = { "cooldowns", "player", "harmful", "helpful" } }
core.ClassSettings = settings
local listeners = {}

local function auraGroup(kind)
    return function(class)
        local profile = core.ClassAuraProfiles and core.ClassAuraProfiles[class]
        return type(profile) == "table" and profile[kind] or nil
    end
end

settings.Kinds.cooldowns = { label = "Class list", limit = 12,
    default = function(class) return core.ClassCooldownProfiles and core.ClassCooldownProfiles[class] end }
settings.Kinds.player = { label = "Your effects", limit = 12, default = auraGroup("player"), reload = true }
settings.Kinds.harmful = { label = "On your target", limit = 6, default = auraGroup("harmful"), reload = true }
settings.Kinds.helpful = { label = "Your effects on others", limit = 6, default = auraGroup("helpful"), reload = true }

local function copy(list)
    local result = {}
    for index, name in ipairs(list or {}) do result[index] = name end
    return result
end

local function kindOf(kind)
    local entry = settings.Kinds[kind]
    if not entry then error("Unknown class list: " .. tostring(kind), 0) end
    return entry
end

local function store(class)
    local profile = core.Profile
    if type(profile) ~= "table" then return nil end
    return type(profile.classes) == "table" and profile.classes[class] or nil
end

-- Every class RikUI ships data for, as tokens in alphabetical order.
function settings.Classes()
    local seen, tokens = {}, {}
    for _, source in ipairs({ core.ClassCooldownProfiles, core.ClassAuraProfiles }) do
        for token in pairs(source or {}) do
            if not seen[token] then seen[token] = true; tokens[#tokens + 1] = token end
        end
    end
    table.sort(tokens)
    return tokens
end

function settings.Default(class, kind)
    return copy(kindOf(kind).default(class))
end

-- The list in force: the profile's override when one exists, else the shipped default.
function settings.List(class, kind)
    local saved = store(class)
    local override = saved and saved[kind]
    if type(override) == "table" then return copy(override) end
    return settings.Default(class, kind)
end

function settings.IsCustom(class, kind)
    local saved = store(class)
    return saved ~= nil and type(saved[kind]) == "table"
end

local function validate(class, kind, list)
    local entry = kindOf(kind)
    if type(list) ~= "table" then return nil, "expected a list of spell names" end
    if #list > entry.limit then return nil, string.format("%s holds at most %d spells", entry.label, entry.limit) end
    local seen = {}
    for index, name in ipairs(list) do
        if type(name) ~= "string" or not (core.Spells and core.Spells.Entry(name, class)) then
            return nil, tostring(name) .. " is not a " .. class:lower() .. " spell RikUI knows"
        end
        if seen[name] then return nil, name .. " is listed twice" end
        seen[name], list[index] = true, name
    end
    return true
end

local function notify(class, kind)
    if kindOf(kind).reload then settings.reloadPending = true end
    if core.Changed then core:Changed() end
    for _, callback in ipairs(listeners) do
        local ok, reason = pcall(callback, class, kind)
        if not ok and core.Runtime and core.Runtime.Report then core.Runtime.Report("Class settings", reason) end
    end
end

-- Replace a list. Saving the shipped default removes the override instead of storing a copy.
function settings.Set(class, kind, list)
    if type(core.Profile) ~= "table" then return nil, "Still loading." end
    local candidate = copy(list)
    local ok, reason = validate(class, kind, candidate)
    if not ok then return nil, reason end
    local default = settings.Default(class, kind)
    local same = #default == #candidate
    for index, name in ipairs(candidate) do if default[index] ~= name then same = false end end
    core.Profile.classes = type(core.Profile.classes) == "table" and core.Profile.classes or {}
    local saved = core.Profile.classes[class] or {}
    saved[kind] = (not same) and candidate or nil
    core.Profile.classes[class] = next(saved) ~= nil and saved or nil
    notify(class, kind)
    return true
end

function settings.Reset(class, kind)
    kindOf(kind)
    if type(core.Profile) ~= "table" then return nil, "Still loading." end
    local saved = store(class)
    if not saved or saved[kind] == nil then return true end
    saved[kind] = nil
    if next(saved) == nil then core.Profile.classes[class] = nil end
    notify(class, kind)
    return true
end

function settings.Add(class, kind, name)
    local list = settings.List(class, kind)
    for _, existing in ipairs(list) do
        if existing == name then return nil, name .. " is already listed" end
    end
    list[#list + 1] = name
    return settings.Set(class, kind, list)
end

function settings.Remove(class, kind, name)
    local list, kept = settings.List(class, kind), {}
    for _, existing in ipairs(list) do if existing ~= name then kept[#kept + 1] = existing end end
    if #kept == #list then return nil, name .. " is not listed" end
    return settings.Set(class, kind, kept)
end

-- Move a name up (delta -1) or down (delta 1); the ends stay put.
function settings.Move(class, kind, name, delta)
    local list = settings.List(class, kind)
    for index, existing in ipairs(list) do
        if existing == name then
            local target = index + delta
            if target < 1 or target > #list then return true end
            list[index], list[target] = list[target], list[index]
            return settings.Set(class, kind, list)
        end
    end
    return nil, name .. " is not listed"
end

-- Catalogue spells of that class not yet in the list, alphabetically, for an "add" choice.
function settings.Candidates(class, kind)
    local listed, names = {}, {}
    for _, name in ipairs(settings.List(class, kind)) do listed[name] = true end
    local catalog = core.Spells and core.Spells.Catalog(class) or {}
    for name in pairs(catalog) do
        if not listed[name] then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

-- The class effect groups as the aura module reads them, with the shipped enchant flag.
function settings.Effects(class)
    local shipped = core.ClassAuraProfiles and core.ClassAuraProfiles[class]
    if type(shipped) ~= "table" then return nil end
    return { player = settings.List(class, "player"), harmful = settings.List(class, "harmful"),
        helpful = settings.List(class, "helpful"), enchants = shipped.enchants }
end

-- True once an effect list changed in this session; the rows read their lists when they are built.
function settings.NeedsReload() return settings.reloadPending == true end

function settings.OnChange(callback)
    listeners[#listeners + 1] = callback
end
