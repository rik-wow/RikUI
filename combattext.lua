-- The RikUI font on floating combat text. Two writes, because there are two systems. Blizzard's
-- scrolling text (load on demand) gives every string the CombatTextFont object and then scales it
-- with SetTextHeight, so the object is restyled at its own size. The numbers over units in the
-- world are drawn by the engine from the DAMAGE_TEXT_FONT global, which it reads during login. That
-- write waits for RikUI's ADDON_LOADED instead of running at file load: the module flag lives in the
-- saved variables, and core has read it by the time this callback runs.
local addonName = ...
local core, media = RikUI, RikUI.Media
local combattext = {}
core.CombatText = combattext

local FONT_OBJECT, DEFAULT_SIZE, FLAGS = "CombatTextFont", 25, "OUTLINE"
local warnings, state = {}, { font = false, damage = false }

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Combat text " .. operation .. ": " .. tostring(reason))
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
