-- The flat look for the world map's navigation bar. The map's chrome is the panels module's job;
-- this file covers the breadcrumb bar inside it. WorldMapNavBarMixin:Refresh rebuilds the
-- breadcrumbs on every map change, so it is post-hooked on the bar itself, not on the global NavBar
-- functions that other windows share. The obsolete portrait inset is removed out of combat. The two
-- round buttons on the canvas get a flat backing too. The map is where taint does the most damage,
-- so the content overlays (bounty board, action button, threat frame) are never touched.
local core, media, skin = RikUI, RikUI.Media, RikUI.Skin
local worldmap = { Overlays = setmetatable({}, { __mode = "k" }) }
core.WorldMap = worldmap

local MAP = "WorldMapFrame"
local CRUMB_ART = { "arrowUp", "arrowDown", "selected" }
local CRUMB_TEXTURES = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }
local SEPARATOR_INSET, EDGE = 8, 1
local SURFACE = { 0.055, 0.065, 0.08, 1 }
local function divider(owner)
    local line = owner:CreateTexture(nil, "BORDER")
    line:SetTexture(skin.FLAT)
    line:SetVertexColor(0.22, 0.25, 0.3, 0.5)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 8, 0)
    line:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -8, 0)
    return line
end
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
    for index, button in ipairs(bar.navList) do
        if skin.IsRegion(button) then
            skinCrumb(button)
            if skin.IsRegion(button.text) then
                local active = index == #bar.navList
                button.text:SetTextColor(active and 0.95 or 0.65, active and 0.96 or 0.72, active and 1 or 0.8)
            end
        end
    end
end

local function skinBar(bar)
    fadeStock(bar)
    if skin.IsRegion(bar.overlay) then fadeStock(bar.overlay) end
    if not bar.rikFill then
        bar.rikFill = skin.Fill(bar, SURFACE)
        bar.rikBorder = { divider(bar) }
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

-- Skin only presentation surfaces; never fill the high-level frame over the map.
local surfaces = setmetatable({}, { __mode = "k" })
local function flatSurface(owner, color, art)
    if not isFrame(owner) then return end
    if art then skin.Strip(owner, art) end
    if surfaces[owner] then return end
    surfaces[owner] = { fill = skin.Fill(owner, color), edge = skin.Outline(owner) }
end
local function questRows(pool, header)
    if not pool or type(pool.EnumerateActive) ~= "function" then return end
    for row in pool:EnumerateActive() do
        if header then
            skin.Strip(row, { "Left", "Middle", "Right", "Background" })
            if not surfaces[row] then surfaces[row] = { divider = divider(row) } end
            -- ListHeaderVisualTemplate uses button-state textures, not named slices.
            local normal = type(row.GetNormalTexture) == "function" and row:GetNormalTexture()
            if skin.IsRegion(normal) then normal:SetAlpha(0) end
            local highlight = type(row.GetHighlightTexture) == "function" and row:GetHighlightTexture()
            if skin.IsRegion(highlight) then
                highlight:SetTexture(skin.FLAT)
                highlight:SetVertexColor(1, 1, 1, 0.08)
            end
        end
        skin.Typeface(row.Text)
        skin.Typeface(row.ButtonText)
        skin.Typeface(row.Dash)
        if header then
            for _, label in ipairs({ row.Text, row.ButtonText }) do
                if skin.IsRegion(label) then label:SetTextColor(0.72, 0.78, 0.85) end
            end
        end
    end
end
local function questChrome(frame)
    local log = frame.QuestLog
    local quests = isFrame(log) and log.QuestsFrame
    local scroll = isFrame(quests) and quests.ScrollFrame
    if not isFrame(scroll) then return end
    -- Back the whole native panel, including the scrollbar outside its scroll viewport.
    -- Parenting to the log also hides this surface when the quest panel collapses.
    if not surfaces[log] then surfaces[log] = { fill = skin.Fill(log, { 0.055, 0.065, 0.08, 1 }) } end
    skin.Strip(scroll, { "Background", "Edge" })
    local border = scroll.BorderFrame
    if isFrame(border) then skin.Strip(border, { "Border", "TopDetail", "Shadow" }) end
    flatSurface(scroll.SearchBox, skin.CONTROL, { "Left", "Middle", "Right" })
    if isFrame(_G.QuestLogCount) then skin.Strip(_G.QuestLogCount, { "Left", "Middle", "Right" }) end
    if skin.IsRegion(_G.QuestLogQuestCount) then _G.QuestLogQuestCount:SetTextColor(0.72, 0.78, 0.85) end
    questRows(scroll.headerFramePool, true)
    questRows(scroll.titleFramePool)
    questRows(scroll.objectiveFramePool)
    skin.Typeface(scroll.EmptyText)
    skin.Typeface(scroll.NoSearchResultsText)
end
local function alignNavigation(frame)
    core.Combat.Queue(function()
        local bar, spacer = frame.NavBar, frame.TitleCanvasSpacerFrame
        if not isFrame(bar) or not isFrame(spacer) then return end
        -- Replace only the portrait inset; retain the native right/bottom anchors.
        bar:SetPoint("TOPLEFT", spacer, "TOPLEFT", 8, -25)
    end, "worldmap:navigation")
end
local function shell(frame)
    if not worldmap.Backing then worldmap.Backing = skin.Fill(frame, SURFACE, 1) end
    local chrome, canvas = frame.BorderFrame, frame.ScrollContainer
    if isFrame(chrome) and isFrame(canvas) and not worldmap.Header then
        -- BorderFrame is above the navigation siblings; its background would occlude them.
        local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        fill:SetTexture(skin.FLAT)
        fill:SetVertexColor(0.055, 0.065, 0.08, 1)
        -- These two corners bound only the area above the canvas, at either map size.
        fill:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
        fill:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", 0, 0)
        worldmap.Header = fill
        skin.Strip(chrome, { "InsetBorderTop" })
    end
    local title = isFrame(chrome) and chrome.TitleContainer
    if isFrame(title) and skin.IsRegion(title.TitleText) then title.TitleText:SetTextColor(0.9, 0.93, 0.98) end
    questChrome(frame)
end

local function onShow(frame)
    alignNavigation(frame)
    local ok, reason = pcall(shell, frame)
    if not ok then warn("chrome", reason) end
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
    for _, method in ipairs({ "Minimize", "Maximize" }) do
        if type(frame[method]) == "function" then hooksecurefunc(frame, method, alignNavigation) end
    end
    if frame:IsShown() then onShow(frame) end
end

function worldmap:OnEnable()
    if self.EnableTools then self.EnableTools() end
    attachSkin()
    core:RegisterEvent("ADDON_LOADED", attachSkin)
    if type(QuestLogQuests_Update) == "function" then
        hooksecurefunc("QuestLogQuests_Update", function()
            local frame = worldmap.HookedFrame
            if frame and frame:IsShown() then
                local ok, reason = pcall(questChrome, frame)
                if not ok then warn("quest chrome", reason) end
            end
        end)
    end
end

function worldmap:Debug()
    if self.DebugTools then self.DebugTools() end
    core:Print("World map bar=" .. tostring(state.bar) .. " crumbs=" .. state.crumbs
        .. " failed=" .. tostring(state.failed) .. " tools=" .. tostring(worldmap.Toolbar ~= nil)
        .. " reveal=" .. tostring(core.Profile and core.Profile.worldmap and not core.Profile.worldmap.fog))
end

core:RegisterModule("worldmap", worldmap)
