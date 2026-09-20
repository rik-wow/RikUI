-- A fake LossOfControlFrame with the 69913 keys. Blizzard writes the frame's alpha every frame, so
-- the suite checks that the module never touches it and animates only regions of its own.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local saved = LossOfControlFrame
    local restore = widgets.install()

    local function text(owner, key, size)
        local value = owner:CreateFontString()
        function value:GetFont() return "Fonts\\FRIZQT__.TTF", size, "" end
        owner[key] = value
        return value
    end
    local function alert()
        local frame = CreateFrame("Frame", "LossOfControlFrame", UIParent)
        for _, key in ipairs({ "blackBg", "RedLineTop", "RedLineBottom", "Icon" }) do frame[key] = frame:CreateTexture() end
        text(frame, "AbilityName", 24)
        frame.TimeLeft = CreateFrame("Frame", nil, frame)
        text(frame.TimeLeft, "NumberText", 20)
        text(frame.TimeLeft, "SecondsText", 20)
        frame.shown = false
        return frame
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "skin.lua", "lossofcontrol.lua" }, profile, false, prepare or alert)
        return RikUI.LossOfControl
    end
    local ok, reason = pcall(function()
        local module = load()
        local frame = LossOfControlFrame
        check("the shadow and both red glow lines are faded at login", frame.blackBg.alpha == 0
            and frame.RedLineTop.alpha == 0 and frame.RedLineBottom.alpha == 0)
        check("a flat panel takes the shadow's place with a one-pixel edge framing it",
            frame.rikPanel.texture == RikUI.Skin.FLAT and frame.rikPanel.width == 256 and frame.rikPanel.height == 58
            and frame.rikPanel.points[1][1] == "BOTTOM" and #frame.rikBorder == 4
            and frame.rikBorder[1].points[1][2] == frame.rikPanel)
        check("thin red lines sit on the panel's top and bottom edges", #frame.rikAccents == 2
            and frame.rikAccents[1].color[1] > 0.8 and frame.rikAccents[1].color[2] < 0.3
            and frame.rikAccents[1].height == 2 and frame.rikAccents[2].points[1][1] == "BOTTOMLEFT")
        check("the icon is cropped and gets an edge anchored to it", frame.Icon.coords[1] > 0
            and #frame.rikIconBorder == 4 and frame.rikIconBorder[1].points[1][2] == frame.Icon
            and frame.rikIconBorder[1].points[1][4] == -1)
        check("the three strings take the typeface at Blizzard's size and keep their colour",
            frame.AbilityName.fontPath == RikUI.Media.font and frame.AbilityName.fontSize == 24
            and frame.TimeLeft.NumberText.fontSize == 20 and frame.TimeLeft.SecondsText.fontPath == RikUI.Media.font
            and rawget(frame.AbilityName, "textColor") == nil)

        frame:Show()
        check("showing the alert fades the panel in and starts the red pulse", module.Fade.plays == 1
            and module.Fade.animation.to == 1 and module.Pulses[1].playing == true and module.Pulses[2].looping == "BOUNCE")
        check("the frame's own alpha, position, size and scripts are never written", rawget(frame, "alpha") == nil
            and frame.points == nil and frame.width == nil and frame:GetScript("OnShow") == nil
            and frame:GetScript("OnUpdate") == nil and frame.rikFade == nil)
        frame:Hide()
        check("hiding the alert stops the pulse", module.Pulses[1].playing == false and module.Pulses[2].playing == false)
        frame:Show()
        check("the next alert fades in again without a second panel", module.Fade.plays == 2
            and #frame.rikAccents == 2)
        SlashCmdList.RIKUI("debug")
        check("debug reports the skin", widgets.printedContains(env, "LossOfControl skinned=true"))

        module = load(nil, function() LossOfControlFrame = nil end)
        local quiet = #env.printed == 0
        SlashCmdList.RIKUI("debug")
        check("a client without the alert frame does nothing and says nothing", quiet
            and widgets.printedContains(env, "LossOfControl skinned=false"))

        module = load(nil, function()
            local broken = alert()
            function broken.blackBg:SetAlpha() error("shadow locked") end
        end)
        check("a frame that refuses the skin is reported once and gets no panel",
            widgets.printedContains(env, "LossOfControl skin") and #env.printed == 1
            and LossOfControlFrame.rikPanel == nil)

        module = load({ modules = { lossofcontrol = false } })
        LossOfControlFrame:Show()
        check("a disabled module leaves the alert stock", rawget(LossOfControlFrame.blackBg, "alpha") == nil
            and LossOfControlFrame.rikPanel == nil)
    end)
    restore()
    LossOfControlFrame = saved
    check("loss of control suite completes", ok, reason)
end
