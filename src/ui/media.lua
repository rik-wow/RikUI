-- Shared, bundled assets. See media/LICENSES.md for provenance.
local addonName = ...
local root = "Interface\\AddOns\\" .. addonName .. "\\media\\"
local media = {
    font = root .. "font.ttf", statusbar = root .. "statusbar.tga",
    border = root .. "border.tga", checked = root .. "checked.tga",
    highlight = root .. "highlight.tga",
    sizes = { hotkey = 12, count = 12, cooldown = 16, charge = 11, label = 13, heading = 16, small = 11 },
}
RikUI.Media = media
local warned = false
local ICONS = root .. "icons\\"

-- RikUI's icons are white 32x32 textures with the shape in the alpha channel, built from the SVG
-- sources in media/icons by media/build_icons.py (the client cannot load SVG). Tint them with three
-- colour components: the fourth component of SetVertexColor is the region's alpha.
-- Every icon the addon ships; a name outside this set is a typo that would draw nothing in game.
local NAMES = { "achievement", "character", "chevron-down", "chevron-left", "chevron-right", "chevron-up", "close",
    "collections", "copy", "diamond", "groupfinder", "guild", "help", "housing", "journal", "legacy", "lock",
    "lock-open", "menu", "minus", "plus", "profession", "quest", "settings", "skull", "spellbook", "spells", "star",
    "store", "talents" }
media.Icons = {}
for _, name in ipairs(NAMES) do media.Icons[name] = true end

function media.IconPath(name)
    assert(media.Icons[name], "Unknown RikUI icon: " .. tostring(name))
    return ICONS .. name .. ".tga"
end

function media.SetIcon(icon, name)
    icon.rikIcon = name
    icon:SetTexture(media.IconPath(name))
end

function media.Icon(parent, name, size, layer)
    local icon = parent:CreateTexture(nil, layer or "ARTWORK")
    media.SetIcon(icon, name)
    icon:SetSize(size, size)
    return icon
end

function media.Font(region, role)
    local loaded = region:SetFont(media.font, media.sizes[role], "OUTLINE")
    if loaded == false and not warned then
        warned = true
        RikUI:Print("Media font could not load. Fully exit and restart WoW after installing new media.")
    end
    region:SetTextColor(1, 1, 1, 1)
    region:SetShadowColor(0, 0, 0, 1)
    region:SetShadowOffset(1, -1)
end
