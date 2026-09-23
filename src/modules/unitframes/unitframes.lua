-- Secure unit buttons for player, target, target-of-target and pet. Unit values only
-- ever reach sinks (src/modules/unitframes/unitframes-status.lua); this file owns frames, layout and events.
local core, media, layout = RikUI, RikUI.Media, RikUI.Layout
local unitframes = { Frames = {} }
core.UnitFrames = unitframes

local LARGE = { width = 220, height = 44, health = 28, power = 13, font = "label", powerText = true }
local MEDIUM = { width = 160, height = 36, health = 23, power = 10, font = "small", powerText = false }
local SMALL = { width = 110, height = 30, health = 19, power = 8, font = "small", powerText = false }
local UNITS = {
    { key = "player", unit = "player", size = LARGE, threat = { "player" } },
    { key = "target", unit = "target", size = LARGE, threat = { "player", "target" },
        visibility = "[@target,exists] show; hide" },
    { key = "tot", unit = "targettarget", size = SMALL, threat = { "player", "targettarget" },
        visibility = "[@targettarget,exists] show; hide", poll = true },
    -- "pet" is the pet action row's layout key, so the frame uses its own.
    { key = "petframe", unit = "pet", size = SMALL, threat = { "pet" }, visibility = "[@pet,exists] show; hide" },
    { key = "focus", unit = "focus", size = MEDIUM, threat = { "player", "focus" },
        visibility = "[@focus,exists] show; hide" },
}
-- Centre-bottom above the bar stack and the companion rows (which end at y=232);
-- the castbars sit directly under the player and target frames.
local DEFAULTS = {
    player = { point = "BOTTOM", relativePoint = "BOTTOM", x = -140, y = 300 },
    target = { point = "BOTTOM", relativePoint = "BOTTOM", x = 140, y = 300 },
    tot = { point = "BOTTOM", relativePoint = "BOTTOM", x = 313, y = 300 },
    petframe = { point = "BOTTOM", relativePoint = "BOTTOM", x = -313, y = 300 },
    -- Above the pet frame, right-aligned with it, clear of the party column on the left edge.
    focus = { point = "BOTTOM", relativePoint = "BOTTOM", x = -340, y = 340 },
}
local STOCK_FRAMES = { "PlayerFrame", "TargetFrame", "PetFrame", "TargetFrameToT", "FocusFrame" }
local EDGE, THREAT_EDGE, TEXT_INSET, POLL_SECONDS = 1, 2, 4, 0.5
local BACKGROUND, BORDER = { 0.055, 0.065, 0.08, 0.95 }, { 0.25, 0.28, 0.32, 1 }
local FRAME_PREFIX = "RikUIUnit_"
local TOOLTIP_FALLBACK_ANCHOR = "ANCHOR_RIGHT"
local stockPending, tooltipWarned = false, false

local function report(operation, reason)
    core:Print("Unit frames " .. operation .. ": " .. tostring(reason))
end

local edges = core.UI.Edges
unitframes.Edges = edges -- Compatibility alias; rendering primitives belong to the UI service.

local function text(parent, role, point, x)
    local region = parent:CreateFontString(nil, "OVERLAY")
    media.Font(region, role)
    region:SetPoint(point, parent, point, x, 0)
    return region
end

local function statusBar(frame, height, withText, role)
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetStatusBarTexture(media.statusbar)
    bar:SetHeight(height)
    bar.background = bar:CreateTexture(nil, "BACKGROUND")
    bar.background:SetAllPoints()
    bar.background:SetColorTexture(0, 0, 0, 0.4)
    if withText then bar.text = text(bar, role, "RIGHT", -TEXT_INSET) end
    return bar
end

local function decorate(frame, size)
    local owner = frame.presentation or frame
    frame.background = owner:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints(owner)
    frame.background:SetColorTexture(unpack(BACKGROUND))
    frame.border = edges(owner, EDGE, "BORDER")
    for _, line in ipairs(frame.border) do line:SetVertexColor(unpack(BORDER)) end
    frame.threat = edges(owner, THREAT_EDGE, "OVERLAY")
    for _, line in ipairs(frame.threat) do line:Hide() end
    frame.health = statusBar(owner, size.health, true, size.font)
    frame.health:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE, -EDGE)
    frame.health:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -EDGE, -EDGE)
    frame.power = statusBar(owner, size.power, size.powerText, "small")
    frame.power:SetPoint("TOPLEFT", frame.health, "BOTTOMLEFT", 0, -EDGE)
    frame.power:SetPoint("TOPRIGHT", frame.health, "BOTTOMRIGHT", 0, -EDGE)
    frame.name = text(frame.health, size.font, "LEFT", TEXT_INSET)
    frame.level = text(frame.power, "small", "LEFT", TEXT_INSET)
end

local function secure(frame, unit)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame:SetAttribute("unit", unit)
    frame:RegisterForClicks("AnyUp")
end

-- Blizzard's UnitFrame_UpdateTooltip pattern: GameTooltip_OnUpdate calls owner:UpdateTooltip().
local function updateTooltip(frame)
    if type(GameTooltip_SetDefaultAnchor) == "function" then
        GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    else
        GameTooltip:SetOwner(frame, TOOLTIP_FALLBACK_ANCHOR)
    end
    local ok, reason = pcall(GameTooltip.SetUnit, GameTooltip, frame.unit)
    if ok or tooltipWarned then return end
    tooltipWarned = true
    report("tooltip", reason)
end

-- Enter and leave scripts are not protected, so hover works in combat too.
local function hover(frame)
    frame.UpdateTooltip = updateTooltip
    frame:SetScript("OnEnter", updateTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function visibility(frame, driver)
    if not driver then return end
    local ok, reason = pcall(RegisterStateDriver, frame, "visibility", driver)
    if not ok then report("visibility unavailable", reason) end
end

-- Blizzard polls the target's target because its unit events are unreliable.
local function poll(frame)
    frame.elapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < POLL_SECONDS then return end
        self.elapsed = 0
        unitframes.Refresh(self.unit)
    end)
end

-- The shared factory: src/modules/unitframes/unitframes-party.lua builds its members through it, so every
-- built frame lands in Frames and receives the unit events below.
local function build(spec, parent)
    local frame = CreateFrame("Button", FRAME_PREFIX .. spec.key, parent or UIParent, "SecureUnitButtonTemplate")
    frame.key, frame.unit, frame.threatArgs = spec.key, spec.unit, spec.threat
    frame:SetSize(spec.size.width, spec.size.height)
    if spec.groupMotion then unitframes.Motion.CreatePresentation(frame, parent) end
    decorate(frame, spec.size)
    secure(frame, spec.unit)
    hover(frame)
    visibility(frame, spec.visibility)
    if spec.poll then poll(frame) end
    unitframes.Frames[spec.key] = frame
    return frame
end
unitframes.Build = build

local function createFrame(spec)
    local frame = build(spec)
    if unitframes.Motion then unitframes.Motion.Attach(frame) end
    layout.Register(frame, spec.key, DEFAULTS[spec.key])
    return frame
end

local function stockFrame(name)
    local frame = _G[name]
    if not frame and name == "TargetFrameToT" and TargetFrame then frame = TargetFrame.totFrame end
    return frame
end

local function replacementsReady()
    for _, spec in ipairs(UNITS) do
        if not unitframes.Frames[spec.key] then return false end
    end
    return true
end

local function hideStock()
    stockPending = false
    if not unitframes.enabled or not replacementsReady() then return end
    for _, name in ipairs(STOCK_FRAMES) do
        local frame = stockFrame(name)
        -- No native handler must keep running: RikUI frames own these units now.
        if frame then core.Hide.Frame(frame, false) end
    end
end

function unitframes.UpdateStockVisibility()
    if stockPending then return end
    stockPending = true
    core.Combat.Queue(hideStock)
end

local function eachFrame(callback, unit)
    if core.Secret.IsSecret(unit) then unit = nil end
    for _, frame in pairs(unitframes.Frames) do
        if not unit or unit == frame.unit then callback(frame) end
    end
end

function unitframes.Refresh(unit)
    eachFrame(unitframes.Update, unit)
end

-- Unit replacement must not interpolate from a previous unit's fill.
local function replaceUnit(unit)
    eachFrame(function(frame)
        if unitframes.Motion then unitframes.Motion.Reset(frame, true) end
        unitframes.Update(frame)
    end, unit)
end

local function onUnitEvent(updater)
    return function(_, unit) eachFrame(updater, unit) end
end

local function combatFeedback(_, unit, event)
    -- A secret token must not broadcast a damage/heal cue to every frame.
    if core.Secret.IsSecret(unit) or type(unit) ~= "string" then return end
    eachFrame(function(frame) unitframes.Motion.CombatFeedback(frame, event) end, unit)
end

local function registerUnitEvents()
    core:RegisterEvent("UNIT_COMBAT", combatFeedback)
    core:RegisterEvent("UNIT_HEALTH", function(_, unit)
        local updater = core.Secret.IsSecret(unit) and unitframes.UpdateHealth or unitframes.HealthChanged
        eachFrame(updater, unit)
    end)
    core:RegisterEvent("UNIT_MAXHEALTH", onUnitEvent(unitframes.UpdateHealth))
    core:RegisterEvent("UNIT_POWER_UPDATE", onUnitEvent(unitframes.UpdatePower))
    core:RegisterEvent("UNIT_MAXPOWER", onUnitEvent(unitframes.UpdatePower))
    core:RegisterEvent("UNIT_DISPLAYPOWER", onUnitEvent(unitframes.UpdatePower))
    for _, event in ipairs({ "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CONNECTION",
        "UNIT_CLASSIFICATION_CHANGED" }) do
        core:RegisterEvent(event, onUnitEvent(unitframes.UpdateIdentity))
    end
    for _, event in ipairs({ "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        core:RegisterEvent(event, function() eachFrame(unitframes.UpdateThreat) end)
    end
end

local function registerTargetEvents()
    core:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        replaceUnit("target")
        replaceUnit("targettarget")
    end)
    -- core refuses an event the client does not know, so a build without focus loses nothing.
    core:RegisterEvent("PLAYER_FOCUS_CHANGED", function() replaceUnit("focus") end)
    core:RegisterEvent("UNIT_TARGET", function(_, unit)
        if core.Secret.IsSecret(unit) or unit == "target" then replaceUnit("targettarget") end
    end)
    core:RegisterEvent("UNIT_PET", function(_, unit)
        if core.Secret.IsSecret(unit) or unit == "player" then replaceUnit("pet") end
    end)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        unitframes.Refresh()
        unitframes.UpdateStockVisibility()
    end)
end

function unitframes:OnEnable()
    core.Combat.Queue(function()
        for _, spec in ipairs(UNITS) do
            if not unitframes.Frames[spec.key] then unitframes.Update(createFrame(spec)) end
        end
        unitframes.UpdateStockVisibility()
    end)
    registerUnitEvents()
    registerTargetEvents()
    if unitframes.Party then unitframes.Party.Enable() end
    if unitframes.Raid then unitframes.Raid.Enable() end
end

function unitframes:Debug(sample)
    sample("UnitHealth(player)", UnitHealth, "player")
    sample("UnitPower(player)", UnitPower, "player")
    sample("UnitHealth(target)", UnitHealth, "target")
    sample("UnitClass(target)", UnitClass, "target")
    sample("UnitReaction(target)", UnitReaction, "target", "player")
    sample("UnitThreatSituation(player)", UnitThreatSituation, "player")
end

core:RegisterModule("unitframes", unitframes)
