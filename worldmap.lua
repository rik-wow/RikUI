-- The flat look for the world map's navigation bar. The map's chrome is the panels module's job;
-- this file covers the breadcrumb bar inside it. WorldMapNavBarMixin:Refresh rebuilds the
-- breadcrumbs on every map change, so it is post-hooked on the bar itself, not on the global NavBar
-- functions that other windows share. Only alpha, fonts and new child regions are written. The
-- overlay buttons on the canvas are left stock on purpose: Blizzard walks them with
-- secureexecuterange and the map is where taint does the most damage.
local core, media, skin = RikUI, RikUI.Media, RikUI.Skin
local worldmap = {}
core.WorldMap = worldmap

local MAP = "WorldMapFrame"
local CRUMB_ART = { "arrowUp", "arrowDown", "selected" }
local CRUMB_TEXTURES = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }
local SEPARATOR_INSET, EDGE = 4, 1
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

local function onShow(frame)
    local bar = frame.NavBar
    if not isFrame(bar) then return end
    if not worldmap.Hooked and type(bar.Refresh) == "function" then
        worldmap.Hooked = true
        hooksecurefunc(bar, "Refresh", refresh)
    end
    refresh(bar)
end

function worldmap:OnEnable()
    local frame = _G[MAP]
    if not isFrame(frame) then return end
    frame:HookScript("OnShow", onShow)
    if frame:IsShown() then onShow(frame) end
end

function worldmap:Debug()
    core:Print("World map bar=" .. tostring(state.bar) .. " crumbs=" .. state.crumbs
        .. " failed=" .. tostring(state.failed))
end

core:RegisterModule("worldmap", worldmap)
