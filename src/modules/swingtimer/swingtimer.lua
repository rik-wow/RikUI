-- Flat main hand, off hand and ranged swing bars replacing Forever's stock swing timer frames.
-- PLAYER_SWING carries the duration and the bars run on the clock from there, so no unit value is
-- read. A bar shows only while its swing type is swinging, which needs neither UnitAttackSpeed nor
-- the showSwingTimer setting the stock frames follow.
local core, media, layout, unitframes, motion = RikUI, RikUI.Media, RikUI.Layout, RikUI.UnitFrames, RikUI.Motion
local swing = { Bars = {} }
core.SwingTimer = swing

local HOLDER_NAME, KEY = "RikUISwingTimer", "swingtimer"
local WIDTH, HEIGHT, GAP, EDGE, TEXT_INSET, SPARK_WIDTH = 200, 14, 3, 1, 5, 2
local DEFAULTS = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 236 }
local BACKGROUND, BORDER, WHITE = { 0.06, 0.07, 0.09, 0.9 }, { 0.25, 0.28, 0.32, 1 }, { 1, 1, 1, 1 }
local IN_RANGE_TEXT, OUT_OF_RANGE_TEXT, OUT_OF_RANGE_ALPHA = { 1, 1, 1 }, { 1, 0.2, 0.2 }, 0.4
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local FADE_SECONDS, FLASH_SECONDS, FLASH_ALPHA, LINGER_SECONDS = 0.15, 0.2, 0.6, 0.6
-- Stack order, the Enum.PlayerSwingType key, the client's label global and a fallback, fill colour.
local TYPES = {
    { key = "MainHand", global = "SWING_TIMER_MAIN_HAND", label = "Main hand", color = { 0.82, 0.84, 0.9 } },
    { key = "OffHand", global = "SWING_TIMER_OFF_HAND", label = "Off hand", color = { 0.5, 0.58, 0.72 } },
    { key = "Ranged", global = "SWING_TIMER_RANGED", label = "Ranged", color = { 0.62, 0.8, 0.4 } },
}
local STOCK = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }
local holder, order, warnings = nil, {}, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Swing timer " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetParent) == "function"
end

-- The bars are unprotected, so showing, hiding and restacking are safe in combat. They stack
-- upwards: the companion rows end just under the default position.
local function arrange()
    local offset = 0
    for _, bar in ipairs(order) do
        bar:SetShown(bar.endTime ~= nil)
        if bar.endTime then
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, offset)
            bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, offset)
            offset = offset + HEIGHT + GAP
        end
    end
end

local function clear(bar)
    bar.endTime, bar.duration = nil, nil
    bar:SetScript("OnUpdate", nil)
    arrange()
end

-- A finished swing stays full for a moment: the next PLAYER_SWING usually lands within it.
local function update(bar)
    local remaining = bar.endTime - GetTime()
    if remaining < -LINGER_SECONDS then clear(bar) return end
    if remaining < 0 then remaining = 0 end
    bar.bar:SetValue((bar.duration - remaining) / bar.duration)
    bar.time:SetFormattedText("%.1f", remaining)
end

local function swung(_, duration, swingType)
    local bar = holder and swing.Bars[swingType]
    if not bar or type(duration) ~= "number" or duration <= 0 then return end
    local appearing = bar.endTime == nil
    bar.duration, bar.endTime = duration, GetTime() + duration
    bar:SetScript("OnUpdate", update)
    update(bar)
    arrange()
    if appearing then motion.Play(bar.fade) end
    motion.Play(bar.flashAnim)
end

-- The fill, spark and texts dim together; the frame's own alpha stays with the fade tween.
local function setOutOfRange(bar, outOfRange)
    bar.bar:SetAlpha(outOfRange and OUT_OF_RANGE_ALPHA or 1)
    bar.time:SetTextColor(unpack(outOfRange and OUT_OF_RANGE_TEXT or IN_RANGE_TEXT))
end

local function rangeChanged(_, swingType, inRange, checksRange)
    local bar = holder and swing.Bars[swingType]
    if bar then setOutOfRange(bar, checksRange == true and inRange == false) end
end

local function targetChanged()
    if not holder then return end
    for swingType, bar in pairs(swing.Bars) do
        local ok, inRange = pcall(C_SwingTimer.IsTargetWithinSwingRange, swingType)
        setOutOfRange(bar, ok and inRange == false)
    end
end

local function text(bar, justify, point, x)
    local value = bar.bar:CreateFontString(nil, "OVERLAY")
    media.Font(value, "small")
    value:SetJustifyH(justify)
    value:SetPoint(point, bar.bar, point, x, 0)
    return value
end

local function overlay(bar, layer)
    local texture = bar.bar:CreateTexture(nil, layer)
    texture:SetTexture(FLAT)
    texture:SetVertexColor(unpack(WHITE))
    return texture
end

local function createBar(info)
    local bar = CreateFrame("Frame", nil, holder)
    bar:SetHeight(HEIGHT)
    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(bar)
    background:SetTexture(FLAT)
    background:SetVertexColor(unpack(BACKGROUND))
    bar.rikBorder = unitframes.Edges(bar, EDGE, "BORDER")
    for _, line in ipairs(bar.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
    bar.bar = CreateFrame("StatusBar", nil, bar)
    bar.bar:SetAllPoints(bar)
    bar.bar:SetStatusBarTexture(media.statusbar)
    bar.bar:SetStatusBarColor(unpack(info.color))
    bar.bar:SetMinMaxValues(0, 1)
    bar.spark = overlay(bar, "ARTWORK")
    bar.spark:SetSize(SPARK_WIDTH, HEIGHT)
    bar.spark:SetPoint("CENTER", bar.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    bar.flash = overlay(bar, "OVERLAY")
    bar.flash:SetAllPoints(bar.bar)
    bar.flash:SetAlpha(0)
    bar.label, bar.time = text(bar, "LEFT", "LEFT", TEXT_INSET), text(bar, "RIGHT", "RIGHT", -TEXT_INSET)
    bar.label:SetText(type(_G[info.global]) == "string" and _G[info.global] or info.label)
    bar.fade = motion.Tween(bar, 0, 1, FADE_SECONDS)
    bar.flashAnim = motion.Tween(bar.flash, FLASH_ALPHA, 0, FLASH_SECONDS)
    bar:Hide()
    return bar
end

-- The parked stock frames drop their events and with them their own range check requests.
local function enableRangeChecks()
    for swingType in pairs(swing.Bars) do
        local ok, reason = pcall(C_SwingTimer.EnableRangeCheck, swingType, true)
        if not ok then warn("range check", reason) end
    end
end

local function build()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(WIDTH, HEIGHT)
    for _, info in ipairs(TYPES) do
        local swingType = Enum.PlayerSwingType[info.key]
        if swingType ~= nil then
            local bar = createBar(info)
            swing.Bars[swingType], order[#order + 1] = bar, bar
        end
    end
    layout.Register(holder, KEY, DEFAULTS)
    swing.Holder = holder
    enableRangeChecks()
    for _, name in ipairs(STOCK) do
        if isFrame(_G[name]) then core.Hide.Frame(_G[name], false) end
    end
end

local function supported()
    return type(Enum) == "table" and type(Enum.PlayerSwingType) == "table" and type(C_SwingTimer) == "table"
        and type(C_SwingTimer.EnableRangeCheck) == "function"
        and type(C_SwingTimer.IsTargetWithinSwingRange) == "function"
end

function swing:OnEnable()
    if not supported() then return end
    core.Combat.Queue(build)
    core:RegisterEvent("PLAYER_SWING", swung)
    core:RegisterEvent("PLAYER_SWING_RANGE_UPDATE", rangeChanged)
    core:RegisterEvent("PLAYER_TARGET_CHANGED", targetChanged)
end

function swing:Debug()
    local active = 0
    for _, bar in ipairs(order) do
        if bar.endTime then active = active + 1 end
    end
    core:Print("Swing timer holder=" .. tostring(holder ~= nil) .. " active=" .. active)
end

core:RegisterModule("swingtimer", swing)
