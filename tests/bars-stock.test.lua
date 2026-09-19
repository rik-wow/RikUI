-- Stock-bar suppression retains native frame state and queues every parent write.
return function(check)
    local env = require("wow_stub")
    local names = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
        "MultiBarRight", "MultiBarLeft", "ActionButton1", "StanceBar", "PetActionBar",
        "BagsBar", "MicroMenu", "MicroMenuContainer", "StatusTrackingBarManager",
        "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
        "MainMenuBarArtFrame", "QueueStatusButton", "ContainerFrameCombinedBags" }
    local originals = {}
    for _, name in ipairs(names) do originals[name] = _G[name] end
    local function frame(parent)
        local result = { parent = parent, events = { ACTIONBAR_PAGE_CHANGED = true }, shown = true, writes = 0 }
        function result:GetParent() return self.parent end
        function result:SetParent(value)
            if self.secureNextParent then self.secureNextParent = nil
            else assert(not InCombatLockdown(), "stock frame reparented in combat") end
            self.parent, self.writes = value, self.writes + 1
        end
        function result:Show() self.shown = true end
        function result:UnregisterAllEvents() error("native events must be preserved") end
        return result
    end
    local function fresh(profile, combat, missingMain)
        env.frames, env.inCombat = {}, false
        RikUIDB, RikUICharDB = { profiles = { Default = profile or {} } }, nil
        assert(loadfile("core.lua"))("RikUI", {})
        env.fire("ADDON_LOADED", "RikUI")
        RikUI.Bars = { Frames = {}, Options = { settings = {} },
            enabled = not (profile and profile.modules and profile.modules.bars == false) }
        for _, name in ipairs({ "main", "bar2", "bar3", "bar4", "bar5" }) do
            local buttons = {}
            for i = 1, 12 do buttons[i] = {} end
            RikUI.Bars.Frames[name] = { buttons = buttons }
        end
        for _, name in ipairs(names) do _G[name] = frame(UIParent) end
        MicroMenu:SetParent(MicroMenuContainer)
        QueueStatusButton:SetParent(MicroMenuContainer)
        MainStatusTrackingBarContainer:SetParent(StatusTrackingBarManager)
        SecondaryStatusTrackingBarContainer:SetParent(StatusTrackingBarManager)
        function MicroMenuContainer:Layout()
            self.restoredMenu = MicroMenu:GetParent() == self
        end
        ActionButton1.bar = MainActionBar
        ActionButton1:SetParent(frame(MainActionBar))
        local main = MainActionBar
        if missingMain then MainActionBar = nil end
        assert(loadfile("bars-stock.lua"))("RikUI", {})
        env.inCombat = combat == true
        RikUI.Bars.UpdateStockVisibility()
        return RikUI.Bars, main
    end
    local ok, reason = pcall(function()
        local bars, main = fresh()
        local hidden = main:GetParent()
        check("stock main is parked under a hidden parent", hidden ~= UIParent and hidden:IsShown() == false)
        check("corresponding multibars share the hidden parent", MultiBarBottomLeft:GetParent() == hidden
            and MultiBarBottomRight:GetParent() == hidden and MultiBarRight:GetParent() == hidden
            and MultiBarLeft:GetParent() == hidden)
        check("surrounding bar UI is hidden with the action bars", BagsBar:GetParent() == hidden
            and MicroMenu:GetParent() == hidden and StatusTrackingBarManager:GetParent() == hidden
            and MainMenuBarArtFrame:GetParent() == hidden)
        check("progress bar hierarchy remains intact", MainStatusTrackingBarContainer:GetParent() == StatusTrackingBarManager
            and SecondaryStatusTrackingBarContainer:GetParent() == StatusTrackingBarManager)
        check("queue status and opened bags keep their native parents", QueueStatusButton:GetParent() == MicroMenuContainer
            and MicroMenuContainer:GetParent() == UIParent and ContainerFrameCombinedBags:GetParent() == UIParent)
        check("native action events remain registered", main.events.ACTIONBAR_PAGE_CHANGED)
        check("native action hierarchy remains attached", ActionButton1:GetParent():GetParent() == main
            and ActionButton1.bar == main)
        check("stance and pet controls remain available", StanceBar:GetParent() == UIParent
            and PetActionBar:GetParent() == UIParent)
        main:Show()
        check("native Show cannot escape hidden parent", main:GetParent() == hidden and not hidden:IsShown())
        bars.UpdateStockVisibility()
        SlashCmdList.RIKUI("stockbars show")
        check("show restores original parents after repeated hide", main:GetParent() == UIParent
            and MultiBarLeft:GetParent() == UIParent and RikUI.Profile.showStockBars == true)
        check("show restores furniture and refreshes menu layout", BagsBar:GetParent() == UIParent
            and StatusTrackingBarManager:GetParent() == UIParent and MicroMenu:GetParent() == MicroMenuContainer
            and MicroMenuContainer.restoredMenu == true)
        SlashCmdList.RIKUI("stockbars hide")
        check("hide command persists preference and reapplies", main:GetParent() == hidden and RikUI.Profile.showStockBars == false)
        local writes = main.writes
        SlashCmdList.RIKUI("stockbars invalid")
        check("invalid command makes no parent writes", main.writes == writes)

        local otherParent = frame(UIParent)
        main:SetParent(otherParent)
        check("Blizzard reparent is suppressed while hidden", main:GetParent() == hidden)
        SlashCmdList.RIKUI("stockbars show")
        check("restore respects latest native parent", main:GetParent() == otherParent)
        SlashCmdList.RIKUI("stockbars hide")
        MicroMenu:SetParent(otherParent)
        check("native menu relocation cannot escape suppression", MicroMenu:GetParent() == hidden)
        SlashCmdList.RIKUI("stockbars show")
        check("menu restoration retains native override parent", MicroMenu:GetParent() == otherParent)

        env.inCombat = true
        writes = main.writes
        SlashCmdList.RIKUI("stockbars hide")
        SlashCmdList.RIKUI("stockbars show")
        check("combat requests do not mutate protected frames", main.writes == writes)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("queued visibility uses the latest choice", main:GetParent() == otherParent)
        SlashCmdList.RIKUI("stockbars hide")
        env.inCombat = true
        -- The native write is allowed; the addon posthook must wait.
        main.secureNextParent = true
        writes = main.writes
        main:SetParent(UIParent)
        check("native combat reparent queues addon repair", main:GetParent() == UIParent and main.writes == writes + 1)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("queued parent repair reapplies suppression", main:GetParent() == hidden)
        bars.UpdateStockVisibility()
        check("world refresh keeps stock suppression", main:GetParent() == hidden)

        bars, main = fresh(nil, true)
        check("combat login keeps stock bars until overlays can be hidden safely", main:GetParent() == UIParent)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("combat queue hides after leaving combat", main:GetParent() ~= UIParent)

        bars, main = fresh({ showStockBars = true })
        check("show preference survives reload", main:GetParent() == UIParent)
        bars, main = fresh({ modules = { bars = false } })
        check("disabled overlays leave stock frames alone", main:GetParent() == UIParent)
        bars, main = fresh(nil, false, true)
        check("missing main global uses native action button bar owner", main:GetParent() ~= UIParent)
        SlashCmdList.RIKUI("stockbars show")
        bars.Frames.bar2 = nil
        SlashCmdList.RIKUI("stockbars hide")
        check("stock bar remains available without its overlay", MultiBarBottomLeft:GetParent() == UIParent)
        bars.Frames.main = nil
        bars.UpdateStockVisibility()
        check("furniture returns when the main overlay is unavailable", BagsBar:GetParent() == UIParent
            and MicroMenu:GetParent() == MicroMenuContainer and StatusTrackingBarManager:GetParent() == UIParent)
    end)
    env.inCombat = false
    for _, name in ipairs(names) do _G[name] = originals[name] end
    check("stock-bar behavior suite completes", ok, reason)
end
