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
        local clicks = 0
        item:SetScript("OnClick", function() clicks = clicks + 1 end)
        local row = frame("Frame", root)
        row.Label, row.Value, row.Background = row:CreateFontString(), row:CreateFontString(), row:CreateTexture()
        local service = RikUI.Interiors
        service.Walk(root, "character")
        local state, rowState = service.State(item), service.State(row)
        check("equipment gets cropped icon and edge", item.icon.coords[1] == 0.08 and #state.edge == 4)
        check("quality border becomes native-coloured strip", item.IconBorder.texture == RikUI.Skin.FLAT
            and item.IconBorder.height == 2 and item.IconBorder.color[3] == 0.9)
        check("secure buttons have no addon fields or layout writes", item.rikFill == nil
            and item.points == nil and next(item.attributes) == nil)
        env.runScript(item, "OnClick")
        check("native click survives", clicks == 1)
        check("stat rows use flat backing and font", row.Background.alpha == 0 and rowState.fill
            and row.Label.fontPath == RikUI.Media.font)
        env.runScript(row, "OnEnter")
        check("row hover fades in", rowState.enter.playing and rowState.hover.alpha > 0)
        env.runScript(row, "OnLeave")
        check("row hover reverses", not rowState.enter.playing and rowState.leave.playing and rowState.hover.alpha == 0)
        env.runScript(row, "OnHide")
        check("hidden row cancels hover", not rowState.leave.playing)
        service.Walk(root, "character")
        check("repeat walk reuses regions and hooks", service.State(item) == state and #row.hooks.OnEnter == 1)
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
        check("forbidden frames reported once", service.State(forbidden) == nil and #env.printed == 1)
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

