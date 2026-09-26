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
        -- Font recovery must also cover native-sized labels.
        local savedFont, bundled = STANDARD_TEXT_FONT, RikUI.Media.font
        STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
        local attempts = {}
        function label:GetFont() return bundled, 19, "" end
        function label:SetFont(path, size)
            attempts[#attempts + 1] = { path, size }
            return path ~= bundled
        end
        label:SetTextColor(1, 0.2, 0.1, 0.6)
        skin.Typeface(label)
        check("native-sized labels retry a missing font", #attempts == 2
            and attempts[2][1] == STANDARD_TEXT_FONT and attempts[2][2] == 19)
        check("font recovery preserves semantic colour and opacity", label.textColor[1] == 1
            and label.textColor[4] == 0.6)
        STANDARD_TEXT_FONT = savedFont
        local savedCreateFont, objects = CreateFont, {}
        RikUI.Media.font = bundled
        CreateFont = function()
            local object = {}
            function object:SetFont(path, size)
                self.path, self.size = path, size
                return path ~= bundled
            end
            function object:SetTextColor(...) self.color = { ... } end
            objects[#objects + 1] = object
            return object
        end
        skin.ButtonFonts(CreateFrame("Button"))
        CreateFont = savedCreateFont
        check("all button states recover their font", #objects == 3 and objects[1].path ~= bundled
            and objects[2].path ~= bundled and objects[3].path ~= bundled)
        local button = CreateFrame("Button")
        RikUI.Motion.BindHover(button)
        env.runScript(button, "OnEnter")
        button:SetEnabled(false); env.runScript(button, "OnDisable")
        check("disable clears shared hover and its tween", button.rikHover.region.alpha == 0
            and not button.rikHover.enter:IsPlaying())
        env.runScript(button, "OnLeave")
        check("disabled shared hover does not replay leave", not button.rikHover.leave:IsPlaying())
        assert(loadfile("src/modules/panels/interiors.lua"))("RikUI", {})
        local row = CreateFrame("Button")
        RikUI.Interiors.Row(row)
        local rowState = RikUI.Interiors.State(row)
        row:SetEnabled(false); env.runScript(row, "OnEnter")
        check("disabled interior rows never glow", rowState.hover.alpha == 0)
        row:SetEnabled(true); env.runScript(row, "OnEnter")
        row:SetEnabled(false); env.runScript(row, "OnDisable")
        check("disable clears interior hover", rowState.hover.alpha == 0 and not rowState.enter:IsPlaying())
        row:Hide(); row:Show()
        check("recycled row starts with no hover", rowState.hover.alpha == 0)
        -- More visual regressions are added below.
    end)
    restore()
    check("shared visual polish suite completes", ok, reason)
end

