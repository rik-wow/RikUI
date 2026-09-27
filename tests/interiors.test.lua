return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local savedQuality, savedMixin = SetItemButtonQuality, ScrollBoxListMixin
    local function frame(kind, parent)
        local f = CreateFrame(kind or "Frame", nil, parent)
        f.children = {}
        function f:GetChildren() return unpack(self.children) end
        if parent then table.insert(parent.children, f) end
        return f
    end
    local ok, reason = pcall(function()
        SetItemButtonQuality = function() end
        ScrollBoxListMixin = { Event = { OnAcquiredFrame = "acquired", OnInitializedFrame = "initialized" } }
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/panels/interiors.lua",
            "src/modules/panels/interiors-character.lua" })
        local root = frame()
        local item = frame("ItemButton", root)
        item.icon, item.IconBorder = item:CreateTexture(), item:CreateTexture()
        function item:IsProtected() return true end
        item.IconBorder:SetVertexColor(0.6, 0.2, 0.9)
        item.Count = item:CreateFontString()
        item.Count:SetText("20")
        local clicks = 0
        item:SetScript("OnClick", function() clicks = clicks + 1 end)
        local row = frame("Frame", root)
        row.Label, row.Value, row.Background = row:CreateFontString(), row:CreateFontString(), row:CreateTexture()
        row.Label:SetText("Strength")
        row.Value:SetText("142")
        row.Value:SetTextColor(0.2, 1, 0.2)
        row.SelectedBar = row:CreateTexture()
        row.SelectedBar:Hide()
        local service = RikUI.Interiors
        service.Walk(root, "character")
        local state, rowState = service.State(item), service.State(row)
        check("equipment gets cropped icon and edge", item.icon.coords[1] == 0.08 and #state.edge == 4)
        check("quality border becomes native-coloured strip", item.IconBorder.texture == RikUI.Skin.FLAT
            and item.IconBorder.height == 2 and item.IconBorder.color[3] == 0.9)
        local badge = state.countPlate
        check("item count has an inset contrast badge", badge and badge.points[1][2] == item.Count
            and badge:IsShown() and item.Count:GetText() == "20")
        item.Count:Hide()
        service.Item(item)
        check("hidden count clears its badge on reuse", badge and not badge:IsShown())
        item.Count:Show(); item.Count:SetText("")
        service.Item(item)
        check("empty count clears its badge", badge and not badge:IsShown())
        item.Count:SetText("99")
        service.Item(item)
        check("returning stack reuses badge", state.countPlate == badge and badge and badge:IsShown())
        check("secure buttons have no addon fields or layout writes", item.rikFill == nil
            and item.points == nil and next(item.attributes) == nil)
        env.runScript(item, "OnClick")
        check("native click survives", clicks == 1)
        check("stat rows use flat backing and font", row.Background.alpha == 0 and rowState.fill
            and row.Label.fontPath == RikUI.Media.font)
        local valuePlate = rowState.valuePlate
        check("stats reserve a recessed numeric cell", valuePlate and valuePlate.points[1][2] == row.Value
            and row.Value.justify == "RIGHT" and row.Value.textColor[2] == 1)
        row.Value:SetText("")
        service.Walk(root, "character")
        check("empty stat clears numeric cell", valuePlate and not valuePlate:IsShown())
        row.Value:SetText("150")
        service.Walk(root, "character")
        check("stat update keeps native text and reuses cell", rowState.valuePlate == valuePlate
            and valuePlate and valuePlate:IsShown() and row.Value:GetText() == "150")
        check("row has inset separator and native selection rail", rowState.separator
            and row.SelectedBar.width == 3 and row.SelectedBar.texture == RikUI.Skin.FLAT
            and not row.SelectedBar:IsShown())
        row.SelectedBar:Show()
        service.Row(row)
        check("native selection stays visible through refresh", row.SelectedBar:IsShown()
            and row.SelectedBar.points[1][2] == row and row.SelectedBar.color[3] == 1)
        env.runScript(row, "OnEnter")
        check("row hover fades in", rowState.enter.playing and rowState.hover.alpha > 0)
        env.runScript(row, "OnLeave")
        check("row hover reverses", not rowState.enter.playing and rowState.leave.playing and rowState.hover.alpha == 0)
        env.runScript(row, "OnHide")
        check("hidden row cancels hover", not rowState.leave.playing)
        service.Walk(root, "character")
        check("repeat walk reuses regions and hooks", service.State(item) == state and #row.hooks.OnEnter == 1)
        local host = frame("Frame", root)
        local background, icon = host:CreateTexture(), host:CreateTexture()
        function background:GetAtlas() return "UI-Character-Info-General-BG" end
        function icon:GetAtlas() return "semantic-stat-icon" end
        function host:GetRegions() return background, icon end
        local gearBorder = frame("Frame", item)
        local gear = gearBorder:CreateTexture()
        function gear:GetAtlas() return "UI-Character-Info-GearSlot" end
        function gearBorder:GetRegions() return gear end
        local side = frame("Frame", root)
        side.Mask, side.Icon, side.Background, side.SelectedTexture, side.TabGlow, side.HighlightTexture =
            side:CreateTexture(), side:CreateTexture(), side:CreateTexture(), side:CreateTexture(),
            side:CreateTexture(), side:CreateTexture()
        function side.Icon:RemoveMaskTexture(mask) self.removedMask = mask end
        local released = 0
        side:SetScript("OnMouseUp", function() released = released + 1 end)
        side.SelectedTexture:Hide()
        service.Walk(root, "character")
        env.runScript(side, "OnMouseUp")
        check("Camelot unnamed pane and gear art removed selectively", background.alpha == 0 and gear.alpha == 0
            and rawget(icon, "alpha") == nil)
        check("side tabs keep handlers and native selection with flat accents", released == 1
            and side.Icon.removedMask == side.Mask and side.Background.alpha == 0
            and side.SelectedTexture.texture == RikUI.Skin.FLAT and side.SelectedTexture.height == 2
            and not side.SelectedTexture:IsShown())
        side.SelectedTexture:Show()
        check("native side-tab selection still reveals the accent", side.SelectedTexture:IsShown())
        local list = frame("Frame", root)
        list.callbacks = {}
        function list:ForEachFrame() end
        function list:RegisterCallback(event, callback, owner) self.callbacks[event] = { callback, owner } end
        service.Walk(root, "character")
        local late = frame("Button")
        late.Name, late.Background = late:CreateFontString(), late:CreateTexture()
        local cb = list.callbacks.initialized or list.callbacks.acquired
        cb[1](cb[2], late)
        check("late scroll rows are styled", service.State(late) ~= nil)
        local forbidden = frame("Frame", root)
        function forbidden:IsForbidden() return true end
        forbidden.Label = forbidden:CreateFontString()
        service.Walk(root, "character")
        service.Walk(root, "character")
        check("forbidden frames skipped quietly", service.State(forbidden) == nil and #env.printed == 0)
        RikUI.Panels = { enabled = false }
        local stock = frame("ItemButton")
        stock.icon = stock:CreateTexture()
        service.Walk(stock, "character")
        check("disabled panels leave interiors stock", service.State(stock) == nil)
    end)
    SetItemButtonQuality, ScrollBoxListMixin = savedQuality, savedMixin
    restore()
    check("interiors suite completes", ok, reason)
end

