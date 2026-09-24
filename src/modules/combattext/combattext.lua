-- The RikUI font on floating combat text. Two writes, because there are two systems. Blizzard's
-- scrolling text (load on demand) gives every string the CombatTextFont object and then scales it
-- with SetTextHeight, so the object is restyled at its own size. The numbers over units in the
-- world are drawn by the engine from the DAMAGE_TEXT_FONT global, which it reads during login. That
-- write waits for RikUI's ADDON_LOADED instead of running at file load: the module flag lives in the
-- saved variables, and core has read it by the time this callback runs.
local addonName = ...
local core, media = RikUI, RikUI.Media
local combattext = { Options = { title = "Combat text", settings = {} } }
core.CombatText = combattext

local FONT_OBJECT, DEFAULT_SIZE, FLAGS = "CombatTextFont", 25, "OUTLINE"
local warnings, state = {}, { font = false, damage = false }

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Combat text " .. operation .. ": " .. tostring(reason))
end

local ENABLE, FLOW = "enableFloatingCombatText", "floatingCombatTextFloatMode_v2"
local function readCVar(name)
    if type(C_CVar) ~= "table" or type(C_CVar.GetCVar) ~= "function" then return nil end
    local ok, value = pcall(C_CVar.GetCVar, name)
    if ok and not core.Secret.IsSecret(value) and type(value) == "string" then return value end
end

local function available(name)
    if type(C_CVar) ~= "table" or type(C_CVar.SetCVar) ~= "function" or readCVar(name) == nil then return false end
    return name ~= FLOW or (readCVar("classicStyleWorldText") == "0" and readCVar(ENABLE) == "1")
end

local function setNative(name, value)
    if not available(name) then warn(name, "unavailable with the current client settings"); return end
    core.Combat.Queue(function()
        if not available(name) then warn(name, "unavailable with the current client settings"); return end
        local ok, result = pcall(C_CVar.SetCVar, name, value)
        if not ok or result == false or readCVar(name) ~= value then
            warn(name, "the client refused this change"); return
        end
        if name == ENABLE and value == "1" and type(CombatText_LoadUI) == "function" then
            local loaded, reason = pcall(CombatText_LoadUI)
            if not loaded then warn("load", reason) end
        end
        if type(UpdateFloatingCombatTextSafe) == "function" then
            local updated, reason = pcall(UpdateFloatingCombatTextSafe)
            if not updated then warn("refresh", reason) end
        end
    end, "combattext:" .. name)
end

combattext.Options.settings = {
    { type = "checkbox", key = "nativeEnabled", label = "Show native scrolling combat text",
        description = "Client setting shared across RikUI profiles. Changes wait until combat ends.",
        get = function() return readCVar(ENABLE) == "1" end,
        disabled = function() return not available(ENABLE) end,
        set = function(value)
            if type(value) ~= "boolean" then warn(ENABLE, "invalid toggle"); return end
            setNative(ENABLE, value and "1" or "0")
        end },
    { type = "dropdown", key = "nativeFlow", label = "Native scrolling direction",
        description = "Available with scrolling text enabled and classic-style world text off.",
        choices = { { value = 1, label = "Up" }, { value = 2, label = "Down" }, { value = 3, label = "Arc" } },
        get = function() return tonumber(readCVar(FLOW)) or 1 end,
        disabled = function() return not available(FLOW) end,
        set = function(value)
            if value ~= 1 and value ~= 2 and value ~= 3 then warn(FLOW, "invalid direction"); return end
            setNative(FLOW, tostring(value))
        end },
}

-- Native CVars remain client-wide. Unknown build coverage is disabled at runtime.
local CATEGORIES = {
    { "floatingCombatTextCombatDamage_v2", "Damage dealt above enemies" },
    { "floatingCombatTextCombatHealing_v2", "Healing done above targets" },
    { "floatingCombatTextEnergyGains_v2", "Resource gains" },
    { "floatingCombatTextAuras_v2", "Buff and debuff messages" },
    { "floatingCombatTextCombatState_v2", "Entering and leaving combat" },
    { "floatingCombatTextDodgeParryMiss_v2", "Dodges, parries and misses" },
    { "floatingCombatTextLowManaHealth_v2", "Low health and mana warnings" },
    { "floatingCombatTextRepChanges_v2", "Reputation changes" },
}
for _, category in ipairs(CATEGORIES) do
    local name = category[1]
    local function supported()
        local value = readCVar(name)
        return available(name) and (value == "0" or value == "1")
    end
    table.insert(combattext.Options.settings, {
        type = "checkbox", key = name, label = category[2],
        description = "Native client setting, shared across profiles. Unsupported controls are disabled.",
        get = function() return readCVar(name) == "1" end,
        disabled = function() return not supported() end,
        set = function(value)
            if type(value) ~= "boolean" or not supported() then return end
            setNative(name, value and "1" or "0")
        end,
    })
end

local function setDamageFont(_, loadedAddon)
    if loadedAddon ~= addonName or not combattext.enabled then return end
    DAMAGE_TEXT_FONT = media.font
    state.damage = true
end

function combattext:OnEnable()
    local object = _G[FONT_OBJECT]
    if type(object) ~= "table" or type(object.SetFont) ~= "function" then return end
    local ok, _, size = pcall(object.GetFont, object)
    size = ok and type(size) == "number" and size > 0 and size or DEFAULT_SIZE
    local written, loaded = pcall(object.SetFont, object, media.font, size, FLAGS)
    state.font = written and loaded ~= false
    if not state.font then warn("font", written and "the client refused the font" or loaded) end
end

function combattext:Debug()
    core:Print("Combat text font=" .. tostring(state.font) .. " damage=" .. tostring(state.damage))
end

core:RegisterModule("combattext", combattext)
core:RegisterEvent("ADDON_LOADED", setDamageFont)
