-- Unit readers and their sinks. Health and power values are never compared; they go
-- straight into StatusBar and FontString sinks that accept secret values.
local core, unitframes = RikUI, RikUI.UnitFrames
local VALUE_FORMAT, LEVEL_FORMAT, UNKNOWN_LEVEL = "%d / %d", "%d", "??"
local colors = {
    neutral = { r = 0.6, g = 0.6, b = 0.6 },
    disconnected = { r = 0.5, g = 0.5, b = 0.5 },
    tapped = { r = 0.55, g = 0.57, b = 0.61 },
    power = { r = 0, g = 0.5, b = 1 },
}
unitframes.Colors = colors
local warnings = {}

local function warnOnce(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Unit frames " .. operation .. ": " .. tostring(reason))
end

local function readable(value, kind)
    return not core.Secret.IsSecret(value) and type(value) == kind
end

local function readHealth(unit) return UnitHealth(unit), UnitHealthMax(unit) end
local function readPower(unit) return UnitPower(unit), UnitPowerMax(unit) end

local function fill(bar, current, maximum)
    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(current)
    if bar.text then bar.text:SetFormattedText(VALUE_FORMAT, current, maximum) end
end

local function clear(bar)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    if bar.text then bar.text:SetText("") end
end

local function feed(bar, operation, reader, unit)
    local ok, reason = core.Secret.Apply(function(current, maximum) fill(bar, current, maximum) end, reader, unit)
    if not ok then clear(bar); warnOnce(operation, reason) end
end

-- Lookups into Blizzard colour tables use only readable keys; anything else is neutral.
local function lookup(table, key, fallback)
    if type(table) ~= "table" or key == nil then return fallback end
    return table[key] or fallback
end

local function flag(reader, unit)
    local ok, value = core.Secret.Read(reader, unit)
    if ok and readable(value, "boolean") then return value end
    if not ok then warnOnce("state", value) end
end

local function classColor(unit)
    local ok, _, classFilename = core.Secret.Read(UnitClass, unit)
    if not ok then warnOnce("class", classFilename); return colors.neutral end
    if not readable(classFilename, "string") then return colors.neutral end
    return lookup(RAID_CLASS_COLORS, classFilename, colors.neutral)
end

local function reactionColor(unit)
    local ok, reaction = core.Secret.Read(UnitReaction, unit, "player")
    if not ok then warnOnce("reaction", reaction); return colors.neutral end
    if not readable(reaction, "number") then return colors.neutral end
    return lookup(FACTION_BAR_COLORS, reaction, colors.neutral)
end

function unitframes.HealthColor(unit)
    if flag(UnitIsConnected, unit) == false then return colors.disconnected end
    if flag(UnitIsTapDenied, unit) == true then return colors.tapped end
    if flag(UnitIsPlayer, unit) == true then return classColor(unit) end
    return reactionColor(unit)
end

function unitframes.PowerColor(unit)
    local ok, _, token = core.Secret.Read(UnitPowerType, unit)
    if not ok then warnOnce("power type", token); return colors.power end
    if not readable(token, "string") then return colors.power end
    return lookup(PowerBarColor, token, colors.power)
end

local function tint(bar, color)
    bar:SetStatusBarColor(color.r, color.g, color.b)
end

function unitframes.UpdateHealth(frame)
    feed(frame.health, "health", readHealth, frame.unit)
end

function unitframes.UpdatePower(frame)
    tint(frame.power, unitframes.PowerColor(frame.unit))
    feed(frame.power, "power", readPower, frame.unit)
end

local function updateName(frame)
    local ok, name = core.Secret.Read(UnitName, frame.unit)
    if not ok then warnOnce("name", name); frame.name:SetText(""); return end
    frame.name:SetText(name)
end

local function updateLevel(frame)
    local ok, level = core.Secret.Read(UnitLevel, frame.unit)
    if not ok then warnOnce("level", level); frame.level:SetText(""); return end
    if core.Secret.IsSecret(level) or (type(level) == "number" and level > 0) then
        frame.level:SetFormattedText(LEVEL_FORMAT, level)
    else
        frame.level:SetText(UNKNOWN_LEVEL)
    end
end

function unitframes.UpdateIdentity(frame)
    updateName(frame)
    updateLevel(frame)
    tint(frame.health, unitframes.HealthColor(frame.unit))
end

local function threatColor(status)
    if not readable(status, "number") or status <= 0 then return nil end
    local ok, r, g, b = core.Secret.Read(GetThreatStatusColor, status)
    if not ok then warnOnce("threat colour", r); return nil end
    return r, g, b
end

-- Inert when threat is secret: the border simply stays hidden.
function unitframes.UpdateThreat(frame)
    local ok, status = core.Secret.Read(UnitThreatSituation, unpack(frame.threatArgs))
    if not ok then warnOnce("threat", status); status = nil end
    local r, g, b = threatColor(status)
    for _, line in ipairs(frame.threat) do
        if r then line:SetVertexColor(r, g, b, 1); line:Show() else line:Hide() end
    end
end

function unitframes.Update(frame)
    unitframes.UpdateIdentity(frame)
    unitframes.UpdateHealth(frame)
    unitframes.UpdatePower(frame)
    unitframes.UpdateThreat(frame)
end
