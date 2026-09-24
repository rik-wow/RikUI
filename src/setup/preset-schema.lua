-- Structural boundary for imported presets; semantic spell checks stay in Setup.
local core, setup = RikUI, RikUI.Setup
local ROOT = { author=true, class=true, version=true, roles=true, roleOrder=true, bars=true, macros=true, roleOverrides=true }
local ROLE = { label=true, trees=true }
local MACRO = { icon=true, body=true, spells=true, scope=true }
local SLOT = { spell=true, macro=true, item=true, level=true, fallback=true }

local function requireValue(ok, path, reason)
    if not ok then error(path .. ": " .. reason, 0) end
end

local function name(value, limit)
    return type(value) == "string" and value:match("%S") and #value <= limit and not value:find("[%c|]")
end

local function integer(value, low, high)
    return type(value) == "number" and value >= low and value <= high and value % 1 == 0
end

local function record(value, allowed, path)
    requireValue(type(value) == "table", path, "must be a table")
    if not allowed then return end
    for key in pairs(value) do
        requireValue(allowed[key], path .. "." .. tostring(key), "unknown field")
    end
end

local function list(value, path, maximum, visit)
    record(value, nil, path)
    local count = 0
    for key in pairs(value) do
        requireValue(integer(key, 1, maximum), path, "must be a bounded dense list")
        count = count + 1
    end
    requireValue(count > 0 and count <= maximum, path, "must not be empty")
    for i = 1, count do
        requireValue(value[i] ~= nil, path, "must be a dense list")
        visit(value[i], path .. "[" .. i .. "]")
    end
end

local function roles(preset)
    record(preset.roles, nil, "roles")
    local seen = {}
    list(preset.roleOrder, "roleOrder", 6, function(role, path)
        requireValue(name(role, 32) and preset.roles[role] ~= nil and not seen[role], path, "unknown or duplicate role")
        seen[role] = true
    end)
    for role, data in pairs(preset.roles) do
        local path = "roles." .. tostring(role)
        requireValue(name(role, 32) and seen[role], "roleOrder", "must include every role exactly once")
        record(data, ROLE, path)
        requireValue(name(data.label, 80), path .. ".label", "must be a readable label")
        local trees = {}
        list(data.trees, path .. ".trees", 3, function(tree, location)
            requireValue(integer(tree, 1, 3) and not trees[tree], location, "must name a unique talent tree 1..3")
            trees[tree] = true
        end)
    end
end

local function characterCount(value)
    local _, count = value:gsub("[^\128-\191]", "")
    return count
end

local function macros(preset)
    record(preset.macros, nil, "macros")
    for key, macro in pairs(preset.macros) do
        local path = "macros." .. tostring(key)
        requireValue(name(key, 64) and characterCount(key) <= 16, path, "name must be 1..16 characters")
        record(macro, MACRO, path)
        requireValue(type(macro.body) == "string" and characterCount(macro.body) <= 255
            and not macro.body:find("%z"), path .. ".body", "must be text up to 255 characters")
        requireValue(integer(macro.icon, 1, 2147483647) or name(macro.icon, 256), path .. ".icon", "must be a texture ID or path")
        requireValue(macro.scope == nil or macro.scope == "character" or macro.scope == "account", path .. ".scope", "unknown scope")
        if macro.spells ~= nil then
            list(macro.spells, path .. ".spells", 32, function(spell, location)
                requireValue(name(spell, 128), location, "must name a spell")
            end)
        end
    end
end

local function pages(value, path)
    record(value, nil, path)
    for page, slots in pairs(value) do
        requireValue(type(page) == "string" and setup.SlotToAction(page, 1) ~= nil, path, "unknown page " .. tostring(page))
        record(slots, nil, path .. "." .. page)
        for index, slot in pairs(slots) do
            local location = path .. "." .. page .. "[" .. tostring(index) .. "]"
            requireValue(integer(index, 1, 12), location, "slot index must be 1..12")
            record(slot, SLOT, location)
            for _, key in ipairs({ "spell", "macro", "item", "fallback" }) do
                requireValue(slot[key] == nil or name(slot[key], 128), location .. "." .. key, "must be a readable name")
            end
            requireValue(slot.level == nil or integer(slot.level, 1, 255), location .. ".level", "must be a level")
        end
    end
end

local function shape(preset)
    record(preset, ROOT, "preset")
    requireValue(type(preset.class) == "string" and core.SpellCatalogs[preset.class] ~= nil, "class", "unknown class")
    requireValue(integer(preset.version, 1, 1000000), "version", "must be a positive integer")
    requireValue(preset.author == nil or name(preset.author, 80), "author", "must be readable text up to 80 bytes")
    roles(preset)
    macros(preset)
    pages(preset.bars, "bars")
    if preset.roleOverrides ~= nil then
        record(preset.roleOverrides, nil, "roleOverrides")
        for role, overrides in pairs(preset.roleOverrides) do
            requireValue(preset.roles[role] ~= nil, "roleOverrides." .. tostring(role), "unknown role")
            pages(overrides, "roleOverrides." .. tostring(role))
        end
    end
end

function setup.ValidateSharedPreset(preset)
    local encoded, reason = core.Serialize(preset)
    if not encoded then return { "preset: " .. reason } end
    local ok, problem = pcall(shape, preset)
    if not ok then return { tostring(problem) } end
    return setup.ValidatePreset(preset)
end
