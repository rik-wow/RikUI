local core, interiors, skin = RikUI, RikUI.Interiors, RikUI.Skin
local PAPER = { "MaterialTopLeft", "MaterialTopRight", "MaterialBotLeft", "MaterialBotRight",
    "Background", "Bg", "SealMaterialBG", "Parchment", "TopDetail", "Top", "Bottom" }
local MAP_SURFACES = { "SidePanelToggle", "Coordinates", "BountyBoard", "BountyBoardFrame",
    "ActionButton", "WorldMapActionButton", "ThreatFrame" }
local mapHooks = setmetatable({}, { __mode = "k" })

local function readable(region)
    if not skin.IsRegion(region) or region:GetObjectType() ~= "FontString" then return end
    skin.Typeface(region)
    if type(region.GetTextColor) ~= "function" then return end
    local ok, r, g, b = pcall(region.GetTextColor, region)
    if not ok or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return end
    if type(issecretvalue) == "function" and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then return end
    -- Neutral parchment prose only; preserve red requirements and coloured quest states.
    if r < 0.5 and g < 0.5 and b < 0.5 and math.max(r, g, b) - math.min(r, g, b) < 0.15 then
        region:SetTextColor(0.9, 0.92, 0.96)
    end
end

local function quest(frame)
    if skin.IsRegion(interiors.Icon(frame)) then interiors.Item(frame) end
    if skin.IsRegion(frame.Text) or skin.IsRegion(frame.ButtonText) then interiors.Row(frame) end
    for _, key in ipairs(PAPER) do
        if skin.IsRegion(frame[key]) then interiors.Surface(frame, PAPER); break end
    end
    if type(frame.GetRegions) == "function" then
        for _, region in ipairs({ frame:GetRegions() }) do readable(region) end
    end
end

function interiors.MapSurfaces(map)
    if not interiors.IsFrame(map) then return end
    for _, key in ipairs(MAP_SURFACES) do
        local frame = map[key]
        if interiors.IsFrame(frame) then interiors.Walk(frame, "mapSurfaces") end
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

