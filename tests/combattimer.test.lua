return function(check)
    local env = require("wow_stub")
    local restore = require("widget_stub").install()
    local savedCore, savedClock = RikUI, GetTime
    local now, events = 100, {}
    GetTime = function() return now end
    local function load()
        RikUI = { Profile = { combattimer = { show = true, linger = 5 } },
            Secret = { IsSecret = function(v) return v == env.SECRET end },
            Media = { Font = function() end }, UI = { Edges = function() return {} end },
            Layout = { Register = function(frame, key) frame.layoutKey = key end },
            RegisterEvent = function(_, event, callback) events[event] = callback end,
            RegisterCommand = function() end, Changed = function() end, Print = function() end,
            RegisterModule = function() end }
        local chunk = loadfile("src/modules/combattimer/combattimer.lua")
        if not chunk then return nil end
        chunk()
        RikUI.CombatTimer:OnEnable()
        return RikUI.CombatTimer
    end
    local ok, reason = pcall(function()
        env.inCombat = false
        local timer = load()
        check("combat timer module exists", timer ~= nil)
        if not timer then return end
        local frame = timer.Holder
        check("timer starts hidden and has shared layout", not frame:IsShown() and frame.layoutKey == "combattimer")
        events.PLAYER_REGEN_DISABLED()
        now = 165; env.runScript(frame, "OnUpdate", 1)
        check("combat duration uses absolute elapsed time", frame.state.text == "Combat" and frame.label.text == "1:05" and frame:IsShown())
        events.PLAYER_REGEN_DISABLED()
        now = 170; env.runScript(frame, "OnUpdate", 1)
        check("duplicate combat entry does not restart", frame.state.text == "Combat" and frame.label.text == "1:10")
        events.PLAYER_REGEN_ENABLED()
        check("combat end retains final duration", frame.state.text == "Last" and frame.label.text == "1:10" and frame:IsShown())
        now = 176; env.runScript(frame, "OnUpdate", 1)
        check("last duration expires and removes ticker", not frame:IsShown() and frame:GetScript("OnUpdate") == nil)
        env.inCombat = true
        timer.Options.settings[1].set(false)
        timer.Options.settings[1].set(true)
        now = 180; env.runScript(frame, "OnUpdate", 1)
        check("enabling during combat marks partial timing", frame.state.text == "Combat" and frame.label.text == "0:04+")
        now = env.SECRET; env.runScript(frame, "OnUpdate", 1)
        check("secret clock never fabricates duration", frame.state.text == "Combat" and frame.label.text == "--:--")
        timer.Options.settings[1].set(false)
        check("disabled timer removes update callback", not frame:IsShown() and frame:GetScript("OnUpdate") == nil)
        local watch = timer.Stopwatch
        check("stopwatch exists with separate layout and starts hidden", watch and watch.layoutKey == "stopwatch" and not watch:IsShown())
        if not watch then return end
        now = 200; timer.StopwatchAction("start")
        now = 265; env.runScript(watch, "OnUpdate", 1)
        check("stopwatch shows absolute elapsed time", watch.state.text == "Run" and watch.label.text == "1:05" and watch:IsShown())
        timer.StopwatchAction("start")
        timer.StopwatchAction("pause")
        now = 300; timer.RefreshStopwatch()
        check("pause freezes duration and removes ticker", watch.state.text == "Pause" and watch.label.text == "1:05" and not watch:GetScript("OnUpdate"))
        env.runScript(watch, "OnClick", "LeftButton")
        now = 310; timer.StopwatchAction("hide")
        now = 315; timer.StopwatchAction("show")
        check("hidden stopwatch keeps elapsed session time", watch.state.text == "Run" and watch.label.text == "1:20")
        now = 305; env.runScript(watch, "OnUpdate", 1)
        check("backward clock marks stopwatch unavailable", watch.state.text == "Reset" and watch.label.text == "--:--" and not watch:GetScript("OnUpdate"))
        env.runScript(watch, "OnClick", "RightButton")
        check("right click resets and pauses stopwatch", watch.state.text == "Pause" and watch.label.text == "0:00")
        now = env.SECRET; timer.StopwatchAction("start")
        check("secret start cannot invent stopwatch time", watch.state.text == "Reset" and watch.label.text == "--:--")
        now = 400; timer.StopwatchAction("reset"); timer.StopwatchAction("start")
        now = 400000; env.runScript(watch, "OnUpdate", 1)
        check("stopwatch stops at bounded maximum", watch.state.text == "Pause" and watch.label.text == "99:59:59" and not watch:GetScript("OnUpdate"))
        check("stopwatch state never written to profile", RikUI.Profile.combattimer.started == nil and RikUI.Profile.combattimer.elapsed == nil)
    end)
    RikUI, GetTime, env.inCombat = savedCore, savedClock, false
    restore()
    check("combat timer suite completes", ok, reason)
end

