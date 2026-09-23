-- Edit Mode never overrides RikUI. Some frames RikUI sizes or places are Edit Mode systems (the main
-- chat window, the damage meter): whenever Edit Mode applies a layout (login, a spec change, a layout
-- switch, leaving Edit Mode) the system's UpdateSystem re-anchors it and writes the size stored in the
-- Edit Mode layout. A guard puts RikUI's values back afterwards. While Edit Mode is open the frame is
-- left to it, so its sliders and drags still work; leaving Edit Mode restores RikUI's values.
-- The guard never hooks the system's own methods: on 1.60.1.69977 a method hook on a Blizzard frame
-- left the method nil for Blizzard's callers (ChatFrame1:SetPoint inside InitSystemAnchors). It listens
-- to the events that make EditModeManagerFrame apply a layout, and re-applies on the next frame, after
-- Blizzard's own handler has run.
local core = RikUI
local editmode = { Guards = {} }
core.EditMode = editmode

-- A frame is an Edit Mode system when the client copied the system mixin onto the frame itself.
local SYSTEM_METHODS = { "UpdateSystem", "ApplySystemAnchor", "UpdateSystemSetting" }
-- Events EditModeManagerFrame answers by applying the active layout (EditModeManager.lua OnEvent).
local LAYOUT_EVENTS = { "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_SPECIALIZATION_CHANGED" }
local EXIT_EVENT = "EditMode.Exit"
local guarded = setmetatable({}, { __mode = "k" })
local listening, deferred = false, false

function editmode.IsActive()
    local manager = EditModeManagerFrame
    if type(manager) ~= "table" or type(manager.IsEditModeActive) ~= "function" then return false end
    local ok, active = pcall(manager.IsEditModeActive, manager)
    return ok and active == true
end

local function run(guard)
    guard.pending = false
    if editmode.IsActive() then return end
    local ok, reason = pcall(guard.reapply, guard.frame)
    if ok or guard.warned then return end
    guard.warned = true
    core:Print("Edit Mode guard " .. guard.label .. ": " .. tostring(reason))
end

-- One queued re-apply per frame: in combat Edit Mode may apply a layout several times.
local function request(guard)
    if guard.pending or editmode.IsActive() then return end
    guard.pending = true
    core.Combat.Queue(function() run(guard) end)
end

function editmode.RestoreAll()
    for _, guard in ipairs(editmode.Guards) do request(guard) end
end

-- A layout event reaches RikUI and Blizzard in an unknown order; the re-apply waits a frame.
local function afterLayout()
    if deferred then return end
    deferred = true
    local function fire() deferred = false; editmode.RestoreAll() end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(0, fire) else fire() end
end

local function listen()
    if listening then return end
    listening = true
    for _, event in ipairs(LAYOUT_EVENTS) do core:RegisterEvent(event, afterLayout, editmode) end
    if type(EventRegistry) ~= "table" or type(EventRegistry.RegisterCallback) ~= "function" then return end
    local ok, reason = pcall(EventRegistry.RegisterCallback, EventRegistry, EXIT_EVENT, editmode.RestoreAll, editmode)
    if not ok then core:Print("Edit Mode guard: " .. tostring(reason)) end
end

-- reapply(frame) writes RikUI's size or place. Returns false for a frame Edit Mode does not manage.
-- One frame may carry several guards under different labels (the chat window's place and its size).
function editmode.Guard(frame, label, reapply)
    assert(type(label) == "string" and type(reapply) == "function", "EditMode.Guard needs a label and a function")
    if type(frame) ~= "table" then return false end
    if guarded[frame] and guarded[frame][label] then return true end
    local system = false
    for _, method in ipairs(SYSTEM_METHODS) do
        -- rawget: a frame that only inherits a method of that name is not an Edit Mode system.
        if type(rawget(frame, method)) == "function" then system = true end
    end
    if not system then return false end
    local guard = { frame = frame, label = label, reapply = reapply, pending = false }
    guarded[frame] = guarded[frame] or {}
    guarded[frame][label] = guard
    editmode.Guards[#editmode.Guards + 1] = guard
    listen()
    return true
end
