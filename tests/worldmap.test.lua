-- A fake WorldMapFrame with the 69913 navigation bar: anonymous bar art, an overlay child, a
-- navList of chevron buttons and a Refresh that rebuilds the list on a map change. The suite also
-- checks that the canvas and the tracking button next to the bar are never written.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local saved = WorldMapFrame
    local restore = widgets.install()
    local GETTERS = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }
    local function regions(frame, count)
        frame.art = {}
        for index = 1, count do frame.art[index] = frame:CreateTexture() end
        -- Like the client, the list includes regions an addon created on the frame later.
        function frame:GetRegions()
            local all = { unpack(self.art) }
            if self.rikFill then all[#all + 1] = self.rikFill end
            for _, line in ipairs(self.rikBorder or {}) do all[#all + 1] = line end
            return unpack(all)
        end
    end
    local function crumb(bar, name)
        local button = CreateFrame("Button", nil, bar)
        button.textures = {}
        for _, getter in ipairs(GETTERS) do
            local texture = button:CreateTexture()
            button.textures[getter] = texture
            button[getter] = function() return texture end
        end
        for _, key in ipairs({ "arrowUp", "arrowDown", "selected" }) do button[key] = button:CreateTexture() end
        button.text = button:CreateFontString()
        function button.text:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
        button.text:SetText(name)
        return button
    end
    local function map()
        local frame = CreateFrame("Frame", "WorldMapFrame", UIParent)
        frame.ScrollContainer = CreateFrame("Frame", nil, frame)
        frame.BorderFrame = CreateFrame("Frame", nil, frame)
        local createTexture = frame.CreateTexture
        function frame:CreateTexture(...)
            local texture = createTexture(self, ...)
            texture.owner = self
            return texture
        end
        frame.QuestLog = CreateFrame("Frame", nil, frame)
        frame.QuestLog.QuestsFrame = CreateFrame("Frame", nil, frame.QuestLog)
        local scroll = CreateFrame("Frame", nil, frame.QuestLog.QuestsFrame)
        frame.QuestLog.QuestsFrame.ScrollFrame = scroll
        scroll.Background = scroll:CreateTexture()
        scroll.BorderFrame = CreateFrame("Frame", nil, scroll)
        scroll.BorderFrame.Border = scroll.BorderFrame:CreateTexture()
        scroll.BorderFrame.TopDetail = scroll.BorderFrame:CreateTexture()
        scroll.SearchBox = CreateFrame("EditBox", nil, scroll)
        scroll.SearchBox.Left = scroll.SearchBox:CreateTexture()
        local header = CreateFrame("Button", nil, scroll)
        header.Background = header:CreateTexture()
        header.normal = header:CreateTexture()
        header.highlight = header:CreateTexture()
        header.CollapseButton = CreateFrame("Button", nil, header)
        function header:GetNormalTexture() return self.normal end
        function header:GetHighlightTexture() return self.highlight end
        header.Text = header:CreateFontString()
        scroll.headerRow = header
        scroll.headerFramePool = { EnumerateActive = function()
            local done
            return function() if not done then done = true; return header end end
        end }
        for _, key in ipairs({ "WorldMapTrackingOptionsButton", "WorldMapTrackingPinButton" }) do
            local round = CreateFrame("Button", nil, frame)
            for _, art in ipairs({ "Background", "Icon", "Border" }) do round[art] = round:CreateTexture() end
            frame[key] = round
        end
        local bar = CreateFrame("Frame", nil, frame)
        regions(bar, 3)
        bar.overlay = CreateFrame("Frame", nil, bar)
        regions(bar.overlay, 2)
        bar.home = crumb(bar, "World")
        bar.navList = { bar.home }
        function bar:Refresh() self.refreshes = (self.refreshes or 0) + 1 end
        frame.NavBar = bar
        frame:Hide()
        return frame
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/worldmap/worldmap.lua" }, profile, false, function()
            map()
            if prepare then prepare() end
        end)
        return RikUI.WorldMap
    end
    local function flatCrumb(button)
        return button.textures.GetNormalTexture.alpha == 0 and button.textures.GetPushedTexture.alpha == 0
            and button.arrowUp.alpha == 0 and button.arrowDown.alpha == 0 and button.selected.alpha == 0
            and button.text.fontPath == RikUI.Media.font and button.rikHighlight ~= nil
            and button.rikHighlight.texture == RikUI.Media.highlight and button.rikSeparator ~= nil
    end
    local ok, reason = pcall(function()
        local module = load()
        local frame, bar = WorldMapFrame, WorldMapFrame.NavBar
        check("nothing is skinned before the map opens", bar.rikFill == nil and rawget(bar.art[1], "alpha") == nil)
        frame:Show()
        check("header background belongs below navigation siblings", module.Header.owner == frame)
        check("opaque header ends above the map", module.Header.color[4] == 1
            and module.Header.points[2][1] == "BOTTOMLEFT"
            and module.Header.points[2][2] == frame.ScrollContainer
            and module.Header.points[2][3] == "TOPLEFT")
        local scroll = frame.QuestLog.QuestsFrame.ScrollFrame
        check("native quest panel loses ornate chrome without hiding content",
            scroll.Background.alpha == 0 and scroll.BorderFrame.Border.alpha == 0
            and scroll.BorderFrame.TopDetail.alpha == 0 and scroll.alpha ~= 0)
        check("native category button artwork is removed and collapse remains visible",
            scroll.headerRow.normal.alpha == 0 and scroll.headerRow.highlight.texture == RikUI.Skin.FLAT
            and scroll.headerRow.CollapseButton.alpha ~= 0)
        check("quest headers and search share flat skin",
            scroll.headerRow.Background.alpha == 0 and scroll.SearchBox.Left.alpha == 0
            and scroll.headerRow.Text.fontPath == RikUI.Media.font)
        check("the navigation bar's own art and its overlay art are faded and the bar gets a flat fill and edge",
            bar.art[1].alpha == 0 and bar.art[3].alpha == 0 and bar.overlay.art[2].alpha == 0
            and bar.rikFill.texture == RikUI.Skin.FLAT and #bar.rikBorder == 4)
        check("the home breadcrumb goes flat with the typeface, a highlight and a separator on its right edge",
            flatCrumb(bar.home) and bar.home.text.fontSize == 12 and bar.home.rikSeparator.points[1][1] == "TOPRIGHT")
        check("the canvas is not written and the map is not moved", frame.ScrollContainer.rikFill == nil
            and frame.points == nil)
        local tracking, pin = frame.WorldMapTrackingOptionsButton, frame.WorldMapTrackingPinButton
        local record = module.Overlays[tracking]
        check("the round tracking button loses its disc and ring, keeps its icon and gets an inset flat backing and edge",
            tracking.Background.alpha == 0 and tracking.Border.alpha == 0 and rawget(tracking.Icon, "alpha") == nil
            and record.fill.texture == RikUI.Skin.FLAT and record.fill.points[1][4] > 0 and #record.edge == 4
            and record.highlight.texture == RikUI.Media.highlight)
        check("the pin button gets the same look", module.Overlays[pin] ~= nil and pin.Border.alpha == 0)
        check("no field, point, size or script is written on an overlay button", tracking.rikFill == nil
            and tracking.rikBorder == nil and tracking.points == nil and tracking.width == nil
            and tracking:GetScript("OnShow") == nil)
        frame:Hide()
        frame:Show()
        check("a second show adds no second backing", module.Overlays[tracking] == record)

        local zone = crumb(bar, "Elwynn Forest")
        bar.navList[2] = zone
        bar:Refresh()
        check("Blizzard's Refresh still runs and a breadcrumb it added is skinned", bar.refreshes == 1
            and flatCrumb(zone))
        local highlight, fill = bar.home.rikHighlight, bar.rikFill
        bar.home.arrowUp.alpha = 1
        bar:Refresh()
        frame:Hide()
        frame:Show()
        check("a breadcrumb and the bar are decorated once while restored art is faded again",
            bar.home.rikHighlight == highlight and bar.rikFill == fill and bar.home.arrowUp.alpha == 0)
        check("later passes never fade the bar's own fill and edge", rawget(bar.rikFill, "alpha") ~= 0
            and rawget(bar.rikBorder[1], "alpha") ~= 0 and bar.art[2].alpha == 0)
        env.inCombat = true
        bar:Refresh()
        env.inCombat = false
        check("a map change in combat is skinned without a protected write and nothing is printed", #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports the bar", widgets.printedContains(env, "World map bar=true crumbs=2 failed=false"))

        module = load(nil, function()
            WorldMapFrame.NavBar.art[1].SetAlpha = function() error("alpha refused") end
        end)
        WorldMapFrame:Show()
        WorldMapFrame:Hide()
        WorldMapFrame:Show()
        WorldMapFrame.NavBar:Refresh()
        check("a refused skin is reported once and never retried, not even from Refresh",
            widgets.printedContains(env, "World map skin") and #env.printed == 1
            and WorldMapFrame.NavBar.home.rikHighlight == nil)

        module = load(nil, function() WorldMapFrame.NavBar.navList, WorldMapFrame.NavBar.overlay = nil, nil end)
        WorldMapFrame:Show()
        check("a bar without a list or an overlay still gets the fill", WorldMapFrame.NavBar.rikFill ~= nil
            and #env.printed == 0)

        module = load(nil, function() WorldMapFrame.NavBar = nil end)
        WorldMapFrame:Show()
        check("a map without a navigation bar is left alone silently", #env.printed == 0)

        module = load(nil, function() WorldMapFrame = nil end)
        check("a client without the map says nothing", #env.printed == 0)

        module = load({ modules = { worldmap = false } })
        WorldMapFrame:Show()
        check("a disabled module leaves the bar stock", WorldMapFrame.NavBar.rikFill == nil)
    end)
    restore()
    WorldMapFrame = saved
    env.inCombat = false
    check("world map suite completes", ok, reason)
end
