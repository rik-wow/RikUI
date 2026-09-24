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
        check("connections are thin flat lines", edge.Line.texture == RikUI.Skin.FLAT and edge.Line.thickness == 2)
    end)
    restore()
    check("spell interiors suite completes", ok, reason)
end

