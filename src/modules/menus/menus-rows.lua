-- Compositor-owned regions permit SetFontObject and texture writes, not SetFont or new regions.
local core, menus, media, skin = RikUI, RikUI.Menus, RikUI.Media, RikUI.Skin
local fonts, ownFonts, serial = {}, {}, 0
local GLYPHS = {
    ["common-dropdown-ticksquare"] = "box",
    ["common-dropdown-icon-checkmark-yellow"] = "check",
    ["common-dropdown-tickradial"] = "radio",
    ["common-dropdown-icon-radialtick-yellow"] = "selected",
}

local function typeface(region)
    if type(CreateFont) ~= "function" then return end
    local source = region:GetFontObject()
    if not source or ownFonts[source] then return end
    local font = fonts[source]
    if not font then
        serial = serial + 1
        font = CreateFont("RikUIMenuFont" .. serial)
        font:CopyFontObject(source)
        local _, size, flags = region:GetFont()
        font:SetFont(media.font, type(size) == "number" and size or media.sizes.label, flags or "")
        fonts[source], ownFonts[font] = font, true
    end
    -- Explicit text colours (disabled, class and title) continue to belong to Blizzard.
    region:SetFontObject(font)
end

local function glyph(region)
    local kind = type(region.GetAtlas) == "function" and GLYPHS[region:GetAtlas()]
    if not kind then return end
    local path = kind == "check" and media.checked or kind == "box" and media.border
        or media.IconPath("diamond")
    region:SetTexture(path)
    region:SetTexCoord(0, 1, 0, 1)
    if kind == "box" or kind == "radio" then region:SetVertexColor(0.3, 0.33, 0.38)
    else region:SetVertexColor(1, 0.82, 0) end
    -- Native anchors, dimensions, alpha and selection visibility remain authoritative.
end

local function walk(frame, seen, depth)
    if not frame or seen[frame] or depth > 8 then return end
    seen[frame] = true
    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "FontString" then typeface(region)
        elseif region:GetObjectType() == "Texture" then glyph(region) end
    end
    if skin.IsRegion(frame.arrow) then
        frame.arrow:SetTexture(media.IconPath("chevron-right"))
        frame.arrow:SetTexCoord(0, 1, 0, 1)
    end
    if skin.IsRegion(frame.highlight) then
        frame.highlight:SetTexture(skin.FLAT)
        frame.highlight:SetVertexColor(0.18, 0.14, 0.04)
    end
    for _, child in ipairs({ frame:GetChildren() }) do walk(child, seen, depth + 1) end
end

function menus.StyleRows(menu)
    local ok, reason = pcall(walk, menu, {}, 0)
    if not ok and not menus.rowWarning then
        menus.rowWarning = true
        core:Print("Menus rows client limit: " .. tostring(reason))
    end
end

