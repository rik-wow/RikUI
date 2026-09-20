-- Swing bars run on the PLAYER_SWING duration and the clock alone; the suite drives GetTime by hand.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local API = { "GetTime", "C_SwingTimer", "SwingTimerMainHandFrame", "SwingTimerOffHandFrame",
        "SwingTimerRangedFrame" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local savedSwingEnum = Enum.PlayerSwingType
    local restore = widgets.install()
    local stub = {}
    local MAIN, OFF, RANGED = 0, 1, 2
    local STOCK = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }
    local function installClient()
        stub.now, stub.rangeChecks, stub.inRange, stub.rangeError = 100, {}, {}, nil
        GetTime = function() return stub.now end
        Enum.PlayerSwingType = { MainHand = MAIN, OffHand = OFF, Ranged = RANGED }
        for _, name in ipairs(STOCK) do _G[name] = CreateFrame("Frame", name, UIParent) end
        C_SwingTimer = {
            EnableRangeCheck = function(swingType, enabled)
                if stub.rangeError then error(stub.rangeError) end
                stub.rangeChecks[swingType] = enabled
            end,
            IsTargetWithinSwingRange = function(swingType) return stub.inRange[swingType] end,
        }
    end
    local function load(profile, combat, prepare)
        widgets.loadAddon(env, { "swingtimer.lua" }, profile, combat, function()
            installClient()
            if prepare then prepare() end
        end)
        return RikUI.SwingTimer
    end
    local function advance(bar, seconds)
        stub.now = stub.now + seconds
        env.runScript(bar, "OnUpdate", seconds)
    end
    local function parked(frame) return frame.parent == RikUIHiddenFrames and RikUI.Hide.IsHidden(frame) end
    local function near(value, expected) return type(value) == "number" and math.abs(value - expected) < 0.001 end
    local function offset(bar) return bar.points[1][5] end
    local ok, reason = pcall(function()
        local module = load()
        local holder, group = module.Holder, RikUI.Layout.Groups.swingtimer
        local main, off, ranged = module.Bars[MAIN], module.Bars[OFF], module.Bars[RANGED]
        check("the swing bars register with the layout under key swingtimer above the bottom of the screen",
            holder and group and group.frames[1] == holder and group.defaults.point == "BOTTOM"
            and group.defaults.y > 0)
        check("three bars exist with their labels and none shows before a swing", main and off and ranged
            and main.shown == false and off.shown == false and ranged.shown == false
            and main.label.text == "Main hand" and off.label.text == "Off hand" and ranged.label.text == "Ranged")
        check("bars are flat, in the RikUI media, with a spark on the fill edge",
            main.bar.texture == RikUI.Media.statusbar and #main.rikBorder == 4 and main.bar.low == 0
            and main.bar.high == 1 and main.spark.points[1][2] == main.bar.fill
            and main.label.fontPath == RikUI.Media.font)
        check("the module switches the client's range check on for each swing type", stub.rangeChecks[MAIN] == true
            and stub.rangeChecks[OFF] == true and stub.rangeChecks[RANGED] == true)

        env.fire("PLAYER_SWING", 2.6, MAIN)
        check("a swing shows its bar empty with the full time, a fade and a flash", main.shown == true
            and near(main.bar.value, 0) and main.time.text == "2.6" and main.fade.plays == 1
            and main.flashAnim.plays == 1 and off.shown == false)
        advance(main, 1.3)
        check("the bar fills with the clock and counts down", near(main.bar.value, 0.5) and main.time.text == "1.3")
        advance(main, 1.4)
        check("a finished swing lingers full instead of vanishing", main.shown == true and near(main.bar.value, 1)
            and main.time.text == "0.0")
        env.fire("PLAYER_SWING", 2.6, MAIN)
        check("the next swing restarts the same bar with a flash and no second fade", near(main.bar.value, 0)
            and main.fade.plays == 1 and main.flashAnim.plays == 2)

        env.fire("PLAYER_SWING", 1.8, OFF)
        check("an off hand swing stacks a second bar under the first", off.shown == true and offset(main) == 0
            and offset(off) < 0 and off.bar.color[1] ~= main.bar.color[1])
        advance(main, 2.6)
        advance(main, 0.7)
        check("a bar past its linger clears and the rest restack", main.shown == false and offset(off) == 0
            and main:GetScript("OnUpdate") == nil)

        env.printed = {}
        env.fire("PLAYER_SWING", 0, MAIN)
        env.fire("PLAYER_SWING", nil, MAIN)
        env.fire("PLAYER_SWING", env.SECRET, MAIN)
        env.fire("PLAYER_SWING", 2, 7)
        env.fire("PLAYER_SWING", 2, env.SECRET)
        check("a non-positive, missing or secret duration and an unknown swing type are ignored silently",
            main.shown == false and #env.printed == 0)

        env.fire("PLAYER_SWING_RANGE_UPDATE", OFF, false, true)
        check("out of range dims the bar and turns the time red", off.bar.alpha < 1 and off.time.textColor[1] == 1
            and off.time.textColor[2] < 0.5)
        env.fire("PLAYER_SWING_RANGE_UPDATE", OFF, true, true)
        check("back in range restores the bar", off.bar.alpha == 1 and off.time.textColor[2] == 1)
        env.fire("PLAYER_SWING_RANGE_UPDATE", OFF, false, false)
        check("a swing type that does not check range is never dimmed", off.bar.alpha == 1)
        stub.inRange[OFF] = false
        env.fire("PLAYER_TARGET_CHANGED")
        check("a new target asks the client for the range of every bar", off.bar.alpha < 1 and main.bar.alpha == 1)

        check("the three stock swing frames are parked once the bars exist", parked(SwingTimerMainHandFrame)
            and parked(SwingTimerOffHandFrame) and parked(SwingTimerRangedFrame))
        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports the bar state", widgets.printedContains(env, "Swing timer holder=true active=1"))

        module = load(nil, false, function() stub.rangeError = "range check refused" end)
        check("a refused range check is reported once and the bars still build", module.Holder ~= nil
            and widgets.printedContains(env, "Swing timer range check") and #env.printed == 1)

        module = load(nil, true)
        env.fire("PLAYER_SWING", 2.6, MAIN)
        check("a combat login builds nothing, parks nothing and survives a swing", module.Holder == nil
            and SwingTimerMainHandFrame.parent == UIParent and #env.printed == 0)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat builds the bars and parks the stock frames", module.Holder ~= nil
            and parked(SwingTimerMainHandFrame))

        module = load(nil, false, function() Enum.PlayerSwingType, C_SwingTimer = nil, nil end)
        env.fire("PLAYER_SWING", 2.6, MAIN)
        check("a client without the swing API builds nothing and says nothing", module.Holder == nil
            and SwingTimerMainHandFrame.parent == UIParent and #env.printed == 0)

        module = load({ modules = { swingtimer = false } })
        check("a disabled module leaves the stock swing frames untouched", module.Holder == nil
            and SwingTimerMainHandFrame.parent == UIParent and RikUI.Layout.Groups.swingtimer == nil)
    end)
    restore()
    for _, name in ipairs(API) do _G[name] = saved[name] end
    Enum.PlayerSwingType = savedSwingEnum
    env.inCombat = false
    check("swing timer suite completes", ok, reason)
end
