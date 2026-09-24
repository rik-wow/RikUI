-- Flat main hand, off hand and ranged swing bars replacing Forever's stock swing timer frames.
-- Native PLAYER_SWING supplies cooldown duration. Optional kiting cues use readable player
-- movement and cast state; hidden wind-up/retry clocks are never presented as measured.
local core, media, layout, ui, motion = RikUI, RikUI.Media, RikUI.Layout, RikUI.UI, RikUI.Motion
local swing = { Bars = {}, Options = { title = "Weapon timers", settings = {} } }
core.SwingTimer = swing

local HOLDER_NAME, KEY = "RikUISwingTimer", "swingtimer"
local WIDTH, HEIGHT, GAP, EDGE, TEXT_INSET, SPARK_WIDTH, FOOTER = 200, 18, 3, 1, 5, 2, 16
local FOOTPRINT = HEIGHT * 3 + GAP * 2 + FOOTER
local DEFAULTS = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 236 }
local BACKGROUND, BORDER, WHITE = { 0.06, 0.07, 0.09, 0.9 }, { 0.25, 0.28, 0.32, 1 }, { 1, 1, 1, 1 }
local IN_RANGE_TEXT, OUT_OF_RANGE_TEXT, OUT_OF_RANGE_ALPHA = { 1, 1, 1 }, { 1, 0.2, 0.2 }, 0.4
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local FADE_SECONDS, FLASH_SECONDS, FLASH_ALPHA, LINGER_SECONDS = 0.08, 0.12, 0.08, 0.6
local MAX_DURATION = 60
-- Stack order, the Enum.PlayerSwingType key, the client's label global and a fallback, fill colour.
local TYPES = {
    { key = "MainHand", global = "SWING_TIMER_MAIN_HAND", label = "Main hand", color = { 0.25, 0.34, 0.45 } },
    { key = "OffHand", global = "SWING_TIMER_OFF_HAND", label = "Off hand", color = { 0.3, 0.3, 0.42 } },
    { key = "Ranged", global = "SWING_TIMER_RANGED", label = "Ranged", color = { 0.18, 0.55, 0.4 } },
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
    local offset = FOOTER
    for _, bar in ipairs(order) do
        bar:SetShown(bar.endTime ~= nil or bar.waiting == true)
        if bar.endTime or bar.waiting then
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, offset)
            bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, offset)
            offset = offset + HEIGHT + GAP
        end
    end
end

function swing.Clear(bar)
    bar.endTime, bar.duration, bar.waiting = nil, nil, nil
    bar:SetScript("OnUpdate", nil)
    if bar.fade then bar.fade:Stop() end
    if bar.flashAnim then bar.flashAnim:Stop() end
    bar.flash:SetAlpha(0);bar:SetAlpha(1)
    arrange()
end

-- Absolute clock interpolation at display refresh rate; text changes only on a new tenth.
local function update(bar)
    local now = GetTime()
    local remaining = bar.endTime and bar.endTime - now
    local keep = bar.ranged and swing.Kiting.auto
    if remaining and remaining < -LINGER_SECONDS and not keep then swing.Clear(bar);return end
    local value = remaining and math.max(0, remaining) or 0
    bar.bar:SetValue(bar.duration and math.max(0, math.min(1, (bar.duration - value) / bar.duration)) or 0)
    local display = remaining and remaining > 0 and string.format("%.1f", value) or "--"
    if not bar.ranged and remaining then display = string.format("%.1f", value) end
    if bar.lastTime ~= display then bar.lastTime = display;bar.time:SetText(display) end
    if bar.ranged then swing.Kiting.Paint(bar, now) end
end

function swing.Activate(bar)
    local appearing = not bar:IsShown()
    bar:SetScript("OnUpdate", update)
    update(bar);arrange()
    if appearing then motion.Play(bar.fade) end
end

local function swung(_, duration, swingType)
    if core.Secret.IsSecret(swingType) or core.Secret.IsSecret(duration) then return end
    if type(swingType) ~= "number" or type(duration) ~= "number" or duration ~= duration
        or duration <= 0 or duration > MAX_DURATION then return end
    local bar = holder and swing.Bars[swingType]
    if not bar then return end
    if not bar.ranged then swing.Kiting.Invalidate() end
    bar.duration, bar.endTime, bar.waiting = duration, GetTime() + duration, nil
    swing.RefreshRange(bar)
    swing.Activate(bar)
    motion.Play(bar.flashAnim)
end

-- The fill, spark and texts dim together; the frame's own alpha stays with the fade tween.
local function setOutOfRange(bar, outOfRange)
    bar.bar:SetAlpha(outOfRange and OUT_OF_RANGE_ALPHA or 1)
    bar.time:SetTextColor(unpack(outOfRange and OUT_OF_RANGE_TEXT or IN_RANGE_TEXT))
end

local function applyRange(bar, value)
    bar.inRange = nil
    if not core.Secret.IsSecret(value) and type(value) == "boolean" then bar.inRange = value end
    setOutOfRange(bar, bar.inRange == false)
end

local function rangeChanged(_, swingType, inRange, checksRange)
    if core.Secret.IsSecret(swingType) or core.Secret.IsSecret(checksRange) then return end
    local bar = holder and swing.Bars[swingType]
    if bar then
        if checksRange == true then applyRange(bar, inRange) else applyRange(bar, nil) end
    end
end

function swing.RefreshRange(bar)
    local ok, inRange = pcall(C_SwingTimer.IsTargetWithinSwingRange, bar.swingType)
    if not ok then warn("range", inRange);applyRange(bar, nil);return end
    applyRange(bar, inRange)
end

local function targetChanged()
    if not holder then return end
    for _, bar in pairs(swing.Bars) do swing.RefreshRange(bar) end
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

local function decorateRanged(bar)
    bar.cue = bar:CreateFontString(nil, "OVERLAY");media.Font(bar.cue, "small")
    bar.cue:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", TEXT_INSET, 0)
    bar.cue:SetWidth(WIDTH - 2 * TEXT_INSET);bar.cue:SetJustifyH("LEFT");bar.cue:SetWordWrap(false)
    bar.window = overlay(bar, "ARTWORK");bar.window:SetVertexColor(1, 0.65, 0.15);bar.window:SetAlpha(0.16)
    bar.window:SetHeight(HEIGHT - 2 * EDGE);bar.window:SetPoint("RIGHT", bar.bar, "RIGHT", 0, 0)
    bar.marker = overlay(bar, "OVERLAY");bar.marker:SetSize(1, HEIGHT - 2 * EDGE)
    bar.marker:SetVertexColor(1, 0.7, 0.2)
end

local function decorateFill(bar, info)
    bar.bar = CreateFrame("StatusBar", nil, bar)
    bar.bar:SetPoint("TOPLEFT", bar, "TOPLEFT", EDGE, -EDGE)
    bar.bar:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -EDGE, EDGE)
    bar.bar:SetStatusBarTexture(media.statusbar)
    bar.bar:SetStatusBarColor(unpack(info.color))
    bar.bar:SetMinMaxValues(0, 1)
    bar.spark = overlay(bar, "ARTWORK")
    bar.spark:SetSize(SPARK_WIDTH, HEIGHT)
    bar.spark:SetPoint("CENTER", bar.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    bar.flash = overlay(bar, "ARTWORK")
    bar.flash:SetAllPoints(bar.bar)
    bar.flash:SetAlpha(0)
end

local function createBar(info)
    local bar = CreateFrame("Frame", nil, holder)
    bar:SetSize(WIDTH, HEIGHT)
    bar.color, bar.ranged, bar.swingType, bar.innerWidth = info.color, info.key == "Ranged", Enum.PlayerSwingType[info.key], WIDTH - 2 * EDGE
    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(bar)
    background:SetTexture(FLAT)
    background:SetVertexColor(unpack(BACKGROUND))
    bar.rikBorder = ui.Edges(bar, EDGE, "BORDER")
    for _, line in ipairs(bar.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
    decorateFill(bar, info)
    bar.label, bar.time = text(bar, "LEFT", "LEFT", TEXT_INSET), text(bar, "RIGHT", "RIGHT", -TEXT_INSET)
    bar.baseLabel = type(_G[info.global]) == "string" and _G[info.global] or info.label
    bar.label:SetText(bar.baseLabel);bar.label:SetWidth(WIDTH - 60);bar.label:SetWordWrap(false)
    bar.time:SetWidth(44);bar.time:SetWordWrap(false)
    if bar.ranged then decorateRanged(bar) end
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

-- Only move the old shipped Centered position; leave custom positions intact.
local function migratePosition()
    local layouts = core.Layouts
    local old = layouts and layouts.LegacySwingCentered
    local saved = core.Profile.positions.swingtimer
    if not old or not saved or saved.point ~= old.point or saved.relativePoint ~= old.relativePoint
        or saved.x ~= old.x or saved.y ~= old.y then return end
    core.Profile.positions.swingtimer = core.Setup.CopyState(layouts.centered.positions.swingtimer)
    core:Changed()
end

local function build()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(WIDTH, FOOTPRINT)
    for _, info in ipairs(TYPES) do
        local swingType = Enum.PlayerSwingType[info.key]
        if swingType ~= nil then
            local bar = createBar(info)
            swing.Bars[swingType], order[#order + 1] = bar, bar
        end
    end
    migratePosition()
    layout.Register(holder, KEY, DEFAULTS)
    swing.Holder = holder
    for _, name in ipairs(STOCK) do
        if isFrame(_G[name]) then core.Hide.Frame(_G[name], false) end
    end
    enableRangeChecks()
    targetChanged()
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
    swing.Kiting.Register()
end

function swing:Debug()
    local active = 0
    for _, bar in ipairs(order) do
        if bar.endTime then active = active + 1 end
    end
    core:Print("Swing timer holder=" .. tostring(holder ~= nil) .. " active=" .. active)
end

core:RegisterModule("swingtimer", swing)
