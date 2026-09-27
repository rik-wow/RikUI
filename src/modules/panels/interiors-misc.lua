local core, interiors, skin = RikUI, RikUI.Interiors, RikUI.Skin
local ART = { "BorderOverlay", "BackgroundTile", "Background", "Bg", "BackgroundTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "BottomLine", "TitleDivider", "CurrencyBackground",
    "PortraitFrame", "TopBorder", "BottomBorder", "LeftBorder", "RightBorder" }
local TEXT = { "Title", "Text", "Header", "Label", "Description", "Name", "name",
    "GridSelectionHeader", "GridSelectionDescription", "GridNoSelectionHeader", "GridNoSelectionDescription",
    "UnspentPointsCount" }
local HEADINGS = { "Title", "Header", "HeaderText", "GridSelectionHeader", "GridNoSelectionHeader" }
local closed = setmetatable({}, { __mode = "k" })
local ROOTS = { "PlayerChoiceFrame", "SplashFrame", "GenericTraitFrame", "CollectionsJournal",
    "MountJournal", "PetJournal", "ToyBox", "HeirloomsJournal", "WardrobeCollectionFrame",
    "TransmogFrame", "WardrobeFrame", "StopwatchFrame" }

local function close(button)
    if not interiors.IsFrame(button) or closed[button] or not core.Panels then return end
    -- The regular panel pass may already own this close button.
    if not button.rikIcon then core.Panels.Skin.Close(button) end
    closed[button] = true
end

local function misc(frame)
    local surface = false
    for _, key in ipairs(ART) do if skin.IsRegion(frame[key]) then surface = true end end
    if surface then interiors.Surface(frame, ART) end
    for _, key in ipairs(TEXT) do skin.Typeface(frame[key]) end
    for _, key in ipairs(HEADINGS) do
        local heading = frame[key]
        if skin.IsRegion(heading) and heading:GetObjectType() == "FontString" then
            skin.SectionHeading(frame, heading)
        elseif interiors.IsFrame(heading) then
            skin.SectionHeading(heading, heading.Text)
        end
    end
    if skin.IsRegion(frame.PageText) then
        skin.Typeface(frame.PageText)
        skin.TextPlate(frame, frame.PageText, nil, 4, "ARTWORK")
    end
    if skin.IsRegion(interiors.Icon(frame)) then interiors.Item(frame) end
    if skin.IsRegion(frame.StateBorder) and skin.IsRegion(frame.Icon) then interiors.Spells(frame) end
    if frame == _G.PlayerChoiceFrame then
        skin.Strip(frame.Title or {}, { "Left", "Middle", "Right" })
        skin.Strip(frame.Header or {}, { "Texture" })
    end
    close(frame.TopCloseButton)
    if frame == _G.StopwatchFrame then close(_G.StopwatchCloseButton or frame.CloseButton) end
end
interiors.Register("misc", ROOTS, misc)
interiors.RegisterRefresh("misc", { "PLAYER_CHOICE_UPDATE", "NEW_MOUNT_ADDED", "PET_JOURNAL_LIST_UPDATE",
    "TRANSMOG_COLLECTION_UPDATED" }, {})

