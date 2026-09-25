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
        check("combat duration uses absolute elapsed time", frame.label.text == "Combat 1:05" and frame:IsShown())
        events.PLAYER_REGEN_DISABLED()
        now = 170; env.runScript(frame, "OnUpdate", 1)
        check("duplicate combat entry does not restart", frame.label.text == "Combat 1:10")
        events.PLAYER_REGEN_ENABLED()
        check("combat end retains final duration", frame.label.text == "Last 1:10" and frame:IsShown())
        now = 176; env.runScript(frame, "OnUpdate", 1)
        check("last duration expires and removes ticker", not frame:IsShown() and frame:GetScript("OnUpdate") == nil)
        env.inCombat = true
        timer.Options.settings[1].set(false)
        timer.Options.settings[1].set(true)
        now = 180; env.runScript(frame, "OnUpdate", 1)
        check("enabling during combat marks partial timing", frame.label.text == "Combat 0:04+")
        now = env.SECRET; env.runScript(frame, "OnUpdate", 1)
        check("secret clock never fabricates duration", frame.label.text == "Combat --:--")
        timer.Options.settings[1].set(false)
        check("disabled timer removes update callback", not frame:IsShown() and frame:GetScript("OnUpdate") == nil)
    end)
    RikUI, GetTime, env.inCombat = savedCore, savedClock, false
    restore()
    check("combat timer suite completes", ok, reason)
end

