-- One cooldown strip: the client's configured cooldown entries first (its order), then RikUI's
-- class profile, drawn with RikUI's own widgets from native duration objects. Membership is
-- resolved outside combat and never from secret values; a failed read keeps the last strip.
local core = RikUI
local panel = { title = "Cooldowns", Entries = {}, Stats = {}, Buttons = {} }
core.Cooldowns = panel
core.ClassCooldownProfiles = core.ClassCooldownProfiles or {}
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

-- Native strip entries in the client's order ahead of the profile; families appear once.
function panel.Merge(native, profile, class, known)
    local stats = { native = 0, profile = 0, unlearned = 0, duplicates = 0, itemOnly = 0, capped = 0 }
    local placed, result = {}, {}
    for _, entry in ipairs(native) do
        if entry.strip then
            local resolved = nativeEntry(entry, class, known, placed, stats)
            if resolved then result[#result + 1] = resolved; stats.native = stats.native + 1 end
        end
    end
    for _, entry in ipairs(profile) do
        if placed[entry.name] then stats.duplicates = stats.duplicates + 1
        else placed[entry.name] = true; result[#result + 1] = entry; stats.profile = stats.profile + 1 end
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
    local profile, problem = panel.Resolve(class, core.ClassCooldownProfiles[class] or {})
    if not profile then return nil, problem end
    local native, source = {}, "absent"
    if panel.Native then
        native, source = panel.Native.Read()
        if not native then return nil, "native entries " .. tostring(source) end
    end
    local entries, stats = panel.Merge(native, profile, class, known)
    return entries, stats, native, source
end

function panel.Rebuild()
    if panel.enabled == false then return end
    local class = readClass()
    if not class then return end
    local ok, entries, stats, native, source = pcall(compose, class)
    if not ok then panel.Warn("spellbook", entries); return end
    if not entries then panel.Warn("spellbook", stats); return end
    panel.Entries, panel.Stats, panel.Source = entries, stats, source
    if panel.Strip then panel.Strip.Apply(entries) end
    if panel.Native and core.ClassAuras and core.ClassAuras.SetNativeAuraIDs then
        core.ClassAuras.SetNativeAuraIDs(panel.Native.AuraIDs(native))
    end
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
    if panel.Controls and core.Shell then panel.Controls.Create() end
end

function panel:Debug()
    local s = panel.Stats
    core:Print(string.format("Cooldowns: %d icons (native=%d, profile=%d; skipped unlearned=%d, duplicates=%d, item-only=%d, capped=%d); provider=%s; native viewers=%s",
        #panel.Entries, s.native or 0, s.profile or 0, s.unlearned or 0, s.duplicates or 0, s.itemOnly or 0, s.capped or 0,
        tostring(panel.Source or "absent"), panel.Native and panel.Native.ViewerState() or "unknown"))
end

core:RegisterModule("cooldowns", panel)
