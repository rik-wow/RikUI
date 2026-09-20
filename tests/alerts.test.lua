-- Fake alert toasts with the 69913 template keys: a loot toast with a lootItem child, a money toast
-- and an achievement-style toast whose Icon is a frame. The suite checks that the skin rides on
-- AlertFrame_ShowNewAlert, leaves Blizzard's animations and text colours alone and re-fades art that
-- a SetUp restored.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local saved = AlertFrame_ShowNewAlert
    local restore = widgets.install()
    local function art(frame, key)
        local value = frame:CreateTexture()
        value.texture = key .. "-art"
        frame[key] = value
        frame.regions[#frame.regions + 1] = value
        return value
    end
    local function text(frame, key, size)
        local value = frame:CreateFontString()
        function value:GetFont() return "Fonts\\FRIZQT__.TTF", size, "" end
        frame[key] = value
        frame.regions[#frame.regions + 1] = value
        return value
    end
    local function toast(keys, strings)
        local frame = CreateFrame("Button", nil, UIParent)
        frame.regions, frame.animIn = {}, widgets.animationGroup()
        function frame:GetRegions() return unpack(self.regions) end
        for _, key in ipairs(keys) do art(frame, key) end
        for key, size in pairs(strings) do text(frame, key, size) end
        frame:Hide()
        return frame
    end
    local function lootToast()
        local frame = toast({ "Background", "PvPBackground", "BGAtlas", "glow", "shine" }, { Label = 12, ItemName = 14 })
        local item = CreateFrame("Frame", nil, frame)
        item.regions = {}
        function item:GetRegions() return unpack(self.regions) end
        art(item, "Icon")
        art(item, "IconBorder")
        text(item, "Count", 10)
        frame.lootItem = item
        return frame
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/alerts/alerts.lua" }, profile, false, function()
            AlertFrame_ShowNewAlert = function(frame)
                frame:Show()
                frame.animIn:Play()
            end
            if prepare then prepare() end
        end)
        return RikUI.Alerts
    end
    local ok, reason = pcall(function()
        local module = load()
        local loot = lootToast()
        AlertFrame_ShowNewAlert(loot)
        check("Blizzard still shows the toast and plays its own intro", loot:IsShown() and loot.animIn.plays == 1)
        check("every background is faded and the toast gets an inset flat fill with an edge",
            loot.Background.alpha == 0 and loot.PvPBackground.alpha == 0 and loot.BGAtlas.alpha == 0
            and loot.rikFill.texture == RikUI.Skin.FLAT and loot.rikFill.points[1][4] > 0 and #loot.rikBorder == 4)
        check("glow and shine are blanked, not faded", rawget(loot.glow, "texture") == nil
            and rawget(loot.shine, "texture") == nil and rawget(loot.glow, "alpha") == nil)
        local icon = loot.lootItem.Icon
        check("the loot icon is cropped, loses its border art and gets an edge anchored to the icon",
            icon.coords[1] > 0 and loot.lootItem.IconBorder.alpha == 0 and #loot.rikIconBorder == 4
            and loot.rikIconBorder[1].points[1][2] == icon)
        check("the icon edge sits one pixel outside the icon, where the icon cannot cover it",
            loot.rikIconBorder[1].points[1][4] == -1)
        check("text takes the RikUI typeface at Blizzard's size and keeps its colour",
            loot.ItemName.fontPath == RikUI.Media.font and loot.ItemName.fontSize == 14 and loot.Label.fontSize == 12
            and loot.lootItem.Count.fontPath == RikUI.Media.font and rawget(loot.ItemName, "textColor") == nil)
        check("the toast was not moved, resized or rescripted and got no tween of its own", loot.points == nil
            and loot.width == nil and loot:GetScript("OnShow") == nil and loot.rikFade == nil)

        local fill = loot.rikFill
        loot:Hide()
        loot.Background.alpha, loot.glow.texture = 1, "glow-art"
        AlertFrame_ShowNewAlert(loot)
        check("a reused toast is not filled twice but art a SetUp restored is removed again",
            loot.rikFill == fill and loot.Background.alpha == 0 and rawget(loot.glow, "texture") == nil)

        local money = toast({ "Background", "Icon", "IconBorder" }, { Label = 12, Amount = 16 })
        AlertFrame_ShowNewAlert(money)
        check("a toast with the icon on the frame itself is handled the same way", money.Icon.coords[1] > 0
            and money.IconBorder.alpha == 0 and money.rikIconBorder[1].points[1][2] == money.Icon
            and money.Amount.fontSize == 16)

        local achievement = toast({ "Background", "glow", "shine" }, { Name = 12, Unlocked = 10 })
        local holder = CreateFrame("Frame", nil, achievement)
        holder.regions = {}
        art(holder, "Texture")
        art(holder, "Overlay")
        art(holder, "Bling")
        achievement.Icon = holder
        AlertFrame_ShowNewAlert(achievement)
        check("an icon frame has its overlay and bling faded and its inner texture cropped",
            holder.Texture.coords[1] > 0 and holder.Overlay.alpha == 0 and holder.Bling.alpha == 0
            and achievement.rikIconBorder[1].points[1][2] == holder.Texture)

        local bare = CreateFrame("Frame", nil, UIParent)
        bare.animIn = widgets.animationGroup()
        AlertFrame_ShowNewAlert(bare)
        check("a toast missing every optional key still gets the fill and says nothing", bare.rikFill ~= nil
            and bare.rikIconBorder == nil and #env.printed == 0)
        env.inCombat = true
        AlertFrame_ShowNewAlert(lootToast())
        env.inCombat = false
        check("a toast in combat is skinned without a protected write", #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports the toasts", widgets.printedContains(env, "Alerts hooked=true skinned=5 failed=0"))

        module = load()
        local broken = lootToast()
        function broken.Background:SetAlpha() error("alpha refused") end
        AlertFrame_ShowNewAlert(broken)
        broken:Hide()
        AlertFrame_ShowNewAlert(broken)
        check("a toast that refuses the skin is reported once, not retried and still shown",
            widgets.printedContains(env, "Alerts skin") and #env.printed == 1 and broken:IsShown())

        module = load(nil, function() AlertFrame_ShowNewAlert = nil end)
        SlashCmdList.RIKUI("debug")
        check("a client without the alert system hooks nothing", widgets.printedContains(env, "Alerts hooked=false"))

        module = load({ modules = { alerts = false } })
        local stock = lootToast()
        AlertFrame_ShowNewAlert(stock)
        check("a disabled module leaves toasts stock", rawget(stock.Background, "alpha") == nil and stock.rikFill == nil)
    end)
    restore()
    AlertFrame_ShowNewAlert = saved
    env.inCombat = false
    check("alert suite completes", ok, reason)
end
