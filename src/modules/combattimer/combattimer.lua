-- Elapsed player combat time only; no combat-log or unit-value reads.
local core = RikUI
local timer = { Options = { title = "Combat timer", settings = {} } }
core.CombatTimer = timer
local holder, active, started, ended, duration, partial
local DEFAULT_LINGER, UPDATE_INTERVAL = 5, 0.2
local ACTIVE_COLOR, IDLE_COLOR = { 1, 0.65, 0.25 }, { 0.6, 0.7, 0.8 }
local DEFAULT_POSITION = { point = "TOP", relativePoint = "TOP", x = 66, y = -110 }

local function now()
    if type(GetTime) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    if ok and not core.Secret.IsSecret(value) and type(value) == "number"
        and value >= 0 and value < math.huge then return value end
end

local function clockFace(frame, clockWidth)
    frame.label = frame:CreateFontString(nil, "OVERLAY")
    core.Media.Font(frame.label, "small")
    frame.label:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
    frame.label:SetWidth(clockWidth)
    frame.label:SetWordWrap(false)
    frame.label:SetJustifyH("RIGHT")
    frame.label:SetTextColor(0.95, 0.97, 1)
    frame.state = frame:CreateFontString(nil, "OVERLAY")
    core.Media.Font(frame.state, "small")
    frame.state:SetPoint("LEFT", frame, "LEFT", 7, 0)
    frame.state:SetPoint("RIGHT", frame.label, "LEFT", -3, 0)
    frame.state:SetJustifyH("LEFT")
    frame.state:SetWordWrap(false)
    frame.accent = frame:CreateTexture(nil, "ARTWORK")
    frame.accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    frame.accent:SetWidth(2)
end

local stopwatch, watchStart, watchLast, watchInvalid
local watchElapsed, watchRunning = 0, false
local WATCH_MAX = 359999 -- 99:59:59; session-only state, never saved.
local function watchValue()
    if watchRunning then
        local at = now()
        if not at or not watchStart or (watchLast and at < watchLast) then
            watchInvalid, watchRunning = true, false
        else
            watchLast = at
            local value = watchElapsed + at - watchStart
            if value >= WATCH_MAX then watchElapsed, watchRunning = WATCH_MAX, false end
            return math.min(WATCH_MAX, value)
        end
    end
    return watchElapsed
end

local function watchTick(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < UPDATE_INTERVAL then return end
    self.elapsed = 0
    timer.RefreshStopwatch()
end

function timer.RefreshStopwatch()
    if not stopwatch then return end
    local value = math.floor(watchValue())
    local visible = core.Profile and core.Profile.combattimer and core.Profile.combattimer.stopwatch == true
    stopwatch:SetShown(visible)
    stopwatch:SetScript("OnUpdate", visible and watchRunning and watchTick or nil)
    local color = watchInvalid and { 1, 0.35, 0.25 } or watchRunning and { 0.4, 0.9, 0.65 } or IDLE_COLOR
    stopwatch.state:SetText(watchInvalid and "Reset" or watchRunning and "Run" or "Pause")
    stopwatch.state:SetTextColor(unpack(color))
    stopwatch.accent:SetColorTexture(unpack(color))
    if watchInvalid then stopwatch.label:SetText("--:--"); return end
    local text = value >= 3600 and string.format("%d:%02d:%02d", math.floor(value / 3600), math.floor(value / 60) % 60, value % 60)
        or string.format("%d:%02d", math.floor(value / 60), value % 60)
    stopwatch.label:SetText(text)
end

function timer.StopwatchAction(action)
    if not stopwatch then return "Enable the Combat timer module first." end
    if action == "reset" then
        watchElapsed, watchRunning, watchStart, watchLast, watchInvalid = 0, false, nil, nil, false
    elseif action == "start" then
        if not watchRunning and not watchInvalid then
            watchStart = now()
            watchLast, watchRunning, watchInvalid = watchStart, watchStart ~= nil, watchStart == nil
        end
        core.Profile.combattimer.stopwatch = true
    elseif action == "pause" then
        watchElapsed = watchValue()
        watchRunning = false
    elseif action == "show" or action == "hide" then
        core.Profile.combattimer.stopwatch = action == "show"
    else return "Use /rik stopwatch start, pause, reset, show or hide. Left-click toggles; right-click resets." end
    timer.RefreshStopwatch()
    return watchInvalid and "Clock unavailable or moved backwards; reset the stopwatch." or nil
end

local function buildStopwatch()
    stopwatch = CreateFrame("Button", "RikUIStopwatch", UIParent)
    timer.Stopwatch = stopwatch
    stopwatch:SetSize(110, 20)
    stopwatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    stopwatch.background = stopwatch:CreateTexture(nil, "BACKGROUND")
    stopwatch.background:SetAllPoints()
    stopwatch.background:SetColorTexture(0.055, 0.065, 0.08, 0.9)
    for _, edge in ipairs(core.UI.Edges(stopwatch, 1, "BORDER")) do edge:SetVertexColor(0.25, 0.28, 0.32, 1) end
    clockFace(stopwatch, 62)
    stopwatch.hover = stopwatch:CreateTexture(nil, "HIGHLIGHT")
    stopwatch.hover:SetAllPoints(stopwatch)
    stopwatch.hover:SetColorTexture(0.35, 0.5, 0.65, 0.2)
    stopwatch:SetScript("OnClick", function(_, button)
        timer.StopwatchAction(button == "RightButton" and "reset" or (watchRunning and "pause" or "start"))
    end)
    stopwatch:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Stopwatch")
        GameTooltip:AddLine("Left-click: start/pause. Right-click: reset.")
        GameTooltip:AddLine("Move with /rik move. Clears on reload.")
        GameTooltip:Show()
    end)
    stopwatch:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    core.Layout.Register(stopwatch, "stopwatch", { point = "TOP", relativePoint = "TOP", x = 66, y = -134 },
        { label = "Stopwatch", onApply = timer.RefreshStopwatch })
    timer.RefreshStopwatch()
end

local function enabled()
    return core.Profile and core.Profile.combattimer and core.Profile.combattimer.show == true
end

local function linger()
    local value = core.Profile.combattimer.linger
    if type(value) ~= "number" or value ~= value then return DEFAULT_LINGER end
    return math.max(0, math.min(30, value))
end

local function stopDisplay()
    if not holder then return end
    holder:Hide()
    holder:SetScript("OnUpdate", nil)
end

local function seconds(at)
    if at and started and at >= started then return math.floor(at - started) end
end

local function clock(value)
    if not value then return "--:--" end
    return string.format("%d:%02d", math.floor(value / 60), value % 60) .. (partial and "+" or "")
end

local function paint()
    if not enabled() then stopDisplay(); return end
    local at = now()
    if active then
        holder.label:SetText(clock(seconds(at)))
    elseif ended and at and at - ended < linger() then
        holder.label:SetText(clock(duration))
    else stopDisplay(); return end
    local color = active and ACTIVE_COLOR or IDLE_COLOR
    holder.state:SetText(active and "Combat" or "Last")
    holder.state:SetTextColor(unpack(color))
    holder.accent:SetColorTexture(unpack(color))
    holder:Show()
end

local function tick(_, elapsed)
    holder.elapsed = holder.elapsed + elapsed
    if holder.elapsed < UPDATE_INTERVAL then return end
    holder.elapsed = 0
    paint()
end

local function start(isPartial)
    if not enabled() or active then return end
    active, started, ended, duration, partial = true, now(), nil, nil, isPartial == true
    holder.elapsed = 0
    holder:SetScript("OnUpdate", tick)
    paint()
end

local function finish()
    if not active then return end
    ended = now()
    duration, active = seconds(ended), false
    paint()
end

function timer.Refresh()
    timer.RefreshStopwatch()
    if not holder then return end
    if not enabled() then
        active, started, ended, duration = false, nil, nil, nil
        stopDisplay()
        return
    end
    if InCombatLockdown() and not active then start(true) else paint() end
end

local function world()
    active, started, ended, duration = false, nil, nil, nil
    timer.Refresh()
end

function timer:OnEnable()
    buildStopwatch()
    holder = CreateFrame("Frame", "RikUICombatTimer", UIParent)
    timer.Holder = holder
    holder:SetSize(110, 20)
    holder.background = holder:CreateTexture(nil, "BACKGROUND")
    holder.background:SetAllPoints()
    holder.background:SetColorTexture(0.055, 0.065, 0.08, 0.9)
    for _, edge in ipairs(core.UI.Edges(holder, 1, "BORDER")) do edge:SetVertexColor(0.25, 0.28, 0.32, 1) end
    clockFace(holder, 52)
    core.Layout.Register(holder, "combattimer", DEFAULT_POSITION, { label = "Combat timer", onApply = timer.Refresh })
    core:RegisterEvent("PLAYER_REGEN_DISABLED", function() start(false) end)
    core:RegisterEvent("PLAYER_REGEN_ENABLED", finish)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", world)
    timer.Refresh()
end

table.insert(timer.Options.settings, { type = "checkbox", key = "show", label = "Show combat timer",
    description = "Elapsed player combat time. A + marks timing that began after combat was already active.",
    get = enabled, set = function(value) core.Profile.combattimer.show = value == true; timer.Refresh() end })
table.insert(timer.Options.settings, { type = "slider", key = "linger", label = "Keep final duration",
    description = "Seconds to show the last combat duration; zero hides it immediately.",
    min = 0, max = 30, step = 1, get = linger,
    set = function(value)
        if type(value) ~= "number" or value ~= value or value < 0 or value > 30 then return nil, "Use 0 to 30 seconds." end
        core.Profile.combattimer.linger = math.floor(value); timer.Refresh()
        return true
    end })
table.insert(timer.Options.settings, { type = "checkbox", key = "stopwatch", label = "Show session stopwatch",
    description = "Left-click starts or pauses; right-click resets. Move with /rik move; elapsed time clears on reload.",
    get = function() return core.Profile.combattimer.stopwatch == true end,
    set = function(value) core.Profile.combattimer.stopwatch = value == true; timer.RefreshStopwatch() end })
core:RegisterCommand("stopwatch", function(input)
    local message = timer.StopwatchAction(string.lower((input or ""):match("^%s*(.-)%s*$")))
    if message then core:Print(message) end
end, "Session stopwatch: start, pause, reset, show or hide", timer)
core:RegisterModule("combattimer", timer)

