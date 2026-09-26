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
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
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

-- Resolve after saved profiles are bound, before native and addon font consumers start.
function media.Configure()
    local choice = RikUI.Profile and RikUI.Profile.font
    media.font = root .. "font.ttf"
    if choice == "game" then
        media.font = type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT or FALLBACK_FONT
    end
end

function media.Size(role)
    local scale = RikUI.Profile and RikUI.Profile.textScale or 1
    if type(scale) ~= "number" or scale ~= scale or math.abs(scale) == math.huge then scale = 1 end
    scale = math.max(0.85, math.min(1.3, scale))
    return math.floor((media.sizes[role] or media.sizes.label) * scale + 0.5)
end

-- Apply type without changing a native label's colour, shadow or size.
function media.SetFont(region, size, flags)
    local loaded = region:SetFont(media.font, size, flags)
    if loaded == false then
        local fallback = type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT or FALLBACK_FONT
        local recovered = region:SetFont(fallback, size, flags) ~= false
        loaded = recovered
        -- Share a working path with callers that use Media.font directly.
        if recovered then media.font = fallback end
        if not warned then
            warned = true
            RikUI:Print(recovered and "Media font unavailable; using the game font."
                or "Media font and game-font fallback could not load.")
        end
    end
    return loaded ~= false
end

function media.Font(region, role)
    media.SetFont(region, media.Size(role), "OUTLINE")
    region:SetTextColor(1, 1, 1, 1)
    region:SetShadowColor(0, 0, 0, 1)
    region:SetShadowOffset(1, -1)
end
