-- Two small stock frames in the RikUI look. QueueStatusFrame is the tooltip beside the group finder
-- eye; it inherits TooltipBackdropTemplate and fills from a pool of entries, so its art goes on
-- first show and its entries take the typeface on every show. FramerateFrame is two font strings
-- and only needs the typeface. Nothing is moved, resized, reparented, shown, hidden or rescripted.
local core, skin, motion = RikUI, RikUI.Skin, RikUI.Motion
local hudframes = {}
core.HudFrames = hudframes

local QUEUE, FRAMERATE = "QueueStatusFrame", "FramerateFrame"
local QUEUE_ART = { "NineSlice" }
local ENTRY_TEXT = { "Title", "Status", "SubTitle", "TimeInQueue", "AverageWait", "ExtraText" }
local FRAMERATE_TEXT = { "Label", "FramerateText" }
local warnings, skinned, failed = {}, {}, {}
local counts = { hooked = 0, skinned = 0, fonts = 0 }

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("HUD frames " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.HookScript) == "function"
end

local function typefaces(owner, keys)
    local written = 0
    for _, key in ipairs(keys) do
        if skin.IsRegion(owner[key]) then
            skin.Typeface(owner[key])
            written = written + 1
        end
    end
    return written
end

local function applyQueue(frame)
    skin.Strip(frame, QUEUE_ART)
    frame.rikFill = skin.Fill(frame, skin.BACKING)
    frame.rikBorder = skin.Outline(frame)
    frame.rikFade = motion.Tween(frame, 0, 1, skin.FADE_SECONDS)
end

-- The pool hands out entries as queues come and go, so they are restyled on every show.
local function refreshQueue(frame)
    local pool = frame.statusEntriesPool
    if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
    for entry in pool:EnumerateActive() do typefaces(entry, ENTRY_TEXT) end
end

-- A failed frame is not retried: half a skin applied twice is worse than half a skin.
local function showQueue(frame)
    if not skinned[QUEUE] and not failed[QUEUE] then
        local ok, reason = pcall(applyQueue, frame)
        if ok then
            skinned[QUEUE] = true
            counts.skinned = counts.skinned + 1
        else
            failed[QUEUE] = true
            warn("skin " .. QUEUE, reason)
        end
    end
    if not skinned[QUEUE] then return end
    local ok, reason = pcall(refreshQueue, frame)
    if not ok then warn("entries " .. QUEUE, reason) end
    motion.Play(frame.rikFade)
end

local function hookQueue()
    local frame = _G[QUEUE]
    if not isFrame(frame) then return end
    counts.hooked = counts.hooked + 1
    frame:HookScript("OnShow", showQueue)
    if frame:IsShown() then showQueue(frame) end
end

local function restyleFramerate()
    local frame = _G[FRAMERATE]
    if not isFrame(frame) then return end
    local ok, written = pcall(typefaces, frame, FRAMERATE_TEXT)
    if ok then counts.fonts = written else warn("font " .. FRAMERATE, written) end
end

function hudframes:OnEnable()
    hookQueue()
    restyleFramerate()
end

function hudframes:Debug()
    core:Print("HUD frames hooked=" .. counts.hooked .. " skinned=" .. counts.skinned .. " fonts=" .. counts.fonts)
end

core:RegisterModule("hudframes", hudframes)
