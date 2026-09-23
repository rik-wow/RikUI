return function(check, env, module, group, units, prefix)
    local one, two = group.Frames[1], group.Frames[2]
    local art = one.motion
    check(prefix .. " opts into shared motion", art ~= nil and one.health.motionEnabled == true)
    if not art or not one.presentation then return end
    check(prefix .. " first fill is immediate", one.health.easing == 0 and one.power.easing == 0)
    check(prefix .. " visual sibling cannot catch clicks", one.presence.owner == group.Holder
        and one.presence.template == nil and one.presentation.owner == one.presence
        and one.health.owner == one.presentation and one.presence.mouseEnabled == false)
    env.fire("UNIT_HEALTH", one.unit)
    check(prefix .. " secret fill eases and flashes", one.health.value == env.SECRET
        and one.health.easing == 2 and art.flash.plays == 1)
    env.fire("UNIT_POWER_UPDATE", one.unit)
    check(prefix .. " power eases without flashing", one.power.easing == 2 and art.flash.plays == 1)
    local range = two.motion.range
    check(prefix .. " initial range target is direct", two.presentation.alpha == group.FadeAlpha)
    units[two.unit].inRange = true
    group.UpdateRange(two)
    check(prefix .. " readable range change tweens", range.playing and range.alpha.FromAlpha == group.FadeAlpha
        and range.alpha.ToAlpha == 1 and range.alpha.Duration == 0.15)
    local plays = range.plays
    group.UpdateRange(two)
    check(prefix .. " unchanged poll keeps tween", range.plays == plays)
    units[two.unit].inRange = env.SECRET
    group.UpdateRange(two)
    check(prefix .. " secret range cancels tween and reaches sink", not range.playing
        and two.presentation.fromBoolean[1] == env.SECRET)
    units[two.unit].inRange = false
    group.UpdateRange(two)
    check(prefix .. " readable recovery does not inspect secret alpha", two.presentation.alpha == group.FadeAlpha
        and range.plays == plays)
    local savedMember = units[one.unit]
    local beforeRemoval = one.health.sets
    units[one.unit] = nil
    env.fire("GROUP_ROSTER_UPDATE")
    check(prefix .. " roster removal before secure hide preserves departing art", one.health.sets == beforeRemoval)
    units[one.unit] = savedMember
    one:Hide()
    local lastValue, fills = one.health.value, one.health.sets
    check(prefix .. " leave hides button immediately but fades art", not one:IsShown()
        and one.presence:IsShown() and art.leave.playing and not art.flash.playing)
    env.fire("UNIT_HEALTH", one.unit)
    env.fire("GROUP_ROSTER_UPDATE")
    check(prefix .. " departing art is frozen", one.health.value == lastValue and one.health.sets == fills)
    one:Show()
    check(prefix .. " rejoin cancels leave and resets fills", not art.leave.playing and art.fade.playing
        and one.health.easing == 0 and one.power.easing == 0)
    art.leave:Finish()
    check(prefix .. " stale leave completion cannot hide rejoined art", one.presence:IsShown())
    one:Hide()
    art.leave:Finish()
    check(prefix .. " completed departure hides art", not one.presence:IsShown())
    one:Show()
    env.fire("GROUP_ROSTER_UPDATE")
    check(prefix .. " roster replacement resets fill without cancelling join", one.health.easing == 0
        and art.fade.playing)
    local wasCombat = env.inCombat
    env.inCombat = true
    -- Simulate the secure driver, then invoke only the addon callbacks in combat.
    one.shown = false
    env.runScript(one, "OnHide")
    check(prefix .. " combat departure starts visual fade", art.leave.playing)
    art.leave:Finish()
    check(prefix .. " combat departure finishes without showing the button", not one:IsShown()
        and not one.presence:IsShown())
    one.shown = true
    env.runScript(one, "OnShow")
    check(prefix .. " combat join refreshes visual sinks", one.presence:IsShown() and one.health.easing == 0)
    env.inCombat = wasCombat
end
