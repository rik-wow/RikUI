return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local ok, reason = pcall(function()
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/panels/interiors.lua",
            "src/modules/panels/interiors-spells.lua" })
        local function frame(kind)
            local f = CreateFrame(kind or "Frame")
            function f:GetChildren() return end
            return f
        end
        local service = RikUI.Interiors
        local book = frame()
        book.BookBGLeft, book.BookBGRight = book:CreateTexture(), book:CreateTexture()
        service.Walk(book, "spells")
        check("book page art is flat", book.BookBGLeft.alpha == 0 and service.State(book).fill)
        local spell = frame("Button")
        spell.Icon, spell.Border = spell:CreateTexture(), spell:CreateTexture()
        spell.DisabledOverlay = spell:CreateTexture()
        local clicks, drags = 0, 0
        spell:SetScript("OnClick", function() clicks = clicks + 1 end)
        spell:SetScript("OnDragStart", function() drags = drags + 1 end)
        function spell:IsProtected() return true end
        env.inCombat = true
        service.Walk(spell, "spells")
        env.runScript(spell, "OnClick"); env.runScript(spell, "OnDragStart")
        check("secure spell handlers and overlays preserved in combat", clicks == 1 and drags == 1
            and spell.Icon.coords[1] == 0.08 and spell.Border.alpha == 0
            and rawget(spell.DisabledOverlay, "alpha") == nil)
        local talent = frame()
        talent.Icon, talent.StateBorder, talent.SpendText = talent:CreateTexture(), talent:CreateTexture(), talent:CreateFontString()
        function talent.SpendText:GetTextColor() return 0.2, 1, 0.3 end
        service.Walk(talent, "spells")
        local state = service.State(talent)
        check("talent outline takes native state colour", state.edge[1].color[2] == 1 and talent.StateBorder.alpha == 0)
        function talent.SpendText:GetTextColor() return 1, 0.1, 0.1 end
        env.runScript(talent, "OnUpdate", 0.2)
        check("talent state changes update the outline", state.edge[1].color[1] == 1 and state.edge[1].color[2] == 0.1)
        local edge = frame()
        edge.Line = edge:CreateTexture()
        function edge.Line:SetThickness(v) self.thickness = v end
        service.Walk(edge, "spells")
        check("connections retain native inactive art and use thin geometry", rawget(edge.Line, "texture") == nil
            and edge.Line.thickness == 2)
        local tab = frame("Button")
        tab.LeftActive, tab.MiddleActive, tab.Icon = tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture()
        tab.Icon:Hide()
        service.Walk(tab, "spells")
        check("hidden tab placeholder icons get no stray outline", service.State(tab) == nil
            and rawget(tab.Icon, "coords") == nil)
        local header = frame()
        header.Icon, header.MainRing, header.TextBackground, header.Divider =
            header:CreateTexture(), header:CreateTexture(), header:CreateTexture(), header:CreateTexture()
        local mask = {}
        function header.Icon:GetNumMaskTextures() return mask and 1 or 0 end
        function header.Icon:GetMaskTexture() return mask end
        function header.Icon:RemoveMaskTexture(value) if value == mask then mask = nil end end
        service.Walk(header, "spells")
        check("talent headers lose portrait rings and mask without losing the icon", header.MainRing.alpha == 0
            and header.TextBackground.alpha == 0 and header.Divider.alpha == 0 and mask == nil
            and service.State(header).edge)
        local currency = frame()
        currency.UnspentLabel, currency.Border = currency:CreateFontString(), currency:CreateTexture()
        service.Walk(currency, "spells")
        check("unspent count frame art is removed but label remains", currency.Border.alpha == 0
            and currency.UnspentLabel.fontPath == RikUI.Media.font)
    end)
    restore()
    check("spell interiors suite completes", ok, reason)
end

