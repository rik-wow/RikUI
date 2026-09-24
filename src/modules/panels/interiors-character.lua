local interiors, skin = RikUI.Interiors, RikUI.Skin
local ART = { "StoneBg", "ClassBackground", "BackgroundTopLeft", "BackgroundTopRight",
    "BackgroundBotLeft", "BackgroundBotRight", "BackgroundOverlay" }
-- Camelot puts much of its leather/stone art in unnamed regions on pane hosts and gear borders.
local ATLAS_ART = {
    ["UI-Character-Info-General-BG"] = true, ["UI-Character-Info-Stat-BG"] = true,
    ["UI-Character-Info-Stat-StoneBG"] = true, ["UI-Character-Info-GearSlot"] = true,
    ["UI-Character-Info-ScrollLine"] = true,
}
local function paneArt(frame)
    if type(frame.GetRegions) ~= "function" then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if skin.IsRegion(region) and region:GetObjectType() == "Texture" and type(region.GetAtlas) == "function" then
            local atlas = region:GetAtlas()
            if not RikUI.Secret.IsSecret(atlas) and type(atlas) == "string" and ATLAS_ART[atlas] then
                region:SetAlpha(0)
            end
        end
    end
end

local function character(frame)
    if interiors.SideTab(frame) then return end
    local kind = frame:GetObjectType()
    local icon = interiors.Icon(frame)
    if skin.IsRegion(icon) and (kind == "ItemButton" or kind == "Button" or kind == "CheckButton") then
        interiors.Item(frame)
    elseif skin.IsRegion(frame.Label) or skin.IsRegion(frame.Name)
        or (skin.IsRegion(frame.Title) and skin.IsRegion(frame.Background)) then
        interiors.Row(frame)
    end
    paneArt(frame)
    skin.Strip(frame, ART)
    interiors.Labels(frame)
end
interiors.Register("character", { "CharacterFrame", "PaperDollFrame", "ReputationFrame",
    "SkillFrame", "TokenFrame", "CharacterStatsPane", "CharacterStatsPaneScrollBox" }, character)

