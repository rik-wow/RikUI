-- Fake small dialogs with the 69913 keys: the ready check listener (nine-slice, portrait, title), the
-- role poll (Border child, global-named close button), the Camelot stack split (two backgrounds and
-- a push button) and a legacy dropdown list (Border child and a global-named backdrop child). The
-- suite checks the generic skin, the fade on every show and that absent dialogs are skipped.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local NAMES = { "ReadyCheckListenerFrame", "RolePollPopup", "RolePollPopupCloseButton", "StackSplitFrame",
        "DropDownList1", "DropDownList1MenuBackdrop", "AutoCompleteBox", "GuildInviteFrame", "CreateChannelPopup" }
    local saved = {}
    for _, name in ipairs(NAMES) do saved[name] = _G[name] end
    local restore = widgets.install()

    local function dialog(name, artKeys)
        local frame = CreateFrame("Frame", name, UIParent)
        frame.children, frame.regions = {}, {}
        function frame:GetChildren() return unpack(self.children) end
        function frame:GetRegions() return unpack(self.regions) end
        for _, key in ipairs(artKeys) do frame[key] = frame:CreateTexture() end
        frame.shown = false
        return frame
    end
    local function text(frame, size)
        local value = frame:CreateFontString()
        function value:GetFont() return "Fonts\\FRIZQT__.TTF", size, "" end
        frame.regions[#frame.regions + 1] = value
        return value
    end
    local function closeButton(parent)
        local button = CreateFrame("Button", nil, parent)
        button.normal = button:CreateTexture()
        function button:GetNormalTexture() return self.normal end
        return button
    end
    local function pushButton(parent)
        local button = CreateFrame("Button", nil, parent)
        button.children = {}
        function button:GetChildren() end
        for _, key in ipairs({ "Left", "Middle", "Right" }) do button[key] = button:CreateTexture() end
        parent.children[#parent.children + 1] = button
        return button
    end
    local function installClient()
        for _, name in ipairs(NAMES) do _G[name] = nil end
        local ready = dialog("ReadyCheckListenerFrame", { "Bg" })
        ready.NineSlice, ready.PortraitContainer = CreateFrame("Frame", nil, ready), CreateFrame("Frame", nil, ready)
        ready.TitleContainer = CreateFrame("Frame", nil, ready)
        ready.TitleContainer.TitleText = ready.TitleContainer:CreateFontString()
        ready.Text, ready.YesButton = text(ready, 12), pushButton(ready)
        local poll = dialog("RolePollPopup", {})
        poll.Border, RolePollPopupCloseButton = CreateFrame("Frame", nil, poll), closeButton(poll)
        local split = dialog("StackSplitFrame", { "SingleItemSplitBackground", "MultiItemSplitBackground" })
        split.OkayButton = pushButton(split)
        local list = dialog("DropDownList1", {})
        list.Border, DropDownList1MenuBackdrop = CreateFrame("Frame", nil, list), CreateFrame("Frame", nil, list)
    end
    -- The audit's dialogs: a translucent-template one and a backdrop-mixin one.
    local function installRest()
        installClient()
        dialog("GuildInviteFrame", { "Bg", "TopLeftCorner", "BotRightCorner", "TopBorder", "LeftBorder" })
        dialog("CreateChannelPopup", { "Center", "TopEdge", "LeftEdge", "TopLeftCorner", "BottomRightCorner" })
    end
    local function load(profile, combat, install)
        widgets.loadAddon(env, { "panels.lua", "panels-skin.lua", "skin.lua", "controls.lua", "dialogs.lua" },
            profile, combat, install or installClient)
        return RikUI.Dialogs
    end
    local ok, reason = pcall(function()
        local module = load()
        local ready = ReadyCheckListenerFrame
        check("a dialog that was never shown is left alone", rawget(ready.Bg, "alpha") == nil and ready.rikFill == nil)
        ready:Show()
        check("the ready check loses its nine-slice, background and portrait and gets a flat fill and edge",
            ready.NineSlice.alpha == 0 and ready.Bg.alpha == 0 and ready.PortraitContainer.alpha == 0
            and ready.rikFill.texture == RikUI.Skin.FLAT and #ready.rikBorder == 4)
        check("its title turns gold in the RikUI font and its text keeps Blizzard's size and colour",
            ready.TitleContainer.TitleText.fontPath == RikUI.Media.font and ready.TitleContainer.TitleText.textColor[3] == 0
            and ready.Text.fontPath == RikUI.Media.font and ready.Text.fontSize == 12
            and rawget(ready.Text, "textColor") == nil)
        check("its push button is flat through the controls walk", ready.YesButton.rikFill ~= nil
            and ready.YesButton.Left.alpha == 0)
        check("the dialog fades in and was not moved, resized or rescripted", ready.rikFade.plays == 1
            and ready.points == nil and ready.width == nil and ready:GetScript("OnShow") == nil)
        local fill = ready.rikFill
        ready:Hide()
        ready:Show()
        check("a second show fades again without a second fill", ready.rikFade.plays == 2 and ready.rikFill == fill)

        RolePollPopup:Show()
        check("the role poll loses its border frame and its global-named close button goes flat",
            RolePollPopup.Border.alpha == 0 and RolePollPopupCloseButton.rikLabel.text == "x")
        StackSplitFrame:Show()
        check("the stack split loses both backgrounds", StackSplitFrame.SingleItemSplitBackground.alpha == 0
            and StackSplitFrame.MultiItemSplitBackground.alpha == 0 and StackSplitFrame.OkayButton.rikFill ~= nil)
        DropDownList1:Show()
        check("a legacy dropdown list loses its border and its global-named backdrop child",
            DropDownList1.Border.alpha == 0 and DropDownList1MenuBackdrop.alpha == 0 and DropDownList1.rikFill ~= nil)
        check("a dialog the client lacks is skipped without a message", module.Hooked.AutoCompleteBox == nil
            and #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports the dialogs", widgets.printedContains(env, "Dialogs hooked=4 skinned=4 failed=0"))

        module = load(nil, true)
        StackSplitFrame:Show()
        check("a first show in combat skins without a protected write", StackSplitFrame.rikFill ~= nil
            and #env.printed == 0)
        env.inCombat = false

        module = load()
        function RolePollPopup.Border:SetAlpha() error("border locked") end
        RolePollPopup:Show()
        RolePollPopup:Hide()
        RolePollPopup:Show()
        check("a dialog that refuses the skin is reported once and left alone", #env.printed == 1
            and widgets.printedContains(env, "Dialogs skin RolePollPopup") and RolePollPopup.rikFade == nil)

        module = load(nil, false, installRest)
        GuildInviteFrame:Show()
        check("a translucent-template dialog loses its corners and borders and gets the flat fill",
            GuildInviteFrame.TopLeftCorner.alpha == 0 and GuildInviteFrame.BotRightCorner.alpha == 0
            and GuildInviteFrame.TopBorder.alpha == 0 and GuildInviteFrame.LeftBorder.alpha == 0
            and GuildInviteFrame.rikFill ~= nil and GuildInviteFrame.rikFade.plays == 1)
        CreateChannelPopup:Show()
        check("a backdrop-mixin dialog loses its centre, edges and corners",
            CreateChannelPopup.Center.alpha == 0 and CreateChannelPopup.TopEdge.alpha == 0
            and CreateChannelPopup.LeftEdge.alpha == 0 and CreateChannelPopup.BottomRightCorner.alpha == 0
            and #CreateChannelPopup.rikBorder == 4 and #env.printed == 0)

        module = load({ modules = { dialogs = false } })
        ReadyCheckListenerFrame:Show()
        check("a disabled module leaves dialogs stock", rawget(ReadyCheckListenerFrame.Bg, "alpha") == nil
            and ReadyCheckListenerFrame.rikFill == nil)
    end)
    restore()
    for _, name in ipairs(NAMES) do _G[name] = saved[name] end
    env.inCombat = false
    check("dialogs suite completes", ok, reason)
end
