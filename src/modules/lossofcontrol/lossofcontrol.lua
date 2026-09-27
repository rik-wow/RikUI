-- Flat look for Blizzard's loss-of-control alert (stunned, feared, silenced). The frame is skinned in
-- place so Blizzard keeps deciding what is shown and for how long; this file never calls
-- C_LossOfControl. Blizzard writes the frame's alpha every frame in OnUpdate, so the frame's alpha is
-- never touched or animated here: the fade-in and the red pulse run on RikUI's own textures.
local core, skin, motion = RikUI, RikUI.Skin, RikUI.Motion
local loc = { Pulses = {} }
core.LossOfControl = loc

local FRAME_NAME = "LossOfControlFrame"
local ART = { "blackBg", "RedLineTop", "RedLineBottom" }
-- The size and anchor of Blizzard's shadow texture, which the panel replaces.
local PANEL_WIDTH, PANEL_HEIGHT, PANEL_POINT = 256, 58, "BOTTOM"
local ACCENT_HEIGHT, ACCENT_COLOR, ICON_EDGE_INSET = 2, { 0.9, 0.15, 0.15, 1 }, -1
local PULSE_FROM, PULSE_TO, PULSE_SECONDS = 1, 0.35, 0.6
local ACCENT_SIDES = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }
local skinned, warned = false, false

local function warn(operation, reason)
    if warned then return end
    warned = true
    core:Print("LossOfControl " .. operation .. ": " .. tostring(reason))
end

local function panel(frame)
    local texture = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    texture:SetTexture(skin.FLAT)
    texture:SetVertexColor(unpack(skin.BACKING))
    texture:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    texture:SetPoint(PANEL_POINT, frame, PANEL_POINT, 0, 0)
    return texture
end

-- Red stays the signal for "you are not in control"; the glow becomes two thin lines.
local function accent(frame, target, first, second)
    local texture = frame:CreateTexture(nil, "BORDER")
    texture:SetTexture(skin.FLAT)
    texture:SetVertexColor(unpack(ACCENT_COLOR))
    texture:SetPoint(first, target, first, 0, 0)
    texture:SetPoint(second, target, second, 0, 0)
    texture:SetHeight(ACCENT_HEIGHT)
    return texture
end

local function typefaces(frame)
    skin.Typeface(frame.AbilityName)
    local timeLeft = frame.TimeLeft
    if not skin.IsRegion(timeLeft) then return end
    skin.Typeface(timeLeft.NumberText)
    skin.Typeface(timeLeft.SecondsText)
end

local function contrast(frame)
    frame.rikNamePlate = skin.TextPlate(frame, frame.AbilityName, nil, 4)
    local timer = frame.TimeLeft
    if not skin.IsRegion(timer) then return end
    timer.rikNumberPlate = skin.TextPlate(timer, timer.NumberText, nil, 3)
end

local function details(frame)
    frame.rikSteady = frame:CreateTexture(nil, "BORDER")
    frame.rikSteady:SetTexture(skin.FLAT)
    frame.rikSteady:SetVertexColor(unpack(ACCENT_COLOR))
    frame.rikSteady:SetPoint("TOPLEFT", frame.rikPanel, "TOPLEFT", 2, -4)
    frame.rikSteady:SetPoint("BOTTOMLEFT", frame.rikPanel, "BOTTOMLEFT", 2, 4)
    frame.rikSteady:SetWidth(3)
    if skin.IsRegion(frame.Icon) then
        frame.rikIconBacking = skin.Fill(frame, { 0.16, 0.045, 0.055, 0.95 })
        frame.rikIconBacking:ClearAllPoints()
        frame.rikIconBacking:SetPoint("TOPLEFT", frame.Icon, "TOPLEFT", -4, 4)
        frame.rikIconBacking:SetPoint("BOTTOMRIGHT", frame.Icon, "BOTTOMRIGHT", 4, -4)
    end
    contrast(frame)
end

-- The art goes first: if the client refuses that write nothing else has been added.
local function apply(frame)
    skin.Strip(frame, ART)
    frame.rikPanel = panel(frame)
    frame.rikBorder = skin.Outline(frame, nil, 0, frame.rikPanel)
    frame.rikAccents = {}
    for index, pair in ipairs(ACCENT_SIDES) do
        frame.rikAccents[index] = accent(frame, frame.rikPanel, pair[1], pair[2])
        loc.Pulses[index] = motion.Pulse(frame.rikAccents[index], PULSE_FROM, PULSE_TO, PULSE_SECONDS)
    end
    if skin.IsRegion(frame.Icon) then
        skin.CropIcon(frame.Icon)
        -- One pixel outside the icon: the lines are in a lower layer than the icon and would be covered.
        frame.rikIconBorder = skin.Outline(frame, nil, ICON_EDGE_INSET, frame.Icon)
    end
    typefaces(frame)
    details(frame)
    loc.Fade = motion.Tween(frame.rikPanel, 0, 1, skin.FADE_SECONDS)
end

local function onShow(frame)
    contrast(frame)
    motion.Play(loc.Fade)
    for _, pulse in ipairs(loc.Pulses) do motion.Play(pulse) end
end

local function onHide()
    for _, pulse in ipairs(loc.Pulses) do motion.Stop(pulse) end
end

function loc:OnEnable()
    local frame = _G[FRAME_NAME]
    if not skin.IsRegion(frame) or type(frame.HookScript) ~= "function" then return end
    local ok, reason = pcall(apply, frame)
    if not ok then return warn("skin", reason) end
    skinned = true
    frame:HookScript("OnShow", onShow)
    frame:HookScript("OnHide", onHide)
    if frame:IsShown() then onShow(frame) end
end

function loc:Debug()
    core:Print("LossOfControl skinned=" .. tostring(skinned))
end

core:RegisterModule("lossofcontrol", loc)
