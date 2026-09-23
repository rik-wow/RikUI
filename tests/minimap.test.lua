local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Parent and anchor writes on Blizzard frames run through the combat queue; native mask rendering,
-- menu anchoring and the day/night indicator need a beta check.
return function(check)
    local env = require("wow_stub")
    local stub = require("minimap_stub")
    local originalCreate = CreateFrame
    local API = { "GetMinimapZoneText", "C_PvP", "C_Map", "GetCursorPosition", "MinimapCluster", "Minimap",
        "MinimapBackdrop", "MinimapCompassTexture", "MinimapZoneText", "QueueStatusButton" }
    local saved, savedGetCVar = {}, C_CVar.GetCVar
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local function protected()
        assert(not InCombatLockdown(), "frame reparented in combat")
    end
    local function region(value)
        local methods = getmetatable(value).__index
        setmetatable(value, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function value:SetTexture(texture) self.texture = texture end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetTextColor(...) self.color = { ... } end
        function value:SetPoint(...) self.point = { ... } end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        return value
    end
    CreateFrame = function(kind, name, parent, template)
        local frame = originalCreate(kind, name, parent, template)
        local methods = getmetatable(frame).__index
        setmetatable(frame, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function frame:SetParent(value) protected(); self.parent = value end
        function frame:GetParent() return self.parent end
        function frame:SetSize(w, h) self.width, self.height = w, h end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:ClearAllPoints() self.point = nil end
        function frame:SetAlpha(alpha) self.alpha = alpha end
        function frame:EnableMouse(enabled) self.mouse = enabled end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        return frame
    end
    local function printedContains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.00001 end
    local function color(actual, expected)
        return type(actual) == "table" and near(actual[1], expected[1]) and near(actual[2], expected[2])
            and near(actual[3], expected[3])
    end
    local function parked(frame) return frame and frame.parent == RikUIHiddenFrames and RikUI.Hide.IsHidden(frame) end
    local function tick(holder, seconds) env.runScript(holder, "OnUpdate", seconds or 1) end
    -- The unit frame module stays off: only its edge helper is under test here.
    local function load(profile, combat, prepare)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        stub.install(env)
        if prepare then prepare() end
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes = false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua",
            "src/platform/editmode.lua", "src/modules/unitframes/unitframes.lua", "src/modules/unitframes/unitframes-status.lua", "src/modules/minimap/minimap.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Minimap
    end
    local ok, reason = pcall(function()
        local module = load()
        local media, holder, cluster, map = RikUI.Media, module.Holder, MinimapCluster, Minimap
        local group = RikUI.Layout.Groups.minimap
        check("the holder registers with the layout under key minimap with top-right defaults", holder and group
            and group.frames[1] == holder and group.defaults.point == "TOPRIGHT"
            and group.defaults.relativePoint == "TOPRIGHT" and group.defaults.x < 0 and group.defaults.y < 0)
        check("the holder is a bordered square two pixels wider than the map", holder.width == 200 and holder.height == 200
            and type(rawget(holder, "rikBorder")) == "table" and #holder.rikBorder == 4
            and holder.rikBorder[1].texture == media.border)
        check("the Minimap moves into the holder as a 198 square with the flat mask", map.parent == holder
            and map.width == 198 and map.height == 198 and map.mask == "Interface\\BUTTONS\\WHITE8X8"
            and map.point[1] == "TOPLEFT" and map.point[2] == holder)
        -- Skin.lua's rotateMinimap callback puts the round mask back when the CVar changes.
        map:SetMaskTexture(stub.ROUND_MASK)
        env.fire("CVAR_UPDATE", "rotateMinimap")
        check("a Skin.lua mask reset waits for Blizzard's callback", map.mask == stub.ROUND_MASK)
        env.flushTimers()
        check("and is answered with the square mask a frame later", map.mask == "Interface\\BUTTONS\\WHITE8X8")
        check("cluster art, native coords and both zoom buttons are parked", parked(cluster.BorderTop)
            and parked(cluster.ZoneTextButton) and parked(cluster.InstanceDifficulty) and parked(cluster.DielFrame)
            and parked(cluster.MinimapContainer.PlayerCoords) and parked(map.ZoomIn) and parked(map.ZoomOut)
            and parked(MinimapBackdrop) and #module.Parked == 8)
        check("the cluster itself and the mail indicator are not hidden", cluster.parent == UIParent
            and not RikUI.Hide.IsHidden(cluster) and not RikUI.Hide.IsHidden(cluster.IndicatorFrame))
        check("the mail indicator and queue button move into the holder", cluster.IndicatorFrame.parent == holder
            and cluster.IndicatorFrame.point[1] == "TOPRIGHT" and QueueStatusButton.parent == holder
            and QueueStatusButton.point[1] == "BOTTOMLEFT")
        check("the tracking frame sits in the holder unseen with its button ignoring the mouse",
            cluster.Tracking.parent == holder and cluster.Tracking.alpha == 0 and cluster.Tracking.Button.mouse == false)

        -- The cluster is an Edit Mode system: its header setting re-anchors the indicator and the map
        -- container's children to the cluster whenever a layout applies.
        module = load(nil, false, function()
            function MinimapCluster:UpdateSystem()
                self.IndicatorFrame:ClearAllPoints()
                self.IndicatorFrame:SetPoint("BOTTOMRIGHT", self.Tracking, "TOPRIGHT")
                self.Tracking:ClearAllPoints()
                self.Tracking:SetPoint("TOPLEFT", self, "TOPLEFT", 9, -17)
            end
        end)
        holder, cluster, map = module.Holder, MinimapCluster, Minimap
        local function applyLayout()
            cluster:UpdateSystem()
            env.fire("EDIT_MODE_LAYOUTS_UPDATED")
            env.flushTimers()
        end
        applyLayout()
        check("Edit Mode applying its layout leaves the indicator and the tracking frame on the holder",
            cluster.IndicatorFrame.point[1] == "TOPRIGHT" and cluster.IndicatorFrame.point[2] == holder
            and cluster.Tracking.point[2] == holder and map.point[2] == holder and #module.Adopted == 3)
        env.inCombat = true
        applyLayout()
        check("in combat the answer waits", cluster.IndicatorFrame.point[1] == "BOTTOMRIGHT")
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("and lands when combat ends", cluster.IndicatorFrame.point[2] == holder)
        module = load()
        holder, cluster, map = module.Holder, MinimapCluster, Minimap

        check("the zone label shows the zone name in the friendly colour at login", holder.zone.text == "Northshire Valley"
            and color(holder.zone.color, { 0.1, 1, 0.1 }) and holder.zone.fontPath == media.font)
        stub.zone, stub.pvpType = "Stranglethorn Vale", "contested"
        env.fire("ZONE_CHANGED_NEW_AREA")
        check("zone events refresh the name and PvP colour", holder.zone.text == "Stranglethorn Vale"
            and color(holder.zone.color, { 1, 0.7, 0 }))
        stub.pvpType = nil
        env.fire("ZONE_CHANGED")
        check("an unknown PvP type keeps the gold zone colour", color(holder.zone.color, { 1, 0.82, 0 }))
        stub.zone = env.SECRET
        env.fire("ZONE_CHANGED_INDOORS")
        check("a secret zone name clears the label without printing", holder.zone.text == "" and #env.printed == 0)

        stub.position = { 0.4234, 0.5 }
        tick(holder)
        check("a tick writes the local 24-hour time and one-decimal coordinates", holder.clock.text:match("^%d%d:%d%d$")
            and holder.coords.text == "42.3, 50.0")
        stub.position = nil
        tick(holder)
        check("no map position clears the coordinates", holder.coords.text == "")
        stub.position = { 0.25, 0.75 }
        tick(holder, 0.05)
        check("ticks are throttled", holder.coords.text == "")
        tick(holder)
        check("the next full tick reads again", holder.coords.text == "25.0, 75.0")
        stub.position = { env.SECRET, 0.5 }
        tick(holder)
        check("a secret coordinate clears the text without printing", holder.coords.text == "" and #env.printed == 0)
        stub.positionError = "position unavailable"
        tick(holder)
        tick(holder)
        check("a failing position read is reported once and contained", printedContains("Minimap coords")
            and #env.printed == 1 and holder.coords.text == "")
        stub.positionError = nil
        C_CVar.GetCVar = function() return "0" end
        tick(holder)
        check("the clock follows the 12-hour setting", holder.clock.text:match("^%d+:%d%d [AP]M$") ~= nil)
        C_CVar.GetCVar = savedGetCVar

        check("the mouse wheel is enabled on the map", map.wheel == true)
        env.runScript(map, "OnMouseWheel", 1)
        check("wheel up zooms in", map.zoom == 1)
        env.runScript(map, "OnMouseWheel", -1)
        env.runScript(map, "OnMouseWheel", -1)
        check("wheel down zooms out and stops at zero", map.zoom == 0)
        map.zoom = stub.ZOOM_LEVELS - 1
        env.runScript(map, "OnMouseWheel", 1)
        check("wheel up stops at the last zoom level", map.zoom == stub.ZOOM_LEVELS - 1)
        env.runScript(map, "OnMouseUp", "RightButton")
        check("right click opens the tracking menu instead of pinging", cluster.Tracking.Button.opened == 1
            and rawget(map, "pings") == nil)
        env.runScript(map, "OnMouseUp", "LeftButton")
        check("left click still reaches the native ping handler", map.pings == 1 and cluster.Tracking.Button.opened == 1)

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports the holder state and samples", printedContains("Minimap holder=true parked=8 adopted=3")
            and printedContains("minimap.GetBestMapForUnit(player)") and printedContains("minimap.GetZonePVPInfo()"))

        module = load(nil, true)
        holder, cluster, map = module.Holder, MinimapCluster, Minimap
        check("a combat login queues every write", holder == nil and map.parent == cluster.MinimapContainer
            and map.mask == nil and not RikUI.Hide.IsHidden(cluster.BorderTop))
        env.fire("ZONE_CHANGED")
        check("zone events before the holder exists are ignored", #env.printed == 0)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        holder = module.Holder
        check("leaving combat builds the holder and parks the art", holder ~= nil and map.parent == holder
            and map.mask == "Interface\\BUTTONS\\WHITE8X8" and parked(cluster.BorderTop)
            and holder.zone.text == "Northshire Valley")

        module = load(nil, false, function() MinimapCluster.Tracking = nil end)
        map = Minimap
        env.runScript(map, "OnMouseUp", "RightButton")
        env.runScript(map, "OnMouseUp", "RightButton")
        check("a missing tracking dropdown prints one line", printedContains("Minimap tracking") and #env.printed == 1)

        module = load(nil, false, function() QueueStatusButton = nil end)
        check("an absent queue button is skipped", module.Holder ~= nil and #module.Adopted == 2)

        module = load({ modules = { minimap = false } })
        cluster, map = MinimapCluster, Minimap
        check("a disabled module leaves the cluster untouched", module.Holder == nil and map.parent == cluster.MinimapContainer
            and map.mask == nil and cluster.BorderTop.parent == cluster and cluster.Tracking.parent == cluster
            and #env.hooks == 0 and RikUI.Layout.Groups.minimap == nil)
        env.runScript(map, "OnMouseUp", "RightButton")
        check("a disabled module keeps the native click handler", map.pings == 1)
    end)
    CreateFrame = originalCreate
    C_CVar.GetCVar = savedGetCVar
    for name, value in pairs(saved) do _G[name] = value end
    env.inCombat = false
    check("minimap suite completes", ok, reason)
end
