-- The Class area of the settings: a sidebar group of its own where any class can be chosen, not
-- only the one being played, so its lists can be changed before logging over. Pages: an overview
-- with the class chooser and the module switches, the cooldown strip's class list, and the class
-- effect groups; each list is editable from RikUI's catalogue with a reset to the shipped default
-- (src/core/class-settings.lua). Nothing here reads combat values.
local core, options = RikUI, RikUI.Options
local GROUP, KEY_PREFIX, CHOOSE = "Class", "class.", ""
local SUPPORTING = {
    { key = "combopoints", title = "Combo points", note = "Five pips near your target or resource bar." },
    { key = "totems", title = "Totems", note = "Four buttons with each totem's icon and remaining time." },
    { key = "druidmana", title = "Form mana", note = "Mana while shifted into Cat or Bear." },
}
local EFFECT_KINDS = { "player", "harmful", "helpful" }
local SHARED = " Shared by every class in this profile."
local state = {}

local function readable(value, kind)
    return not core.Secret.IsSecret(value) and type(value) == kind
end

local function className(token)
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    local name = type(names) == "table" and names[token]
    if type(name) == "string" then return name end
    return token:sub(1, 1) .. token:sub(2):lower()
end

-- The class token being played; nil when it cannot be read.
local function playerClass()
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, token = core.Secret.Read(UnitClass, "player")
    if ok and readable(token, "string") then return token end
    return nil
end
options.PlayerClass = playerClass

local function classes() return core.ClassSettings and core.ClassSettings.Classes() or {} end

-- The class the area shows: the chosen one, else the player's, else the first RikUI knows.
function options.SelectedClass()
    local available = classes()
    local known = {}
    for _, token in ipairs(available) do known[token] = true end
    local token = state.class
    if not token or not known[token] then token = playerClass() end
    if not token or not known[token] then token = available[1] end
    return token, token and className(token), token ~= nil and token == playerClass()
end

local function subject()
    local token, name, own = options.SelectedClass()
    return name .. (own and " (your class)" or "")
end

local function settingsFor()
    return core.ClassSettings, (options.SelectedClass())
end

local function chooser()
    return { type = "dropdown", key = KEY_PREFIX .. "selected", label = "Class shown",
        description = "Pick any class to see or change its settings. Changes for another class are saved now and take effect when you play it.",
        values = function()
            local entries, player = {}, playerClass()
            for _, token in ipairs(classes()) do
                entries[#entries + 1] = { value = token, text = className(token) .. (token == player and " (you)" or "") }
            end
            return entries
        end,
        get = function() return (options.SelectedClass()) end,
        set = function(value) state.class = value; return true end }
end

local function usesRow(key, class)
    for _, row in ipairs(core.Layouts and core.Layouts.SupportingRows or {}) do
        if row.key == key then return row.classes[class] == true end
    end
    return false
end

local function moduleToggle(name, module, extra)
    local toggle = options.ModuleToggle(name, module, KEY_PREFIX)
    local status = toggle.getDescription
    toggle.getDescription = function() return (extra and extra .. " " or "") .. status() .. SHARED end
    return toggle
end

local function overviewPage()
    local specs = { chooser(), { type = "heading", label = "Displays",
        description = "Module switches apply to the whole profile; Reload UI applies them. Their lists and options follow the class shown." } }
    if core.Modules.cooldowns then specs[#specs + 1] = moduleToggle("cooldowns", core.Modules.cooldowns, "The cooldown strip with the class list.") end
    if core.Modules.classauras then
        local toggle = moduleToggle("classauras", core.Modules.classauras, "The tracked effect rows beside the cast bar.")
        toggle.visible = function() local settings, class = settingsFor(); return settings ~= nil and settings.Effects(class) ~= nil end
        specs[#specs + 1] = toggle
    end
    for _, entry in ipairs(SUPPORTING) do
        local module = core.Modules[entry.key]
        if module then
            local visible = function() return usesRow(entry.key, (options.SelectedClass())) end
            local toggle = moduleToggle(entry.key, module, entry.note)
            toggle.visible = visible
            specs[#specs + 1] = toggle
            for _, spec in ipairs(module.ClassSettings or {}) do
                local wrapped = options.ModuleSpec(entry.key, module, spec)
                wrapped.visible = visible
                specs[#specs + 1] = wrapped
            end
        end
    end
    return { id = "class", group = GROUP, title = "Overview",
        description = function() return subject() .. ": which displays run, and the class-only options." end, specs = specs }
end

local function listCount(kind)
    return function()
        local settings, class = settingsFor()
        if not settings or not class then return "" end
        local entry, count = settings.Kinds[kind], #settings.List(class, kind)
        return string.format("%d of %d for %s. %s", count, entry.limit, className(class),
            settings.IsCustom(class, kind) and "Changed in this profile." or "RikUI's list.")
    end
end

local function listSpecs(specs, kind, label, extraDescription)
    specs[#specs + 1] = { type = "heading", key = KEY_PREFIX .. kind .. ".heading", label = label,
        description = "", getDescription = function() return listCount(kind)() .. (extraDescription and " " .. extraDescription or "") end }
    specs[#specs + 1] = { type = "spelllist", key = KEY_PREFIX .. kind, label = "",
        class = function() return (options.SelectedClass()) end,
        get = function() local settings, class = settingsFor(); return settings and class and settings.List(class, kind) or {} end,
        move = function(name, delta) local settings, class = settingsFor(); return settings.Move(class, kind, name, delta) end,
        remove = function(name) local settings, class = settingsFor(); return settings.Remove(class, kind, name) end }
    specs[#specs + 1] = { type = "dropdown", key = KEY_PREFIX .. kind .. ".add", label = "Add a spell",
        values = function()
            local settings, class = settingsFor()
            local entries = { { value = CHOOSE, text = "Choose a spell" } }
            for _, name in ipairs(settings and class and settings.Candidates(class, kind) or {}) do
                entries[#entries + 1] = { value = name, text = name }
            end
            return entries
        end,
        get = function() return CHOOSE end,
        disabled = function()
            local settings, class = settingsFor()
            return not settings or not class or #settings.List(class, kind) >= settings.Kinds[kind].limit
        end,
        set = function(name)
            if name == CHOOSE then return true end
            local settings, class = settingsFor()
            return settings.Add(class, kind, name)
        end }
    specs[#specs + 1] = { type = "button", key = KEY_PREFIX .. kind .. ".reset", label = "Back to RikUI's list", text = "Reset",
        disabled = function() local settings, class = settingsFor(); return not settings or not class or not settings.IsCustom(class, kind) end,
        confirm = function() local _, class = settingsFor(); return "Replace the " .. label:lower() .. " for " .. className(class) .. " with RikUI's?" end,
        action = function() local settings, class = settingsFor(); return settings.Reset(class, kind) end }
end

local function cellText()
    local _, class = settingsFor()
    local labels = {}
    for _, cell in ipairs(core.ClassAuraCells and core.ClassAuraCells[class] or {}) do
        if type(cell.label) == "string" then labels[#labels + 1] = cell.label end
    end
    if #labels == 0 then return "None for " .. className(class) .. "." end
    return table.concat(labels, ", ") .. ". A cell stays dim until its effect is up and then shows the active effect."
end

local function trackedSpellsUnavailable()
    local native = core.Cooldowns and core.Cooldowns.Native
    return not native or type(native.OpenSettings) ~= "function" or CooldownViewerSettings == nil
end

local function openTrackedSpells()
    if options.Panel and options.Panel() then options.Panel():Hide() end
    return core.Cooldowns.Native.OpenSettings()
end

local function cooldownPage()
    local specs = { chooser() }
    listSpecs(specs, "cooldowns", "Class list",
        "The strip shows these after the game's tracked entries; only learned abilities appear, at their highest rank.")
    specs[#specs + 1] = { type = "heading", key = KEY_PREFIX .. "cells", label = "Effect cells", description = "", getDescription = cellText }
    specs[#specs + 1] = { type = "button", key = KEY_PREFIX .. "trackedSpells", label = "The game's tracked spells", text = "Tracked spells",
        description = "Choose and order the game's own cooldown entries. The strip lists them first.",
        disabled = function() return InCombatLockdown() or trackedSpellsUnavailable() end, action = openTrackedSpells }
    return { id = "class-cooldowns", group = GROUP, title = "Cooldown strip",
        description = function() return subject() .. ": the strip's class list." end, specs = specs }
end

local function effectsPage()
    local specs = { chooser(), { type = "heading", key = KEY_PREFIX .. "effects.reload", label = "Class effects", reload = true,
        pending = function() return core.ClassSettings ~= nil and core.ClassSettings.NeedsReload() end,
        description = "The rows beside the cast bar. Changes to these lists apply after Reload UI." } }
    for _, kind in ipairs(EFFECT_KINDS) do listSpecs(specs, kind, core.ClassSettings.Kinds[kind].label) end
    return { id = "class-effects", group = GROUP, title = "Class effects",
        description = function() return subject() .. ": the tracked effects." end, specs = specs }
end

-- The sidebar group's label names the class shown.
function options.GroupLabel(group)
    if group ~= GROUP then return nil end
    local _, name = options.SelectedClass()
    return name and (GROUP .. ": " .. name) or GROUP
end

-- The area's pages, or none when RikUI has no class data or the settings layer is absent.
function options.ClassPages()
    if not core.ClassSettings or #classes() == 0 then return {} end
    local pages = { overviewPage() }
    if core.Modules.cooldowns then pages[#pages + 1] = cooldownPage() end
    if core.Modules.classauras then pages[#pages + 1] = effectsPage() end
    return pages
end
