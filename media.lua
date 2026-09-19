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
