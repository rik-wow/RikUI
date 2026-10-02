-- Shared pieces of the flat skin: fade or blank Blizzard art, add a flat fill, a one-pixel edge, the
-- RikUI font and a cropped icon. Every helper skips a value that is not a region, so a frame that
-- lacks a piece keeps that piece stock. Art is faded, never hidden: Blizzard's own Show calls then
-- change nothing.
local media = RikUI.Media
local skin = {}
RikUI.Skin = skin

skin.FLAT = "Interface\\BUTTONS\\WHITE8X8"
skin.BACKING, skin.CONTROL = { 0.06, 0.07, 0.09, 0.95 }, { 0.1, 0.11, 0.14, 1 }
skin.LINE, skin.GOLD = { 0.25, 0.28, 0.32, 1 }, { 1, 0.82, 0 }
-- Body text on the dark skin. Blizzard's parchment windows colour their labels dark brown or
-- black (SPELLBOOK_FONT_COLOR and kin); anything whose brightest channel stays under the limit
-- becomes ink, while red, green, gold and the 0.5 greys keep their meaning.
skin.INK = { 0.9, 0.92, 0.96 }
local DARK_LIMIT = 0.5
skin.FADE_SECONDS = 0.15
local EDGE, ICON_CROP = 1, 0.08
local BUTTON_FONT_PREFIX = "RikUIControlFont"
local BUTTON_FONT_COLORS = { Normal = { 1, 0.82, 0 }, Highlight = { 1, 1, 1 }, Disabled = { 0.5, 0.5, 0.5 } }
function skin.Configure(theme)
    theme = theme or {}
    EDGE = theme.border or 1
    local accent = theme.accent == "blue" and {0.3,0.75,1} or theme.accent == "white" and {1,1,1} or {1,0.82,0}
    skin.GOLD = accent
    skin.LINE = RikUI.Profile and RikUI.Profile.borderColor or {0.25,0.28,0.32,1}
end
local fonts
-- The direction that moves each corner towards the middle of its owner.
local CORNERS = { TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 } }
local SIDES = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
    { "TOPRIGHT", "BOTTOMRIGHT" } }

function skin.IsRegion(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetAlpha) == "function"
end

function skin.Strip(owner, keys)
    for _, key in ipairs(keys) do
        if skin.IsRegion(owner[key]) then owner[key]:SetAlpha(0) end
    end
end

-- For art whose alpha Blizzard animates: a faded region would come back, an empty one cannot.
function skin.Blank(owner, keys)
    for _, key in ipairs(keys) do
        local region = owner[key]
        local blankable = skin.IsRegion(region) and type(region.SetTexture) == "function"
        if blankable then pcall(region.SetTexture, region, nil) end
    end
end

-- Sublevel -8 keeps the fill under every region Blizzard draws in the same layer.
function skin.Fill(owner, color, inset)
    inset = inset or 0
    local texture = owner:CreateTexture(nil, "BACKGROUND", nil, -8)
    texture:SetTexture(skin.FLAT)
    texture:SetVertexColor(unpack(color or skin.BACKING))
    texture:SetPoint("TOPLEFT", owner, "TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -inset, inset)
    return texture
end

local function line(owner, target, first, second, inset, color, layer)
    local texture = owner:CreateTexture(nil, layer)
    texture:SetTexture(media.border)
    texture:SetVertexColor(unpack(color))
    for _, point in ipairs({ first, second }) do
        local direction = CORNERS[point]
        texture:SetPoint(point, target, point, direction[1] * inset, direction[2] * inset)
    end
    if first:sub(1, 3) == second:sub(1, 3) then texture:SetHeight(EDGE) else texture:SetWidth(EDGE) end
    return texture
end

-- Four one-pixel lines, pulled in by inset so they can frame an inset fill. With a target the lines
-- are still created on owner but frame the target, which is how a texture gets an edge. The lines
-- draw in BORDER, under an ARTWORK icon; a caller that cannot frame outside the icon (a clipping
-- parent) passes OVERLAY as layer and frames at the icon's own bounds.
function skin.Outline(owner, color, inset, target, layer)
    local lines = {}
    inset, color, target, layer = inset or 0, color or skin.LINE, target or owner, layer or "BORDER"
    for index, pair in ipairs(SIDES) do lines[index] = line(owner, target, pair[1], pair[2], inset, color, layer) end
    return lines
end

-- Layered furniture for addon-owned windows. Repeated layout calls reuse every region.
local windows = setmetatable({}, { __mode = "k" })
local HEADER_FILL, FOOTER_FILL = { 0.095, 0.115, 0.15, 1 }, { 0.045, 0.055, 0.075, 1 }
local function windowBand(owner, color, top)
    local band = owner:CreateTexture(nil, "BACKGROUND", nil, -7)
    band:SetTexture(skin.FLAT)
    band:SetVertexColor(unpack(color))
    band:SetPoint(top and "TOPLEFT" or "BOTTOMLEFT", owner, top and "TOPLEFT" or "BOTTOMLEFT", 1, top and -1 or 1)
    band:SetPoint(top and "TOPRIGHT" or "BOTTOMRIGHT", owner, top and "TOPRIGHT" or "BOTTOMRIGHT", -1, top and -1 or 1)
    return band
end

local function windowDepth(owner, chrome)
    chrome.shadow = {}
    for index, alpha in ipairs({ 0.55, 0.3, 0.12 }) do
        chrome.shadow[index] = skin.Outline(owner, { 0, 0, 0, alpha }, -index, nil, "BACKGROUND")
    end
    chrome.inner = skin.Outline(owner, { 0.13, 0.16, 0.2, 0.8 }, 1)
    chrome.accent = line(owner, owner, "TOPLEFT", "TOPRIGHT", 2, { 0.42, 0.58, 0.68, 0.85 }, "BORDER")
    chrome.headerLight = line(owner, chrome.header, "TOPLEFT", "TOPRIGHT", 1,
        { 0.23, 0.29, 0.36, 0.65 }, "BORDER")
end

function skin.WindowChrome(owner, headerHeight, footerHeight)
    local chrome = windows[owner]
    if not chrome then
        chrome = { fill = skin.Fill(owner), edge = skin.Outline(owner) }
        chrome.header = windowBand(owner, HEADER_FILL, true)
        chrome.footer = windowBand(owner, FOOTER_FILL, false)
        windowDepth(owner, chrome)
        chrome.headerRule = line(owner, chrome.header, "BOTTOMLEFT", "BOTTOMRIGHT", 0, skin.LINE, "BORDER")
        chrome.footerRule = line(owner, chrome.footer, "TOPLEFT", "TOPRIGHT", 0, skin.LINE, "BORDER")
        windows[owner] = chrome
    end
    chrome.header:SetHeight(math.max(1, headerHeight or 1))
    chrome.footer:SetHeight(math.max(1, footerHeight or 1))
    chrome.header:SetShown((headerHeight or 0) > 0)
    chrome.headerRule:SetShown((headerHeight or 0) > 0)
    chrome.accent:SetShown((headerHeight or 0) > 0)
    chrome.headerLight:SetShown((headerHeight or 0) > 0)
    chrome.footer:SetShown((footerHeight or 0) > 0)
    chrome.footerRule:SetShown((footerHeight or 0) > 0)
    return chrome
end

-- Decorative controls are cached separately from input and hover/press handlers.
local buttons = setmetatable({}, { __mode = "k" })
function skin.ButtonSurface(owner, primary)
    local surface = buttons[owner]
    if surface then return surface end
    surface = { fill = skin.Fill(owner, primary and { 0.08, 0.24, 0.32, 1 } or skin.CONTROL, 1) }
    surface.edge = skin.Outline(owner, primary and { 0.3, 0.58, 0.7, 1 } or skin.LINE)
    surface.light = line(owner, owner, "TOPLEFT", "TOPRIGHT", 1, { 0.28, 0.34, 0.4, 0.75 }, "BORDER")
    surface.shade = line(owner, owner, "BOTTOMLEFT", "BOTTOMRIGHT", 1, { 0.02, 0.03, 0.045, 1 }, "BORDER")
    buttons[owner] = surface
    return surface
end

-- Contrast plates follow the native string's bounds. Call again after native setup/reuse.
local textPlates = setmetatable({}, { __mode = "k" })
function skin.TextPlate(owner, region, color, padding, layer)
    if not skin.IsRegion(region) or type(region.GetText) ~= "function" then return end
    local plate = textPlates[region]
    if not plate then
        plate = owner:CreateTexture(nil, layer or "BACKGROUND", nil, -1)
        plate:SetTexture(skin.FLAT)
        textPlates[region] = plate
    end
    padding = padding or 3
    plate:ClearAllPoints()
    plate:SetPoint("TOPLEFT", region, "TOPLEFT", -padding, 1)
    plate:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", padding, -1)
    plate:SetVertexColor(unpack(color or { 0.025, 0.035, 0.05, 0.9 }))
    local text = region:GetText()
    local secret = RikUI.Secret and RikUI.Secret.IsSecret(text)
    plate:SetShown(not secret and type(text) == "string" and text ~= "" and region:IsShown())
    return plate
end

local sections = setmetatable({}, { __mode = "k" })
function skin.SectionHeading(owner, region)
    if not skin.IsRegion(region) or type(region.GetObjectType) ~= "function"
        or region:GetObjectType() ~= "FontString" then return end
    local section = sections[region]
    if not section then
        section = { rule = owner:CreateTexture(nil, "ARTWORK", nil, 0) }
        section.rule:SetTexture(skin.FLAT)
        section.rule:SetVertexColor(0.65, 0.52, 0.25, 0.7)
        section.rule:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", -4, -1)
        section.rule:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 4, -1)
        section.rule:SetHeight(1)
        sections[region] = section
    end
    skin.Typeface(region)
    region:SetTextColor(unpack(skin.GOLD))
    region:SetDrawLayer("ARTWORK", 1)
    section.fill = skin.TextPlate(owner, region, { 0.14, 0.125, 0.085, 0.85 }, 4, "ARTWORK")
    section.rule:SetShown(section.fill:IsShown())
    return section
end

function skin.Font(region, role)
    if skin.IsRegion(region) and type(region.SetFont) == "function" then media.Font(region, role) end
end

local function isSecret(value)
    local secret = RikUI.Secret
    return secret ~= nil and secret.IsSecret(value)
end

-- Dark text (parchment ink) becomes skin.INK; any other colour, or one that cannot be read, is
-- left as Blizzard set it.
function skin.Ink(region)
    if not skin.IsRegion(region) or type(region.GetTextColor) ~= "function" then return false end
    local ok, r, g, b, alpha = pcall(region.GetTextColor, region)
    if not ok or isSecret(r) or isSecret(g) or isSecret(b) or isSecret(alpha) then return false end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
    if r ~= r or g ~= g or b ~= b or math.min(r, g, b) < 0 then return false end
    if alpha ~= nil and (type(alpha) ~= "number" or alpha ~= alpha or alpha < 0 or alpha > 1) then return false end
    if math.max(r, g, b) >= DARK_LIMIT then return false end
    region:SetTextColor(skin.INK[1], skin.INK[2], skin.INK[3], alpha)
    return true
end

-- The RikUI typeface at the string's own size; dark parchment text takes the ink colour and any
-- other colour Blizzard gave it stays.
function skin.Typeface(region, fallbackSize)
    if not skin.IsRegion(region) or type(region.SetFont) ~= "function" then return end
    local ok, _, size = pcall(region.GetFont, region)
    size = ok and type(size) == "number" and size > 0 and size or fallbackSize or media.sizes.label
    media.SetFont(region, size, "OUTLINE")
    skin.Ink(region)
end

-- A button reapplies its font objects on every state change, so the typeface goes on shared font
-- objects, not on the font string. false marks a client without CreateFont.
local function buttonFonts()
    if fonts ~= nil then return fonts end
    fonts = false
    if type(CreateFont) ~= "function" then return fonts end
    fonts = {}
    for state, color in pairs(BUTTON_FONT_COLORS) do
        local object = CreateFont(BUTTON_FONT_PREFIX .. state)
        media.SetFont(object, media.Size("label"), "OUTLINE")
        object:SetTextColor(unpack(color))
        fonts[state] = object
    end
    return fonts
end

function skin.ButtonFonts(button)
    local objects = buttonFonts()
    if not objects then return end
    for state, object in pairs(objects) do
        local setter = button["Set" .. state .. "FontObject"]
        if type(setter) == "function" then setter(button, object) end
    end
end


-- Animate addon chrome only; native frame fades, queues and clicks remain authoritative.
local cards = setmetatable({}, { __mode = "k" })
local function cardIcon(owner, card, icon)
    if not skin.IsRegion(icon) or (type(icon.IsShown) == "function" and not icon:IsShown()) then
        if card.iconBlock then card.iconBlock:Hide() end
        for _, edge in ipairs(card.iconEdge or {}) do edge:Hide() end
        return
    end
    if not card.iconBlock then
        card.iconBlock = owner:CreateTexture(nil, "BACKGROUND")
        card.iconBlock:SetTexture(skin.FLAT)
        card.iconBlock:SetVertexColor(0.14, 0.12, 0.08, 1)
    end
    card.iconBlock:ClearAllPoints()
    card.iconBlock:SetPoint("TOPLEFT", icon, "TOPLEFT", -4, 4)
    card.iconBlock:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4)
    card.iconBlock:Show()
    if not card.iconEdge then card.iconEdge = skin.Outline(owner, skin.LINE, 0, card.iconBlock) end
    for _, edge in ipairs(card.iconEdge) do edge:Show() end
end

function skin.NotificationCard(owner, icon, inset)
    local card = cards[owner]
    if not card then
        inset = inset or 0
        card = { fill = skin.Fill(owner, skin.BACKING, inset) }
        card.edge = skin.Outline(owner, nil, inset)
        card.topLight = line(owner, owner, "TOPLEFT", "TOPRIGHT", inset + 2,
            { 0.2, 0.24, 0.3, 0.8 }, "BORDER")
        card.accent = owner:CreateTexture(nil, "BORDER")
        card.accent:SetTexture(skin.FLAT)
        card.accent:SetVertexColor(unpack(skin.GOLD))
        card.accent:SetPoint("TOPLEFT", owner, "TOPLEFT", inset, -inset)
        card.accent:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", inset, inset)
        card.accent:SetWidth(2)
        cards[owner] = card
        RikUI.Hooks.Script(owner, "OnHide", function() RikUI.Motion.Stop(card.enter) end)
    end
    cardIcon(owner, card, icon)
    card.enter = card.enter or RikUI.Motion.Tween(card.accent, 0, 1, 0.24)
    if owner:IsShown() then RikUI.Motion.Play(card.enter) else RikUI.Motion.Stop(card.enter) end
    return card
end

function skin.CropIcon(icon)
    if not skin.IsRegion(icon) or type(icon.SetTexCoord) ~= "function" then return end
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
end
