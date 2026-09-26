return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local savedFriends, savedAdd, savedCreate, savedUpdate = FriendsFrame, CommunitiesAddDialog,
        CommunitiesCreateDialog, FriendsList_Update
    local ok, reason = pcall(function()
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/panels/interiors.lua",
            "src/modules/panels/interiors-social.lua" })
        local function frame(name)
            local f = CreateFrame("Button", name)
            function f:GetChildren() end
            return f
        end
        local friend = frame()
        friend.name, friend.background, friend.status = friend:CreateFontString(), friend:CreateTexture(), friend:CreateTexture()
        RikUI.Interiors.Walk(friend, "social")
        check("friend row flat with status retained", friend.background.alpha == 0
            and friend.name.fontPath == RikUI.Media.font and rawget(friend.status, "alpha") == nil)
        local day = frame("CalendarDayButton42")
        CalendarDayButton42DateFrameDate = day:CreateFontString()
        CalendarDayButton42EventBackgroundTexture = day:CreateTexture()
        local event = day:CreateTexture()
        day.EventTexture = event
        RikUI.Interiors.Walk(day, "social")
        check("calendar dates styled without erasing events", RikUI.Interiors.State(day).fill
            and CalendarDayButton42DateFrameDate.fontPath == RikUI.Media.font
            and CalendarDayButton42EventBackgroundTexture.alpha == 0 and rawget(event, "alpha") == nil)
        local achievement = frame()
        achievement.Title, achievement.Description, achievement.Background = achievement:CreateFontString(),
            achievement:CreateFontString(), achievement:CreateTexture()
        achievement.ProgressBar = CreateFrame("StatusBar")
        achievement.Description:SetTextColor(0.2, 0.2, 0.2)
        RikUI.Interiors.Walk(achievement, "social")
        check("achievement card flat with progress retained", achievement.Background.alpha == 0
            and achievement.Description.fontPath == RikUI.Media.font and achievement.Description.textColor[1] > 0.8
            and achievement.ProgressBar.value == nil)
        local locked = frame()
        function locked:IsForbidden() return true end
        function locked:GetChildren() error("must not traverse forbidden frame") end
        RikUI.Interiors.Walk(locked, "social"); RikUI.Interiors.Walk(locked, "social")
        check("forbidden community surfaces skipped quietly", #env.printed == 0
            and RikUI.Interiors.State(locked) == nil)
        -- Reproduce the native FriendsList_Update hook and deferred event refresh.
        local service, visibleReads, forbiddenReads = RikUI.Interiors, 0, 0
        FriendsFrame = frame()
        FriendsFrame.name = FriendsFrame:CreateFontString()
        function FriendsFrame:IsShown() visibleReads = visibleReads + 1; return true end
        CommunitiesAddDialog, CommunitiesCreateDialog = frame(), frame()
        local newlyForbidden = false
        function CommunitiesAddDialog:IsForbidden() return true end
        function CommunitiesAddDialog:IsShown()
            forbiddenReads = forbiddenReads + 1
            error("Attempt to access forbidden object")
        end
        function CommunitiesCreateDialog:IsForbidden() return newlyForbidden end
        function CommunitiesCreateDialog:IsShown()
            if newlyForbidden then
                forbiddenReads = forbiddenReads + 1
                error("Attempt to access newly forbidden object")
            end
            return true
        end
        FriendsList_Update = function() return "native result" end
        service.Enable()
        newlyForbidden = true
        check("social hook preserves native result", FriendsList_Update() == "native result")
        env.fire("FRIENDLIST_UPDATE"); env.flushTimers()
        check("social hook and queued refresh skip forbidden visibility reads", forbiddenReads == 0
            and visibleReads >= 3 and service.State(FriendsFrame) ~= nil)
        check("all forbidden roots are skipped without forbidden-frame warnings",
            not widgets.printedContains(env, "Interiors client limit: forbidden frame"))
        local warningCount = #env.printed
        FriendsList_Update(); service.Refresh("social")
        check("repeated refresh does not retry or repeat forbidden warnings", forbiddenReads == 0
            and #env.printed == warningCount)
        local refused = frame()
        function refused:IsShown() error("must not query refused root") end
        service.Warn(refused, "prior decoration refusal")
        check("unexpected decoration failures remain reported", widgets.printedContains(env, "prior decoration refusal"))
        CommunitiesAddDialog = refused
        service.Refresh("social")
        check("previously refused roots skip visibility reads", service.State(refused) == nil)
        RikUI.Panels = { enabled = false }
        local before = visibleReads
        FriendsList_Update(); service.Refresh("social")
        check("disabled refresh does not inspect root visibility", visibleReads == before)
    end)
    FriendsFrame, CommunitiesAddDialog, CommunitiesCreateDialog, FriendsList_Update =
        savedFriends, savedAdd, savedCreate, savedUpdate
    CalendarDayButton42, CalendarDayButton42DateFrameDate, CalendarDayButton42EventBackgroundTexture = nil, nil, nil
    restore()
    check("social interiors suite completes", ok, reason)
end

