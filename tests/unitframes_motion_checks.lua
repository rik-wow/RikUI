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
    env.flushTimers()
    check("health event eases secret values without guessing damage", target.health.value == env.SECRET
        and target.health.easing == 2 and art.flash.plays == 0)
    env.fire("UNIT_POWER_UPDATE", "target")
    check("power update eases without a health flash", target.power.easing == 2 and art.flash.plays == 0)
    env.fire("UNIT_MAXHEALTH", "target")
    module.Refresh("target")
    check("maximum and full refresh do not flash", art.flash.plays == 0)
    env.fire("PLAYER_TARGET_CHANGED")
    check("new target starts immediately without carrying its old flash", target.health.easing == 0
        and target.power.easing == 0 and not art.flash.playing and tot.health.easing == 0)
    target:Hide()
    check("hide stops every motion", not art.fade.playing and not art.flash.playing and not pulse.playing)
    env.fire("UNIT_HEALTH", "target")
    env.flushTimers()
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
    env.flushTimers()
    check("failed read clears immediately without flashing", target.health.value == 0
        and target.health.easing == 0 and art.flash.plays == flashCount)
    units.target.error = nil
    env.fire("UNIT_HEALTH", "target")
    env.flushTimers()
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
    env.flushTimers()
    check("secret health token refreshes without inventing feedback", art.flash.plays == flashCount)
    env.fire("UNIT_TARGET", "target")
    check("ToT replacement resets easing", tot.health.easing == 0)
    local totFlashes = tot.motion.flash.plays
    env.runScript(tot, "OnUpdate", 0.6)
    check("ToT polling eases without flashing", tot.health.easing == 2 and tot.motion.flash.plays == totFlashes)
    env.fire("UNIT_PET", "player")
    env.fire("PLAYER_FOCUS_CHANGED")
    check("pet and focus replacement reset easing", pet.health.easing == 0 and frames.focus.health.easing == 0)

    -- All five solo frames use the same typed feedback, even with opaque health.
    for _, frame in pairs(frames) do
        local effects = frame.motion
        env.fire("UNIT_COMBAT", frame.unit, "HEAL", "", env.SECRET, env.SECRET)
        env.fire("UNIT_HEALTH", frame.unit)
        env.flushTimers()
        check(frame.key .. " healing uses the green glow", effects.heal and effects.heal.playing
            and effects.feedback.heal.region.color[2] > effects.feedback.heal.region.color[1])
        local fills, flashes = frame.health.sets, effects.flash.plays
        env.fire("UNIT_HEALTH", frame.unit)
        env.fire("UNIT_COMBAT", frame.unit, "WOUND", "", env.SECRET, env.SECRET)
        check(frame.key .. " holds damage fill and cue for the same batch",
            frame.health.sets == fills and effects.flash.plays == flashes)
        env.flushTimers()
        check(frame.key .. " commits damage fill with cue",
            frame.health.sets == fills + 1 and frame.health.easing == 0 and effects.flash.plays == flashes + 1)
        check(frame.key .. " damage replaces healing with the red flash", effects.flash.playing
            and effects.heal and not effects.heal.playing
            and effects.feedback.damage.region.color[1] > effects.feedback.damage.region.color[2])
    end
    check("healing is softer and slower than damage", art.heal and art.heal.alpha.Duration > art.flash.alpha.Duration
        and art.heal.alpha.FromAlpha < art.flash.alpha.FromAlpha)
    local damagePlays, healPlays = art.flash.plays, art.heal and art.heal.plays
    env.fire("UNIT_COMBAT", env.SECRET, "WOUND")
    env.fire("UNIT_COMBAT", "target", env.SECRET)
    env.fire("UNIT_COMBAT", "target", "BLOCK")
    check("unknown combat feedback is never broadcast or guessed", art.flash.plays == damagePlays
        and art.heal and art.heal.plays == healPlays)
    target:Hide()
    env.fire("UNIT_COMBAT", "target", "HEAL")
    check("hidden frames cannot start either cue", not art.flash.playing and art.heal and not art.heal.playing)
    target:Show()
    env.fire("UNIT_COMBAT", "target", "HEAL")
    env.fire("PLAYER_TARGET_CHANGED")
    check("replacement stops stale healing", art.heal and not art.heal.playing)

    env.flushTimers()
    damagePlays = art.flash.plays
    RikUI.Motion.StopHealthFeedback(art.feedback)
    env.fire("UNIT_HEALTH", "target")
    env.flushTimers()
    env.fire("UNIT_COMBAT", "target", "WOUND")
    env.flushTimers()
    check("late combat cannot flash after health already dropped", art.flash.plays == damagePlays)
    env.fire("UNIT_HEALTH", "target")
    env.flushTimers()
    check("expired combat cannot flash on a later health update", art.flash.plays == damagePlays)
    env.fire("UNIT_HEALTH", "target")
    env.fire("UNIT_COMBAT", "target", "WOUND")
    env.fire("UNIT_COMBAT", "target", "HEAL")
    env.flushTimers()
    check("mixed direction batch keeps eased fill without guessing", art.flash.plays == damagePlays
        and not art.heal.playing and target.health.easing == 2)
    env.fire("UNIT_COMBAT", "target", "WOUND")
    env.fire("UNIT_MAXHEALTH", "target")
    env.fire("UNIT_HEALTH", env.SECRET)
    env.flushTimers()
    check("maximum and secret-token events cannot time a damage cue", art.flash.plays == damagePlays)
    env.fire("UNIT_HEALTH", "target")
    env.fire("UNIT_COMBAT", "target", "WOUND")
    target:Hide()
    target:Show()
    env.flushTimers()
    check("hide invalidates queued damage", art.flash.plays == damagePlays)
    env.fire("UNIT_HEALTH", "target")
    env.fire("UNIT_COMBAT", "target", "WOUND")
    env.fire("PLAYER_TARGET_CHANGED")
    env.flushTimers()
    check("replacement invalidates queued damage", art.flash.plays == damagePlays)
    env.fire("UNIT_HEALTH", "target")
    env.fire("UNIT_COMBAT", "target", "WOUND")
    units.target.error = true
    env.flushTimers()
    check("failed health read suppresses queued damage", art.flash.plays == damagePlays)
    units.target.error = nil
    env.fire("UNIT_HEALTH", "target")
    env.flushTimers()
    env.fire("UNIT_COMBAT", "target", "WOUND")
    env.fire("UNIT_COMBAT", "target", "WOUND")
    env.fire("UNIT_HEALTH", "target")
    env.flushTimers()
    check("combat-first duplicate hits produce one synchronized cue", art.flash.plays == damagePlays + 1
        and target.health.easing == 0)

    Enum = nil
    env.fire("UNIT_HEALTH", "target")
    env.flushTimers()
    check("missing interpolation enum preserves direct fills", target.health.easing == nil and target.health.value == env.SECRET)
    Enum = { StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 2 } }
end
