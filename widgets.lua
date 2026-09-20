-- Flat skin for the UI widget bars: status bars, double status bars and capture bars, which is
-- what battlegrounds, world PvP towers and scripted events draw. Each widget mixin's Setup runs on
-- every update, so it is post-hooked on the mixin table; a frame copies its mixin's functions when
-- it is made, so a widget made before login keeps the stock Setup until a reload. Blizzard's fill
-- textures, colours, sparks, state glows and values stay: the fill colour carries the faction or the
-- state, and nothing about a value is read here. Setup re-applies label font objects, so the
-- typeface is written again every time; fill and edge are made once per frame.
local core, skin = RikUI, RikUI.Skin
local widgets = {}
core.Widgets = widgets

local BAR_ART = { "BG", "BGLeft", "BGRight", "BGCenter", "BorderLeft", "BorderRight", "BorderCenter", "BackgroundGlow" }
local CAPTURE_ART = { "BarBackground", "LeftLine", "RightLine", "Divider" }
local decorated, failed = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local warnings, counts = {}, { hooked = 0, skinned = 0, failed = 0 }

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Widgets " .. operation .. ": " .. tostring(reason))
end

local function skinBar(bar)
    if not skin.IsRegion(bar) then return false end
    skin.Strip(bar, BAR_ART)
    skin.Typeface(bar.Label)
    if bar.rikFill then return true end
    bar.rikFill = skin.Fill(bar, skin.BACKING)
    bar.rikBorder = skin.Outline(bar)
    return true
end

local function skinStatusBar(frame)
    skin.Typeface(frame.Label)
    return skinBar(frame.Bar)
end

local function skinDoubleStatusBar(frame)
    skin.Typeface(frame.Label)
    local left, right = skinBar(frame.LeftBar), skinBar(frame.RightBar)
    return left or right
end

-- The zones are textures on the widget, so the fill goes on the widget too, stretched from the left
-- zone to the right one. The edge lines frame an empty span frame anchored the same way.
local function spanCapture(frame)
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetTexture(skin.FLAT)
    fill:SetVertexColor(unpack(skin.BACKING))
    local span = CreateFrame("Frame", nil, frame)
    for _, region in ipairs({ fill, span }) do
        region:SetPoint("TOPLEFT", frame.LeftBar, "TOPLEFT", 0, 0)
        region:SetPoint("BOTTOMRIGHT", frame.RightBar, "BOTTOMRIGHT", 0, 0)
    end
    frame.rikFill, frame.rikSpan = fill, span
    frame.rikBorder = skin.Outline(frame, nil, 0, span)
end

local function skinCaptureBar(frame)
    if not skin.IsRegion(frame.LeftBar) or not skin.IsRegion(frame.RightBar) then return false end
    skin.Strip(frame, CAPTURE_ART)
    if not frame.rikFill then spanCapture(frame) end
    return true
end

local TARGETS = {
    { mixin = "UIWidgetTemplateStatusBarMixin", apply = skinStatusBar },
    { mixin = "UIWidgetTemplateDoubleStatusBarMixin", apply = skinDoubleStatusBar },
    { mixin = "UIWidgetTemplateCaptureBarMixin", apply = skinCaptureBar },
}

-- A failed widget is not retried: half a skin applied on every update is worse than half a skin.
local function afterSetup(frame, apply)
    if type(frame) ~= "table" or failed[frame] then return end
    local ok, found = pcall(apply, frame)
    if not ok then
        failed[frame] = true
        counts.failed = counts.failed + 1
        warn("skin", found)
    elseif found and not decorated[frame] then
        decorated[frame] = true
        counts.skinned = counts.skinned + 1
    end
end

function widgets:OnEnable()
    for _, target in ipairs(TARGETS) do
        local mixin = _G[target.mixin]
        if type(mixin) == "table" and type(mixin.Setup) == "function" then
            hooksecurefunc(mixin, "Setup", function(frame) afterSetup(frame, target.apply) end)
            counts.hooked = counts.hooked + 1
        end
    end
end

function widgets:Debug()
    core:Print("Widgets hooked=" .. counts.hooked .. " skinned=" .. counts.skinned .. " failed=" .. counts.failed)
end

core:RegisterModule("widgets", widgets)
