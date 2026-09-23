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
    if not keepFade then
        motion.Stop(art.fade)
        motion.Stop(art.range)
        art.rangeTarget = nil
    end
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
    local art = frame.motion
    motion.Stop(art.leave)
    effects.Reset(frame)
    if frame.presence then frame.presence:Show() end
    unitframes.Update(frame)
    if art.updateStatus then art.updateStatus(frame) end
    motion.Play(art.fade)
end

-- Group art is a noninteractive sibling: secure visibility can remove the button immediately.
function effects.CreatePresentation(frame, parent)
    local presence = CreateFrame("Frame", nil, parent)
    presence:SetAllPoints(frame)
    presence:EnableMouse(false)
    local presentation = CreateFrame("Frame", nil, presence)
    presentation:SetAllPoints(presence)
    presentation:EnableMouse(false)
    frame.presence, frame.presentation = presence, presentation
end

local function onHide(frame)
    effects.Reset(frame)
    if not frame.presence then return end
    if frame.motion.leave then motion.Play(frame.motion.leave)
    else frame.presence:Hide() end
end

local function groupAnimations(frame, art)
    if not frame.presence then return end
    art.leave = motion.Tween(frame.presence, 1, 0, FADE_SECONDS)
    if art.leave then
        art.leave:SetScript("OnFinished", function()
            if not frame:IsShown() then frame.presence:Hide() end
        end)
    end
    art.range = motion.Tween(frame.presentation, 1, 1, FADE_SECONDS)
    if art.range then art.rangeAlpha = art.range:GetAnimations() end
end

function effects.Attach(frame, updateStatus)
    local art = { pulses = {}, threatActive = false, updateStatus = updateStatus }
    frame.motion = art
    frame.health.motionEnabled, frame.power.motionEnabled = true, true
    art.fade = motion.Tween(frame.presence or frame, 0, 1, FADE_SECONDS)
    local flash = frame.health:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints(frame.health)
    flash:SetColorTexture(1, 1, 1, 1)
    flash:SetAlpha(0)
    art.flash = motion.Tween(flash, FLASH_ALPHA, 0, FLASH_SECONDS)
    for _, line in ipairs(frame.threat) do
        local pulse = motion.Pulse(line, 1, PULSE_LOW, PULSE_SECONDS)
        if pulse then art.pulses[#art.pulses + 1] = pulse end
    end
    groupAnimations(frame, art)
    frame:HookScript("OnShow", onShow)
    frame:HookScript("OnHide", onHide)
    if frame:IsShown() then motion.Play(art.fade)
    elseif frame.presence then frame.presence:Hide() end
end

-- Local range targets only; never read alpha back after a secret boolean sink.
function effects.Range(frame, target)
    local owner, art = frame.presentation or frame, frame.motion
    if not art or not frame.presentation then owner:SetAlpha(target); return end
    if not frame:IsShown() or art.rangeTarget == target then return end
    local previous = art.rangeTarget
    motion.Stop(art.range)
    art.rangeTarget = target
    owner:SetAlpha(target)
    if previous and art.rangeAlpha then
        art.rangeAlpha:SetFromAlpha(previous)
        art.rangeAlpha:SetToAlpha(target)
        motion.Play(art.range)
    end
end

function effects.SecretRange(frame, value, fadeAlpha)
    local art = frame.motion
    if art then motion.Stop(art.range); art.rangeTarget = nil end
    unitframes.AlphaFromBoolean(frame.presentation or frame, value, 1, fadeAlpha)
end

-- Roster slots may be reassigned even when their secure buttons never hide.
function effects.RefreshMember(frame)
    if not frame:IsShown() then return end
    local ok, exists = RikUI.Secret.Read(UnitExists, frame.unit)
    if ok and not RikUI.Secret.IsSecret(exists) and exists == false then return end
    effects.Reset(frame, true)
    unitframes.Update(frame)
end
