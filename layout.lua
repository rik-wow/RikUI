-- Shared UIParent anchors. Secure frames are only written outside combat.
local core, setup = RikUI, RikUI.Setup
local layout = { Groups = {} }
core.Layout = layout
local POINTS = { TOP = true, TOPLEFT = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOM = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
local ORIGIN = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
local frameKeys, pending = {}, false

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function position(value, defaults)
    if type(value) ~= "table" then value = {} end
    return {
        point = POINTS[value.point] and value.point or defaults.point,
        relativePoint = POINTS[value.relativePoint] and value.relativePoint or defaults.relativePoint,
        x = finite(value.x) and value.x or defaults.x,
        y = finite(value.y) and value.y or defaults.y,
    }
end

function layout.GetPosition(key)
    local defaults = layout.Groups[key].defaults
    return position(core.Profile.positions[key], defaults)
end

function layout.GetScale()
    local scale = core.Profile.scale
    return finite(scale) and scale > 0 and scale or 1
end

local function applyGroup(key, group)
    local saved = layout.GetPosition(key)
    for _, frame in ipairs(group.frames) do
        frame:SetScale(layout.GetScale())
        frame:ClearAllPoints()
        frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    end
end

function layout.Apply()
    if pending or not core.Profile then return end
    pending = true
    core.Combat.Queue(function()
        pending = false
        for key, group in pairs(layout.Groups) do applyGroup(key, group) end
        if layout.RefreshMovers then layout.RefreshMovers() end
        if layout.NotifyLimits then layout.NotifyLimits() end
    end)
end

-- What the arrangement system (layout-rects.lua) needs to know about a group. label names it to the
-- player; grow is the direction a frame that changes size grows in ("UP", "DOWN", "LEFT", "RIGHT");
-- onLimit(room) hears how far it may grow; floating marks a reference place other things float over
-- (the tooltip anchor), which neither blocks nor is blocked; groups with the same exclusive tag are
-- never shown together (party and raid) and do not block each other.
local OPTIONS = { "label", "grow", "onLimit", "floating", "exclusive" }

local function newGroup(key, defaults, opts)
    defaults = position(defaults or setup.DefaultPositions[key], ORIGIN)
    local group = { frames = {}, defaults = defaults }
    for _, name in ipairs(OPTIONS) do group[name] = opts and opts[name] or nil end
    layout.Groups[key] = group
    setup.DefaultPositions[key] = position(defaults, ORIGIN)
    return group
end

function layout.Register(frame, key, defaults, opts)
    assert(frame and type(key) == "string" and key ~= "", "Layout.Register needs a frame and key")
    assert(not frameKeys[frame] or frameKeys[frame] == key, "Frame already has a different layout key")
    if frameKeys[frame] then return layout.Groups[key] end
    local group = layout.Groups[key] or newGroup(key, defaults, opts)
    frameKeys[frame] = key
    group.frames[#group.frames + 1] = frame
    core.Combat.Queue(function()
        frame:HookScript("OnSizeChanged", function()
            if layout.RefreshMovers then layout.RefreshMovers() end
            if layout.Settle then layout.Settle(key) end
        end)
    end)
    layout.Apply()
    if layout.Settle then layout.Settle(key) end
    return group
end

function layout.Reset()
    if InCombatLockdown() then return nil, "Cannot reset frames in combat." end
    if not core.Profile then return nil, "Still loading." end
    for key, group in pairs(layout.Groups) do
        core.Profile.positions[key] = position(group.defaults, ORIGIN)
    end
    layout.Apply()
    return true
end

function layout.SetScale(scale)
    if InCombatLockdown() then return nil, "Cannot scale frames in combat." end
    if not core.Profile then return nil, "Still loading." end
    if not finite(scale) or scale < 0.25 or scale > 3 then return nil, "Usage: /rik scale <0.25-3>" end
    core.Profile.scale = scale
    layout.Apply()
    return true
end

core:RegisterEvent("PLAYER_LOGIN", layout.Apply)
