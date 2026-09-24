return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
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
        RikUI.Interiors.Walk(achievement, "social")
        check("achievement card flat with progress retained", achievement.Background.alpha == 0
            and achievement.Description.fontPath == RikUI.Media.font and achievement.Description.textColor[1] > 0.8
            and achievement.ProgressBar.value == nil)
        local locked = frame()
        function locked:IsForbidden() return true end
        function locked:GetChildren() error("must not traverse forbidden frame") end
        RikUI.Interiors.Walk(locked, "social"); RikUI.Interiors.Walk(locked, "social")
        check("forbidden community surfaces reported once", #env.printed == 1
            and widgets.printedContains(env, "forbidden") and RikUI.Interiors.State(locked) == nil)
    end)
    CalendarDayButton42, CalendarDayButton42DateFrameDate, CalendarDayButton42EventBackgroundTexture = nil, nil, nil
    restore()
    check("social interiors suite completes", ok, reason)
end

