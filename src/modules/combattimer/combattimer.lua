-- Elapsed player combat time only; no combat-log or unit-value reads.
local core = RikUI
local timer = { Options = { title = "Combat timer", settings = {} } }
core.CombatTimer = timer
local holder, active, started, ended, duration, partial
local DEFAULT_LINGER, UPDATE_INTERVAL = 5, 0.2
local DEFAULT_POSITION = { point = "TOP", relativePoint = "TOP", x = 66, y = -110 }

local function now()
    if type(GetTime) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    if ok and not core.Secret.IsSecret(value) and type(value) == "number"
        and value >= 0 and value < math.huge then return value end
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
        holder.label:SetText("Combat " .. clock(seconds(at)))
    elseif ended and at and at - ended < linger() then
        holder.label:SetText("Last " .. clock(duration))
    else stopDisplay(); return end
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
    holder = CreateFrame("Frame", "RikUICombatTimer", UIParent)
    timer.Holder = holder
    holder:SetSize(110, 20)
    holder.background = holder:CreateTexture(nil, "BACKGROUND")
    holder.background:SetAllPoints()
    holder.background:SetColorTexture(0.055, 0.065, 0.08, 0.9)
    for _, edge in ipairs(core.UI.Edges(holder, 1, "BORDER")) do edge:SetVertexColor(0.25, 0.28, 0.32, 1) end
    holder.label = holder:CreateFontString(nil, "OVERLAY")
    core.Media.Font(holder.label, "small")
    holder.label:SetPoint("CENTER", holder, "CENTER")
    holder.label:SetTextColor(1, 0.82, 0)
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
core:RegisterModule("combattimer", timer)

