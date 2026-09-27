-- Flat breath, fatigue and feign death bars replacing MirrorTimerContainer. The client sends the
-- range with MIRROR_TIMER_START and the bars poll GetMirrorTimerProgress while they run. Whether
-- that value is secret on 69913 is unverified, so it goes reader-to-sink in milliseconds and the
-- seconds text is worked out inside pcall: a secret blanks the text instead of raising.
local core, media, layout, ui, motion = RikUI, RikUI.Media, RikUI.Layout, RikUI.UI, RikUI.Motion
local timers = { Bars = {}, Active = {} }
core.MirrorTimers = timers

local HOLDER_NAME, KEY = "RikUIMirrorTimers", "mirrortimers"
local WIDTH, HEIGHT, GAP, EDGE, TEXT_INSET, SLOTS = 220, 16, 4, 1, 5, 3
local DEFAULTS = { point = "TOP", relativePoint = "TOP", x = 0, y = -120 }
local BACKGROUND, BORDER, LOW_COLOR = { 0.06, 0.07, 0.09, 0.9 }, { 0.25, 0.28, 0.32, 1 }, { 1, 0.15, 0.15, 1 }
local COLORS = { BREATH = { 0.2, 0.55, 0.95 }, EXHAUSTION = { 0.95, 0.75, 0.15 }, FEIGNDEATH = { 0.85, 0.5, 0.2 },
    DEATH = { 0.8, 0.13, 0.13 } }
local DEFAULT_COLOR = { 0.6, 0.65, 0.7 }
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local FADE_SECONDS, PULSE_SECONDS, PULSE_ALPHA, LOW_SECONDS = 0.15, 0.4, 0.45, 10
local UNKNOWN, STOCK = "UNKNOWN", "MirrorTimerContainer"
local holder, warnings = nil, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Mirror timers " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetParent) == "function"
end

local function describe(progress)
    local seconds = math.max(0, math.ceil(progress / 1000))
    if seconds < 60 then return tostring(seconds), seconds <= LOW_SECONDS end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60), false
end

local function setLow(bar, low)
    low = low == true
    bar.severity:SetVertexColor(unpack(low and LOW_COLOR or COLORS[bar.timer] or DEFAULT_COLOR))
    if bar.isLow == low then return end
    bar.isLow = low
    if low then motion.Play(bar.pulse) return end
    motion.Stop(bar.pulse)
    bar.low:SetAlpha(0)
end

local function feed(bar, progress)
    bar.bar:SetValue(progress)
    local ok, text, low = pcall(describe, progress)
    bar.time:SetText(ok and text or "")
    setLow(bar, ok and low and bar.draining)
end

local function readProgress(timer) return GetMirrorTimerProgress(timer) end

local function update(bar)
    local ok, reason = core.Secret.Apply(bar.sink, readProgress, bar.timer)
    if not ok then warn("progress", reason) end
end

local function text(bar, justify, point, x)
    local value = bar.bar:CreateFontString(nil, "OVERLAY")
    media.Font(value, "small")
    value:SetJustifyH(justify)
    value:SetWordWrap(false)
    value:SetPoint(point, bar.bar, point, x, 0)
    return value
end

local function timerChrome(bar)
    bar.scrim = bar.bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.scrim:SetAllPoints(bar.bar)
    bar.scrim:SetColorTexture(0.02, 0.025, 0.04, 0.25)
    bar.timeBacking = bar.bar:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.timeBacking:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -1, -1)
    bar.timeBacking:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
    bar.timeBacking:SetWidth(60)
    bar.timeBacking:SetColorTexture(0.02, 0.025, 0.04, 0.75)
    bar.severity = bar.bar:CreateTexture(nil, "OVERLAY")
    bar.severity:SetTexture(FLAT)
    bar.severity:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    bar.severity:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
    bar.severity:SetWidth(2)
end

local function createBar(index)
    local bar = CreateFrame("Frame", nil, holder)
    bar:SetHeight(HEIGHT)
    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(bar)
    background:SetTexture(FLAT)
    background:SetVertexColor(unpack(BACKGROUND))
    bar.rikBorder = ui.Edges(bar, EDGE, "BORDER")
    for _, line in ipairs(bar.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
    bar.bar = CreateFrame("StatusBar", nil, bar)
    bar.bar:SetAllPoints(bar)
    bar.bar:SetStatusBarTexture(media.statusbar)
    bar.low = bar.bar:CreateTexture(nil, "ARTWORK")
    bar.low:SetAllPoints(bar.bar)
    bar.low:SetTexture(FLAT)
    bar.low:SetVertexColor(unpack(LOW_COLOR))
    bar.low:SetAlpha(0)
    timerChrome(bar)
    bar.label, bar.time = text(bar, "LEFT", "LEFT", TEXT_INSET), text(bar, "RIGHT", "RIGHT", -TEXT_INSET)
    bar.time:SetWidth(52)
    bar.label:SetPoint("RIGHT", bar.time, "LEFT", -8, 0)
    bar.fade = motion.Tween(bar, 0, 1, FADE_SECONDS)
    bar.pulse = motion.Pulse(bar.low, 0, PULSE_ALPHA, PULSE_SECONDS)
    bar.sink = function(progress) feed(bar, progress) end
    bar:Hide()
    timers.Bars[index] = bar
end

-- The bars are unprotected, so showing, hiding and restacking are safe in combat.
local function arrange()
    local offset = 0
    for _, bar in ipairs(timers.Bars) do
        bar:SetShown(bar.timer ~= nil)
        if bar.timer then
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -offset)
            bar:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -offset)
            offset = offset + HEIGHT + GAP
        end
    end
end

local function freeBar()
    for _, bar in ipairs(timers.Bars) do
        if not bar.timer then return bar end
    end
end

local function isPaused(paused) return paused ~= nil and paused ~= false and paused ~= 0 end

local function setPaused(bar, paused)
    bar:SetScript("OnUpdate", not isPaused(paused) and update or nil)
end

local function isDraining(scale) return scale < 0 end

local function start(_, timer, value, maximum, scale, paused, label)
    if not holder or type(timer) ~= "string" or timer == UNKNOWN then return end
    local running = timers.Active[timer]
    local bar = running or freeBar()
    if not bar then return end
    local ok, draining = pcall(isDraining, scale)
    timers.Active[timer], bar.timer, bar.draining = bar, timer, ok and draining
    bar.bar:SetStatusBarColor(unpack(COLORS[timer] or DEFAULT_COLOR))
    bar.bar:SetMinMaxValues(0, maximum)
    bar.label:SetText(label or timer)
    bar.sink(value)
    setPaused(bar, paused)
    arrange()
    if not running then motion.Play(bar.fade) end
end

local function stop(_, timer)
    local bar = timers.Active[timer]
    if not bar then return end
    timers.Active[timer], bar.timer = nil, nil
    bar:SetScript("OnUpdate", nil)
    setLow(bar, false)
    arrange()
end

local function pause(_, timer, paused)
    local bar = timers.Active[timer]
    if bar then setPaused(bar, paused) end
end

-- A timer that was already running at login or when the bars were built sends no start event.
local function scan()
    if not holder or type(GetMirrorTimerInfo) ~= "function" then return end
    for index = 1, SLOTS do
        local ok, timer, value, maximum, scale, paused, label = pcall(GetMirrorTimerInfo, index)
        if ok then start(nil, timer, value, maximum, scale, paused, label) else warn("info", timer) end
    end
end

local function build()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(WIDTH, HEIGHT)
    for index = 1, SLOTS do createBar(index) end
    layout.Register(holder, KEY, DEFAULTS)
    timers.Holder = holder
    scan()
    local stock = _G[STOCK]
    if isFrame(stock) then core.Hide.Frame(stock, false) end
end

function timers:OnEnable()
    if type(GetMirrorTimerProgress) ~= "function" then return end
    core.Combat.Queue(build)
    core:RegisterEvent("MIRROR_TIMER_START", start)
    core:RegisterEvent("MIRROR_TIMER_STOP", stop)
    core:RegisterEvent("MIRROR_TIMER_PAUSE", pause)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", scan)
end

function timers:Debug()
    local active = 0
    for _ in pairs(timers.Active) do active = active + 1 end
    core:Print("Mirror timers holder=" .. tostring(holder ~= nil) .. " active=" .. active)
end

core:RegisterModule("mirrortimers", timers)
