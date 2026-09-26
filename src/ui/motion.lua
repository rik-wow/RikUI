-- Shared animation helpers for the furniture modules: one alpha tween per owner and the client's
-- StatusBar easing. Every helper degrades to nothing on a client without the feature.
local motion = {}
RikUI.Motion = motion

function motion.Reduced()
    return RikUI.Profile and RikUI.Profile.reducedMotion == true
end

function motion.Interpolation(name)
    if motion.Reduced() then name = "Immediate" end
    local enum = type(Enum) == "table" and Enum.StatusBarInterpolation
    return type(enum) == "table" and enum[name] or nil
end

-- One alpha tween on a region or frame; nil where the client has no animation groups. delay holds
-- the start back, which staggers a row of things that appear together.
function motion.Tween(owner, from, to, seconds, delay)
    if motion.Reduced() then return nil end
    local group = type(owner.CreateAnimationGroup) == "function" and owner:CreateAnimationGroup() or nil
    if not group then return nil end
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(from)
    alpha:SetToAlpha(to)
    alpha:SetDuration(seconds)
    group.rikAlpha = alpha
    if delay and type(alpha.SetStartDelay) == "function" then alpha:SetStartDelay(delay) end
    return group
end

-- A region travelling distance units to the right over and over: the band of an indeterminate
-- state. The region's parent has to clip it. nil where the client lacks translation animations.
function motion.Sweep(region, distance, seconds)
    if motion.Reduced() then return nil end
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
    if motion.Reduced() then return end
    group:Play()
end


local ENTRY_SECONDS, HOVER_SECONDS, FLASH_SECONDS = 0.18, 0.1, 0.45
local SLIDE_DISTANCE, HOVER_ALPHA = 6, 0.12

-- Cosmetic transforms reset when the group ends; layout anchors are never moved.
function motion.Entrance(owner, slide)
    local group = motion.Tween(owner, 0, 1, ENTRY_SECONDS)
    if not group then return end
    if slide then
        local shift = group:CreateAnimation("Translation")
        shift:SetOffset(0, -SLIDE_DISTANCE)
        shift:SetDuration(0)
        shift:SetOrder(1)
        local rise = group:CreateAnimation("Translation")
        rise:SetOffset(0, SLIDE_DISTANCE)
        rise:SetDuration(ENTRY_SECONDS)
        rise:SetOrder(2)
        -- Alpha and rise start after the instantaneous initial offset.
        group.rikAlpha:SetOrder(2)
    end
    return group
end

-- Only addon-owned surfaces may opt into a delayed hide.
function motion.CloseOwned(owner)
    if not owner or not owner:IsShown() then return end
    if motion.Reduced() then
        motion.CancelClose(owner)
        motion.Stop(owner.rikEntry)
        owner:Hide()
        return
    end
    if owner.rikClosing then return end
    motion.Stop(owner.rikEntry)
    local group = owner.rikExit
    if not group then
        group = motion.Tween(owner, 1, 0, 0.12)
        if not group then owner:Hide(); return end
        owner.rikExit = group
        group:SetScript("OnFinished", function()
            if owner.rikClosing then owner.rikClosing = nil; owner:Hide() end
        end)
        owner:HookScript("OnHide", function() owner.rikClosing = nil; motion.Stop(group) end)
    end
    owner.rikClosing = true
    motion.Play(group)
end

function motion.CancelClose(owner)
    if not owner then return end
    owner.rikClosing = nil
    motion.Stop(owner.rikExit)
end
function motion.BindEntrance(owner, slide)
    local existing = owner.rikEntry
    if type(existing) == "table" or type(existing) == "userdata" then return end
    local group = motion.Entrance(owner, slide)
    if not group then return end
    owner.rikEntry = group
    owner:HookScript("OnShow", function() motion.Play(group) end)
    owner:HookScript("OnHide", function() motion.Stop(group) end)
end

local function effectRegion(owner)
    local region = owner:CreateTexture(nil, "OVERLAY")
    region:SetAllPoints(owner)
    region:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    region:SetVertexColor(1, 0.82, 0)
    region:SetAlpha(0)
    return region
end

function motion.BindHover(owner)
    if owner.rikHover then return end
    local value = { region = effectRegion(owner) }
    value.enter = motion.Tween(value.region, 0, HOVER_ALPHA, HOVER_SECONDS)
    value.leave = motion.Tween(value.region, HOVER_ALPHA, 0, HOVER_SECONDS)
    owner.rikHover = value
    local function clear()
        motion.Stop(value.enter); motion.Stop(value.leave); value.region:SetAlpha(0)
    end
    if not owner.HasScript or owner:HasScript("OnDisable") ~= false then owner:HookScript("OnDisable", clear) end
    owner:HookScript("OnEnter", function()
        if owner.IsEnabled and owner:IsEnabled() == false then return end
        motion.Stop(value.leave)
        value.region:SetAlpha(HOVER_ALPHA)
        motion.Play(value.enter)
    end)
    owner:HookScript("OnLeave", function()
        clear()
        if not owner.IsEnabled or owner:IsEnabled() ~= false then motion.Play(value.leave) end
    end)
    owner:HookScript("OnHide", clear)
end

local PRESS_ALPHA, RELEASE_SECONDS = 0.24, 0.18

-- Region-only response: native click handlers and button geometry stay authoritative.
function motion.BindPress(owner, storage)
    storage = storage or owner
    if storage.rikPress then return end
    local value = { region = effectRegion(owner) }
    value.release = motion.Tween(value.region, PRESS_ALPHA, 0, RELEASE_SECONDS)
    storage.rikPress = value
    local function clear()
        value.down = false
        motion.Stop(value.release)
        value.region:SetAlpha(0)
    end
    owner:HookScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or (owner.IsEnabled and owner:IsEnabled() == false) then return end
        motion.Stop(value.release)
        value.down = true
        value.region:SetAlpha(PRESS_ALPHA)
    end)
    owner:HookScript("OnMouseUp", function()
        local down = value.down
        clear()
        if down and not motion.Reduced() then motion.Play(value.release) end
    end)
    owner:HookScript("OnHide", clear)
    if not owner.HasScript or owner:HasScript("OnDisable") ~= false then owner:HookScript("OnDisable", clear) end
end

function motion.Flash(owner, color)
    if motion.Reduced() then return end
    if not owner.rikFlashRegion then
        local region = effectRegion(owner)
        owner.rikFlashRegion = region
        owner.rikFlash = motion.Tween(region, 0.32, 0, FLASH_SECONDS)
        owner:HookScript("OnHide", function() motion.Stop(owner.rikFlash); region:SetAlpha(0) end)
    end
    color = color or { 1, 0.82, 0 }
    owner.rikFlashRegion:SetVertexColor(color[1], color[2], color[3])
    owner.rikFlashRegion:SetAlpha(0)
    motion.Play(owner.rikFlash)
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
