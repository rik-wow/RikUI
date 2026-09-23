-- Fake holders with the 69913 keys: ExtraActionBarFrame with its fixed button, ZoneAbilityFrame with
-- a pooled button container and an update method, and SpellFlyout with child buttons. These are
-- secure buttons, so the suite also checks that no field is written on a button.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local NAMES = { "ExtraActionBarFrame", "ZoneAbilityFrame", "SpellFlyout", "PossessActionBar", "OverrideActionBar" }
    local saved = {}
    for _, name in ipairs(NAMES) do saved[name] = _G[name] end
    local restore = widgets.install()

    local function button(parent, iconKey)
        local value = CreateFrame("CheckButton", nil, parent)
        value[iconKey] = value:CreateTexture()
        value.normal = value:CreateTexture()
        function value:GetNormalTexture() return self.normal end
        value[iconKey].RemoveMaskTexture = function(self, mask) self.removedMask = mask end
        if parent.children then parent.children[#parent.children + 1] = value end
        return value
    end
    local function holder(name)
        local frame = CreateFrame("Frame", name, UIParent)
        frame.children = {}
        function frame:GetChildren() return unpack(self.children) end
        frame.shown = false
        return frame
    end
    local function ownKeys(value)
        local keys = {}
        for key in pairs(value) do keys[key] = true end
        return keys
    end
    local function installClient()
        local extra = holder("ExtraActionBarFrame")
        extra.button = button(extra, "icon")
        extra.button.style, extra.button.IconMask = extra.button:CreateTexture(), extra.button:CreateTexture()
        extra.button.HotKey, extra.button.Count = extra.button:CreateFontString(), extra.button:CreateFontString()
        local zone = holder("ZoneAbilityFrame")
        zone.Style, zone.SpellButtonContainer = zone:CreateTexture(), holder(nil)
        function zone:UpdateDisplayedZoneAbilities() self.updates = (self.updates or 0) + 1 end
        local flyout = holder("SpellFlyout")
        flyout.Background = CreateFrame("Frame", nil, flyout)
        for _, key in ipairs({ "End", "HorizontalMiddle", "VerticalMiddle", "Start" }) do
            flyout.Background[key] = flyout.Background:CreateTexture()
        end
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/extrabuttons/extrabuttons.lua" }, profile, false, prepare or installClient)
        return RikUI.ExtraButtons
    end
    local ok, reason = pcall(function()
        local module = load()
        local extra = ExtraActionBarFrame.button
        local before = ownKeys(extra)
        check("a button that was never shown is left alone", rawget(extra.style, "alpha") == nil)
        ExtraActionBarFrame:Show()
        check("the extra action button loses its ornament and normal texture and its icon loses the round mask",
            extra.style.alpha == 0 and extra.normal.alpha == 0 and extra.icon.removedMask == extra.IconMask)
        local edge = module.Edges[extra]
        check("its icon is cropped and framed one pixel outside in the border colour", extra.icon.coords[1] > 0
            and #edge == 4 and edge[1].points[1][2] == extra.icon and edge[1].points[1][4] == -1
            and edge[1].color[1] == RikUI.Skin.LINE[1])
        check("hotkey and count take the RikUI font", extra.HotKey.fontPath == RikUI.Media.font
            and extra.Count.fontPath == RikUI.Media.font)
        local clean = true
        for key in pairs(extra) do
            if not before[key] then clean = false end
        end
        check("no field, attribute, point, parent or script is written on the secure button", clean
            and next(extra.attributes) == nil and extra.points == nil and extra.parent == ExtraActionBarFrame
            and extra:GetScript("OnShow") == nil)
        check("the edge fades in when the holder shows", module.Fades[extra].plays == 1)
        ExtraActionBarFrame:Hide()
        ExtraActionBarFrame:Show()
        check("a second show fades again without a second edge", module.Fades[extra].plays == 2
            and module.Edges[extra] == edge)

        RikUI.Bars = { BorderColor = function() return { 0.9, 0.1, 0.1 } end }
        local zone = ZoneAbilityFrame
        local first = button(zone.SpellButtonContainer, "Icon")
        zone:Show()
        check("zone ability buttons are skinned from the container and follow the bar border colour",
            zone.Style.alpha == 0 and first.normal.alpha == 0 and first.Icon.coords[1] > 0
            and module.Edges[first][1].color[1] == 0.9)
        local second = button(zone.SpellButtonContainer, "Icon")
        env.runScript(zone.SpellButtonContainer, "OnShow")
        check("a button the pool hands out later is skinned when its container shows", module.Edges[second] ~= nil)

        local flyout = SpellFlyout
        local spell = button(flyout, "icon")
        flyout:Show()
        check("the flyout loses its background pieces and its buttons get the bar look",
            flyout.Background.End.alpha == 0 and flyout.Background.VerticalMiddle.alpha == 0
            and module.Edges[spell] ~= nil)
        env.inCombat = true
        local combat = button(flyout, "icon")
        flyout:Hide()
        flyout:Show()
        env.inCombat = false
        check("a button first seen in combat is skinned without a protected write", module.Edges[combat] ~= nil
            and #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports the buttons", widgets.printedContains(env, "ExtraButtons hooked=3 skinned=5 failed=0"))

        module = load(nil, function()
            for _, name in ipairs(NAMES) do _G[name] = nil end
        end)
        local quiet = #env.printed == 0
        SlashCmdList.RIKUI("debug")
        check("a client without any of the holders hooks nothing and says nothing", quiet
            and widgets.printedContains(env, "ExtraButtons hooked=0"))

        module = load()
        function ExtraActionBarFrame.button.style:SetAlpha() error("style locked") end
        ExtraActionBarFrame:Show()
        ExtraActionBarFrame:Hide()
        ExtraActionBarFrame:Show()
        check("a button that refuses the skin is reported once and not retried", #env.printed == 1
            and widgets.printedContains(env, "ExtraButtons skin") and module.Edges[ExtraActionBarFrame.button] == nil)

        module = load(nil, function()
            installClient()
            local possess = holder("PossessActionBar")
            possess.actionButtons = { button(possess, "icon"), button(possess, "icon") }
            local override = holder("OverrideActionBar")
            override.SpellButton1, override.SpellButton2 = button(override, "icon"), button(override, "icon")
        end)
        local possess, override = PossessActionBar, OverrideActionBar
        local cancel = possess.actionButtons[2]
        local keysBefore = ownKeys(cancel)
        possess:Show()
        check("both possess buttons get the cropped icon and the bar edge from the bar's button list",
            module.Edges[possess.actionButtons[1]] ~= nil and cancel.icon.coords[1] > 0 and cancel.normal.alpha == 0
            and module.Edges[cancel][1].points[1][4] == -1 and module.Fades[cancel].plays == 1)
        local untouched = true
        for key in pairs(cancel) do
            if not keysBefore[key] then untouched = false end
        end
        check("nothing is written on the secure possess button or its bar", untouched and next(cancel.attributes) == nil
            and cancel.points == nil and possess.points == nil and possess:GetScript("OnShow") == nil)
        override:Show()
        check("the override bar's spell buttons are skinned by key", module.Edges[override.SpellButton1] ~= nil
            and module.Edges[override.SpellButton2] ~= nil and #env.printed == 0)

        module = load({ modules = { extrabuttons = false } })
        ExtraActionBarFrame:Show()
        check("a disabled module leaves the buttons stock", rawget(ExtraActionBarFrame.button.style, "alpha") == nil)
    end)
    restore()
    for _, name in ipairs(NAMES) do _G[name] = saved[name] end
    env.inCombat = false
    check("extra buttons suite completes", ok, reason)
end
