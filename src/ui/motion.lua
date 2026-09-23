-- Shared animation helpers for the furniture modules: one alpha tween per owner and the client's
-- StatusBar easing. Every helper degrades to nothing on a client without the feature.
local motion = {}
RikUI.Motion = motion

function motion.Interpolation(name)
    local enum = type(Enum) == "table" and Enum.StatusBarInterpolation
    return type(enum) == "table" and enum[name] or nil
end

-- One alpha tween on a region or frame; nil where the client has no animation groups. delay holds
-- the start back, which staggers a row of things that appear together.
function motion.Tween(owner, from, to, seconds, delay)
    local group = type(owner.CreateAnimationGroup) == "function" and owner:CreateAnimationGroup() or nil
    if not group then return nil end
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(from)
    alpha:SetToAlpha(to)
    alpha:SetDuration(seconds)
    if delay and type(alpha.SetStartDelay) == "function" then alpha:SetStartDelay(delay) end
    return group
end

-- A region travelling distance units to the right over and over: the band of an indeterminate
-- state. The region's parent has to clip it. nil where the client lacks translation animations.
function motion.Sweep(region, distance, seconds)
    local group = type(region.CreateAnimationGroup) == "function" and region:CreateAnimationGroup() or nil
    local slide = group and group:CreateAnimation("Translation") or nil
    if not slide or type(slide.SetOffset) ~= "function" then return nil end
    slide:SetOffset(distance, 0)
    slide:SetDuration(seconds)
    if type(group.SetLooping) == "function" then group:SetLooping("REPEAT") end
    return group
end

-- The same tween bouncing between its two alphas until it is stopped.
function motion.Pulse(owner, from, to, seconds)
    local group = motion.Tween(owner, from, to, seconds)
    if group and type(group.SetLooping) == "function" then group:SetLooping("BOUNCE") end
    return group
end

function motion.Stop(group)
    if group then group:Stop() end
end

function motion.Play(group)
    if not group then return end
    group:Stop()
    group:Play()
end

-- Native fill geometry selects loss/gain regions without inspecting secret values.
local HEALTH_FEEDBACK = {
    damage = { color = { 1, 0.18, 0.12 }, alpha = 0.5, seconds = 0.18 },
    heal = { color = { 0.2, 1, 0.45 }, alpha = 0.28, seconds = 0.4 },
}
local FLAT = "Interface\\BUTTONS\\WHITE8X8"

local function healthBoundary(owner)
    local bar = CreateFrame("StatusBar", nil, owner)
    bar:SetAllPoints(owner)
    bar:EnableMouse(false)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetTexture(FLAT)
    bar:SetStatusBarTexture(bar.fill)
    bar:SetStatusBarColor(1, 1, 1, 0)
    return bar
end

local function healthOverlay(owner, inside, outside, style)
    local clip = CreateFrame("Frame", nil, owner)
    clip:SetAllPoints(inside.fill)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    local canvas = CreateFrame("Frame", nil, clip)
    canvas:SetAllPoints(owner)
    canvas:EnableMouse(false)
    local region = canvas:CreateTexture(nil, "OVERLAY")
    region:SetTexture(FLAT)
    region:SetVertexColor(unpack(style.color))
    region:SetPoint("TOPLEFT", outside.fill, "TOPRIGHT")
    region:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT")
    region:SetAlpha(0)
    return { region = region, clip = clip, group = motion.Tween(region, style.alpha, 0, style.seconds) }
end

function motion.HealthFeedback(owner)
    local feedback = { previous = healthBoundary(owner), current = healthBoundary(owner) }
    feedback.damage = healthOverlay(owner, feedback.previous, feedback.current, HEALTH_FEEDBACK.damage)
    feedback.heal = healthOverlay(owner, feedback.current, feedback.previous, HEALTH_FEEDBACK.heal)
    owner:HookScript("OnHide", function() motion.StopHealthFeedback(feedback) end)
    return feedback
end

function motion.StopHealthFeedback(feedback)
    if not feedback then return end
    motion.Stop(feedback.damage.group)
    motion.Stop(feedback.heal.group)
    feedback.initialized, feedback.value, feedback.maximum = false, nil, nil
end

local function healthBounds(bar, value, maximum)
    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(value, motion.Interpolation("Immediate"))
end

-- Call in the same sink as the visible bar's SetValue. Both fades start now;
-- clipping leaves only the lost (red) or gained (green) interval visible.
function motion.UpdateHealthFeedback(feedback, value, maximum, animate)
    if not feedback then return end
    local play = animate and feedback.initialized
    local previous, previousMax = value, maximum
    if play then previous, previousMax = feedback.value, feedback.maximum end
    motion.Stop(feedback.damage.group)
    motion.Stop(feedback.heal.group)
    healthBounds(feedback.previous, previous, previousMax)
    healthBounds(feedback.current, value, maximum)
    feedback.value, feedback.maximum, feedback.initialized = value, maximum, true
    if play then
        motion.Play(feedback.damage.group)
        motion.Play(feedback.heal.group)
    end
end
