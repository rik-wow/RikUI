-- Unit readers and their sinks. Health and power values are never compared; they go
-- straight into StatusBar and FontString sinks that accept secret values.
local core, unitframes = RikUI, RikUI.UnitFrames
local VALUE_FORMAT, LEVEL_FORMAT, UNKNOWN_LEVEL = "%d / %d", "%d", "??"
-- Preserve the public aliases for existing extensions.
unitframes.Colors = core.UI.Colors
unitframes.HealthColor, unitframes.PowerColor = core.UI.HealthColor, core.UI.PowerColor
local warnings = {}

local function warnOnce(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Unit frames " .. operation .. ": " .. tostring(reason))
end

local function readable(value, kind)
    return not core.Secret.IsSecret(value) and type(value) == kind
end

local function departing(frame)
    return frame.presentation and not frame:IsShown()
end

local function readHealth(unit) return UnitHealth(unit), UnitHealthMax(unit) end
local function readPower(unit) return UnitPower(unit), UnitPowerMax(unit) end

local function fill(bar, current, maximum)
    bar:SetMinMaxValues(0, maximum)
    local easing = bar.motionEnabled and unitframes.Motion.Interpolation(bar) or nil
    bar:SetValue(current, easing)
    if bar.motionEnabled then bar.motionFilled = true end
    if bar.text then bar.text:SetFormattedText(VALUE_FORMAT, current, maximum) end
end

local function clear(bar)
    bar:SetMinMaxValues(0, 1)
    bar.motionFilled = false
    local easing = bar.motionEnabled and unitframes.Motion.Interpolation(bar) or nil
    bar:SetValue(0, easing)
    if bar.text then bar.text:SetText("") end
end

local function feed(bar, operation, reader, unit)
    local ok, reason = core.Secret.Apply(function(current, maximum) fill(bar, current, maximum) end, reader, unit)
    if not ok then clear(bar); warnOnce(operation, reason) end
    return ok
end

local function tint(bar, color)
    bar:SetStatusBarColor(color.r, color.g, color.b)
end

function unitframes.UpdateHealth(frame)
    if departing(frame) then return end
    return feed(frame.health, "health", readHealth, frame.unit)
end

-- Health events update the fill immediately; readable combat actions own cues.
function unitframes.HealthChanged(frame)
    return unitframes.UpdateHealth(frame)
end

function unitframes.UpdatePower(frame)
    if departing(frame) then return end
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
    if departing(frame) then return end
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
    if departing(frame) then return end
    local ok, status = core.Secret.Read(UnitThreatSituation, unpack(frame.threatArgs))
    if not ok then warnOnce("threat", status); status = nil end
    local r, g, b = threatColor(status)
    for _, line in ipairs(frame.threat) do
        if r then line:SetVertexColor(r, g, b, 1); line:Show() else line:Hide() end
    end
    if frame.motion then unitframes.Motion.Threat(frame, r ~= nil) end
end

-- A secret boolean is never compared: SetAlphaFromBoolean takes it as it is.
function unitframes.AlphaFromBoolean(region, value, yes, no)
    if not core.Secret.IsSecret(value) then region:SetAlpha(value == true and yes or no); return end
    if type(region.SetAlphaFromBoolean) == "function" then
        region:SetAlphaFromBoolean(value, yes, no)
    else
        region:SetAlpha(yes)
    end
end

local function applyRange(frame, fadeAlpha, inRange, checked)
    if core.Secret.IsSecret(inRange) or core.Secret.IsSecret(checked) then
        unitframes.Motion.SecretRange(frame, inRange, fadeAlpha)
    else
        -- An unchecked range says nothing about distance, so the member stays opaque.
        unitframes.Motion.Range(frame, (checked ~= true or inRange == true) and 1 or fadeAlpha)
    end
end

-- Shared by the party and raid frames. A failed read leaves the member opaque.
function unitframes.FadeByRange(frame, fadeAlpha)
    if departing(frame) then return end
    if type(frame.IsVisible) == "function" then
        local ok, visible = pcall(frame.IsVisible, frame)
        if ok and not core.Secret.IsSecret(visible) and visible == false then return end
    end
    local ok, reason = core.Secret.Apply(function(inRange, checked) applyRange(frame, fadeAlpha, inRange, checked) end,
        UnitInRange, frame.unit)
    if ok then return end
    unitframes.Motion.Range(frame, 1)
    warnOnce("range", reason)
end

function unitframes.Update(frame)
    unitframes.UpdateIdentity(frame)
    unitframes.UpdateHealth(frame)
    unitframes.UpdatePower(frame)
    unitframes.UpdateThreat(frame)
end
