-- Fake banners with the 69913 keys: the event toast manager (DisplayToast stores a pooled toast in
-- currentDisplayingToast and re-applies the gold line atlas), the boss banner (animated art, title,
-- loot rows) and the objective tracker's top banner. The suite checks the typeface, the emptied
-- art, the flat lines and that the module adds no tween, point or size.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local NAMES = { "EventToastManagerFrame", "BossBanner", "BossBanner_ConfigureLootFrame",
        "ObjectiveTrackerTopBannerFrame" }
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
        text(toast, "Title", 26)
        text(toast, "SubTitle", 14)
        art(toast, { "Icon", "IconBorder" })
        return toast
    end
    local function installManager()
        local manager = CreateFrame("Frame", "EventToastManagerFrame", UIParent)
        art(manager, { "GLine", "GLine2", "BlackBG" })
        manager.pooled = makeToast(manager)
        function manager:SetupGLineAtlas() self.GLine.texture, self.GLine2.texture = "gold-bar", "gold-bar" end
        function manager:DisplayToast()
            self.currentDisplayingToast = self.pooled
            self:SetupGLineAtlas()
        end
        manager.shown = false
    end
    local function installClient()
        for _, name in ipairs(NAMES) do _G[name] = nil end
        installManager()
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
        widgets.loadAddon(env, { "skin.lua", "banners.lua" }, profile, false, prepare or installClient)
        return RikUI.Banners
    end
    local ok, reason = pcall(function()
        local module = load()
        local manager = EventToastManagerFrame
        local toast = manager.pooled
        check("a toast that was never displayed is left alone", rawget(toast.Title, "fontPath") == nil)
        manager:DisplayToast()
        check("the displayed toast's strings take the typeface at Blizzard's size and keep their colour",
            toast.Title.fontPath == RikUI.Media.font and toast.Title.fontSize == 26 and toast.SubTitle.fontSize == 14
            and rawget(toast.Title, "textColor") == nil)
        check("its icon is cropped, loses the ring and is framed one pixel outside",
            toast.Icon.coords[1] > 0 and toast.IconBorder.alpha == 0
            and module.IconEdges[toast][1].points[1][2] == toast.Icon and module.IconEdges[toast][1].points[1][4] == -1)
        check("the two gold bars become flat one-pixel lines and the shadow stays",
            manager.GLine.texture == RikUI.Skin.FLAT and manager.GLine2.texture == RikUI.Skin.FLAT
            and manager.GLine.height == 1 and manager.BlackBG.texture == "stock-art")
        check("the toast got no tween, point, size or script", toast.rikFade == nil and toast.points == nil
            and toast.width == nil and toast:GetScript("OnShow") == nil)
        local edges = module.IconEdges[toast]
        manager:DisplayToast()
        check("a second display flattens the lines again without a second icon edge",
            manager.GLine.texture == RikUI.Skin.FLAT and module.IconEdges[toast] == edges)

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
        check("debug reports the banners", widgets.printedContains(env, "Banners hooked=2 failed=0"))

        module = load()
        function BossBanner.Title:SetFont() error("font locked") end
        BossBanner:Show()
        BossBanner:Hide()
        BossBanner:Show()
        check("a banner that refuses the skin is reported once and not retried", #env.printed == 1
            and widgets.printedContains(env, "Banners skin BossBanner"))

        module = load({ modules = { banners = false } })
        EventToastManagerFrame:DisplayToast()
        BossBanner:Show()
        check("a disabled module leaves banners stock", rawget(EventToastManagerFrame.pooled.Title, "fontPath") == nil
            and BossBanner.BannerTop.texture == "stock-art" and EventToastManagerFrame.GLine.texture == "gold-bar")
    end)
    restore()
    for _, name in ipairs(NAMES) do _G[name] = saved[name] end
    check("banners suite completes", ok, reason)
end
