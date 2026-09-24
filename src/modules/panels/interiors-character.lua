local interiors, skin = RikUI.Interiors, RikUI.Skin
local ART = { "StoneBg", "ClassBackground", "BackgroundTopLeft", "BackgroundTopRight",
    "BackgroundBotLeft", "BackgroundBotRight", "BackgroundOverlay" }
local function character(frame)
    local kind = frame:GetObjectType()
    local icon = interiors.Icon(frame)
    if skin.IsRegion(icon) and (kind == "ItemButton" or kind == "Button" or kind == "CheckButton") then
        interiors.Item(frame)
    elseif skin.IsRegion(frame.Label) or skin.IsRegion(frame.Name)
        or (skin.IsRegion(frame.Title) and skin.IsRegion(frame.Background)) then
        interiors.Row(frame)
    end
    skin.Strip(frame, ART)
    interiors.Labels(frame)
end
interiors.Register("character", { "CharacterFrame", "PaperDollFrame", "ReputationFrame",
    "SkillFrame", "TokenFrame", "CharacterStatsPane", "CharacterStatsPaneScrollBox" }, character)

