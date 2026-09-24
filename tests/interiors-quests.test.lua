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
        check("quest parchment replaced and dark prose lightened", q.MaterialTopLeft.alpha == 0
            and text.textColor[1] > 0.8 and RikUI.Interiors.State(q).fill)
        text:SetTextColor(1, 0.2, 0.1)
        RikUI.Interiors.Walk(q, "quests")
        check("semantic quest text colours retained", text.textColor[2] == 0.2)
        text:SetTextColor(0, 0, 0)
        RikUI.Interiors.Walk(q, "quests")
        check("rewritten quest prose becomes readable again", text.textColor[1] > 0.8)
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

