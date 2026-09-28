-- One cooldown strip: the client's configured cooldown entries first (its order), then RikUI's
-- class profile, drawn with RikUI's own widgets from native duration objects. Membership is
-- resolved outside combat and never from secret values; a failed read keeps the last strip.
local core = RikUI
local panel = { title = "Cooldowns", Entries = {}, Stats = {}, Buttons = {} }
core.Cooldowns = panel
core.ClassCooldownProfiles = core.ClassCooldownProfiles or {}
-- Per class: aura cells for the strip, e.g. { label = "Seal", unit = "player", families = { ... } }.
core.ClassAuraCells = core.ClassAuraCells or {}
local MAX_PROFILE, REBUILD_KEY, NATIVE_ADDON = 12, "cooldowns-rebuild", "Blizzard_CooldownViewer"
local MEMBERSHIP_EVENTS = { "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_ENTERING_WORLD",
    "UPDATE_SHAPESHIFT_FORM", "SPELL_UPDATE_ICON", "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",
    "COOLDOWN_VIEWER_DATA_LOADED" }
local REFRESH_EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USES", "BAG_UPDATE_DELAYED" }
local warnings = {}

function panel.Warn(key, reason)
    if warnings[key] then return end
    warnings[key] = true
    core:Print("Cooldowns " .. key .. ": " .. tostring(reason))
end

local function validID(id)
    return not core.Secret.IsSecret(id) and type(id) == "number"
        and id > 0 and id < math.huge and id % 1 == 0
end

-- Resolve the entire profile before changing any visible slot.
function panel.Resolve(class, names)
    if type(names) ~= "table" then return nil, "profile must be a spell list" end
    local count, seen, result = 0, {}, {}
    for key in pairs(names) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > MAX_PROFILE then
            return nil, "profile must contain at most 12 ordered spells"
        end
        count = count + 1
    end
    if count ~= #names then return nil, "profile has a missing slot" end
    for _, name in ipairs(names) do
        local entry = type(name) == "string" and core.Spells.Entry(name, class)
        if not entry or seen[name] then return nil, "unknown or duplicate class spell" end
        seen[name] = true
        local id, reason = core.Spells.HighestKnownRank(name, class)
        if reason then return nil, reason end
        if core.Secret.IsSecret(id) then return nil, "unreadable learned spell ID" end
        if id ~= nil then
            if not validID(id) then return nil, "unreadable learned spell ID" end
            result[#result + 1] = { id = id, name = name, icon = entry.icon, source = "profile" }
        end
    end
    return result
end

-- A native entry becomes the highest learned rank of its catalogue family (so rank twins
-- collapse into Blizzard's slot), or stays as its own learned ID when uncatalogued.
local function nativeEntry(entry, class, known, placed, stats)
    if not entry.spellID then stats.itemOnly = stats.itemOnly + 1; return nil end
    local family = core.Spells.FamilyOf(entry.spellID, class) or core.Spells.FamilyOf(entry.baseSpellID, class)
    if family then
        local id, reason = core.Spells.HighestKnownRank(family, class)
        if reason then error(reason, 0) end
        if not id then stats.unlearned = stats.unlearned + 1; return nil end
        if placed[family] then stats.duplicates = stats.duplicates + 1; return nil end
        placed[family] = true
        return { id = id, name = family, icon = core.Spells.Entry(family, class).icon, source = "native" }
    end
    if not known[entry.spellID] then stats.unlearned = stats.unlearned + 1; return nil end
    local key = "id:" .. entry.spellID
    if placed[key] then stats.duplicates = stats.duplicates + 1; return nil end
    placed[key] = true
    return { id = entry.spellID, source = "native" }
end

-- The aura a cell watches: every ID the client lists for the entry, on the player or the target.
local function auraOf(entry)
    if entry.hideAura or (entry.strip and not entry.hasAura) then return nil end
    local ids = {}
    for _, id in ipairs(entry.auraIDs or {}) do ids[id] = true end
    if next(ids) == nil then return nil end
    return { unit = entry.selfAura and "player" or "target", ids = ids }
end

-- A tracked-category entry is a pure aura cell: its own icon, dim until the aura is up.
local function trackedEntry(entry, class, placed, stats)
    if not entry.spellID then stats.itemOnly = stats.itemOnly + 1; return nil end
    local key = core.Spells.FamilyOf(entry.spellID, class) or ("id:" .. entry.spellID)
    if placed[key] then stats.duplicates = stats.duplicates + 1; return nil end
    placed[key] = true
    return { id = entry.spellID, source = "native", dim = true, aura = auraOf(entry) }
end

-- A class cell (data/class-cooldowns-<class>.lua): one icon for a family set, e.g. "Seal" for
-- every seal, drawn from the first learned family and watching every rank of every family.
function panel.ResolveCells(class, list)
    if type(list) ~= "table" then return {} end
    local result = {}
    for _, cell in ipairs(list) do
        local ids, families, id, icon = {}, {}, nil, nil
        for _, name in ipairs(cell.families or {}) do
            local entry = core.Spells.Entry(name, class)
            if not entry then return nil, "unknown class spell " .. tostring(name) end
            for _, rank in ipairs(entry.ranks) do ids[rank] = true end
            families[#families + 1] = name
            if not id then
                local known, reason = core.Spells.HighestKnownRank(name, class)
                if reason then return nil, reason end
                if known ~= nil and validID(known) then id, icon = known, entry.icon end
            end
        end
        if id then
            result[#result + 1] = { id = id, name = cell.label, icon = icon, families = families, source = "cell",
                dim = true, aura = { unit = cell.unit == "target" and "target" or "player", ids = ids } }
        end
    end
    return result
end

local function placeCell(cell, placed, stats)
    for _, name in ipairs(cell.families) do
        if placed[name] then stats.duplicates = stats.duplicates + 1; return nil end
    end
    for _, name in ipairs(cell.families) do placed[name] = true end
    return cell
end

-- Native entries in the client's order (strip categories, then tracked ones as aura cells), the
-- class aura cells, then the class cooldown profile; a family appears once.
function panel.Merge(native, profile, cells, class, known)
    local stats = { native = 0, cells = 0, profile = 0, unlearned = 0, duplicates = 0, itemOnly = 0, capped = 0 }
    local placed, result = {}, {}
    local function add(entry, counter)
        if entry then result[#result + 1] = entry; stats[counter] = stats[counter] + 1 end
    end
    for _, entry in ipairs(native) do
        if entry.strip then
            local resolved = nativeEntry(entry, class, known, placed, stats)
            if resolved then resolved.aura = auraOf(entry) end
            add(resolved, "native")
        end
    end
    for _, entry in ipairs(native) do
        if not entry.strip then add(trackedEntry(entry, class, placed, stats), "native") end
    end
    for _, cell in ipairs(cells) do add(placeCell(cell, placed, stats), "cells") end
    for _, entry in ipairs(profile) do
        if placed[entry.name] then stats.duplicates = stats.duplicates + 1
        else placed[entry.name] = true; add(entry, "profile") end
    end
    local limit = panel.Strip and panel.Strip.MAX_ENTRIES or #result
    while #result > limit do table.remove(result); stats.capped = stats.capped + 1 end
    return result, stats
end

local function readClass()
    local ok, _, class = core.Secret.Read(UnitClass, "player")
    if not ok or core.Secret.IsSecret(class) or type(class) ~= "string" then return nil end
    return class
end

local function compose(class)
    local known, reason = core.Spells.KnownIDs()
    if not known then return nil, reason end
    local names = core.ClassSettings and core.ClassSettings.List(class, "cooldowns") or core.ClassCooldownProfiles[class] or {}
    local profile, problem = panel.Resolve(class, names)
    if not profile then return nil, problem end
    local cells, trouble = panel.ResolveCells(class, core.ClassAuraCells[class])
    if not cells then return nil, trouble end
    local native, source = {}, "absent"
    if panel.Native then
        native, source = panel.Native.Read()
        if not native then return nil, "native entries " .. tostring(source) end
    end
    local entries, stats = panel.Merge(native, profile, cells, class, known)
    return entries, stats, source
end

function panel.Rebuild()
    if panel.enabled == false then return end
    local class = readClass()
    if not class then return end
    local ok, entries, stats, source = pcall(compose, class)
    if not ok then panel.Warn("spellbook", entries); return end
    if not entries then panel.Warn("spellbook", stats); return end
    panel.Entries, panel.Stats, panel.Source = entries, stats, source
    if panel.Strip then panel.Strip.Apply(entries) end
end

function panel.Schedule()
    core.Combat.Queue(panel.Rebuild, REBUILD_KEY)
end

function panel:OnEnable()
    panel.Schedule()
    for _, event in ipairs(MEMBERSHIP_EVENTS) do core:RegisterEvent(event, panel.Schedule) end
    for _, event in ipairs(REFRESH_EVENTS) do core:RegisterEvent(event, panel.Refresh) end
    -- The client's settings provider (the native part of the list) exists once its viewer addon loads.
    core:RegisterEvent("ADDON_LOADED", function(_, name) if name == NATIVE_ADDON then panel.Schedule() end end)
    if panel.Native then panel.Native.Enable() end
    if panel.Cells then panel.Cells.Enable() end
    if panel.Controls and core.Shell then panel.Controls.Create() end
    -- An edited class list (src/core/class-settings.lua) rebuilds the strip outside combat.
    if core.ClassSettings then core.ClassSettings.OnChange(function(_, kind) if kind == "cooldowns" then panel.Schedule() end end) end
end

function panel:Debug()
    local s = panel.Stats
    core:Print(string.format("Cooldowns: %d icons (native=%d, cells=%d, profile=%d; skipped unlearned=%d, duplicates=%d, item-only=%d, capped=%d); provider=%s; native viewers=%s",
        #panel.Entries, s.native or 0, s.cells or 0, s.profile or 0, s.unlearned or 0, s.duplicates or 0, s.itemOnly or 0, s.capped or 0,
        tostring(panel.Source or "absent"), panel.Native and panel.Native.ViewerState() or "unknown"))
end

core:RegisterModule("cooldowns", panel)
