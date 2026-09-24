-- Advisory movement cues. Only native swing events advance the weapon cooldown.
local core, swing = RikUI, RikUI.SwingTimer
local kiting = { auto = false }
swing.Kiting = kiting
local DEFAULT_LEAD, MIN_LEAD, MAX_LEAD, SAMPLE_SECONDS = 0.6, 0.1, 1.5, 0.05
local COLORS = { move = { 0.18, 0.55, 0.4 }, stop = { 0.7, 0.42, 0.12 },
    wait = { 0.45, 0.35, 0.2 }, blocked = { 0.65, 0.18, 0.18 }, unknown = { 0.35, 0.4, 0.48 } }

local function readable(value, kind)
    return not core.Secret.IsSecret(value) and type(value) == kind
end

function kiting.Lead()
    local value = core.Profile.swingtimer.stopLead
    if not readable(value, "number") or value ~= value then return DEFAULT_LEAD end
    return math.max(MIN_LEAD, math.min(MAX_LEAD, value))
end

function kiting.Enabled() return core.Profile.swingtimer.kiting ~= false end

local function casting()
    if type(UnitCastingInfo) ~= "function" or type(UnitChannelInfo) ~= "function" then return nil end
    for _, reader in ipairs({ UnitCastingInfo, UnitChannelInfo }) do
        local ok, name = pcall(reader, "player")
        if not ok or core.Secret.IsSecret(name) then return nil end
        if type(name) == "string" and name ~= "" then return true end
    end
    return false
end

function kiting.Sample(now)
    if kiting.sampleAt and now < kiting.sampleAt then return end
    kiting.sampleAt = now + SAMPLE_SECONDS
    kiting.casting = casting()
    kiting.moving = nil
    if type(GetUnitSpeed) ~= "function" then return end
    local ok, speed = pcall(GetUnitSpeed, "player")
    if ok and readable(speed, "number") and speed >= 0 and speed < math.huge then kiting.moving = speed > 0 end
end

function kiting.Cue(bar, now)
    kiting.Sample(now)
    local remaining = bar.endTime and math.max(0, bar.endTime - now) or 0
    if kiting.casting == true then return "Casting - hold", "stop" end
    if bar.inRange == false then return "Out of range", "blocked" end
    if bar.inRange == nil then return "Range unknown", "unknown" end
    if kiting.casting == nil then return "Cast state unknown", "unknown" end
    if not bar.endTime then return "Wait for shot", "wait" end
    if remaining <= kiting.Lead() then
        if kiting.moving then return "Stop moving", "stop" end
        if remaining > 0 then return "Hold for shot", "stop" end
        return "Wait for shot", "wait"
    end
    return "Move window", "move"
end

function kiting.Paint(bar, now)
    if not kiting.Enabled() then
        bar.lastState = nil
        bar.cue:Hide();bar.window:Hide();bar.marker:Hide()
        bar.label:SetText(bar.baseLabel)
        bar.bar:SetStatusBarColor(unpack(bar.color))
        return
    end
    local label, state = kiting.Cue(bar, now)
    if bar.lastCue ~= label then bar.lastCue = label;bar.cue:SetText(label) end
    bar.cue:Show()
    if bar.lastState ~= state then bar.lastState = state;bar.bar:SetStatusBarColor(unpack(COLORS[state])) end
    local ratio = bar.duration and math.min(1, kiting.Lead() / bar.duration) or 0
    if bar.lastRatio ~= ratio then
        bar.lastRatio = ratio
        bar.window:SetWidth(bar.innerWidth * ratio)
        bar.marker:ClearAllPoints()
        bar.marker:SetPoint("CENTER", bar.bar, "LEFT", bar.innerWidth * (1 - ratio), 0)
    end
    bar.window:SetShown(ratio > 0);bar.marker:SetShown(ratio > 0)
end

local function ranged() return swing.Bars[Enum.PlayerSwingType.Ranged] end

local function autoStart()
    kiting.auto = true;kiting.sampleAt = nil
    local bar = ranged()
    if not bar then return end
    bar.endTime, bar.duration, bar.waiting = nil, nil, true
    swing.RefreshRange(bar)
    swing.Activate(bar)
end

local function autoStop()
    kiting.auto = false
    local bar = ranged()
    if bar then swing.Clear(bar) end
end

function kiting.Invalidate()
    kiting.sampleAt = nil
    local bar = ranged()
    if not bar then return end
    if kiting.auto then
        bar.endTime, bar.duration, bar.waiting = nil, nil, true
        swing.Activate(bar)
    else swing.Clear(bar) end
end

function kiting.Reset()
    kiting.auto, kiting.sampleAt = false, nil
    for _, bar in pairs(swing.Bars) do swing.Clear(bar) end
end

function kiting.Register()
    core:RegisterEvent("START_AUTOREPEAT_SPELL", autoStart)
    core:RegisterEvent("STOP_AUTOREPEAT_SPELL", autoStop)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", kiting.Reset)
    core:RegisterEvent("PLAYER_DEAD", kiting.Reset)
    core:RegisterEvent("WEAPON_SLOT_CHANGED", kiting.Reset)
    core:RegisterEvent("UNIT_ATTACK_SPEED", function(_, unit)
        if readable(unit, "string") and unit == "player" then kiting.Invalidate() end
    end)
    for _, event in ipairs({ "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
        core:RegisterEvent(event, function() kiting.sampleAt = nil end)
    end
end

table.insert(swing.Options.settings, { type = "checkbox", key = "kiting", label = "Ranged kiting cues",
    description = "Movement and stop cues for any ranged weapon. The stop window is a timing aid, not a confirmed cast.",
    get = kiting.Enabled, set = function(value) core.Profile.swingtimer.kiting = value == true end })
table.insert(swing.Options.settings, { type = "slider", key = "stopLead", label = "Stop lead time (seconds)",
    description = "Stop this long before the next expected shot. Default 0.6s allows for the intended 0.5s wind-up. Tune for haste and latency.",
    min = MIN_LEAD, max = MAX_LEAD, step = 0.05, get = kiting.Lead,
    set = function(value)
        if not readable(value, "number") or value ~= value then return end
        core.Profile.swingtimer.stopLead = math.max(MIN_LEAD, math.min(MAX_LEAD, value))
    end })
