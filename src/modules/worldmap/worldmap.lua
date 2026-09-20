-- The flat look for the world map's navigation bar. The map's chrome is the panels module's job;
-- this file covers the breadcrumb bar inside it. WorldMapNavBarMixin:Refresh rebuilds the
-- breadcrumbs on every map change, so it is post-hooked on the bar itself, not on the global NavBar
-- functions that other windows share. Only alpha, fonts and new child regions are written. The two
-- round buttons on the canvas get a flat backing too. The map is where taint does the most damage,
-- so the content overlays (bounty board, action button, threat frame) are never touched.
local core, media, skin = RikUI, RikUI.Media, RikUI.Skin
local worldmap = { Overlays = setmetatable({}, { __mode = "k" }) }
core.WorldMap = worldmap

local MAP = "WorldMapFrame"
local CRUMB_ART = { "arrowUp", "arrowDown", "selected" }
local CRUMB_TEXTURES = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }
local SEPARATOR_INSET, EDGE = 4, 1
-- The disc and the ring of the round canvas buttons; the icon stays. The backing sits inside the
-- ring's transparent margin.
local OVERLAY_KEYS = { "WorldMapTrackingOptionsButton", "WorldMapTrackingPinButton" }
local OVERLAY_ART, OVERLAY_INSET = { "Background", "Border" }, 4
local overlayFailed = setmetatable({}, { __mode = "k" })
local warnings, state = {}, { bar = false, failed = false, crumbs = 0 }
local decorated, stock = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("World map " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.HookScript) == "function"
end

local function textures(...)
    local list = {}
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if skin.IsRegion(region) and region:GetObjectType() == "Texture" then list[#list + 1] = region end
    end
    return list
end

-- GetRegions also answers with regions this file creates, so Blizzard's textures are listed once,
-- on the first pass, before the fill and edge exist. Later passes fade that list again.
local function fadeStock(owner)
    stock[owner] = stock[owner] or textures(owner:GetRegions())
    for _, texture in ipairs(stock[owner]) do texture:SetAlpha(0) end
end

local function decorateCrumb(button)
    button.rikHighlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.rikHighlight:SetAllPoints(button)
    button.rikHighlight:SetTexture(media.highlight)
    local separator = button:CreateTexture(nil, "BORDER")
    separator:SetTexture(media.border)
    separator:SetVertexColor(unpack(skin.LINE))
    separator:SetWidth(EDGE)
    separator:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, -SEPARATOR_INSET)
    separator:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, SEPARATOR_INSET)
    button.rikSeparator = separator
end

-- Blizzard re-shows the chevron art when a breadcrumb changes state, so it is faded every time.
local function skinCrumb(button)
    skin.Strip(button, CRUMB_ART)
    for _, getter in ipairs(CRUMB_TEXTURES) do
        local texture = type(button[getter]) == "function" and button[getter](button) or nil
        if skin.IsRegion(texture) then texture:SetAlpha(0) end
    end
    skin.Typeface(button.text)
    if decorated[button] then return end
    decorated[button] = true
    state.crumbs = state.crumbs + 1
    decorateCrumb(button)
end

local function skinCrumbs(bar)
    if type(bar.navList) ~= "table" then return end
    for _, button in ipairs(bar.navList) do
        if skin.IsRegion(button) then skinCrumb(button) end
    end
end

local function skinBar(bar)
    fadeStock(bar)
    if skin.IsRegion(bar.overlay) then fadeStock(bar.overlay) end
    if not bar.rikFill then
        bar.rikFill = skin.Fill(bar, skin.CONTROL)
        bar.rikBorder = skin.Outline(bar)
    end
    skinCrumbs(bar)
end

-- A failed bar is not retried: half a skin applied on every map change is worse than half a skin.
local function refresh(bar)
    if state.failed then return end
    local ok, reason = pcall(skinBar, bar)
    state.bar = ok
    if ok then return end
    state.failed = true
    warn("skin", reason)
end

-- The two round buttons on the canvas. Like the bar they are overlay frames Blizzard walks with
-- secureexecuterange, so nothing is stored on them: the record lives in a weak table.
local function applyOverlay(button)
    skin.Strip(button, OVERLAY_ART)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetTexture(media.highlight)
    worldmap.Overlays[button] = { fill = skin.Fill(button, skin.CONTROL, OVERLAY_INSET),
        edge = skin.Outline(button, nil, OVERLAY_INSET), highlight = highlight }
end

local function skinOverlays(frame)
    for _, key in ipairs(OVERLAY_KEYS) do
        local button = frame[key]
        local fresh = skin.IsRegion(button) and type(button.CreateTexture) == "function"
            and not worldmap.Overlays[button] and not overlayFailed[button]
        if fresh then
            local ok, reason = pcall(applyOverlay, button)
            if not ok then overlayFailed[button] = true; warn("overlay", reason) end
        end
    end
end

local function onShow(frame)
    skinOverlays(frame)
    local bar = frame.NavBar
    if not isFrame(bar) then return end
    if not worldmap.Hooked and type(bar.Refresh) == "function" then
        worldmap.Hooked = true
        hooksecurefunc(bar, "Refresh", refresh)
    end
    refresh(bar)
end

local function attachSkin()
    local frame = _G[MAP]
    if worldmap.HookedFrame or not isFrame(frame) then return end
    worldmap.HookedFrame = frame
    frame:HookScript("OnShow", onShow)
    if frame:IsShown() then onShow(frame) end
end

function worldmap:OnEnable()
    if self.EnableTools then self.EnableTools() end
    attachSkin()
    core:RegisterEvent("ADDON_LOADED", attachSkin)
end

function worldmap:Debug()
    core:Print("World map bar=" .. tostring(state.bar) .. " crumbs=" .. state.crumbs
        .. " failed=" .. tostring(state.failed) .. " tools=" .. tostring(worldmap.Toolbar ~= nil)
        .. " reveal=" .. tostring(core.Profile and core.Profile.worldmap and not core.Profile.worldmap.fog))
end

core:RegisterModule("worldmap", worldmap)
