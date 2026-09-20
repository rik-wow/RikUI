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
skin.FADE_SECONDS = 0.15
local EDGE, ICON_CROP = 1, 0.08
local BUTTON_FONT_PREFIX = "RikUIControlFont"
local BUTTON_FONT_COLORS = { Normal = { 1, 0.82, 0 }, Highlight = { 1, 1, 1 }, Disabled = { 0.5, 0.5, 0.5 } }
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

function skin.Font(region, role)
    if skin.IsRegion(region) and type(region.SetFont) == "function" then media.Font(region, role) end
end

-- The RikUI typeface at the string's own size, leaving the colour Blizzard gave it.
function skin.Typeface(region, fallbackSize)
    if not skin.IsRegion(region) or type(region.SetFont) ~= "function" then return end
    local ok, _, size = pcall(region.GetFont, region)
    size = ok and type(size) == "number" and size > 0 and size or fallbackSize or media.sizes.label
    region:SetFont(media.font, size, "OUTLINE")
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
        object:SetFont(media.font, media.sizes.label, "OUTLINE")
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

function skin.CropIcon(icon)
    if not skin.IsRegion(icon) or type(icon.SetTexCoord) ~= "function" then return end
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
end
