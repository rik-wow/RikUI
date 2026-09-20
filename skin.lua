-- Shared pieces of the flat skin: fade or blank Blizzard art, add a flat fill, a one-pixel edge, the
-- RikUI font and a cropped icon. Every helper skips a value that is not a region, so a frame that
-- lacks a piece keeps that piece stock. Art is faded, never hidden: Blizzard's own Show calls then
-- change nothing. Loads after unitframes.lua, whose edge lines it reuses.
local media, unitframes = RikUI.Media, RikUI.UnitFrames
local skin = {}
RikUI.Skin = skin

skin.FLAT = "Interface\\BUTTONS\\WHITE8X8"
skin.BACKING, skin.CONTROL = { 0.06, 0.07, 0.09, 0.95 }, { 0.1, 0.11, 0.14, 1 }
skin.LINE, skin.GOLD = { 0.25, 0.28, 0.32, 1 }, { 1, 0.82, 0 }
skin.FADE_SECONDS = 0.15
local EDGE, ICON_CROP = 1, 0.08

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

function skin.Outline(owner, color)
    local lines = unitframes.Edges(owner, EDGE, "BORDER")
    for _, line in ipairs(lines) do line:SetVertexColor(unpack(color or skin.LINE)) end
    return lines
end

function skin.Font(region, role)
    if skin.IsRegion(region) and type(region.SetFont) == "function" then media.Font(region, role) end
end

function skin.CropIcon(icon)
    if not skin.IsRegion(icon) or type(icon.SetTexCoord) ~= "function" then return end
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
end
