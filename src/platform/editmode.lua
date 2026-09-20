-- Edit Mode never overrides RikUI. Some frames RikUI sizes or places are Edit Mode systems (the main
-- chat window, the damage meter): whenever Edit Mode applies a layout (login, a spec change, a layout
-- switch, leaving Edit Mode) the system's UpdateSystem re-anchors it and writes the size stored in the
-- Edit Mode layout. A guard post-hooks the frame's own Edit Mode methods and puts RikUI's values back
-- afterwards. While Edit Mode is open the frame is left to it, so its sliders and drags still work;
-- leaving Edit Mode restores RikUI's values. Post-hooks on the frame itself leave Blizzard's call
-- path untouched.
local core = RikUI
local editmode = { Guards = {} }
core.EditMode = editmode

-- What Edit Mode calls on a system when a layout applies, and when a single setting changes.
local METHODS = { "UpdateSystem", "ApplySystemAnchor", "UpdateSystemSetting" }
local EXIT_EVENT = "EditMode.Exit"
local guarded = setmetatable({}, { __mode = "k" })
local listening = false

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

-- One queued re-apply per frame: in combat Edit Mode may touch a system several times.
local function request(guard)
    if guard.pending or editmode.IsActive() then return end
    guard.pending = true
    core.Combat.Queue(function() run(guard) end)
end

local function restoreAll()
    for _, guard in ipairs(editmode.Guards) do request(guard) end
end

local function listenForExit()
    if listening then return end
    listening = true
    if type(EventRegistry) ~= "table" or type(EventRegistry.RegisterCallback) ~= "function" then return end
    local ok, reason = pcall(EventRegistry.RegisterCallback, EventRegistry, EXIT_EVENT, restoreAll, editmode)
    if not ok then core:Print("Edit Mode guard: " .. tostring(reason)) end
end

-- reapply(frame) writes RikUI's size or place. Returns false for a frame Edit Mode does not manage.
function editmode.Guard(frame, label, reapply)
    assert(type(label) == "string" and type(reapply) == "function", "EditMode.Guard needs a label and a function")
    if type(frame) ~= "table" then return false end
    if guarded[frame] then return true end
    local guard = { frame = frame, label = label, reapply = reapply, pending = false }
    local hooked = false
    for _, method in ipairs(METHODS) do
        -- rawget: the client copies a system's mixin onto the frame itself, so a frame that only
        -- inherits a method of that name is not an Edit Mode system.
        if type(rawget(frame, method)) == "function" then
            hooksecurefunc(frame, method, function() request(guard) end)
            hooked = true
        end
    end
    if not hooked then return false end
    guarded[frame] = guard
    editmode.Guards[#editmode.Guards + 1] = guard
    listenForExit()
    return true
end
