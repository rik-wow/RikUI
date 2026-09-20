-- Shared reversible hiding for Blizzard frames. Parent writes run only out of combat.
local core = RikUI
local CONTAINER_NAME = "RikUIHiddenFrames"
local EDIT_MODE_WARNING = "Edit Mode cannot show or move frames RikUI has hidden; " ..
    "use /rik move for RikUI frames or /rik stockbars show first."
local hide = {}
core.Hide = hide
local records, container, changing, editModeHooked = {}, nil, false, false

local function hiddenParent()
    if not container then
        container = CreateFrame("Frame", CONTAINER_NAME, UIParent)
        container:Hide()
    end
    return container
end

local function isFrame(frame)
    local kind = type(frame)
    if kind ~= "table" and kind ~= "userdata" then return false end
    return type(frame.SetParent) == "function" and type(frame.GetParent) == "function"
end

local function setParent(frame, parent)
    changing = true
    local ok, reason = pcall(frame.SetParent, frame, parent)
    changing = false
    if not ok then error(reason, 0) end
end

local function park(record)
    local frame = record.frame
    if not record.keepEvents and not record.eventsDropped then
        record.eventsDropped = true
        frame:UnregisterAllEvents()
    end
    if frame:GetParent() ~= hiddenParent() then setParent(frame, hiddenParent()) end
end

local function release(record)
    local frame = record.frame
    if frame:GetParent() == hiddenParent() then setParent(frame, record.parent) end
    local callback = record.onRestored
    record.onRestored = nil
    if callback then callback(frame) end
end

-- The latest request wins; one queued application serves any number of calls.
local function apply(record)
    record.pending = false
    if record.wanted then park(record) else release(record) end
end

local function schedule(record)
    if record.pending then return end
    record.pending = true
    core.Combat.Queue(function() apply(record) end)
end

local function warnOnEditMode()
    if editModeHooked then return end
    editModeHooked = true
    local manager = EditModeManagerFrame
    if not isFrame(manager) or type(manager.HookScript) ~= "function" then return end
    local ok, reason = pcall(manager.HookScript, manager, "OnShow", function() core:Print(EDIT_MODE_WARNING) end)
    if not ok then core:Print("Edit Mode warning unavailable: " .. tostring(reason)) end
end

local function remember(frame)
    local record = records[frame]
    if record then return record end
    record = { frame = frame, parent = frame:GetParent() }
    records[frame] = record
    hooksecurefunc(frame, "SetParent", function(self)
        if changing or self:GetParent() == hiddenParent() then return end
        -- Track the latest native attachment, including Edit Mode changes, then re-park.
        record.parent = self:GetParent()
        if record.wanted then schedule(record) end
    end)
    return record
end

-- keepEvents == false unregisters the frame's events once it is parked; the
-- events return only after a reload. Omit or pass true for frames whose native
-- handlers must keep running, such as action bars driven by key bindings.
function hide.Frame(frame, keepEvents)
    if not isFrame(frame) then return nil, "Hide.Frame needs a frame" end
    local record = remember(frame)
    record.wanted, record.keepEvents = true, keepEvents ~= false
    schedule(record)
    warnOnEditMode()
    return true
end

function hide.Restore(frame, onRestored)
    local record = records[frame]
    if not record then return nil, "frame was never hidden" end
    record.wanted, record.onRestored = false, onRestored
    schedule(record)
    return true
end

function hide.IsHidden(frame)
    local record = records[frame]
    return record ~= nil and record.wanted == true
end
