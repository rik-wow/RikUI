-- The RikUI font on the text Blizzard writes across the middle of the screen: zone, subzone and
-- PvP zone text, the red error line, auto-follow and raid/boss warnings. Accent regions animate;
-- native message frames retain their queues and scripts. Dedicated font objects are restyled.
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

local accents, orders = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
screentext.Accents = accents
local function accent(owner, target)
    local value = accents[target]
    if value then return value end
    if type(owner.CreateTexture) ~= "function" then return end
    local line = owner:CreateTexture(nil, "OVERLAY")
    line:SetTexture(media.border)
    line:SetVertexColor(1, 0.82, 0)
    line:SetSize(128, 1)
    line:SetPoint("TOP", target, "BOTTOM", 0, -6)
    line:SetAlpha(0)
    local group = line:CreateAnimationGroup()
    local enter = group:CreateAnimation("Alpha")
    enter:SetFromAlpha(0)
    enter:SetToAlpha(1)
    enter:SetDuration(0.2)
    enter:SetOrder(1)
    local leave = group:CreateAnimation("Alpha")
    leave:SetFromAlpha(1)
    leave:SetToAlpha(0)
    leave:SetStartDelay(1.6)
    leave:SetDuration(0.4)
    leave:SetOrder(2)
    value = { line = line, animation = group }
    accents[target] = value
    return value
end

local function playAccent(owner, target)
    local value = accent(owner, target)
    if value then value.animation:Stop(); value.animation:Play() end
end

-- The pool reuses its strings, so each one is restyled once.
local function restyleWarnings(frame)
    local pool = frame.fontStringPool
    if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
    for line in pool:EnumerateActive() do
        local order = line.messageOrder or true
        if orders[line] ~= order then
            orders[line] = order
            playAccent(frame, line)
        end
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
    for _, name in ipairs({ WARNING_FRAME, "RaidBossEmoteFrame" }) do
        local frame = _G[name]
        if type(frame) == "table" and type(frame[WARNING_METHOD]) == "function" then
            core.Hooks.Script(frame, "OnUpdate", restyleWarnings)
        end
    end
end

-- Font writes are not protected, so nothing here waits for combat to end.
function screentext:OnEnable()
    for _, target in ipairs(TARGETS) do
        local object = _G[target.name]
        if hasFont(object) and restyle(object, target.name, target.size) then counts.fonts = counts.fonts + 1 end
    end
    hookWarnings()
    for _, name in ipairs({ "ZoneTextFrame", "SubZoneTextFrame" }) do
        local frame = _G[name]
        if type(frame) == "table" then
            local target = _G[name:gsub("Frame$", "String")] or frame
            core.Hooks.Script(frame, "OnShow", function(self) playAccent(self, target) end)
        end
    end
    local errors = _G.UIErrorsFrame
    if errors and type(errors.SetTimeVisible) == "function" and type(errors.SetFadeDuration) == "function" then
        errors:SetTimeVisible(2)
        errors:SetFadeDuration(0.35)
    end
end

function screentext:Debug()
    core:Print("Screen text fonts=" .. counts.fonts .. " warnings=" .. counts.warnings)
end

core:RegisterModule("screentext", screentext)
