-- Two supplemental map controls; Blizzard owns the quest list and navigation.
local core, map = RikUI, RikUI.WorldMap
local nav, skin, media = map.Navigation, RikUI.Skin, RikUI.Media
local TOOLBAR_WIDTH, TOOLBAR_HEIGHT = 214, 22
local toolbar, frame, pending
local function settings() return core.Profile.worldmap end
local function text(parent, label, role)
    local region = parent:CreateFontString(nil, "OVERLAY")
    media.Font(region, role or "small")
    region:SetText(label)
    region:SetJustifyH("LEFT")
    return region
end
local function tooltip(owner, title, detail)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    GameTooltip:AddLine(detail, 1, 1, 1, true)
    GameTooltip:Show()
end
local function button(parent, label, width, action, hint)
    local control = CreateFrame("Button", nil, parent)
    control:SetSize(width, 20)
    skin.Fill(control, skin.CONTROL)
    control:SetHighlightTexture(media.highlight)
    control.label = text(control, label)
    control.label:SetPoint("CENTER")
    control:SetScript("OnClick", action)
    if hint then control:SetScript("OnEnter", function() tooltip(control, label, hint) end) end
    control:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return control
end
function map.SetOption(key, value)
    if key ~= "fog" or type(value) ~= "boolean" then return end
    settings()[key] = value
    core:Changed()
    map.RefreshTools()
end
local function toggle(key) map.SetOption(key, not settings()[key]) end
function map.RefreshTools()
    if not toolbar then return end
    toolbar.fog.label:SetText(settings().fog and "Fog: on" or "Fog: off")
    local supported = map.Terrain.Available(frame)
    toolbar.fog:SetEnabled(supported or not settings().fog)
    toolbar.fog.label:SetTextColor(settings().fog and 0.8 or 0.4, settings().fog and 0.82 or 0.8, 1)
    map.Terrain.Refresh(frame)
end
function map.RequestTools()
    if pending or not toolbar or not frame:IsShown() then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        if frame:IsShown() then map.RefreshTools() end
    end)
end
local function build()
    if toolbar then return end
    local canvas = frame:GetCanvasContainer()
    if not canvas then return end
    local host = frame.BorderFrame or frame
    toolbar = CreateFrame("Frame", "RikUIMapTools", host)
    toolbar:SetSize(TOOLBAR_WIDTH, TOOLBAR_HEIGHT)
    -- Share the title row, leaving breadcrumbs and the entire terrain unobstructed.
    toolbar:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -4)
    toolbar:SetFrameLevel(canvas:GetFrameLevel() + 50)
    toolbar.fog = button(toolbar, "Fog: on", 94, function() toggle("fog") end,
        "On: normal exploration. Off: reveal unexplored terrain in blue. Click to switch. Exploration progress is unchanged.")
    toolbar.fog:SetPoint("LEFT", 4, 0)
    toolbar.player = button(toolbar, "My location", 104, function() nav.Player(frame) end,
        "Return to your current zone. Use the map breadcrumbs or right-click to go up.")
    toolbar.player:SetPoint("LEFT", toolbar.fog, "RIGHT", 4, 0)
    map.Toolbar = toolbar
    map.RefreshTools()
end
-- OnShow can run while the native canvas is still being sized. Finish on the
-- next frame, then rebuild native providers once with the settled dimensions.
local opening
local function opened()
    if opening then return end
    opening = true
    C_Timer.After(0, function()
        opening = false
        if not frame:IsShown() then return end
        core.Combat.Queue(function()
            if not frame:IsShown() then return end
            -- RefreshAll alone skips clean cached detail layers and never sizes pins.
            -- Repeat the geometry/detail portion of map navigation on the current map.
            if type(frame.OnFrameSizeChanged) == "function" then frame:OnFrameSizeChanged() end
            if type(frame.ForceRefreshDetailLayers) == "function" then frame:ForceRefreshDetailLayers() end
            if type(frame.RefreshAll) == "function" then frame:RefreshAll(true) end
            build()
            map.RequestTools()
        end, "worldmap:tools")
    end)
end
local function attach()
    if frame then return end
    local candidate = WorldMapFrame
    if not candidate or type(candidate.GetCanvasContainer) ~= "function" then return end
    frame = candidate
    frame:HookScript("OnShow", opened)
    if type(frame.OnMapChanged) == "function" then hooksecurefunc(frame, "OnMapChanged", map.RequestTools) end
    if frame:IsShown() then opened() end
end
function map.DebugTools()
    if not frame then core:Print("World map canvas not attached"); return end
    local canvas = nav.Call(frame.GetCanvasContainer, frame)
    core:Print("World map id=" .. tostring(nav.Call(frame.GetMapID, frame))
        .. " alpha=" .. tostring(nav.Call(frame.GetAlpha, frame))
        .. " canvas=" .. tostring(canvas and nav.Call(canvas.GetWidth, canvas))
        .. "x" .. tostring(canvas and nav.Call(canvas.GetHeight, canvas))
        .. " detailsLoaded=" .. tostring(nav.Call(frame.AreDetailLayersLoaded, frame)))
    if type(frame.EnumeratePinsByTemplate) ~= "function" then return end
    for pin in frame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        core:Print("World map exploration=" .. tostring(nav.Call(pin.GetWidth, pin))
            .. "x" .. tostring(nav.Call(pin.GetHeight, pin))
            .. " alpha=" .. tostring(nav.Call(pin.GetAlpha, pin))
            .. " waiting=" .. tostring(pin.isWaitingForLoad))
    end
end
function map.EnableTools()
    attach()
    core:RegisterEvent("ADDON_LOADED", attach)
    for _, event in ipairs({ "MAP_EXPLORATION_UPDATED", "PLAYER_ENTERING_WORLD" }) do
        core:RegisterEvent(event, map.RequestTools)
    end
    hooksecurefunc(core, "SetProfile", map.RequestTools)
end
map.Options = { title = "World map", settings = {
    { type = "checkbox", key = "worldmap.fog", label = "Fog of war (off reveals terrain)",
        get = function() return settings().fog end,
        set = function(value) map.SetOption("fog", value) end },
} }
