-- Shared unit colours. This service is available even when unit frames are disabled.
local core, ui = RikUI, RikUI.UI
local colors = {
    neutral = { r = 0.6, g = 0.6, b = 0.6 },
    disconnected = { r = 0.5, g = 0.5, b = 0.5 },
    tapped = { r = 0.55, g = 0.57, b = 0.61 },
    power = { r = 0, g = 0.5, b = 1 },
}
ui.Colors = colors
local warnings = {}

local function warnOnce(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core.Runtime.Report("Unit frames " .. operation, reason)
end

local function readable(value, kind)
    return not core.Secret.IsSecret(value) and type(value) == kind
end

local function lookup(palette, key, fallback)
    if type(palette) ~= "table" or key == nil then return fallback end
    return palette[key] or fallback
end

local function flag(reader, unit)
    local ok, value = core.Secret.Read(reader, unit)
    if ok and readable(value, "boolean") then return value end
    if not ok then warnOnce("state", value) end
end

local function classColor(unit)
    local ok, name, classFilename = core.Secret.Read(UnitClass, unit)
    if not ok then warnOnce("class", name); return colors.neutral end
    if not readable(classFilename, "string") then return colors.neutral end
    return lookup(RAID_CLASS_COLORS, classFilename, colors.neutral)
end

local function reactionColor(unit)
    local ok, reaction = core.Secret.Read(UnitReaction, unit, "player")
    if not ok then warnOnce("reaction", reaction); return colors.neutral end
    if not readable(reaction, "number") then return colors.neutral end
    return lookup(FACTION_BAR_COLORS, reaction, colors.neutral)
end

function ui.HealthColor(unit)
    if flag(UnitIsConnected, unit) == false then return colors.disconnected end
    if flag(UnitIsTapDenied, unit) == true then return colors.tapped end
    if flag(UnitIsPlayer, unit) == true then return classColor(unit) end
    return reactionColor(unit)
end

function ui.PowerColor(unit)
    local ok, powerIndex, powerType = core.Secret.Read(UnitPowerType, unit)
    if not ok then warnOnce("power type", powerIndex); return colors.power end
    if not readable(powerType, "string") then return colors.power end
    return lookup(PowerBarColor, powerType, colors.power)
end
