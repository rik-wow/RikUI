-- Regression scenarios for shared visual state and geometry.
return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local ok, reason = pcall(function()
        widgets.loadAddon(env, { "src/ui/skin.lua" })
        local skin = RikUI.Skin
        local label = CreateFrame("Frame"):CreateFontString()
        for _, alpha in ipairs({ 0, 0.25, 1 }) do
            label:SetTextColor(0.2, 0.15, 0.1, alpha)
            check("dark ink retains alpha " .. alpha, skin.Ink(label) and label.textColor[4] == alpha)
        end
        label:SetTextColor(1, 0, 0, 0.4)
        check("semantic text stays unchanged", not skin.Ink(label) and label.textColor[4] == 0.4)
        local opaque = {}
        RikUI.Secret = { IsSecret = function(value) return value == opaque end }
        label:SetTextColor(0.2, 0.15, 0.1, opaque)
        check("secret text alpha is untouched", not skin.Ink(label) and label.textColor[4] == opaque)
        label:SetTextColor(0 / 0, 0.1, 0.1, 1)
        check("invalid text colour is untouched", not skin.Ink(label))
        -- More visual regressions are added below.
    end)
    restore()
    check("shared visual polish suite completes", ok, reason)
end

