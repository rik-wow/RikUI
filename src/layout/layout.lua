-- Shared UIParent anchors. Secure frames are only written outside combat.
local core, setup = RikUI, RikUI.Setup
local layout = { Groups = {} }
core.Layout = layout
local POINTS = { TOP = true, TOPLEFT = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOM = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
local ORIGIN = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
local frameKeys, registrations, groupOwners, pending = {}, {}, {}, false

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

-- floating is true, or a function for a group that floats only some of the time (the loot list while
-- it opens at the cursor).
function layout.Floats(group)
    if group.overlay then return true end
    local floating = group.floating
    if type(floating) == "function" then return floating() == true end
    return floating == true
end

local function applyFrame(frame, key)
    local group = layout.Groups[key]
    -- Self-positioning groups retain their anchors, but still refresh their appearance.
    if type(group.floating) ~= "function" or group.floating() ~= true then
        local saved = layout.GetPosition(key)
        frame:SetScale(layout.GetScale())
        frame:ClearAllPoints()
        frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    end
    if group.onApply then group.onApply(frame) end
    local hidden=core.Profile.presentation and core.Profile.presentation.hidden
    if key=="chat" and core.Chat and core.Chat.SetPresentationHidden then core.Chat.SetPresentationHidden(hidden and hidden.chat==true) end
    if hidden and hidden[key] then
        if not frame.rikStudioHidden then frame.rikStudioWasShown=frame:IsShown();frame.rikStudioHidden=true end
        frame:Hide()
    elseif frame.rikStudioHidden then
        frame.rikStudioHidden=nil;if frame.rikStudioWasShown then frame:Show() end;frame.rikStudioWasShown=nil
    end
end

local function applyRegistered()
    -- Append-only registration order also includes frames registered by a callback.
    for _, entry in ipairs(registrations) do
        core.Runtime.InvokeOwned(groupOwners[entry.key], entry.label, applyFrame, entry.frame, entry.key)
    end
end

function layout.Apply()
    if pending or not core.Profile then return end
    pending = true
    core.Combat.Queue(function()
        -- Keep the guard through callbacks: nested refresh requests join this pass.
        core.Runtime.Invoke("Layout refresh", applyRegistered)
        pending = false
        -- Completion may settle resized frames and request a new geometry pass.
        if layout.RefreshMovers then core.Runtime.Invoke("Layout movers", layout.RefreshMovers) end
        if layout.NotifyLimits then core.Runtime.Invoke("Layout limits", layout.NotifyLimits) end
    end)
end

-- What the arrangement system (src/layout/layout-rects.lua) needs to know about a group. label names it to the
-- player; grow is the direction a frame that changes size grows in ("UP", "DOWN", "LEFT", "RIGHT");
-- onLimit(room) hears how far it may grow; floating marks a reference place other things float over
-- (the tooltip anchor), which neither blocks nor is blocked, and may be a function;
-- overlay also avoids collisions but retains normal saved-position placement;
-- groups with the same exclusive tag are
-- never shown together (party and raid) and do not block each other; resize holds the bounds and the
-- apply(width, height) of a group the player may resize (src/layout/layout-resize.lua); onUnlock(open) hears when
-- the group is unlocked or locked; onApply(frame) refreshes each frame's appearance after placement.
local OPTIONS = { "label", "grow", "onLimit", "floating", "overlay", "exclusive", "resize", "onUnlock", "onApply" }

-- The Centered layout (data/layouts.lua) is the default look and the one source for default places.
-- The position a module registers with is the fallback for a key that layout does not know.
local function defaultFor(key, registered)
    -- src/layout/layout-presets.lua fits the chat's place to the screen; the raw data is for the narrowest one.
    local fitted = layout.PresetPositions and core.Layouts and layout.PresetPositions(core.Layouts.Order[1])
    local centered = fitted or (core.Layouts and core.Layouts.centered and core.Layouts.centered.positions)
    return centered and centered[key] or registered or setup.DefaultPositions[key]
end

local function newGroup(key, defaults, opts)
    defaults = position(defaultFor(key, defaults), ORIGIN)
    local group = { key = key, frames = {}, defaults = defaults }
    for _, name in ipairs(OPTIONS) do group[name] = opts and opts[name] or nil end
    -- The first registration owns every refresh callback, even when another module requests it.
    local owner = opts and opts.owner
    if owner == nil then owner = core.Runtime.owner end
    groupOwners[key] = owner
    layout.Groups[key] = group
    setup.DefaultPositions[key] = position(defaults, ORIGIN)
    return group
end

function layout.Register(frame, key, defaults, opts)
    assert(frame and type(key) == "string" and key ~= "", "Layout.Register needs a frame and key")
    assert(not frameKeys[frame] or frameKeys[frame] == key, "Frame already has a different layout key")
    if frameKeys[frame] then return layout.Groups[key] end
    assert(opts == nil or type(opts) == "table", "Layout options must be a table")
    assert(not opts or opts.onApply == nil or type(opts.onApply) == "function", "Layout onApply must be a function")
    local group = layout.Groups[key] or newGroup(key, defaults, opts)
    frameKeys[frame] = key
    group.frames[#group.frames + 1] = frame
    registrations[#registrations + 1] = { frame = frame, key = key, label = "Layout " .. key }
    core.Combat.Queue(function()
        frame:HookScript("OnSizeChanged", function()
            if layout.RefreshMovers then layout.RefreshMovers() end
            if layout.Settle then layout.Settle(key, true) end
        end)
    end)
    layout.Apply()
    if layout.Settle then layout.Settle(key) end
    return group
end

-- Temporary frame placement never enters saved profile state.
function layout.Preview(profile,selected,definitions)
    if InCombatLockdown() then return nil,"Preview unavailable in combat" end
    local scale=profile.scale or layout.GetScale()
    for key,definition in pairs(definitions or {}) do
        local group=layout.Groups[key];local anchor=profile.positions and profile.positions[key]
        if group and anchor and selected[definition.component] and not layout.Floats(group) then
            for _,frame in ipairs(group.frames) do
                frame:SetScale(scale);frame:ClearAllPoints()
                frame:SetPoint(anchor.point,UIParent,anchor.relativePoint,anchor.x,anchor.y)
            end
        end
    end
    return true
end

function layout.Reset(selected)
    if InCombatLockdown() then return nil, "Cannot reset frames in combat." end
    if not core.Profile then return nil, "Still loading." end
    if selected and not layout.Groups[selected] then return nil, "Choose a registered frame." end
    if layout.StopMoving then layout.StopMoving() end
    local chat = core.Profile.chat
    core.Profile.layoutUndo = { positions = setup.CopyState(core.Profile.positions),
        chatSize = type(chat) == "table" and setup.CopyState(chat.size) or false }
    for key, group in pairs(layout.Groups) do
        if not selected or key == selected then core.Profile.positions[key] = position(group.defaults, ORIGIN) end
    end
    if core.Changed then core:Changed() end
    layout.Apply()
    return true
end

function layout.SetScale(scale)
    if InCombatLockdown() then return nil, "Cannot scale frames in combat." end
    if not core.Profile then return nil, "Still loading." end
    if not finite(scale) or scale < 0.25 or scale > 3 then return nil, "Usage: /rik scale <0.25-3>" end
    core.Profile.scale = scale
    if core.Changed then core:Changed() end
    layout.Apply()
    return true
end

core:RegisterEvent("PLAYER_LOGIN", layout.Apply)
