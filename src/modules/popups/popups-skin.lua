-- The popup skin. Dialog art lives in a Border child frame (DialogBorderTemplate), so one alpha
-- write removes it. Every key is touched only when it holds a region, so a frame that lacks one
-- keeps that piece stock. Art is faded, never hidden: Blizzard's own Show calls then change nothing.
local core, media, ui, motion = RikUI, RikUI.Media, RikUI.UI, RikUI.Motion
local skin = core.Popups.Skin

local EDGE, BUTTON_INSET, ICON_CROP = 1, 2, 0.08
local BACKING, CONTROL, FIELD = { 0.06, 0.07, 0.09, 0.95 }, { 0.1, 0.11, 0.14, 1 }, { 0.03, 0.035, 0.045, 0.8 }
local LINE, TITLE_COLOR = { 0.25, 0.28, 0.32, 1 }, { 1, 0.82, 0 }
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local FADE_SECONDS = 0.15
local FONT_PREFIX = "RikUIPopupFont"
local FONT_COLORS = { Normal = { 1, 0.82, 0 }, Highlight = { 1, 1, 1 }, Disabled = { 0.5, 0.5, 0.5 } }
local DIALOG_ART, HEADER_ART = { "Border", "BG" }, { "LeftBG", "RightBG", "CenterBG" }
local SLICE_ART = { "Left", "Center", "Middle", "Right" }
local BUTTON_TEXTURES = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }
local POPUP_BUTTONS = { "Button1", "Button2", "Button3", "Button4" }
local GHOST_TEXT, GHOST_ICON = "GhostFrameContentsFrameText", "GhostFrameContentsFrameIcon"
local skinned, fonts = setmetatable({}, { __mode = "k" }), nil

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
    local lines = ui.Edges(owner, EDGE, "BORDER")
    for _, line in ipairs(lines) do line:SetVertexColor(unpack(LINE)) end
    return lines
end

local function font(region, role)
    if isRegion(region) and type(region.SetFont) == "function" then media.Font(region, role) end
end

-- A button reapplies its font objects on every state change, so the font goes on shared font
-- objects, not on the font string. false marks a client without CreateFont.
local function buttonFonts()
    if fonts ~= nil then return fonts end
    fonts = false
    if type(CreateFont) ~= "function" then return fonts end
    fonts = {}
    for state, color in pairs(FONT_COLORS) do
        local object = CreateFont(FONT_PREFIX .. state)
        object:SetFont(media.font, media.sizes.label, "OUTLINE")
        object:SetTextColor(unpack(color))
        fonts[state] = object
    end
    return fonts
end

local function applyFonts(button)
    local objects = buttonFonts()
    if not objects then return end
    for state, object in pairs(objects) do
        local setter = button["Set" .. state .. "FontObject"]
        if type(setter) == "function" then setter(button, object) end
    end
end

function skin.Button(button)
    if skinned[button] or not isRegion(button) or type(button.CreateTexture) ~= "function" then return end
    skinned[button] = true
    for _, getter in ipairs(BUTTON_TEXTURES) do
        local texture = type(button[getter]) == "function" and button[getter](button) or nil
        if isRegion(texture) then texture:SetAlpha(0) end
    end
    strip(button, SLICE_ART)
    button.rikBacking = fill(button, CONTROL, BUTTON_INSET)
    button.rikBorder = outline(button)
    button.rikHighlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.rikHighlight:SetAllPoints(button)
    button.rikHighlight:SetTexture(media.highlight)
    applyFonts(button)
end

local function skinEditBox(box)
    if not isRegion(box) or type(box.CreateTexture) ~= "function" then return end
    strip(box, { "NineSlice" })
    box.rikBackdrop = fill(box, FIELD, 0)
    box.rikBorder = outline(box)
end

local function skinPopup(frame)
    font(frame.Text, "label")
    font(frame.SubText, "small")
    local container = isRegion(frame.ButtonContainer) and frame.ButtonContainer or frame
    for _, key in ipairs(POPUP_BUTTONS) do skin.Button(container[key]) end
    skin.Button(frame.ExtraButton)
    skinEditBox(frame.EditBox)
end

local function skinMenu(frame)
    local header = frame.Header
    if not isRegion(header) then return end
    strip(header, HEADER_ART)
    font(header.Text, "heading")
    if isRegion(header.Text) then header.Text:SetTextColor(unpack(TITLE_COLOR)) end
end

local function skinGhost(frame)
    skin.Button(frame)
    font(_G[GHOST_TEXT], "label")
    local icon = _G[GHOST_ICON]
    if isRegion(icon) and type(icon.SetTexCoord) == "function" then
        icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    end
end

local KINDS = { popup = skinPopup, menu = skinMenu, ghost = skinGhost }

-- The border goes first: if the client refuses that write nothing else has been added.
function skin.Apply(frame, target)
    strip(frame, DIALOG_ART)
    if target.kind ~= "ghost" then
        frame.rikBackdrop = fill(frame, BACKING, 0)
        frame.rikBorder = outline(frame)
    end
    KINDS[target.kind](frame)
    frame.rikFade = motion.Tween(frame, 0, 1, FADE_SECONDS)
end

-- The game menu releases and re-acquires its buttons from a pool whenever it is built.
function skin.Refresh(frame, target)
    local pool = frame.buttonPool
    if target.kind ~= "menu" or type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
    for button in pool:EnumerateActive() do skin.Button(button) end
end

function skin.FadeIn(frame) motion.Play(frame.rikFade) end
