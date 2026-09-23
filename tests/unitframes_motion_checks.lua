-- Motion assertions share the unit-frame fixture and its secret-value recording sinks.
return function(check, env, module, units)
    local frames = module.Frames
    local target, tot, pet = frames.target, frames.tot, frames.petframe
    local art = target.motion
    check("appearance uses a short fade", art.fade.alpha.FromAlpha == 0 and art.fade.alpha.ToAlpha == 1
        and art.fade.alpha.Duration == 0.15 and art.fade.plays == 1)
    check("initial fill never flashes", art.flash.plays == 0)
    local pulse = art.pulses[1]
    check("readable threat starts a bouncing edge pulse", pulse.playing and pulse.looping == "BOUNCE")
    module.UpdateThreat(target)
    check("repeated threat refresh does not restart pulse", pulse.plays == 1)
    env.fire("UNIT_HEALTH", "target")
    check("health event eases secret values untouched and flashes", target.health.value == env.SECRET
        and target.health.easing == 2 and art.flash.plays == 1)
    env.fire("UNIT_POWER_UPDATE", "target")
    check("power update eases without a health flash", target.power.easing == 2 and art.flash.plays == 1)
    env.fire("UNIT_MAXHEALTH", "target")
    module.Refresh("target")
    check("maximum and full refresh do not flash", art.flash.plays == 1)
    env.fire("PLAYER_TARGET_CHANGED")
    check("new target starts immediately without carrying its old flash", target.health.easing == 0
        and target.power.easing == 0 and not art.flash.playing and tot.health.easing == 0)
    target:Hide()
    check("hide stops every motion", not art.fade.playing and not art.flash.playing and not pulse.playing)
    env.fire("UNIT_HEALTH", "target")
    module.UpdateThreat(target)
    check("hidden updates cannot restart flash or threat", not art.flash.playing and not pulse.playing)
    target:Show()
    check("show refreshes immediately and fades with threat restored", target.health.easing == 0
        and target.power.easing == 0 and art.fade.plays == 2 and pulse.playing)
    env.fire("PLAYER_TARGET_CHANGED")
    check("replacement after OnShow preserves the appearance fade", art.fade.playing and art.fade.plays == 2)
    local flashCount = art.flash.plays
    units.target.error = true
    env.fire("UNIT_HEALTH", "target")
    check("failed read clears immediately without flashing", target.health.value == 0
        and target.health.easing == 0 and art.flash.plays == flashCount)
    units.target.error = nil
    env.fire("UNIT_HEALTH", "target")
    check("first fill after reader recovery is immediate", target.health.easing == 0 and art.flash.plays == flashCount)
    units.target.threat = env.SECRET
    module.UpdateThreat(target)
    check("secret threat stops its pulse", not pulse.playing and not target.threat[1].shown)
    units.target.threat = 0
    module.UpdateThreat(target)
    check("zero threat stays stopped", not pulse.playing)
    units.target.threat = 3
    module.UpdateThreat(target)
    env.fire("UNIT_HEALTH", env.SECRET)
    check("secret event token safely refreshes and flashes all initialized frames", art.flash.plays == flashCount + 1)
    env.fire("UNIT_TARGET", "target")
    check("ToT replacement resets easing", tot.health.easing == 0)
    local totFlashes = tot.motion.flash.plays
    env.runScript(tot, "OnUpdate", 0.6)
    check("ToT polling eases without flashing", tot.health.easing == 2 and tot.motion.flash.plays == totFlashes)
    env.fire("UNIT_PET", "player")
    env.fire("PLAYER_FOCUS_CHANGED")
    check("pet and focus replacement reset easing", pet.health.easing == 0 and frames.focus.health.easing == 0)
    Enum = nil
    env.fire("UNIT_HEALTH", "target")
    check("missing interpolation enum preserves direct fills", target.health.easing == nil and target.health.value == env.SECRET)
    Enum = { StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 2 } }
end
