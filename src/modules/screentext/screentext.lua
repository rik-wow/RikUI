-- The RikUI font on the text Blizzard writes across the middle of the screen: zone, subzone and
-- PvP zone text, the red error line, auto-follow and raid warnings. Fonts only; no frame is moved,
-- hidden or rescripted. Zone and error text have font objects of their own, so those are restyled.
-- Raid warning lines come from a pool on GameFontNormalHuge, which the whole UI shares, so they
-- are restyled per string as the pool hands them out.
local core, media = RikUI, RikUI.Media
local screentext = {}
core.ScreenText = screentext

local FLAGS = "OUTLINE"
-- Font object or font string global, and the size used when the client reports none.
local TARGETS = {
    { name = "ZoneTextFont", size = 32 }, { name = "SubZoneTextFont", size = 26 },
    { name = "PVPInfoTextFont", size = 22 }, { name = "ErrorFont", size = 16 },
    { name = "AutoFollowStatusText", size = 20 },
}
local WARNING_FRAME, WARNING_METHOD, WARNING_SIZE = "RaidWarningFrame", "AcquireOrEvictSlot", 20
local restyled, warnings, counts = setmetatable({}, { __mode = "k" }), {}, { fonts = 0, warnings = 0 }

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Screen text " .. operation .. ": " .. tostring(reason))
end

local function hasFont(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetFont) == "function"
        and type(value.GetFont) == "function"
end

local function currentSize(object, fallback)
    local ok, _, size = pcall(object.GetFont, object)
    return ok and type(size) == "number" and size > 0 and size or fallback
end

local function restyle(object, label, fallback)
    local ok, loaded = pcall(object.SetFont, object, media.font, currentSize(object, fallback), FLAGS)
    if ok and loaded ~= false then return true end
    warn("font " .. label, ok and "the client refused the font" or loaded)
    return false
end

-- The pool reuses its strings, so each one is restyled once.
local function restyleWarnings(frame)
    local pool = frame.fontStringPool
    if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
    for line in pool:EnumerateActive() do
        if not restyled[line] and hasFont(line) then
            restyled[line] = true
            if restyle(line, "raid warning", WARNING_SIZE) then counts.warnings = counts.warnings + 1 end
        end
    end
end

-- RaidWarningFrame runs OnUpdate every frame while it shows a line, and a new line is added during
-- event handling, before the next frame draws; restyling from OnUpdate reaches every line first.
-- AcquireOrEvictSlot is not hooked: on 69977 a method hook on a Blizzard frame left the method nil
-- for Blizzard's callers.
local function hookWarnings()
    local frame = _G[WARNING_FRAME]
    if type(frame) ~= "table" or type(frame[WARNING_METHOD]) ~= "function" then return end
    core.Hooks.Script(frame, "OnUpdate", restyleWarnings)
end

-- Font writes are not protected, so nothing here waits for combat to end.
function screentext:OnEnable()
    for _, target in ipairs(TARGETS) do
        local object = _G[target.name]
        if hasFont(object) and restyle(object, target.name, target.size) then counts.fonts = counts.fonts + 1 end
    end
    hookWarnings()
end

function screentext:Debug()
    core:Print("Screen text fonts=" .. counts.fonts .. " warnings=" .. counts.warnings)
end

core:RegisterModule("screentext", screentext)
