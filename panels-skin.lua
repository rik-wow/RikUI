-- The skin itself. It only knows the chrome keys the Mainline window templates share and touches a
-- key only when it holds a region, so a window that lacks one keeps that piece stock. Stripped art
-- is faded, never hidden: Blizzard's own Show calls on it then change nothing.
local core, media, unitframes, motion = RikUI, RikUI.Media, RikUI.UnitFrames, RikUI.Motion
local skin = core.Panels.Skin

local EDGE, CLOSE_INSET, TAB_INSET, ACCENT_HEIGHT = 1, 5, 2, 2
local BACKING, INSET_BACKING, CONTROL = { 0.06, 0.07, 0.09, 0.95 }, { 0.03, 0.035, 0.045, 0.6 }, { 0.1, 0.11, 0.14, 1 }
local LINE, TITLE_COLOR, ACCENT = { 0.25, 0.28, 0.32, 1 }, { 1, 0.82, 0 }, { 0.3, 0.75, 1, 1 }
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local FADE_SECONDS = 0.15
local CLOSE_GLYPH = "x"
-- NineSlice windows, then the dialog border child, then the basic and translucent templates' pieces.
local CHROME_ART = { "NineSlice", "Bg", "TopTileStreaks", "TitleBg", "PortraitContainer", "PortraitFrame", "portrait",
    "Border", "TopLeftCorner", "TopRightCorner", "BotLeftCorner", "BotRightCorner", "BottomLeftCorner",
    "BottomRightCorner", "TopBorder", "BottomBorder", "LeftBorder", "RightBorder" }
local HEADER_ART = { "LeftBG", "RightBG", "CenterBG" }
local CLOSE_KEYS, CLOSE_SUFFIX = { "CloseButton", "CloseXButton" }, "CloseButton"
local INSET_ART = { "NineSlice", "Bg" }
local TAB_ART = { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
    "LeftHighlight", "MiddleHighlight", "RightHighlight" }
local BUTTON_TEXTURES = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }
local tabs = {}

local function isRegion(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetAlpha) == "function"
end

local function strip(owner, keys)
    for _, key in ipairs(keys) do
        if isRegion(owner[key]) then owner[key]:SetAlpha(0) end
    end
end

-- Sublevel -8 keeps the fill under every region Blizzard draws in the same layer.
local function fill(owner, color, inset)
    local texture = owner:CreateTexture(nil, "BACKGROUND", nil, -8)
    texture:SetTexture(FLAT)
    texture:SetVertexColor(unpack(color))
    texture:SetPoint("TOPLEFT", owner, "TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -inset, inset)
    return texture
end

local function outline(owner)
    local lines = unitframes.Edges(owner, EDGE, "BORDER")
    for _, line in ipairs(lines) do line:SetVertexColor(unpack(LINE)) end
    return lines
end

local function skinTitle(chrome)
    local container = chrome.TitleContainer
    local title = isRegion(container) and container.TitleText or chrome.TitleText
    if not isRegion(title) or type(title.SetFont) ~= "function" then return end
    media.Font(title, "label")
    title:SetTextColor(unpack(TITLE_COLOR))
end

local function skinClose(button)
    if not isRegion(button) or type(button.CreateTexture) ~= "function" then return end
    for _, getter in ipairs(BUTTON_TEXTURES) do
        local texture = type(button[getter]) == "function" and button[getter](button) or nil
        if isRegion(texture) then texture:SetAlpha(0) end
    end
    button.rikBacking = fill(button, CONTROL, CLOSE_INSET)
    button.rikBorder = outline(button)
    button.rikLabel = button:CreateFontString(nil, "OVERLAY")
    media.Font(button.rikLabel, "label")
    button.rikLabel:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.rikLabel:SetText(CLOSE_GLYPH)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetTexture(media.highlight)
end

-- Shared with dialogs.lua, which has close buttons but no window chrome.
skin.Close = skinClose

local function skinInset(inset)
    if not isRegion(inset) or type(inset.CreateTexture) ~= "function" then return end
    strip(inset, INSET_ART)
    inset.rikBackdrop = fill(inset, INSET_BACKING, 0)
    inset.rikBorder = outline(inset)
end

local function setAccent(tab, selected)
    if tabs[tab] then tab.rikAccent:SetShown(selected == true) end
end

local function skinTab(tab, selected)
    if tabs[tab] or not isRegion(tab) or type(tab.CreateTexture) ~= "function" then return end
    strip(tab, TAB_ART)
    tab.rikBacking = fill(tab, CONTROL, TAB_INSET)
    tab.rikBorder = outline(tab)
    tab.rikAccent = tab:CreateTexture(nil, "OVERLAY")
    tab.rikAccent:SetTexture(FLAT)
    tab.rikAccent:SetVertexColor(unpack(ACCENT))
    tab.rikAccent:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", TAB_INSET, TAB_INSET)
    tab.rikAccent:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -TAB_INSET, TAB_INSET)
    tab.rikAccent:SetHeight(ACCENT_HEIGHT)
    if isRegion(tab.Text) and type(tab.Text.SetFont) == "function" then media.Font(tab.Text, "small") end
    tabs[tab] = true
    setAccent(tab, selected)
    -- TabSystem tabs report their own selection; PanelTemplates tabs go through the global hooks.
    if type(tab.SetTabSelected) == "function" then hooksecurefunc(tab, "SetTabSelected", setAccent) end
end

local function selectedID(frame)
    if type(PanelTemplates_GetSelectedTab) ~= "function" then return nil end
    local ok, id = pcall(PanelTemplates_GetSelectedTab, frame)
    return ok and id or nil
end

local function skinTabs(frame)
    local system = frame.TabSystem
    local list = type(frame.Tabs) == "table" and frame.Tabs or type(system) == "table" and system.tabs or nil
    if type(list) ~= "table" then return end
    local chosen = selectedID(frame)
    for _, tab in ipairs(list) do
        local id = isRegion(tab) and type(tab.GetID) == "function" and tab:GetID() or nil
        skinTab(tab, chosen ~= nil and id == chosen)
    end
end

function skin.HookTabs()
    if type(PanelTemplates_SelectTab) == "function" then
        hooksecurefunc("PanelTemplates_SelectTab", function(tab) setAccent(tab, true) end)
    end
    if type(PanelTemplates_DeselectTab) == "function" then
        hooksecurefunc("PanelTemplates_DeselectTab", function(tab) setAccent(tab, false) end)
    end
end

local function skinHeader(header)
    if not isRegion(header) then return end
    strip(header, HEADER_ART)
    if not isRegion(header.Text) or type(header.Text.SetFont) ~= "function" then return end
    media.Font(header.Text, "heading")
    header.Text:SetTextColor(unpack(TITLE_COLOR))
end

local function findClose(chrome, name)
    for _, key in ipairs(CLOSE_KEYS) do
        if isRegion(chrome[key]) then return chrome[key] end
    end
    return _G[name .. CLOSE_SUFFIX]
end

-- Hand-drawn windows put unnamed textures straight on the frame. They are listed before any RikUI
-- region exists, because GetRegions returns addon-made regions too.
local function fadeTextures(chrome)
    if type(chrome.GetRegions) ~= "function" then return end
    for _, region in ipairs({ chrome:GetRegions() }) do
        if isRegion(region) and region:GetObjectType() == "Texture" then region:SetAlpha(0) end
    end
end

function skin.Apply(frame, target)
    local chrome = target.chrome and frame[target.chrome] or frame
    if not isRegion(chrome) then chrome = frame end
    strip(chrome, CHROME_ART)
    if target.regions then fadeTextures(chrome) end
    if target.fill ~= false then chrome.rikBackdrop = fill(chrome, BACKING, 0) end
    chrome.rikBorder = outline(chrome)
    skinTitle(chrome)
    skinHeader(chrome.Header)
    skinClose(findClose(chrome, target.name))
    skinInset(frame.Inset)
    skinTabs(frame)
    frame.rikFade = motion.Tween(frame, 0, 1, FADE_SECONDS)
end

function skin.FadeIn(frame) motion.Play(frame.rikFade) end
