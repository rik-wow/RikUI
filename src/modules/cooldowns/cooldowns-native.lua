-- The client's cooldown manager as a data source: its configured entries come from the settings
-- data provider (the user's order and hidden choices) or, before that frame exists, from the
-- C_CooldownViewer API. Its four viewer frames stay hidden through the cooldownViewerEnabled
-- cvar while this module draws the strip; the Tracked spells window still edits the native part.
-- Nothing here reads live cooldown or aura state.
local core, panel = RikUI, RikUI.Cooldowns
local native = {}
panel.Native = native
local CVAR = "cooldownViewerEnabled"
local STRIP_CATEGORIES, AURA_CATEGORIES = { "Essential", "Utility" }, { "TrackedBuff", "TrackedBar" }
local FLAG_HIDE_AURA, FLAG_HIDE_BY_DEFAULT = 1, 2
local DATA_CHANGED, HID_FLAG = "CooldownViewerSettings.OnDataChanged", "cooldownsHidNative"
local ID_FIELDS = { "spellID", "overrideSpellID", "overrideTooltipSpellID" }
local NOTICE = "RikUI's Cooldowns strip replaces Blizzard's cooldown viewer; disable the Cooldowns module to use Blizzard's."
local noticed = false

local function readable(value, kind)
    return not core.Secret.IsSecret(value) and (kind == nil or type(value) == kind)
end
local function flag(flags, bit) return readable(flags, "number") and math.floor(flags / bit) % 2 == 1 end
local function positive(value) if readable(value, "number") and value > 0 then return value end end

local function provider()
    if not CooldownViewerSettings or type(CooldownViewerSettings.GetDataProvider) ~= "function" then return nil end
    local source = CooldownViewerSettings:GetDataProvider()
    if readable(source, "table") then return source end
end

local function apiAvailable()
    return type(C_CooldownViewer) == "table" and type(C_CooldownViewer.GetCooldownViewerCategorySet) == "function"
        and type(C_CooldownViewer.GetCooldownViewerCooldownInfo) == "function"
end

-- Entry IDs of a category as the user sees them (provider) or as the client ships them (API).
local function idsFor(source, category)
    local ids = source and source:GetOrderedCooldownIDsForCategory(category)
        or C_CooldownViewer.GetCooldownViewerCategorySet(category, false)
    assert(readable(ids, "table"), "unreadable entry list")
    return ids
end

local function infoFor(source, id)
    assert(readable(id, "number"), "unreadable entry ID")
    local info = source and source:GetCooldownInfoForID(id) or C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
    if info == nil then return nil end
    assert(readable(info, "table"), "unreadable entry")
    return info
end

-- The API lists what the provider would hide: unknown, invisible and hidden-by-default entries.
local function apiHidden(info)
    return info.isKnown ~= true or info.isInvisible == true or flag(info.flags, FLAG_HIDE_BY_DEFAULT)
end

local function auraIDsOf(info)
    local ids = {}
    for _, field in ipairs(ID_FIELDS) do
        local value = info[field]
        assert(value == nil or readable(value, "number"), "unreadable spell field")
        if value then ids[#ids + 1] = value end
    end
    local linked = info.linkedSpellIDs
    assert(linked == nil or readable(linked, "table"), "unreadable linked spells")
    for _, value in ipairs(linked or {}) do
        assert(readable(value, "number"), "unreadable linked spell")
        ids[#ids + 1] = value
    end
    return ids
end

-- Static spell precedence, Blizzard's minus the live-aura step: tooltip override, override, base.
local function entryFrom(id, info, category, strip)
    for _, field in ipairs({ "hasAura", "selfAura", "flags" }) do assert(readable(info[field]), "unreadable " .. field) end
    return { cooldownID = id, category = category, strip = strip,
        spellID = positive(info.overrideTooltipSpellID) or positive(info.overrideSpellID) or positive(info.spellID),
        baseSpellID = positive(info.spellID), hasAura = info.hasAura == true, selfAura = info.selfAura == true,
        hideAura = flag(info.flags, FLAG_HIDE_AURA), auraIDs = auraIDsOf(info) }
end

local function collectCategory(source, set, name, strip, list)
    local category = set[name]
    if not readable(category, "number") then return end
    for _, id in ipairs(idsFor(source, category)) do
        local info = infoFor(source, id)
        if info and (source or not apiHidden(info)) then list[#list + 1] = entryFrom(id, info, name, strip) end
    end
end

local function collect(source)
    local set = Enum and Enum.CooldownViewerCategory
    assert(readable(set, "table"), "categories unavailable")
    local list = {}
    for _, name in ipairs(STRIP_CATEGORIES) do collectCategory(source, set, name, true, list) end
    for _, name in ipairs(AURA_CATEGORIES) do collectCategory(source, set, name, false, list) end
    return list
end

local function sourceLabel(source)
    if not source then return "api" end
    local ok, manager = pcall(source.GetLayoutManager, source)
    return (ok and manager) and "provider" or "provider-default-order"
end

-- The configured entries (Essential, Utility, then the tracked categories) and where they came
-- from; an empty list and "absent" when the client offers nothing; nil and a reason when a value
-- cannot be read, so a partial list is never used.
function native.Read()
    local source = provider()
    if not source and not apiAvailable() then return {}, "absent" end
    local ok, list = pcall(collect, source)
    if not ok then return nil, tostring(list) end
    return list, sourceLabel(source)
end

-- Spell IDs whose auras the class effect rows should show: tracked categories and aura-backed
-- strip entries, split by whether the aura sits on the player or on the target.
function native.AuraIDs(list)
    local sets = { player = {}, target = {} }
    for _, entry in ipairs(list or {}) do
        if not entry.strip or (entry.hasAura and not entry.hideAura) then
            local set = entry.selfAura and sets.player or sets.target
            for _, id in ipairs(entry.auraIDs) do set[id] = true end
        end
    end
    return sets
end

local function enabled()
    if type(C_CVar) ~= "table" or type(C_CVar.GetCVarBool) ~= "function" then return nil end
    local ok, value = pcall(C_CVar.GetCVarBool, CVAR)
    if not ok or core.Secret.IsSecret(value) then return nil end
    if type(value) == "boolean" then return value end
end
native.ViewersEnabled = enabled

function native.ViewerState()
    local state = enabled()
    if state == nil then return "unreadable" end
    return state and "visible" or "hidden"
end

local function setCVar(value)
    return type(C_CVar) == "table" and type(C_CVar.SetCVar) == "function" and pcall(C_CVar.SetCVar, CVAR, value)
end

local function hideViewers()
    if InCombatLockdown() or enabled() ~= true or not setCVar("0") then return end
    if core.CharDB then core.CharDB[HID_FLAG] = true; core:Changed() end
    if not noticed then noticed = true; core:Print(NOTICE) end
end

function native.HideViewers() core.Combat.Queue(hideViewers, "cooldowns-hide-viewers") end

-- A disabled module gives the viewers back, but only when RikUI was the one that hid them.
local function restoreViewers()
    if panel.enabled ~= false or not core.CharDB or core.CharDB[HID_FLAG] ~= true or InCombatLockdown() then return end
    if enabled() == false and not setCVar("1") then return end
    core.CharDB[HID_FLAG] = nil
    core:Changed()
end

function native.OpenSettings()
    if type(ShowUIPanel) ~= "function" or not CooldownViewerSettings then return nil, "Cooldown settings are unavailable" end
    if core.Shell then core.Shell.Close() end
    if not pcall(ShowUIPanel, CooldownViewerSettings) then return nil, "Cooldown settings are unavailable" end
    return true
end

local function onCVar(_, name)
    if core.Secret.IsSecret(name) or type(name) ~= "string" or name:lower() ~= CVAR:lower() then return end
    if enabled() == true then native.HideViewers() end
end

local function onDataChanged()
    C_Timer.After(0, panel.Schedule)
end

function native.Enable()
    native.HideViewers()
    core:RegisterEvent("PLAYER_ENTERING_WORLD", native.HideViewers, panel)
    core:RegisterEvent("PLAYER_REGEN_ENABLED", native.HideViewers, panel)
    core:RegisterEvent("CVAR_UPDATE", onCVar, panel)
    if type(EventRegistry) == "table" and type(EventRegistry.RegisterCallback) == "function" then
        pcall(EventRegistry.RegisterCallback, EventRegistry, DATA_CHANGED, onDataChanged, panel)
    end
end

core:RegisterEvent("PLAYER_LOGIN", function() core.Combat.Queue(restoreViewers, "cooldowns-restore-viewers") end)
