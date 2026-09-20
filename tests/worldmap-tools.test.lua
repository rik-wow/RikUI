return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local names = { "WorldMapFrame", "C_Map", "C_MapExplorationInfo", "C_QuestLog", "C_CVar",
        "C_SuperTrack", "QuestMapFrame_OpenToQuestDetails" }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local mapID, explored, quests, markers, opened, watched, tracked, pin, canvas, ready, refreshes, loading
    local files = { "src/ui/skin.lua", "src/modules/worldmap/worldmap.lua", "data/map-terrain.lua",
        "src/modules/worldmap/worldmap-terrain.lua", "src/modules/worldmap/worldmap-navigation.lua",
        "src/modules/worldmap/worldmap-tools.lua" }
    local function prepare()
        mapID, explored, markers = 1411, {}, true
        ready, refreshes, loading = false, 0, {}
        quests = { { questID = 2, title = "Second", isHeader = false }, { questID = 1, title = "First", isHeader = false } }
        C_Map = { GetMapArtID = function() return 1194 end,
            GetBestMapForUnit = function() return 1411 end,
            GetMapInfo = function() return { parentMapID = 1414 } end,
            GetMapArtLayers = function() return { { tileWidth = 256, tileHeight = 256 } } end,
            GetPlayerMapPosition = function() return { GetXY = function() return 0.3, 0.4 end } end }
        C_MapExplorationInfo = { GetExploredMapTextures = function() return explored end }
        C_QuestLog = { GetNumQuestLogEntries = function() return #quests end,
            GetInfo = function(i) return quests[i] end, IsComplete = function(id) return id == 1 end,
            GetQuestWatchType = function() return nil end,
            GetQuestsOnMap = function() return { { questID = 1, x = 0.2, y = 0.5 } } end,
            AddQuestWatch = function(id) watched = id end, RemoveQuestWatch = function() watched = nil end }
        C_CVar = { GetCVarBool = function() return markers end, SetCVar = function(_, value) markers = value == "1" end }
        C_SuperTrack = { SetSuperTrackedQuestID = function(id) tracked = id end }
        QuestMapFrame_OpenToQuestDetails = function(id) opened = id end
        WorldMapFrame = CreateFrame("Frame", nil, UIParent)
        canvas = CreateFrame("Frame", nil, WorldMapFrame)
        function canvas:GetCurrentLayerIndex() return 1 end
        function canvas:GetFrameLevel() return 10 end
        function WorldMapFrame:GetCanvasContainer()
            assert(ready, "canvas accessed during cold OnShow")
            return canvas
        end
        function WorldMapFrame:RefreshAll()
            assert(ready, "native refresh ran before layout")
            refreshes = refreshes + 1
            pin:RefreshOverlays()
        end
        function WorldMapFrame:GetMapID() return mapID end
        function WorldMapFrame:OnMapChanged() end
        function WorldMapFrame:SetMapID(id) mapID = id; self:OnMapChanged() end
        function WorldMapFrame:AddMaskableTexture() end
        pin = CreateFrame("Frame", nil, canvas)
        function pin:GetMap() return WorldMapFrame end
        function pin:RefreshOverlays() end
        pin.dataProvider = { GetDrawLayer = function() return "ARTWORK", 0 end }
        pin.isWaitingForLoad = true
        pin.textureLoadGroup = { AddTexture = function(_, texture) loading[texture] = true end }
        function WorldMapFrame:EnumeratePinsByTemplate()
            local once = false
            return function() if not once then once = true; return pin end end
        end
        local create = pin.CreateTexture
        pin.created = {}
        function pin:CreateTexture(...)
            local t = create(self, ...); self.created[#self.created + 1] = t; return t
        end
        WorldMapFrame:Hide()
    end
    local function load(profile, combat)
        widgets.loadAddon(env, files, profile, combat, prepare)
        WorldMapFrame:Show()
        check("cold open defers toolbar until layout", RikUI.WorldMap.Toolbar == nil)
        ready = true
        env.flushTimers()
        return RikUI.WorldMap
    end
    local ok, reason = pcall(function()
        local module = load()
        check("map toolbar builds without native navigation bar", module.Toolbar ~= nil and #env.printed == 0, table.concat(env.printed, " | "))
        check("first open refreshes native canvas after layout", refreshes == 1)
        check("normal fog allocates no reveal artwork", #pin.created == 0 and RikUI.Profile.worldmap.fog)
        module.SetOption("fog", false)
        check("reveal draws client terrain assets", #pin.created > 0 and pin.created[1].texture == 271443)
        check("reveal uses exploration artwork layer", pin.created[1].layer == "ARTWORK")
        check("reveal participates in native texture loading", loading[pin.created[1]] == true)
        local count = #pin.created
        module.SetOption("fog", true)
        check("normal fog hides all addon terrain immediately", pin.created[1].shown == false)
        module.SetOption("fog", false)
        check("reveal reuses textures", #pin.created == count and pin.created[1].shown)
        explored = { { textureWidth = 215, textureHeight = 215, offsetX = 355, offsetY = 320 } }
        pin:RefreshOverlays()
        check("newly explored terrain is excluded", pin.created[1].texture ~= 271443)
        C_Map.GetMapArtID = function() return 1200 end
        module.Terrain.Refresh(WorldMapFrame)
        check("reveal includes flagged Darkshore terrain", pin.created[1].texture == 7938948 and pin.created[1].shown)
        C_Map.GetMapArtID = function() return 999999 end
        WorldMapFrame:OnMapChanged(); env.flushTimers()
        check("unknown map clears old terrain", pin.created[1].shown == false)
        C_Map.GetMapArtID = function() return 1194 end
        module.SetOption("quests", true)
        check("zone quest list shows real location", module.Drawer.rows[1].quest.id == 1
            and module.Drawer.rows[1].detail:GetText():find("20.0, 50.0", 1, true))
        module.SetOption("zoneOnly", false)
        check("all quests retains missing locations honestly", module.Drawer.rows[2].quest.location == "Location unavailable on this map")
        module.Navigation.Select(module.Drawer.rows[1].quest)
        check("quest selection routes through native details and supertracking", opened == 1 and tracked == 1)
        module.Navigation.Watch(module.Drawer.rows[1].quest)
        check("quest can be watched", watched == 1)
        module.Navigation.ToggleMarkers()
        check("marker control updates native questPOI", markers == false)
        module.Navigation.Parent(WorldMapFrame)
        check("up navigates to parent", mapID == 1414)
        module.Navigation.Player(WorldMapFrame)
        check("player navigates home", mapID == 1411)
        check("player coordinates are readable", module.Navigation.Coordinates(WorldMapFrame) == "Player: 30.0, 40.0")
        env.inCombat = true
        module.Navigation.Parent(WorldMapFrame)
        check("navigation is guarded in combat", mapID == 1411)
        env.inCombat = false
        C_Map.GetPlayerMapPosition = function() return env.SECRET end
        check("secret coordinate data is not formatted", module.Navigation.Coordinates(WorldMapFrame) == "Player: --")
        quests[1].title = env.SECRET
        local rows = module.Navigation.Quests(mapID, false)
        check("secret quest data is excluded", #rows == 1)
        C_QuestLog.GetInfo = function() error("unavailable") end
        rows = module.Navigation.Quests(mapID, false)
        check("failed quest reads leave no stale rows", #rows == 0)
        module = load(nil, true)
        check("combat first-open defers toolbar creation", module.Toolbar == nil)
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        check("toolbar builds after combat", module.Toolbar ~= nil)
        module = load({ modules = { worldmap = false } })
        check("disabled map creates no tools", module.Toolbar == nil)
        local maps, total = 0, 0
        for _, overlays in pairs(RikUI.Data.MapTerrain) do
            maps, total = maps + 1, total + #overlays
            local count = 0
            for _, overlay in ipairs(overlays) do
                check("terrain geometry is positive", overlay[1] > 0 and overlay[2] > 0 and overlay[3] >= 0 and overlay[4] >= 0)
                count = count + #overlay[5]
                for _, tile in ipairs(overlay[5]) do check("terrain tile fits geometry",
                    tile[1] * 256 < overlay[2] and tile[2] * 256 < overlay[1] and tile[3] > 0) end
            end
            check("terrain tile allocation is bounded", count <= 256)
        end
        check("complete base terrain dataset retained", maps == 84 and total == 1073)
    end)
    restore()
    for _, name in ipairs(names) do _G[name] = saved[name] end
    env.inCombat = false
    check("map tools suite completes", ok, reason)
end
