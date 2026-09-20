-- Fake SocialToastTemplate frames with the 69913 keys: the nine backdrop pieces, a global-named
-- glow frame, Blizzard's own animIn, and per-toast strings, icon and button. The suite checks the
-- flat pieces and that Blizzard's animation is the only one on the toast.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local NAMES = { "BNToastFrame", "BNToastFrameGlowFrame", "TimeAlertFrame", "VoiceChatPromptActivateChannel",
        "ShardTransferImminentFrame", "VoiceChatChannelActivatedNotification" }
    local BACKDROP = { "Center", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner", "TopRightCorner",
        "BottomLeftCorner", "BottomRightCorner" }
    local saved = {}
    for _, name in ipairs(NAMES) do saved[name] = _G[name] end
    local restore = widgets.install()

    local function text(frame, key, size)
        local value = frame:CreateFontString()
        function value:GetFont() return "Fonts\\FRIZQT__.TTF", size, "" end
        frame[key] = value
        frame.regions[#frame.regions + 1] = value
        return value
    end
    local function toast(name, strings)
        local frame = CreateFrame("Frame", name, UIParent)
        frame.regions, frame.children, frame.animIn = {}, {}, widgets.animationGroup()
        function frame:GetRegions() return unpack(self.regions) end
        function frame:GetChildren() return unpack(self.children) end
        for _, key in ipairs(BACKDROP) do frame[key] = frame:CreateTexture() end
        for key, size in pairs(strings) do text(frame, key, size) end
        frame:SetScript("OnShow", function(self) self.animIn:Play() end)
        frame.shown = false
        return frame
    end
    local function installClient()
        for _, name in ipairs(NAMES) do _G[name] = nil end
        local bnet = toast("BNToastFrame", { TopLine = 12, BottomLine = 10 })
        bnet.IconTexture = bnet:CreateTexture()
        BNToastFrameGlowFrame = CreateFrame("Frame", nil, bnet)
        BNToastFrameGlowFrame.glow = BNToastFrameGlowFrame:CreateTexture()
        BNToastFrameGlowFrame.glow.texture = "glow-art"
        toast("TimeAlertFrame", { Text = 12 })
        local voice = toast("VoiceChatPromptActivateChannel", { Text = 12 })
        voice.Icon = voice:CreateTexture()
        local accept = CreateFrame("Button", nil, voice)
        function accept:GetChildren() end
        for _, key in ipairs({ "Left", "Middle", "Right" }) do accept[key] = accept:CreateTexture() end
        voice.AcceptButton, voice.children[1] = accept, accept
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/controls/controls.lua", "src/modules/toasts/toasts.lua" }, profile, false, prepare or installClient)
        return RikUI.Toasts
    end
    local ok, reason = pcall(function()
        local module = load()
        local bnet = BNToastFrame
        check("a toast that was never shown is left alone", rawget(bnet.Center, "alpha") == nil and bnet.rikFill == nil)
        bnet:Show()
        check("the nine backdrop pieces are faded and the toast gets a flat fill and edge",
            bnet.Center.alpha == 0 and bnet.TopEdge.alpha == 0 and bnet.BottomRightCorner.alpha == 0
            and bnet.rikFill.texture == RikUI.Skin.FLAT and #bnet.rikBorder == 4)
        check("the glow on the global-named glow frame is blanked, not faded",
            rawget(BNToastFrameGlowFrame.glow, "texture") == nil and rawget(BNToastFrameGlowFrame.glow, "alpha") == nil)
        check("the icon is cropped and framed one pixel outside", bnet.IconTexture.coords[1] > 0
            and bnet.rikIconBorder[1].points[1][2] == bnet.IconTexture and bnet.rikIconBorder[1].points[1][4] == -1)
        check("the strings take the typeface at Blizzard's size and keep their colour",
            bnet.TopLine.fontPath == RikUI.Media.font and bnet.TopLine.fontSize == 12 and bnet.BottomLine.fontSize == 10
            and rawget(bnet.TopLine, "textColor") == nil)
        check("Blizzard's fade-in is the only animation: it played and the toast got no tween, point or size",
            bnet.animIn.plays == 1 and bnet.rikFade == nil and bnet.points == nil and bnet.width == nil)
        local fill = bnet.rikFill
        bnet:Hide()
        bnet.Center.alpha, BNToastFrameGlowFrame.glow.texture = 1, "glow-art"
        bnet:Show()
        check("a second show removes restored art again without a second fill", bnet.Center.alpha == 0
            and rawget(BNToastFrameGlowFrame.glow, "texture") == nil and bnet.rikFill == fill)

        TimeAlertFrame:Show()
        check("a toast with only text is handled the same way", TimeAlertFrame.rikFill ~= nil
            and TimeAlertFrame.Text.fontPath == RikUI.Media.font and TimeAlertFrame.rikIconBorder == nil)
        local voice = VoiceChatPromptActivateChannel
        voice:Show()
        check("the voice prompt's icon is framed and its button is flat through the controls walk",
            voice.rikIconBorder ~= nil and voice.AcceptButton.rikFill ~= nil and voice.AcceptButton.Left.alpha == 0)
        check("a toast the client lacks is skipped without a message", module.Hooked.ShardTransferImminentFrame == nil
            and #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports the toasts", widgets.printedContains(env, "Toasts hooked=3 skinned=3 failed=0"))

        module = load()
        function BNToastFrame.Center:SetAlpha() error("backdrop locked") end
        BNToastFrame:Show()
        BNToastFrame:Hide()
        BNToastFrame:Show()
        check("a toast that refuses the skin is reported once, not retried and still shown", #env.printed == 1
            and widgets.printedContains(env, "Toasts skin BNToastFrame") and BNToastFrame:IsShown()
            and BNToastFrame.rikFill == nil)

        module = load({ modules = { toasts = false } })
        BNToastFrame:Show()
        check("a disabled module leaves toasts stock", rawget(BNToastFrame.Center, "alpha") == nil
            and BNToastFrame.rikFill == nil)
    end)
    restore()
    for _, name in ipairs(NAMES) do _G[name] = saved[name] end
    check("toasts suite completes", ok, reason)
end
