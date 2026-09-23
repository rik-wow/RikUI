-- Presentation state only: no unit values or status-bar values are inspected here.
local unitframes, motion = RikUI.UnitFrames, RikUI.Motion
local effects = {}
unitframes.Motion = effects
local FADE_SECONDS, FLASH_SECONDS, FLASH_ALPHA = 0.15, 0.25, 0.5
local PULSE_SECONDS, PULSE_LOW = 0.6, 0.35

function effects.Reset(frame, keepFade)
    local art = frame.motion
    if not art then return end
    frame.health.motionFilled, frame.power.motionFilled = false, false
    if not keepFade then motion.Stop(art.fade) end
    motion.Stop(art.flash)
    for _, pulse in ipairs(art.pulses) do motion.Stop(pulse) end
    art.threatActive = false
end

function effects.Interpolation(bar)
    return motion.Interpolation(bar.motionFilled and "ExponentialEaseOut" or "Immediate")
end

function effects.Threat(frame, active)
    local art = frame.motion
    if not art then return end
    active = active and frame:IsShown()
    if art.threatActive == active then return end
    art.threatActive = active
    for _, pulse in ipairs(art.pulses) do
        if active then motion.Play(pulse) else motion.Stop(pulse) end
    end
end

function effects.HealthChanged(frame, filled, succeeded)
    if frame.motion and filled and succeeded and frame:IsShown() then motion.Play(frame.motion.flash) end
end

local function onShow(frame)
    effects.Reset(frame)
    unitframes.Update(frame)
    motion.Play(frame.motion.fade)
end

-- Only solo frames opt in; the shared Build factory also serves party and raid.
function effects.Attach(frame)
    local art = { pulses = {}, threatActive = false }
    frame.motion = art
    frame.health.motionEnabled, frame.power.motionEnabled = true, true
    art.fade = motion.Tween(frame, 0, 1, FADE_SECONDS)
    local flash = frame.health:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints(frame.health)
    flash:SetColorTexture(1, 1, 1, 1)
    flash:SetAlpha(0)
    art.flash = motion.Tween(flash, FLASH_ALPHA, 0, FLASH_SECONDS)
    for _, line in ipairs(frame.threat) do
        local pulse = motion.Pulse(line, 1, PULSE_LOW, PULSE_SECONDS)
        if pulse then art.pulses[#art.pulses + 1] = pulse end
    end
    frame:HookScript("OnShow", onShow)
    frame:HookScript("OnHide", effects.Reset)
    if frame:IsShown() then motion.Play(art.fade) end
end
