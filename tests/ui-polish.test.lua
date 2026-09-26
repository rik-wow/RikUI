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
        local animated = CreateFrame("Frame")
        local cached = RikUI.Motion.Tween(animated, 0, 1, 0.2)
        RikUI.Motion.Play(cached)
        RikUI.Motion.CloseOwned(animated)
        RikUI.Motion.CancelClose(animated)
        RikUI.Profile.reducedMotion = true
        RikUI.Motion.Play(cached)
        check("reduced motion stops cached effects without replay", not cached:IsPlaying() and cached.plays == 1)
        RikUI.Motion.CloseOwned(animated)
        check("reduced motion bypasses cached window exit", not animated:IsShown() and not animated.rikClosing
            and not animated.rikExit:IsPlaying())
        RikUI.Profile.reducedMotion = false
        RikUI.Motion.Play(cached)
        check("restored motion reuses cached effects", cached.plays == 2 and cached:IsPlaying())
        local notice = CreateFrame("Frame")
        local card = skin.NotificationCard(notice)
        check("notification starts its accent", card.enter and card.enter:IsPlaying())
        notice:Hide()
        check("hidden notification stops accent", not card.enter:IsPlaying())
        notice:Show()
        RikUI.Profile.reducedMotion = true
        skin.NotificationCard(notice)
        check("cached notification respects reduced motion", not card.enter:IsPlaying())
        local quietNotice = skin.NotificationCard(CreateFrame("Frame"))
        check("new notification respects reduced motion", not quietNotice.enter or not quietNotice.enter:IsPlaying())
        RikUI.Profile.reducedMotion = false
        skin.NotificationCard(notice)
        check("notification accent can replay on reuse", card.enter:IsPlaying())
        local firstIcon, secondIcon = notice:CreateTexture(), notice:CreateTexture()
        skin.NotificationCard(notice, firstIcon)
        local shelf = card.iconBlock
        skin.NotificationCard(notice, secondIcon)
        check("pooled notification shelf follows its new icon", shelf.points[1][2] == secondIcon
            and #shelf.points == 2 and card.iconBlock == shelf)
        skin.NotificationCard(notice)
        check("iconless notification hides stale shelf", not shelf:IsShown())
        skin.NotificationCard(notice, firstIcon)
        check("returning icon restores the same shelf", shelf:IsShown() and shelf.points[1][2] == firstIcon
            and card.iconBlock == shelf)
        firstIcon:Hide()
        skin.NotificationCard(notice, firstIcon)
        check("hidden native icon also hides its shelf", not shelf:IsShown())
        firstIcon:Show()
        -- More visual regressions are added below.
    end)
    restore()
    check("shared visual polish suite completes", ok, reason)
end

