-- Widget skinning follows native manager updates; Setup methods remain untouched.
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

local TARGETS = { StatusBar = skinStatusBar, DoubleStatusBar = skinDoubleStatusBar, CaptureBar = skinCaptureBar }

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

local function scanContainer(container)
    local types = Enum and Enum.UIWidgetVisualizationType
    if not types or type(container.widgetFrames) ~= "table" then return end
    for _, frame in pairs(container.widgetFrames) do
        for name, apply in pairs(TARGETS) do
            if types[name] and frame.widgetType == types[name] then afterSetup(frame, apply) end
        end
    end
end

local pending = false
local function scan()
    pending = false
    local manager = _G.UIWidgetManager
    for container in pairs(manager and manager.registeredWidgetContainers or {}) do scanContainer(container) end
end

-- Wait until every native container has processed Setup, regardless of event ordering.
local function requestScan()
    if pending then return end
    pending = true
    C_Timer.After(0, scan)
end

function widgets:OnEnable()
    if core.Hooks.Function("DefaultWidgetLayout", scanContainer) then counts.hooked = 1 end
    for _, event in ipairs({ "UPDATE_UI_WIDGET", "UPDATE_ALL_UI_WIDGETS", "NAME_PLATE_UNIT_ADDED",
        "PLAYER_ENTERING_WORLD", "ADDON_LOADED" }) do
        core:RegisterEvent(event, requestScan)
    end
    scan()
end

function widgets:Debug()
    core:Print("Widgets hooked=" .. counts.hooked .. " skinned=" .. counts.skinned .. " failed=" .. counts.failed)
end

core:RegisterModule("widgets", widgets)
