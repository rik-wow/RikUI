return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local ok, reason = pcall(function()
        widgets.loadAddon(env, {})
        local frame = CreateFrame("Frame")
        function frame:SetPoint() error("layout anchor must not move") end
        env.inCombat = true
        local entry = RikUI.Motion.Entrance(frame, true)
        RikUI.Motion.Play(entry)
        check("entrance uses cosmetic rise and alpha without anchor writes", entry.animation.kind == "Translation"
            and entry.animation.offset[2] == 6 and entry.rikAlpha.order == 2)
        env.inCombat = false
        frame.rikEntry = entry
        RikUI.Motion.CloseOwned(frame)
        check("owned close stops entrance and waits for fade", not entry:IsPlaying()
            and frame:IsShown() and frame.rikExit:IsPlaying())
        RikUI.Motion.CancelClose(frame)
        frame.rikExit:Finish()
        check("reopen cancels stale close completion", frame:IsShown() and not frame.rikClosing)
        RikUI.Motion.CloseOwned(frame)
        frame.rikExit:Finish()
        check("completed close hides owned frame", not frame:IsShown())
        frame:Show()
        RikUI.Motion.CloseOwned(frame)
        frame:Hide()
        check("external hide stops pending close", not frame.rikExit:IsPlaying() and not frame.rikClosing)
    end)
    env.inCombat = false
    restore()
    check("window motion suite completes", ok, reason)
end

