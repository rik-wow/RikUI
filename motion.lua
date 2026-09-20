-- Shared animation helpers for the furniture modules: one alpha tween per owner and the client's
-- StatusBar easing. Every helper degrades to nothing on a client without the feature.
local motion = {}
RikUI.Motion = motion

function motion.Interpolation(name)
    local enum = type(Enum) == "table" and Enum.StatusBarInterpolation
    return type(enum) == "table" and enum[name] or nil
end

-- One alpha tween on a region or frame; nil where the client has no animation groups.
function motion.Tween(owner, from, to, seconds)
    local group = type(owner.CreateAnimationGroup) == "function" and owner:CreateAnimationGroup() or nil
    if not group then return nil end
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(from)
    alpha:SetToAlpha(to)
    alpha:SetDuration(seconds)
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
