-- Mirror timer values are probably readable on 69913 (unverified), so the suite checks the readable
-- path and that a secret progress reaches the StatusBar sink without arithmetic or a print.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local API = { "GetMirrorTimerInfo", "GetMirrorTimerProgress", "MirrorTimerContainer" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local restore = widgets.install()
    local stub = {}
    local function installClient()
        stub.progress, stub.info, stub.error = {}, {}, nil
        MirrorTimerContainer = CreateFrame("Frame", "MirrorTimerContainer", UIParent)
        GetMirrorTimerProgress = function(timer)
            if stub.error then error(stub.error) end
            return stub.progress[timer]
        end
        GetMirrorTimerInfo = function(index)
            local info = stub.info[index]
            if not info then return "UNKNOWN", 0, 0, 0, false, "" end
            return info[1], info[2], info[3], info[4], info[5], info[6]
        end
    end
    local function load(profile, combat, prepare)
        widgets.loadAddon(env, { "src/modules/mirrortimers/mirrortimers.lua" }, profile, combat, function()
            installClient()
            if prepare then prepare() end
        end)
        return RikUI.MirrorTimers
    end
    local function tick(bar) env.runScript(bar, "OnUpdate", 0.02) end
    local function parked(frame) return frame.parent == RikUIHiddenFrames and RikUI.Hide.IsHidden(frame) end
    local function offset(bar) return bar.points[1][5] end
    local ok, reason = pcall(function()
        local module = load()
        local holder, group, bars = module.Holder, RikUI.Layout.Groups.mirrortimers, module.Bars
        check("the timers register with the layout under key mirrortimers at the top of the screen", holder and group
            and group.frames[1] == holder and group.defaults.point == "TOP" and group.defaults.y < 0)
        check("three bars exist and none shows without a timer", #bars == 3 and bars[1].shown == false
            and bars[2].shown == false and bars[3].shown == false)

        env.fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0, "Breath")
        local breath = bars[1]
        check("a started timer shows a bar with its label, range and first value", breath.shown == true
            and breath.label.text == "Breath" and breath.bar.low == 0 and breath.bar.high == 60000
            and breath.bar.value == 60000 and breath.time.text == "1:00")
        check("the bar is flat, in the RikUI media, blue for breath, and fades in",
            breath.bar.texture == RikUI.Media.statusbar and #breath.rikBorder == 4
            and breath.bar.color[3] > breath.bar.color[1] and breath.fade.plays == 1
            and breath.label.fontPath == RikUI.Media.font)
        check("long timer labels reserve a bounded countdown column", breath.time.width == 52
            and breath.label.wordWrap == false and breath.label.points[2][2] == breath.time
            and breath.scrim and breath.timeBacking)
        stub.progress.BREATH = 30000
        tick(breath)
        check("an update feeds the progress and the seconds left", breath.bar.value == 30000
            and breath.time.text == "30" and not breath.pulse.playing)
        env.fire("MIRROR_TIMER_START", "BREATH", 29000, 60000, -1, 0, "Breath")
        check("a restart of a running timer reuses its bar without a second fade", module.Active.BREATH == breath
            and breath.fade.plays == 1 and bars[2].shown == false)

        env.fire("MIRROR_TIMER_START", "EXHAUSTION", 180000, 180000, -1, 0, "Fatigue")
        local fatigue = bars[2]
        check("a second timer stacks under the first in its own colour", fatigue.shown == true
            and offset(breath) == 0 and offset(fatigue) < 0 and fatigue.bar.color[1] > fatigue.bar.color[3])
        stub.progress.BREATH = 8000
        tick(breath)
        check("low time has a steady warning rail", breath.severity and breath.severity.color[1] == 1)
        check("a draining timer under ten seconds pulses", breath.pulse.playing == true and breath.time.text == "8")
        tick(breath)
        check("the pulse is not restarted while it runs", breath.pulse.plays == 1)
        env.fire("MIRROR_TIMER_STOP", "BREATH")
        check("a stopped timer hides its bar, stops the pulse and the rest restack", breath.shown == false
            and not breath.pulse.playing and module.Active.BREATH == nil and offset(fatigue) == 0)

        stub.progress.EXHAUSTION = 170000
        env.fire("MIRROR_TIMER_PAUSE", "EXHAUSTION", 1)
        tick(fatigue)
        check("a paused timer stops filling", fatigue.bar.value == 180000)
        env.fire("MIRROR_TIMER_PAUSE", "EXHAUSTION", 0)
        tick(fatigue)
        check("an unpaused timer fills again", fatigue.bar.value == 170000 and fatigue.time.text == "2:50")

        env.fire("MIRROR_TIMER_START", "BREATH", 5000, 60000, 10, 0, "Breath")
        check("a refilling timer takes the free bar and does not pulse", bars[1].shown == true
            and not bars[1].pulse.playing)

        stub.progress.EXHAUSTION = env.SECRET
        tick(fatigue)
        check("a secret progress reaches the sink and blanks the seconds silently", fatigue.bar.value == env.SECRET
            and fatigue.time.text == "" and #env.printed == 0)
        stub.error = "progress unavailable"
        tick(fatigue)
        tick(fatigue)
        check("a failing progress read is reported once and contained",
            widgets.printedContains(env, "Mirror timers progress") and #env.printed == 1)
        stub.error, env.printed = nil, {}

        env.fire("MIRROR_TIMER_START", "UNKNOWN", 1, 1, -1, 0, "")
        env.fire("MIRROR_TIMER_STOP", "DEATH")
        check("an unknown timer and a stop for an idle timer change nothing", bars[3].shown == false
            and #env.printed == 0)
        check("the stock container is parked once the bars exist", parked(MirrorTimerContainer))
        SlashCmdList.RIKUI("debug")
        check("debug reports the bar state", widgets.printedContains(env, "Mirror timers holder=true active=2"))

        module = load(nil, false, function() stub.pending = { "FEIGNDEATH", 200000, 360000, -1, false, "Feign Death" } end)
        check("a login without running timers shows none", module.Bars[1].shown == false)
        stub.info[1] = stub.pending
        stub.progress.FEIGNDEATH = 200000
        env.fire("PLAYER_ENTERING_WORLD")
        check("entering the world picks up a running timer", module.Bars[1].shown == true
            and module.Bars[1].label.text == "Feign Death" and module.Bars[1].bar.high == 360000)

        module = load(nil, true)
        env.fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0, "Breath")
        check("a combat login builds nothing, parks nothing and survives a timer event", module.Holder == nil
            and MirrorTimerContainer.parent == UIParent and #env.printed == 0)
        stub.info[1] = { "BREATH", 50000, 60000, -1, false, "Breath" }
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat builds the bars, picks up the running timer and parks the stock container",
            module.Holder ~= nil and module.Bars[1].shown == true and parked(MirrorTimerContainer))

        module = load(nil, false, function() GetMirrorTimerProgress, MirrorTimerContainer = nil, nil end)
        check("a client without the progress read builds nothing and says nothing", module.Holder == nil
            and #env.printed == 0)

        module = load({ modules = { mirrortimers = false } })
        check("a disabled module leaves the stock container untouched", module.Holder == nil
            and MirrorTimerContainer.parent == UIParent and RikUI.Layout.Groups.mirrortimers == nil)
    end)
    restore()
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("mirror timer suite completes", ok, reason)
end
