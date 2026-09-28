-- Swing bars run on the PLAYER_SWING duration and the clock alone; the suite drives GetTime by hand.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local API = { "GetTime", "C_SwingTimer", "SwingTimerMainHandFrame", "SwingTimerOffHandFrame",
        "SwingTimerRangedFrame", "UnitCastingInfo", "UnitChannelInfo", "GetUnitSpeed", "UnitClass" }
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
        stub.cast, stub.channel, stub.speed, stub.reads = nil, nil, 0, 0
        UnitCastingInfo = function() stub.reads=stub.reads+1;return stub.cast end
        UnitChannelInfo = function() return stub.channel end
        GetUnitSpeed = function() return stub.speed end
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
        widgets.loadAddon(env, { "data/layouts.lua", "src/modules/swingtimer/swingtimer.lua", "src/modules/swingtimer/swingtimer-kiting.lua" }, profile, combat, function()
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
        check("full three-row footprint includes the cue and subdued fill",holder.height==76 and main.height==18
            and main.bar.color[1]<0.5 and main.flashAnim.animation.from<=0.1
            and main.flash.layer=="ARTWORK" and main.label.width+main.time.width<holder.width)
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
        check("an off hand swing stacks a second bar over the first", off.shown == true and offset(main) == 16
            and offset(off) > 0 and off.bar.color[1] ~= main.bar.color[1])
        advance(main, 2.6)
        advance(main, 0.7)
        check("a bar past its linger clears and the rest restack", main.shown == false and offset(off) == 16
            and main:GetScript("OnUpdate") == nil)

        env.printed = {}
        env.fire("PLAYER_SWING", math.huge, MAIN)
        env.fire("PLAYER_SWING", 0/0, MAIN)
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

        stub.inRange[RANGED]=true
        UnitClass=function() error("timers must not gate on hunter class") end
        env.fire("START_AUTOREPEAT_SPELL")
        check("auto-repeat start waits for native timing without an invented first shot",ranged.shown and not ranged.endTime
            and ranged.cue.text=="Wait for shot" and ranged.time.text=="--")
        env.fire("PLAYER_SWING",3,RANGED)
        check("any ranged weapon gains a movement window and stop marker",ranged.cue.text=="Move window"
            and near(ranged.window.width,55.6) and ranged.marker.shown and near(ranged.bar.value,0))
        local endpoint=ranged.endTime
        advance(ranged,1/120)
        local firstFill=ranged.bar.value
        advance(ranged,1/120)
        check("fill advances every frame without resetting the event deadline",ranged.bar.value>firstFill and ranged.endTime==endpoint)
        stub.now=endpoint-0.5;stub.speed=7
        env.runScript(ranged,"OnUpdate",0)
        check("moving in the stop window gets an explicit stop cue",ranged.cue.text=="Stop moving")
        stub.speed=0;env.fire("PLAYER_STOPPED_MOVING");env.runScript(ranged,"OnUpdate",0)
        check("stationary stop window asks to hold for the shot",ranged.cue.text=="Hold for shot")
        stub.cast="Shoot";env.fire("UNIT_SPELLCAST_START","player");env.runScript(ranged,"OnUpdate",0)
        check("observed player casting suppresses movement advice",ranged.cue.text=="Casting - hold")
        stub.cast=nil;env.fire("UNIT_SPELLCAST_INTERRUPTED","player")
        advance(ranged,2)
        check("late or interrupted auto remains waiting without synthetic retries",ranged.shown
            and ranged.endTime==endpoint and ranged.cue.text=="Wait for shot" and ranged.time.text=="--")
        env.fire("PLAYER_SWING_RANGE_UPDATE",RANGED,false,true);advance(ranged,0.1)
        check("out of range is distinct from a ready shot",ranged.cue.text=="Out of range" and ranged.bar.alpha<1)
        env.fire("PLAYER_SWING_RANGE_UPDATE",RANGED,false,false);advance(ranged,0.1)
        check("unchecked range remains unknown",ranged.cue.text=="Range unknown" and ranged.bar.alpha==1)
        env.fire("PLAYER_SWING_RANGE_UPDATE",RANGED,env.SECRET,true);advance(ranged,0.1)
        check("secret range cannot become permission to fire",ranged.inRange==nil and ranged.cue.text=="Range unknown")
        env.fire("PLAYER_SWING",2.2,RANGED)
        check("next real event resynchronizes the cooldown",ranged.cue.text=="Move window" and near(ranged.endTime,stub.now+2.2))
        env.fire("PLAYER_SWING",2.6,MAIN)
        check("melee interaction retracts stale ranged movement advice",not ranged.endTime and ranged.cue.text=="Wait for shot"
            and main.endTime~=nil)
        local mainEnd=main.endTime
        env.fire("PLAYER_SWING",2.2,RANGED)
        check("ranged event leaves melee timing independent",main.endTime==mainEnd)
        env.fire("UNIT_ATTACK_SPEED","player")
        check("haste changes await a fresh native ranged deadline",not ranged.endTime and ranged.cue.text=="Wait for shot")
        env.fire("PLAYER_SWING",1.4,RANGED)
        stub.cast=env.SECRET;env.fire("UNIT_SPELLCAST_START","player");advance(ranged,0.1)
        check("secret cast state never produces a movement cue",ranged.cue.text=="Cast state unknown")
        stub.cast=nil
        module.Options.settings[1].set(false)
        local beforeReads=stub.reads
        advance(ranged,0.1)
        check("turning cues off hides advisory art and stops its polling",not ranged.cue.shown
            and not ranged.window.shown and not ranged.marker.shown and stub.reads==beforeReads)
        module.Options.settings[1].set(true)
        module.Options.settings[2].set(0.25);advance(ranged,0.1)
        check("stop lead is configurable without changing the native deadline",near(module.Kiting.Lead(),0.25))
        module.Options.settings[2].set(env.SECRET);module.Options.settings[2].set(0/0)
        check("invalid lead input preserves the preference",near(module.Kiting.Lead(),0.25))
        env.fire("STOP_AUTOREPEAT_SPELL")
        check("stopping auto-repeat clears stale timer and animations",not ranged.shown and not ranged:GetScript("OnUpdate")
            and not ranged.flashAnim:IsPlaying() and ranged.flash.alpha==0)
        env.fire("PLAYER_SWING",2,RANGED)
        env.fire("PLAYER_SWING",2.6,MAIN)
        check("manual ranged advice also retracts after a melee swing",not ranged.shown)
        env.fire("PLAYER_SWING",2,RANGED)
        advance(ranged,2.7)
        check("manual ranged attacks work without auto-repeat events and expire",not ranged.shown)
        env.fire("START_AUTOREPEAT_SPELL");env.fire("PLAYER_SWING",2,RANGED)
        env.fire("WEAPON_SLOT_CHANGED")
        check("weapon changes clear all old weapon timelines",not ranged.shown and not main.shown and not off.shown and not module.Kiting.auto)
        env.fire("START_AUTOREPEAT_SPELL");env.fire("PLAYER_DEAD")
        check("death clears waiting guidance",not ranged.shown and not module.Kiting.auto)

        module = load(nil, false, function() stub.rangeError = "range check refused" end)
        check("a refused range check is reported once and the bars still build", module.Holder ~= nil
            and widgets.printedContains(env, "Swing timer range check") and #env.printed == 1, table.concat(env.printed, " | "))

        module = load({ positions = { swingtimer = { point="BOTTOM", relativePoint="BOTTOM", x=0, y=336 } } })
        check("old shipped timer position migrates clear of target auras",RikUI.Profile.positions.swingtimer.x==RikUI.Layouts.centered.positions.swingtimer.x
            and RikUI.Profile.positions.swingtimer.y==RikUI.Layouts.centered.positions.swingtimer.y
            and RikUI.Profile.positions.swingtimer.point=="BOTTOM")
        module = load({ positions = { swingtimer = { point="BOTTOM", relativePoint="BOTTOM", x=42, y=336 } } })
        check("custom weapon timer positions survive migration",RikUI.Profile.positions.swingtimer.x==42)
        module = load({ swingtimer = { kiting=false, stopLead=0.35 } })
        check("kiting preferences survive profile reload",not module.Kiting.Enabled() and near(module.Kiting.Lead(),0.35))

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
