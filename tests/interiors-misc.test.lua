return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local ok, reason = pcall(function()
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/panels/interiors.lua",
            "src/modules/panels/interiors-spells.lua", "src/modules/panels/interiors-misc.lua" })
        local f = CreateFrame("Frame")
        function f:GetChildren() end
        f.BackgroundTile, f.BorderOverlay, f.Model = f:CreateTexture(), f:CreateTexture(), f:CreateTexture()
        f.Description = f:CreateFontString()
        f.Header = f:CreateFontString()
        f.Header:SetText("Collected appearances")
        RikUI.Interiors.Walk(f, "misc")
        check("misc art flattened while models survive", f.BackgroundTile.alpha == 0
            and f.BorderOverlay.alpha == 0 and rawget(f.Model, "alpha") == nil
            and f.Description.fontPath == RikUI.Media.font)
        check("collection heading is distinct from description", type(rawget(f.Header, "textColor")) == "table"
            and f.Header.textColor[2] == 0.82 and f.Header:GetText() == "Collected appearances")
        local heading = RikUI.Skin.SectionHeading(f, f.Header)
        f.Header:Hide()
        RikUI.Interiors.Walk(f, "misc")
        check("hidden collection heading clears band and rule", not heading.fill:IsShown() and not heading.rule:IsShown())
        f.Header:Show()
        RikUI.Interiors.Walk(f, "misc")
        check("collection heading reuses geometry without moving models",
            RikUI.Skin.SectionHeading(f, f.Header) == heading and heading.fill:IsShown()
            and rawget(f.Model, "points") == nil)
        local noSelection = f:CreateFontString()
        noSelection:SetText("Choose an appearance")
        f.GridNoSelectionHeader = noSelection
        RikUI.Interiors.Walk(f, "misc")
        check("late collection empty heading is styled", type(rawget(noSelection, "textColor")) == "table"
            and noSelection.textColor[2] == 0.82)
        local childHeader = CreateFrame("Frame")
        childHeader.Text = childHeader:CreateFontString()
        childHeader.Text:SetText("Choose your reward")
        f.Title = childHeader
        RikUI.Interiors.Walk(f, "misc")
        check("header containers are not treated as text", RikUI.Skin.SectionHeading(f, childHeader) == nil)
        check("native nested choice title receives heading treatment",
            type(rawget(childHeader.Text, "textColor")) == "table" and childHeader.Text.textColor[2] == 0.82)
        local pager = CreateFrame("Frame")
        function pager:GetChildren() end
        pager.PageText = pager:CreateFontString()
        pager.PageText:SetText("3 / 12")
        RikUI.Interiors.Walk(pager, "misc")
        check("collection pagination keeps native numbers with shared typeface",
            pager.PageText.fontPath == RikUI.Media.font and pager.PageText:GetText() == "3 / 12")
        local fill = RikUI.Interiors.State(f).fill
        RikUI.Interiors.Walk(f, "misc")
        check("repeat misc refresh reuses surface", RikUI.Interiors.State(f).fill == fill)
        f.Icon = f:CreateTexture()
        RikUI.Interiors.Walk(f, "misc")
        check("late collection item gets an outline", RikUI.Interiors.State(f).edge and RikUI.Interiors.State(f).hover and f.Icon.coords[1] > 0)
    end)
    restore()
    check("misc interiors suite completes", ok, reason)
end

