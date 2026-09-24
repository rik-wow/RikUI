-- Fake banners with the 69913 keys: the event toast manager (DisplayToast hides the old toast, shows a
-- pooled one as currentDisplayingToast, re-applies the gold line atlas and shows itself), the boss banner (animated art, title,
-- loot rows) and the objective tracker's top banner. The suite checks the typeface, the emptied
-- art, bounded card geometry and untouched native text geometry and animations.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local NAMES = { "EventToastManagerFrame", "BossBanner", "BossBanner_ConfigureLootFrame",
        "ObjectiveTrackerTopBannerFrame", "EventToastManagerSideDisplay" }
    local BOSS_ART = { "BannerTop", "BannerMiddle", "BannerBottom", "SkullCircle", "LeftFillagree" }
    local saved = {}
    for _, name in ipairs(NAMES) do saved[name] = _G[name] end
    local restore = widgets.install()

    local function text(frame, key, size)
        local value = frame:CreateFontString()
        function value:GetFont() return "Fonts\\FRIZQT__.TTF", size, "" end
        frame[key] = value
        return value
    end
    local function art(frame, keys)
        for _, key in ipairs(keys) do
            frame[key] = frame:CreateTexture()
            frame[key].texture = "stock-art"
        end
    end
    local function makeToast(parent)
        local toast = CreateFrame("Frame", nil, parent)
        toast:SetSize(230, 88)
        toast:SetFrameLevel(5)
        text(toast, "Title", 26)
        text(toast, "SubTitle", 14)
        art(toast, { "Icon", "IconBorder" })
        return toast
    end
    local function installManager()
        local manager = CreateFrame("Frame", "EventToastManagerFrame", UIParent)
        manager:SetSize(418, 112)
        art(manager, { "GLine", "GLine2", "BlackBG" })
        manager.pooled = makeToast(manager)
        function manager:SetupGLineAtlas()
            self.GLine.texture, self.GLine2.texture = "gold-bar", "gold-bar"
            self.GLine:SetVertexColor(1, 0.8, 0)
            self.GLine2:SetVertexColor(1, 0.8, 0)
            self.GLine:Show()
            self.GLine2:Show()
            self.BlackBG:SetTexture("stock-art")
            self.BlackBG:SetAlpha(0.6)
        end
        function manager:DisplayToast()
            if self.currentDisplayingToast then self.currentDisplayingToast:Hide() end
            self.currentDisplayingToast = self.pooled
            self.pooled:Show()
            self:SetupGLineAtlas()
            self:Show()
        end
        manager.shown, manager.pooled.shown = false, false
    end
    local function installClient()
        for _, name in ipairs(NAMES) do _G[name] = nil end
        installManager()
        local side = CreateFrame("Button", "EventToastManagerSideDisplay", UIParent)
        side.shown = false
        art(side, { "GoldBG" })
        side:SetScript("OnClick", function(self) self.nativeClick = true end)
        local boss = CreateFrame("Frame", "BossBanner", UIParent)
        art(boss, BOSS_ART)
        text(boss, "Title", 30)
        text(boss, "SubTitle", 16)
        local row = CreateFrame("Frame", nil, boss)
        art(row, { "Icon" })
        text(row, "ItemName", 13)
        boss.LootFrames = { row }
        BossBanner_ConfigureLootFrame = function(lootFrame) lootFrame.configured = true end
        boss.shown = false
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/banners/banners.lua" }, profile, false, prepare or installClient)
        return RikUI.Banners
    end
    local ok, reason = pcall(function()
        local module = load()
        local manager = EventToastManagerFrame
        local toast = manager.pooled
        check("a toast that was never displayed is left alone", rawget(toast.Title, "fontPath") == nil)
        manager:DisplayToast()
        check("the skin waits for the rest of Blizzard's display call", rawget(toast.Title, "fontPath") == nil)
        env.flushTimers()
        check("the displayed toast's strings take the typeface at Blizzard's size and keep their colour",
            toast.Title.fontPath == RikUI.Media.font and toast.Title.fontSize == 26 and toast.SubTitle.fontSize == 14
            and rawget(toast.Title, "textColor") == nil)
        check("its icon is cropped, loses the ring and is framed one pixel outside",
            toast.Icon.coords[1] > 0 and toast.IconBorder.alpha == 0
            and module.IconEdges[toast][1].points[1][2] == toast.Icon and module.IconEdges[toast][1].points[1][4] == -1)
        check("stretched native lines are invisible and the soft shadow stays",
            manager.GLine.alpha == 0 and manager.GLine2.alpha == 0 and manager.BlackBG.texture == "stock-art")
        check("the toast got no tween, point, size or script", toast.rikFade == nil and toast.points == nil
            and toast.width == 230 and toast.height == 88 and toast:GetScript("OnShow") == nil)
        local host = toast.rikCardHost
        check("main toast card surrounds the manager, below native text and outside layout measurement", host ~= nil
            and host.parent == toast and host.ignoreInLayout == true and host:GetFrameLevel() < toast:GetFrameLevel()
            and host.points[1][2] == manager and host.points[2][2] == manager
            and host.points[1][4] == -8 and host.points[2][4] == 8)
        manager:SetupGLineAtlas()
        check("late atlas resets and animated Show cannot revive decoration", manager.GLine.alpha == 0
            and manager.GLine2.alpha == 0 and manager.BlackBG.texture == "stock-art")
        manager:SetSize(418, 144)
        check("card anchors follow native height changes without resizing the toast", host.points[2][2] == manager
            and toast.height == 88 and host.ignoreInLayout == true)
        local edges = module.IconEdges[toast]
        manager:DisplayToast()
        env.flushTimers()
        check("a second display suppresses lines without a second icon edge",
            manager.GLine.alpha == 0 and manager.GLine2.alpha == 0 and module.IconEdges[toast] == edges)

        check("pooled toast reuses its card host", toast.rikCardHost == host)

        local side = EventToastManagerSideDisplay
        side:Show()
        side.lastToastFrame = makeToast(side)
        env.runScript(side, "OnUpdate", 0.016)
        local first = side.lastToastFrame
        check("side history rows get card hierarchy without stealing native click",
            first.rikCard.enter.plays == 1 and first.Title.fontSize == 26
            and rawget(side.GoldBG, "texture") == nil and first.rikCardHost == nil)
        env.runScript(side, "OnClick")
        env.runScript(side, "OnUpdate", 0.016)
        check("idle side display does not replay the card and native click survives",
            first.rikCard.enter.plays == 1 and side.nativeClick == true)
        side.lastToastFrame = makeToast(side)
        env.runScript(side, "OnUpdate", 0.016)
        check("a row acquired after native animation starts is decorated", side.lastToastFrame.rikCard ~= nil)
        side:Hide()
        side:Show()
        side.lastToastFrame = first
        env.runScript(side, "OnUpdate", 0.016)
        check("pooled history row entrance replays on next display", first.rikCard.enter.plays == 2)
        check("centre toast has its own accent motion without moving native content",
            toast.rikCard.enter.plays == 2 and toast.rikCard.iconBlock.points[1][2] == toast.Icon)

        BossBanner:Show()
        check("the boss banner's animated art is emptied, not faded",
            rawget(BossBanner.BannerTop, "texture") == nil and rawget(BossBanner.SkullCircle, "texture") == nil
            and rawget(BossBanner.BannerTop, "alpha") == nil)
        check("its title and subtitle take the typeface at Blizzard's size",
            BossBanner.Title.fontPath == RikUI.Media.font and BossBanner.Title.fontSize == 30
            and BossBanner.SubTitle.fontPath == RikUI.Media.font)
        local row = BossBanner.LootFrames[1]
        check("a loot row is left alone until Blizzard fills it", rawget(row.ItemName, "fontPath") == nil)
        BossBanner_ConfigureLootFrame(row, {})
        check("a filled loot row takes the typeface and a cropped icon after Blizzard's own setup",
            row.configured == true and row.ItemName.fontPath == RikUI.Media.font and row.Icon.coords[1] > 0)
        check("a banner the client lacks is skipped without a message",
            module.Hooked.ObjectiveTrackerTopBannerFrame == nil and #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports the banners", widgets.printedContains(env, "Banners hooked=3 failed=0"))

        module = load()
        function BossBanner.Title:SetFont() error("font locked") end
        BossBanner:Show()
        BossBanner:Hide()
        BossBanner:Show()
        check("a banner that refuses the skin is reported once and not retried", #env.printed == 1
            and widgets.printedContains(env, "Banners skin BossBanner"))

        module = load({ modules = { banners = false } })
        EventToastManagerFrame:DisplayToast()
        env.flushTimers()
        BossBanner:Show()
        check("a disabled module leaves banners stock", rawget(EventToastManagerFrame.pooled.Title, "fontPath") == nil
            and BossBanner.BannerTop.texture == "stock-art" and EventToastManagerFrame.GLine.texture == "gold-bar")
    end)
    restore()
    for _, name in ipairs(NAMES) do _G[name] = saved[name] end
    check("banners suite completes", ok, reason)
end
