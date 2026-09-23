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

-- Typed combat feedback never inspects a health value or combat amount.
local HEALTH_FEEDBACK = {
    damage = { color = { 1, 0.18, 0.12 }, alpha = 0.5, seconds = 0.18 },
    heal = { color = { 0.2, 1, 0.45 }, alpha = 0.28, seconds = 0.4 },
}

function motion.HealthFeedback(owner)
    local feedback = {}
    for key, style in pairs(HEALTH_FEEDBACK) do
        local region = owner:CreateTexture(nil, "OVERLAY")
        region:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        region:SetVertexColor(unpack(style.color))
        region:SetAllPoints(owner)
        region:SetAlpha(0)
        feedback[key] = { region = region, group = motion.Tween(region, style.alpha, 0, style.seconds) }
    end
    return feedback
end

function motion.StopHealthFeedback(feedback)
    if not feedback then return end
    motion.Stop(feedback.damage.group)
    motion.Stop(feedback.heal.group)
end

function motion.PlayHealthFeedback(feedback, event)
    if not feedback or RikUI.Secret.IsSecret(event) or type(event) ~= "string" then return end
    local key = event == "WOUND" and "damage" or event == "HEAL" and "heal"
    if not key then return end
    motion.StopHealthFeedback(feedback)
    motion.Play(feedback[key].group)
end
