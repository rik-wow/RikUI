-- Cast readers and their sinks. Cast times are never subtracted or compared in Lua: the
-- fill comes from the client's duration object, or from readable numbers when no object exists.
local core, castbars = RikUI, RikUI.CastBars
local HOLD_SECONDS, FINISH_HOLD, TIME_FORMAT, MILLISECONDS_THRESHOLD = 0.6, 0.2, "%.1f", 60
local ONE_LETTER = 2 -- Enum.SecondsFormatterAbbreviation.OneLetter on 1.60.1.70009
local FAILED_TEXT, INTERRUPTED_TEXT = FAILED or "Failed", INTERRUPTED or "Interrupted"
local DIRECTION = { cast = { name = "ElapsedTime", value = 0 }, channel = { name = "RemainingTime", value = 1 } }
local colors = {
    cast = { r = 1, g = 0.7, b = 0.1 },
    channel = { r = 0.3, g = 0.65, b = 1 },
    interrupted = { r = 0.9, g = 0.2, b = 0.2 },
}
castbars.Colors = colors
local warnings, formatter = {}, nil

local function warnOnce(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Castbars " .. operation .. ": " .. tostring(reason))
end

local function readable(value, kind)
    return not core.Secret.IsSecret(value) and type(value) == kind
end

-- Secret values are never compared, not even against nil.
local function present(value)
    return core.Secret.IsSecret(value) or value ~= nil
end

local function boolean(value)
    if core.Secret.IsSecret(value) then return value end
    return value == true
end

local function enumValue(group, name, fallback)
    local values = type(Enum) == "table" and Enum[group]
    if type(values) == "table" and values[name] ~= nil then return values[name] end
    return fallback
end

-- UnitCastingInfo: name, text, texture, start, end, tradeskill, castID, notInterruptible.
-- UnitChannelInfo: name, text, texture, start, end, tradeskill, notInterruptible.
local function readInfo(unit, channel)
    local reader = channel and UnitChannelInfo or UnitCastingInfo
    local ok, name, text, texture, startMs, endMs, _, seventh, eighth = core.Secret.Read(reader, unit)
    if not ok then warnOnce("cast info", name); return nil end
    if not present(name) then return nil end
    local info = { text = present(text) and text or name, texture = texture, startMs = startMs, endMs = endMs }
    if channel then info.notInterruptible = seventh else info.castID, info.notInterruptible = seventh, eighth end
    return info
end

local function secondsFormatter()
    if formatter ~= nil then return formatter or nil end
    formatter = false
    if type(C_StringUtil) ~= "table" or type(C_StringUtil.CreateSecondsFormatter) ~= "function" then return nil end
    local ok, created = pcall(function()
        local object = C_StringUtil.CreateSecondsFormatter()
        object:SetMillisecondsThreshold(MILLISECONDS_THRESHOLD)
        object:SetDesiredUnitCount(1)
        object:SetMinInterval(enumValue("SecondsFormatterInterval", "Seconds", 0))
        -- "1.5 s", not "1.5 seconds": the time field is narrow and the unit word would be clipped.
        object:SetDefaultAbbreviation(enumValue("SecondsFormatterAbbreviation", "OneLetter", ONE_LETTER))
        return object
    end)
    if not ok then warnOnce("formatter", created); return nil end
    formatter = created
    return created
end

-- The binding updates the time text from the duration object without Lua arithmetic.
local function binding(bar)
    if bar.binding ~= nil then return bar.binding or nil end
    bar.binding = false
    local format = secondsFormatter()
    if not format or type(C_DurationUtil) ~= "table" then return nil end
    if type(C_DurationUtil.CreateDurationTextBinding) ~= "function" then return nil end
    local ok, created = pcall(function()
        local object = C_DurationUtil.CreateDurationTextBinding()
        object:SetFontString(bar.time)
        object:SetFormatter(format)
        return object
    end)
    if not ok then warnOnce("timer text", created); return nil end
    bar.binding = created
    return created
end

local function durationFill(bar, unit, mode)
    local reader = mode == "channel" and UnitChannelDuration or UnitCastingDuration
    if type(reader) ~= "function" then return false end
    local ok, duration = core.Secret.Read(reader, unit)
    if not ok then warnOnce("duration", duration); return false end
    if core.Secret.IsSecret(duration) or duration == nil then return false end
    local direction = enumValue("StatusBarTimerDirection", DIRECTION[mode].name, DIRECTION[mode].value)
    local interpolation = enumValue("StatusBarInterpolation", "Immediate", 0)
    local applied, reason = pcall(bar.SetTimerDuration, bar, duration, interpolation, direction)
    if not applied then warnOnce("timer", reason); return false end
    local text = binding(bar)
    if text then pcall(text.SetDuration, text, duration); pcall(text.SetEnabled, text, true) end
    return true
end

local function tick(bar)
    local manual = bar.manual
    if not manual then return end
    local now = GetTime()
    local total, remaining = manual.finish - manual.start, math.max(0, manual.finish - now)
    local elapsed = math.min(total, math.max(0, now - manual.start))
    bar:SetValue(manual.channel and math.min(total, remaining) or elapsed)
    bar.time:SetFormattedText(TIME_FORMAT, remaining)
end

function castbars.Tick(frame)
    tick(frame.bar)
end

local function manualFill(bar, info, mode)
    if not readable(info.startMs, "number") or not readable(info.endMs, "number") then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        warnOnce("fill", "cast times are secret and no duration object is available")
        return
    end
    bar.manual = { start = info.startMs / 1000, finish = info.endMs / 1000, channel = mode == "channel" }
    bar:SetMinMaxValues(0, bar.manual.finish - bar.manual.start)
    tick(bar)
end

local function clearFill(bar)
    bar.manual = nil
    local text = bar.binding
    if text then pcall(text.SetEnabled, text, false) end
    bar.time:SetText("")
end

local function fill(bar, unit, info, mode)
    clearFill(bar)
    if durationFill(bar, unit, mode) then return end
    manualFill(bar, info, mode)
end

local function tint(bar, color)
    bar:SetStatusBarColor(color.r, color.g, color.b)
end

function castbars.ResetMotion(frame)
    frame.fading = nil
    core.Motion.Stop(frame.fadeIn)
    core.Motion.Stop(frame.fadeOut)
    core.Motion.Stop(frame.flashTween)
    frame:SetAlpha(1)
    frame.flash:SetAlpha(0)
    frame.spark:Hide()
end

local function fadeOut(frame)
    core.Motion.Stop(frame.fadeIn)
    frame.fading = true
    if frame.fadeOut then core.Motion.Play(frame.fadeOut) else castbars.Finish(frame) end
end

local function cancelHold(frame)
    frame.hold = (frame.hold or 0) + 1
end

function castbars.Finish(frame)
    frame.state, frame.castID = nil, nil
    cancelHold(frame)
    clearFill(frame.bar)
    castbars.ResetMotion(frame)
    frame:Hide()
end

function castbars.SetShield(frame, notInterruptible)
    if frame.shield then frame.shield:SetAlphaFromBoolean(boolean(notInterruptible), 1, 0) end
end

function castbars.Begin(frame, channel, info)
    local mode = channel and "channel" or "cast"
    info = info or readInfo(frame.unit, channel)
    if not info then castbars.Finish(frame); return end
    castbars.ResetMotion(frame)
    frame.state, frame.castID = mode, info.castID
    cancelHold(frame)
    frame.bar.text:SetText(info.text)
    frame.icon:SetTexture(info.texture)
    castbars.SetShield(frame, info.notInterruptible)
    tint(frame.bar, colors[mode])
    fill(frame.bar, frame.unit, info, mode)
    frame:Show()
    frame.spark:Show()
    core.Motion.Play(frame.fadeIn)
end

-- Delays and channel updates keep the state and re-read the times.
function castbars.Refill(frame)
    if not frame.state then return end
    local info = readInfo(frame.unit, frame.state == "channel")
    if not info then castbars.Finish(frame); return end
    fill(frame.bar, frame.unit, info, frame.state)
end

function castbars.Sync(frame)
    local cast = readInfo(frame.unit, false)
    if cast then castbars.Begin(frame, false, cast); return end
    local channel = readInfo(frame.unit, true)
    if channel then castbars.Begin(frame, true, channel); return end
    castbars.Finish(frame)
end

-- Cast identities are compared only when both are readable strings.
local function sameCast(frame, castID)
    if not readable(frame.castID, "string") or not readable(castID, "string") then return true end
    return frame.castID == castID
end

local function hold(frame, label)
    frame.state, frame.castID = nil, nil
    clearFill(frame.bar)
    core.Motion.Stop(frame.fadeIn)
    frame.spark:Hide()
    if label then tint(frame.bar, colors.interrupted) end
    if label then frame.bar.text:SetText(label) end
    frame.flash:SetVertexColor(label and 1 or 0.65, label and 0.15 or 1, label and 0.12 or 0.8)
    core.Motion.Play(frame.flashTween)
    frame.bar:SetMinMaxValues(0, 1)
    frame.bar:SetValue(1)
    cancelHold(frame)
    local token = frame.hold
    C_Timer.After(label and HOLD_SECONDS or FINISH_HOLD, function()
        if frame.hold == token then fadeOut(frame) end
    end)
end

function castbars.Stop(frame, castID)
    if frame.state == "cast" and sameCast(frame, castID) then hold(frame) end
end

function castbars.StopChannel(frame, interruptedBy)
    if frame.state ~= "channel" then return end
    if readable(interruptedBy, "string") and interruptedBy ~= "" then hold(frame, INTERRUPTED_TEXT); return end
    hold(frame)
end

function castbars.Fail(frame, castID)
    if frame.state == "cast" and sameCast(frame, castID) then hold(frame, FAILED_TEXT) end
end

function castbars.Interrupt(frame, castID)
    if frame.state == "channel" or (frame.state == "cast" and sameCast(frame, castID)) then
        hold(frame, INTERRUPTED_TEXT)
    end
end
