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
        RikUI.Interiors.Walk(f, "misc")
        check("misc art flattened while models survive", f.BackgroundTile.alpha == 0
            and f.BorderOverlay.alpha == 0 and rawget(f.Model, "alpha") == nil
            and f.Description.fontPath == RikUI.Media.font)
        local fill = RikUI.Interiors.State(f).fill
        RikUI.Interiors.Walk(f, "misc")
        check("repeat misc refresh reuses surface", RikUI.Interiors.State(f).fill == fill)
        f.Icon = f:CreateTexture()
        RikUI.Interiors.Walk(f, "misc")
        check("late collection item gets an outline", RikUI.Interiors.State(f).edge and f.Icon.coords[1] > 0)
    end)
    restore()
    check("misc interiors suite completes", ok, reason)
end

