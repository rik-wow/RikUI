return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local ok, reason = pcall(function()
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/panels/interiors.lua",
            "src/modules/panels/interiors-quests.lua" })
        local function frame()
            local f = CreateFrame("Frame")
            f.children, f.regions = {}, {}
            function f:GetChildren() return unpack(self.children) end
            function f:GetRegions() return unpack(self.regions) end
            return f
        end
        local q = frame()
        q.MaterialTopLeft = q:CreateTexture()
        local text = q:CreateFontString()
        function text:GetObjectType() return "FontString" end
        function text:GetTextColor() return unpack(rawget(self, "textColor") or { 0, 0, 0 }) end
        q.regions = { text }
        RikUI.Interiors.Walk(q, "quests")
        check("quest parchment replaced and dark prose lightened", q.MaterialTopLeft.texture == RikUI.Skin.FLAT
            and text.textColor[1] > 0.8 and RikUI.Interiors.State(q) == nil)
        text:SetTextColor(1, 0.2, 0.1)
        RikUI.Interiors.Walk(q, "quests")
        check("semantic quest text colours retained", text.textColor[2] == 0.2)
        text:SetTextColor(0, 0, 0)
        RikUI.Interiors.Walk(q, "quests")
        check("rewritten quest prose becomes readable again", text.textColor[1] > 0.8)
        text.fontSize = 14
        function text:GetName() return "QuestInfoDescriptionText" end
        function text:GetFont() return self.fontPath or "Native", self.fontSize or 14, "" end
        RikUI.Profile.panels = { questTextSize = 20 }
        RikUI.Interiors.Walk(q, "quests")
        check("named quest prose gets selected size", text.fontSize == 20)
        RikUI.Interiors.Walk(q, "quests")
        check("quest prose refresh does not compound", text.fontSize == 20)
        RikUI.Profile.panels.questTextSize = 0
        RikUI.Interiors.Walk(q, "quests")
        check("native quest prose size restores", text.fontSize == 14)
        RikUI.Profile.panels.questTextSize = 100
        RikUI.Interiors.Walk(q, "quests")
        check("invalid quest size preserves native size", text.fontSize == 14)
        local border = frame()
        border:SetFrameLevel(100)
        border.TopDetail, border.Border, border.Shadow = border:CreateTexture(), border:CreateTexture(), border:CreateTexture()
        RikUI.Interiors.Walk(border, "quests")
        check("quest border above contents never receives an opaque fill", RikUI.Interiors.State(border) == nil
            and border.TopDetail.alpha == 0 and border.Border.alpha == 0 and border.Shadow.alpha == 0)
        local container = frame()
        container.Background = frame()
        local label = container.Background:CreateFontString()
        container.children = { container.Background }
        RikUI.Interiors.Walk(container, "quests")
        check("a Background child frame is never faded with its content", rawget(container.Background, "alpha") == nil
            and RikUI.Interiors.State(container) == nil and label)
        local map = frame()
        map.SidePanelToggle, map.Coordinates, map.ScrollContainer = frame(), frame(), frame()
        map.SidePanelToggle.Background = map.SidePanelToggle:CreateTexture()
        map.Coordinates.Background = map.Coordinates:CreateTexture()
        local anonymousCoords = frame()
        anonymousCoords.CursorCoords, anonymousCoords.PlayerCoords = frame(), frame()
        map.overlayFrames = { anonymousCoords }
        map.ThreatFrame = frame()
        map.ThreatFrame.Eye = frame()
        map.ThreatFrame.Background = map.ThreatFrame:CreateTexture()
        local pin = frame()
        pin.Background = pin:CreateTexture()
        map.ScrollContainer.children = { pin }
        RikUI.Interiors.MapSurfaces(map)
        check("map side toggle and coordinates flat", RikUI.Interiors.State(map.SidePanelToggle)
            and RikUI.Interiors.State(map.Coordinates) and RikUI.Interiors.State(anonymousCoords))
        check("named threat overlay backs only its eye", RikUI.Interiors.State(map.ThreatFrame) == nil
            and RikUI.Interiors.State(map.ThreatFrame.Eye).fill and map.ThreatFrame.Background.alpha == 0)
        check("map canvas and pin art untouched", RikUI.Interiors.State(map) == nil
            and RikUI.Interiors.State(pin) == nil and rawget(pin.Background, "alpha") == nil)
    end)
    restore()
    check("quest interiors suite completes", ok, reason)
end

