local core, interiors, skin = RikUI, RikUI.Interiors, RikUI.Skin
local PAPER = { "MaterialTopLeft", "MaterialTopRight", "MaterialBotLeft", "MaterialBotRight",
    "Background", "Bg", "SealMaterialBG", "Parchment" }
local MAP_SURFACES = { "SidePanelToggle", "Coordinates", "BountyBoard", "BountyBoardFrame",
    "ActionButton", "WorldMapActionButton", "ThreatFrame" }
local mapHooks = setmetatable({}, { __mode = "k" })

local PROSE = { QuestInfoDescriptionText = true, QuestInfoObjectivesText = true, QuestInfoRewardText = true }
local proseSizes = setmetatable({}, { __mode = "k" })
local HEADINGS = { QuestInfoTitleHeader = true, QuestInfoDescriptionHeader = true,
    QuestInfoObjectivesHeader = true, QuestInfoRewardsHeader = true }

local function proseFont(region)
    local name = type(region.GetName) == "function" and region:GetName()
    if not PROSE[name] then return end
    local saved = core.Profile and core.Profile.panels
    local size = saved and saved.questTextSize or 0
    if type(size) ~= "number" or size < 12 or size > 24 or size % 1 ~= 0 then size = 0 end
    if not proseSizes[region] then
        local ok, _, nativeSize = pcall(region.GetFont, region)
        if not ok or core.Secret.IsSecret(nativeSize) or type(nativeSize) ~= "number" or nativeSize <= 0 then return end
        proseSizes[region] = nativeSize
    end
    region:SetFont(core.Media.font, size == 0 and proseSizes[region] or size, "OUTLINE")
end

-- Typeface lifts dark parchment prose to ink and preserves red requirements and coloured quest
-- states; the named prose strings then take the profile's size.
local function readable(region)
    if not skin.IsRegion(region) or region:GetObjectType() ~= "FontString" then return end
    skin.Typeface(region)
    proseFont(region)
end

local function quest(frame)
    if interiors.SideTab(frame) then return end
    if skin.IsRegion(interiors.Icon(frame)) then interiors.Item(frame) end
    if skin.IsRegion(frame.Text) or skin.IsRegion(frame.ButtonText) then interiors.Row(frame) end
    -- QuestLogBorderFrame sits at level 100 above the scroll contents. Its filigree
    -- is decoration, never a reason to add a full-frame opaque backing.
    if skin.IsRegion(frame.TopDetail) then skin.Strip(frame, { "TopDetail", "Border", "Shadow" }) end
    for _, key in ipairs(PAPER) do
        local texture = frame[key]
        if skin.IsRegion(texture) and texture:GetObjectType() == "Texture" then
            -- Keep the original bounds/layer; a new fill on an overlay obscures the list.
            texture:SetTexture(skin.FLAT)
            texture:SetVertexColor(unpack(skin.BACKING))
        end
    end
    if type(frame.GetRegions) == "function" then
        for _, region in ipairs({ frame:GetRegions() }) do
            readable(region)
            local name = type(region.GetName) == "function" and region:GetName()
            if HEADINGS[name] then skin.SectionHeading(frame, region) end
        end
    end
    if frame == _G.QuestInfoRewardsFrame then
        skin.SectionHeading(frame, frame.Header)
    end
end

function interiors.MapSurfaces(map)
    if not interiors.IsFrame(map) then return end
    if core.Panels and core.Panels.FrameEnabled and not core.Panels.FrameEnabled(map) then return end
    for _, key in ipairs(MAP_SURFACES) do
        local frame = map[key]
        if interiors.IsFrame(frame) then
            if key == "ThreatFrame" then
                skin.Strip(frame, { "Background" })
                if interiors.IsFrame(frame.Eye) then interiors.Walk(frame.Eye, "mapSurfaces") end
            else interiors.Walk(frame, "mapSurfaces") end
        end
    end
    -- These overlays are anonymous in the native registry, not named fields on the map.
    for _, frame in ipairs(type(map.overlayFrames) == "table" and map.overlayFrames or {}) do
        if interiors.IsFrame(frame) then
            if interiors.IsFrame(frame.CursorCoords) or interiors.IsFrame(frame.SpellButton)
                or interiors.IsFrame(frame.BountyDropdown) then
                interiors.Walk(frame, "mapSurfaces")
            elseif interiors.IsFrame(frame.Eye) then
                -- The threat holder is 300px wide; only back its eye, never that canvas-sized holder.
                skin.Strip(frame, { "Background" })
                interiors.Walk(frame.Eye, "mapSurfaces")
            end
        end
    end
    local toggle = map.SidePanelToggle
    if interiors.IsFrame(toggle) then
        for key, glyph in pairs({ OpenButton = "chevron-left", CloseButton = "chevron-right" }) do
            local button = toggle[key]
            if interiors.IsFrame(button) then
                interiors.Row(button)
                local state = interiors.State(button)
                if not state.glyph then
                    for _, region in ipairs({ button:GetRegions() }) do
                        if region ~= state.fill and region ~= state.hover and region:GetObjectType() == "Texture" then
                            region:SetAlpha(0)
                        end
                    end
                    state.glyph = core.Media.Icon(button, glyph, 12, "OVERLAY")
                    state.glyph:SetPoint("CENTER", button, "CENTER")
                end
            end
        end
    end
    if not mapHooks[map] then
        mapHooks[map] = true
        core.Hooks.Script(map, "OnShow", interiors.MapSurfaces)
    end
end

local function overlay(frame)
    interiors.Row(frame)
    skin.Strip(frame, { "Background", "Border", "TrackerBackground", "DesaturatedTrackerBackground", "ActionFrameTexture" })
    if skin.IsRegion(interiors.Icon(frame)) then interiors.Item(frame) end
end

interiors.Register("quests", { "QuestFrame", "GossipFrame", "QuestMapFrame", "QuestLogPopupDetailFrame" }, quest)
interiors.Register("mapSurfaces", {}, overlay)
interiors.RegisterRefresh("quests", { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW",
    "QUEST_LOG_UPDATE", "ADDON_LOADED" }, { "QuestInfo_Display", "QuestInfo_ShowRewards", "QuestLogQuests_Update" },
    function() interiors.MapSurfaces(WorldMapFrame) end)

