-- Target and threat indicators. Blizzard compares units in secure code and expresses the result
-- through its own regions: healthBar.selectedBorder is shown for target and focus, and the unit
-- frame's aggroHighlight while the unit is on you. This file copies those shown states and never
-- compares units or reads threat. Target scale and non-target dimming belong to the engine, which
-- also animates them, so they are set through the client's nameplate CVars.
local core = RikUI
local nameplates = core.Nameplates
local target = {}
nameplates.Target = target

local isRegion, font = nameplates.IsRegion, nameplates.Font
local ACCENT, THREAT = { 0.45, 0.75, 1, 1 }, { 1, 0.25, 0.2, 1 }
local ARROW_GAP, LINE_PIXELS, LINE_GAP_PIXELS = 3, 2, 1
local APPEAR_SECONDS, PULSE_SECONDS, PULSE_LOW = 0.12, 0.6, 0.35
-- Written only when the client knows the CVar; the originals go to the profile.
local CVARS = { nameplateSelectedScale = "1.15", nameplateNotSelectedAlpha = "0.6" }
local INFO_CVAR, INFO_PERCENT = "nameplateInfoDisplay", "CurrentHealthPercent"

local ARROW_SIZE = 12

local function arrow(own, glyph)
    local region = core.Media.Icon(own, glyph, ARROW_SIZE, "OVERLAY")
    region:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
    region.appear = nameplates.Skin.Tween(region, 0, 1, APPEAR_SECONDS)
    return region
end

local function pulse(line)
    local group = nameplates.Skin.Tween(line, 1, PULSE_LOW, PULSE_SECONDS)
    if group then group:SetLooping("BOUNCE") end
    return group
end

local function setSelected(parts, shown)
    if parts.selected == shown then return end
    parts.selected = shown
    for _, region in ipairs({ parts.arrowLeft, parts.arrowRight, parts.accent }) do region:SetShown(shown) end
    if not parts.accentPulse then return end
    if not shown then parts.accentPulse:Stop() return end
    parts.accentPulse:Play()
    nameplates.Skin.Play(parts.arrowLeft.appear)
    nameplates.Skin.Play(parts.arrowRight.appear)
end

local function followSelection(parts, border)
    border:SetAlpha(0)
    local function sync() setSelected(parts, border:IsShown() == true) end
    for _, method in ipairs({ "SetShown", "Show", "Hide" }) do
        if type(border[method]) == "function" then hooksecurefunc(border, method, sync) end
    end
    sync()
end

-- The flare is animated by Blizzard, so its alpha cannot be pinned; the art is blanked instead.
local function blankFlare(frame)
    if type(frame.aggroHighlightTextures) ~= "table" then return end
    for _, texture in ipairs(frame.aggroHighlightTextures) do
        if isRegion(texture) then pcall(texture.SetTexture, texture, nil) end
    end
end

local function followThreat(frame, parts)
    if not isRegion(frame.aggroHighlight) or type(frame.UpdateAggroHighlight) ~= "function" then return end
    blankFlare(frame)
    local function sync() parts.threat:SetShown(frame.aggroHighlight:IsShown() == true) end
    hooksecurefunc(frame, "UpdateAggroHighlight", sync)
    sync()
end

function target.Build(frame, parts)
    local own, bar = parts.bar, frame.HealthBarsContainer.healthBar
    parts.arrowLeft, parts.arrowRight = arrow(own, "chevron-right"), arrow(own, "chevron-left")
    parts.accent = nameplates.Block(own, "OVERLAY", ACCENT)
    parts.accentPulse = pulse(parts.accent)
    parts.threat = nameplates.Block(own, "OVERLAY", THREAT)
    parts.threat:SetShown(false)
    followSelection(parts, bar.selectedBorder)
    followThreat(frame, parts)
end

-- Arrows hug the bar and the level box, with the marker beyond the left arrow: the marker is
-- empty on most units and an empty font string gives an anchored region nothing to draw against.
-- The accent line runs under the bar's outer edge and the threat line over it.
function target.Resize(frame, parts, size)
    local own, backing = parts.bar, frame.HealthBarsContainer.healthBar.bgTexture
    local right = parts.levelBox or own
    parts.arrowLeft:ClearAllPoints()
    parts.arrowLeft:SetPoint("RIGHT", own, "LEFT", -ARROW_GAP, 0)
    parts.arrowRight:ClearAllPoints()
    parts.arrowRight:SetPoint("LEFT", right, "RIGHT", ARROW_GAP, 0)
    for line, point in pairs({ [parts.accent] = { "TOP", "BOTTOM", -1 }, [parts.threat] = { "BOTTOM", "TOP", 1 } }) do
        line:ClearAllPoints()
        line:SetPoint(point[1] .. "LEFT", backing, point[2] .. "LEFT", 0, point[3] * LINE_GAP_PIXELS * size)
        line:SetPoint(point[1] .. "RIGHT", backing, point[2] .. "RIGHT", 0, point[3] * LINE_GAP_PIXELS * size)
        line:SetHeight(LINE_PIXELS * size)
    end
end

local function known(name)
    if type(C_CVar) ~= "table" or type(C_CVar.GetCVarInfo) ~= "function" then return false end
    local ok, value = pcall(C_CVar.GetCVarInfo, name)
    return ok and value ~= nil
end

local function write(name, value)
    local saved = core.Profile.nameplateCVars
    if saved[name] == nil then saved[name] = C_CVar.GetCVar(name) end
    C_CVar.SetCVar(name, value)
end

local function writePercent()
    local index = type(Enum) == "table" and type(Enum.NamePlateInfoDisplay) == "table"
        and Enum.NamePlateInfoDisplay[INFO_PERCENT] or nil
    if index == nil or type(C_CVar.SetCVarBitfield) ~= "function" or not known(INFO_CVAR) then return end
    local saved = core.Profile.nameplateCVars
    if saved[INFO_CVAR] == nil then saved[INFO_CVAR] = C_CVar.GetCVar(INFO_CVAR) end
    C_CVar.SetCVarBitfield(INFO_CVAR, index, true)
end

local function applyCVars()
    core.Profile.nameplateCVars = core.Profile.nameplateCVars or {}
    for name, value in pairs(CVARS) do
        if known(name) then write(name, value) end
    end
    writePercent()
end

local function restoreCVars()
    local saved = core.Profile.nameplateCVars
    if type(saved) ~= "table" then return end
    for name, value in pairs(saved) do
        if known(name) and value ~= nil then C_CVar.SetCVar(name, value) end
    end
    core.Profile.nameplateCVars = nil
end

-- Several nameplate CVars refuse writes in combat.
function target.ApplyCVars()
    core.Combat.Queue(function()
        local ok, reason = pcall(applyCVars)
        if not ok then core:Print("Nameplates settings: " .. tostring(reason)) end
    end)
end

-- CVars outlive the module toggle, so a disabled module hands the saved values back at login.
core:RegisterEvent("PLAYER_LOGIN", function()
    if nameplates.enabled or not core.Profile then return end
    core.Combat.Queue(function()
        local ok, reason = pcall(restoreCVars)
        if not ok then core:Print("Nameplates settings: " .. tostring(reason)) end
    end)
end)
