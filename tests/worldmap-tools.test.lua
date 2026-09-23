return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local names = { "WorldMapFrame", "C_Map", "C_MapExplorationInfo", "EventRegistry" }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local mapID, explored, pin, canvas, ready, refreshes, loading
    local details, sized, nativeLoads
    local files = { "src/ui/skin.lua", "src/modules/worldmap/worldmap.lua", "data/map-terrain.lua",
        "src/modules/worldmap/worldmap-terrain.lua", "src/modules/worldmap/worldmap-navigation.lua",
        "src/modules/worldmap/worldmap-tools.lua" }
    local function prepare()
        local callbacks = {}
        EventRegistry = { RegisterCallback = function(_, event, fn, owner) callbacks[event] = function() fn(owner) end end,
            TriggerEvent = function(_, event) if callbacks[event] then callbacks[event]() end end }
        mapID, explored = 1411, {}
        ready, refreshes, loading = false, 0, {}
        details, sized, nativeLoads = false, false, 0
        C_Map = { GetMapArtID = function() return 1194 end,
            GetBestMapForUnit = function() return 1411 end,
            GetMapInfo = function() return { parentMapID = 1414 } end,
            GetMapArtLayers = function() return { { tileWidth = 256, tileHeight = 256 } } end,
            GetPlayerMapPosition = function() return { GetXY = function() return 0.3, 0.4 end } end }
        C_MapExplorationInfo = { GetExploredMapTextures = function() return explored end }
        WorldMapFrame = CreateFrame("Frame", nil, UIParent)
        local function nativeButton(parent)
            local control = CreateFrame("Button", nil, parent)
            control.stockArt = control:CreateTexture()
            control.drawn = {}
            function control:GetRegions() return self.stockArt end
            local create = control.CreateTexture
            function control:CreateTexture(...)
                local texture = create(self, ...)
                self.drawn[#self.drawn + 1] = texture
                return texture
            end
            function control:IsEnabled() return self.enabled ~= false end
            control:SetScript("OnClick", function(self) self.clicked = true end)
            return control
        end
        WorldMapFrame.BorderFrame = CreateFrame("Frame", nil, WorldMapFrame)
        local sizing = CreateFrame("Frame", nil, WorldMapFrame.BorderFrame)
        WorldMapFrame.BorderFrame.MaximizeMinimizeFrame = sizing
        sizing.MaximizeButton, sizing.MinimizeButton = nativeButton(sizing), nativeButton(sizing)
        WorldMapFrame.WorldMapTrackingOptionsButton = nativeButton(WorldMapFrame)
        WorldMapFrame.QuestLog = CreateFrame("Frame", nil, WorldMapFrame)
        WorldMapFrame.QuestLog.QuestsFrame = CreateFrame("Frame", nil, WorldMapFrame.QuestLog)
        local questScroll = CreateFrame("Frame", nil, WorldMapFrame.QuestLog.QuestsFrame)
        WorldMapFrame.QuestLog.QuestsFrame.ScrollFrame = questScroll
        questScroll.SettingsDropdown = nativeButton(questScroll)
        questScroll.ScrollBar = CreateFrame("Frame", nil, questScroll)
        questScroll.ScrollBar.Back = nativeButton(questScroll.ScrollBar)
        questScroll.ScrollBar.Forward = nativeButton(questScroll.ScrollBar)
        canvas = CreateFrame("Frame", nil, WorldMapFrame)
        function canvas:GetCurrentLayerIndex() return 1 end
        function canvas:GetFrameLevel() return 10 end
        function WorldMapFrame:GetCanvasContainer()
            assert(ready, "canvas accessed during cold OnShow")
            return canvas
        end
        function WorldMapFrame:OnFrameSizeChanged()
            assert(ready, "sizing before layout")
            sized = true
            pin:OnCanvasSizeChanged()
        end
        function WorldMapFrame:ForceRefreshDetailLayers()
            assert(sized, "detail rebuild before geometry")
            details = true
        end
        function WorldMapFrame:RefreshAll()
            assert(ready, "native refresh ran before layout")
            refreshes = refreshes + 1
            pin:RefreshOverlays()
        end
        function WorldMapFrame:GetMapID() return mapID end
        function WorldMapFrame:OnMapChanged() EventRegistry:TriggerEvent("MapCanvas.MapSet") end
        function WorldMapFrame:SetMapID(id) mapID = id; self:OnMapChanged() end
        function WorldMapFrame:AddMaskableTexture() end
        pin = CreateFrame("Frame", nil, canvas)
        function pin:GetMap() return WorldMapFrame end
        pin:SetSize(0, 0)
        pin:SetAlpha(0)
        function pin:OnCanvasSizeChanged()
            if sized then self:SetSize(1002, 668) end
        end
        function pin:RefreshAlpha() self:SetAlpha(1) end
        function pin:RefreshOverlays()
            -- Ordinary refresh does not rebuild clean-but-invalid detail layers.
            if details then self.isWaitingForLoad = false; self:RefreshAlpha() end
        end
        pin.dataProvider = { GetDrawLayer = function() return "ARTWORK", 0 end }
        pin.isWaitingForLoad = true
        pin.textureLoadGroup = { AddTexture = function(_, texture) loading[texture] = true; nativeLoads = nativeLoads + 1 end }
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
        local sizing = WorldMapFrame.BorderFrame.MaximizeMinimizeFrame
        local questScroll = WorldMapFrame.QuestLog.QuestsFrame.ScrollFrame
        for _, control in ipairs({ sizing.MaximizeButton, sizing.MinimizeButton,
            WorldMapFrame.WorldMapTrackingOptionsButton, questScroll.SettingsDropdown,
            questScroll.ScrollBar.Back, questScroll.ScrollBar.Forward }) do
            check("native button artwork replaced by RikUI glyph", control.stockArt.alpha == 0
                and control.drawn[#control.drawn - 1].rikIcon ~= nil)
            env.click(control)
            check("native icon button click preserved", control.clicked == true)
            control.enabled = false
            control.stockArt:SetAlpha(1)
            env.runScript(control, "OnDisable")
            check("native repaint stays hidden and disabled glyph dims", control.stockArt.alpha == 0
                and control.drawn[#control.drawn - 1].alpha == 0.3)
        end
        check("first open refreshes native canvas after layout", refreshes == 1)
        check("normal fog allocates no reveal artwork", #pin.created == 0 and RikUI.Profile.worldmap.fog)
        module.SetOption("fog", false)
        check("reveal draws client terrain assets", #pin.created > 0 and pin.created[1].texture == 271443)
        check("reveal uses exploration artwork layer", pin.created[1].layer == "ARTWORK")
        check("first-open terrain is sized and visible without navigation",
            details and pin.width == 1002 and pin.height == 668 and pin.alpha == 1 and mapID == 1411)
        pin.isWaitingForLoad = true
        module.Terrain.Refresh(WorldMapFrame)
        check("addon assets cannot block native exploration loading", nativeLoads == 0)
        pin.isWaitingForLoad = false
        local count = #pin.created
        module.SetOption("fog", true)
        check("normal fog hides all addon terrain immediately", pin.created[1].shown == false)
        module.SetOption("fog", false)
        check("reveal reuses textures", #pin.created == count and pin.created[1].shown)
        explored = { { textureWidth = 215, textureHeight = 215, offsetX = 355, offsetY = 320 } }
        pin:RefreshOverlays()
        env.fire("MAP_EXPLORATION_UPDATED"); env.flushTimers()
        check("newly explored terrain is excluded", pin.created[1].texture ~= 271443)
        C_Map.GetMapArtID = function() return 1200 end
        module.Terrain.Refresh(WorldMapFrame)
        check("reveal includes flagged Darkshore terrain", pin.created[1].texture == 7938948 and pin.created[1].shown)
        C_Map.GetMapArtID = function() return 999999 end
        WorldMapFrame:OnMapChanged(); env.flushTimers()
        check("unknown map clears old terrain", pin.created[1].shown == false)
        C_Map.GetMapArtID = function() return 1194 end
        check("one quest interface and one coordinate display",
            module.Drawer == nil and module.Toolbar.quests == nil and module.Toolbar.coords == nil)
        check("compact tools share header and leave terrain clear", module.Toolbar.height == 22
            and module.Toolbar.point[1] == "TOPLEFT" and module.Toolbar.width == 214)
        check("fog state is explicit", module.Toolbar.fog.label:GetText() == "Fog: off")
        mapID = 1414
        env.click(module.Toolbar.player)
        check("my location returns to current zone", mapID == 1411)
        env.inCombat = true
        mapID = 1414
        env.click(module.Toolbar.player)
        check("navigation is guarded in combat", mapID == 1414)
        env.inCombat = false
        C_Map.GetBestMapForUnit = function() return env.SECRET end
        check("secret player location is rejected", module.Navigation.Player(WorldMapFrame) == false and mapID == 1414)
        C_Map.GetBestMapForUnit = function() error("unavailable") end
        check("failed player location is rejected", module.Navigation.Player(WorldMapFrame) == false and mapID == 1414)
        module = load({ worldmap = { quests = true, zoneOnly = false } })
        check("old drawer preferences cannot create a second quest list", module.Drawer == nil
            and #module.Options.settings == 1)
        module = load({ worldmap = { fog = false } })
        check("saved reveal preference works on the first zone opening",
            #pin.created > 0 and pin.created[1].shown and pin.alpha == 1 and pin.width == 1002 and mapID == 1411)
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
