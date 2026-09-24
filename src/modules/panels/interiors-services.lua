local interiors, skin = RikUI.Interiors, RikUI.Skin
local TEXT = { "Label", "Text", "Name", "SubText", "Cost", "Price", "Level", "PetName", "RecipeName", "name", "subText", "nameSubText", "alternateCost", "rankText", "levelText" }
local ART = { "Background", "Bg", "TopLeft", "TopRight", "BottomLeft", "BottomRight",
    "TopTex", "BottomTex", "MiddleTex", "SlotBackground", "IconBackground", "NormalTexture", "BG", "background", "LeftPiece", "RightPiece", "CenterPiece" }
local function services(frame)
    interiors.Commerce(frame)
    local row = skin.IsRegion(frame.SelectedHighlight) and skin.IsRegion(frame.NormalTexture)
    for _, key in ipairs(TEXT) do
        if skin.IsRegion(frame[key]) and type(frame[key].SetFont) == "function" then row = true end
        skin.Typeface(frame[key])
    end
    if row then interiors.Row(frame); skin.Strip(frame, ART) end
    if interiors.IsFrame(frame.Button1) or interiors.IsFrame(frame.BackgroundNineSlice) then
        interiors.Surface(frame, { "Background", "BackgroundNineSlice" })
    end
    local nested = frame.Icon
    if interiors.IsFrame(nested) and skin.IsRegion(nested.Icon) then interiors.Item(nested) end
end
interiors.Register("services", { "AuctionHouseFrame", "ClassTrainerFrame", "ProfessionsFrame",
    "ProfessionsBookFrame", "InspectRecipeFrame", "GuildBankFrame", "PetStableFrame", "StableFrame" }, services)
interiors.RegisterRefresh("services", { "TRAINER_UPDATE", "TRADE_SKILL_LIST_UPDATE",
    "GUILDBANKBAGSLOTS_CHANGED", "PET_STABLE_UPDATE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" },
    { "ClassTrainerFrame_Update", "GuildBankFrame_Update", "PetStable_Update" })

