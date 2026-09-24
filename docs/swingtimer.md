# Weapon timers

RikUI replaces Forever's three native swing bars with dark, readable main-hand,
off-hand and ranged bars. All ranged weapons use the same event-driven timer;
there is no hunter-class restriction. Disable the module to restore Blizzard's
frames.

**Fully exit and restart the client after this update** to load the new kiting
companion file.

## Reading the ranged bar

The fill advances smoothly every rendered frame from the last native
`PLAYER_SWING` duration. The number counts down that expected cycle. It updates
only when its displayed tenth changes. A thin amber line marks the start of the
adjustable stop window; the shaded final section is an advisory margin.

- **Move window:** before the stop margin, with readable cast state and a target
  in ranged-weapon range.
- **Stop moving / Hold for shot:** within the stop margin. Stop and wait for the
  shot before moving again.
- **Casting - hold:** the client currently exposes a player cast or channel.
- **Wait for shot:** awaiting the first event, a delayed shot, or fresh timing
  after melee interaction or a speed change. The number becomes `--` after the
  expected cycle. No additional shot or retry is invented.
- **Out of range / Range unknown:** current native range evidence. These do not
  distinguish too close, too far, facing, or line of sight.
- **Cast state unknown:** unavailable or restricted cast data; no move cue.

Auto-repeat keeps the ranged row visible while waiting. Stopping it clears the
row and its animations. A manual ranged attack also shows its native cycle, then
expires after a short linger. Death, weapon changes and entering the world clear
stale timelines. Melee events during auto-repeat retract ranged movement advice
until another ranged event arrives; they never manufacture a ranged deadline.
Cast or movement restrictions are respected rather than reconstructed.

In `/rik config`, **Weapon timers** offers **Ranged kiting cues** and
**Stop lead time (seconds)**, saved per profile. The default 0.6-second lead is a
conservative user-adjustable aid around the intended 0.5-second base wind-up;
it is not measured wind-up, latency compensation or a hidden retry clock. Adjust
for your haste and connection. Cues never move the player or fire an ability.

## Layout and readability

Rows are 200 by 18 pixels with an inset fill, separate bounded label and number,
a subtle pulse below the text, and a spark. The holder reserves all three rows
plus the cue (200 by 76), so layout collision checks see the full footprint.
Centered places the timer above the player, clear of the target's upward aura
column. Existing positions that exactly match the old shipped Centered position
migrate; custom positions are preserved. Use `/rik move` to reposition it.

Range checking is enabled after parking the native frames so their teardown
cannot cancel the request. Unknown range is distinct from out of range. Fill
interpolation uses the absolute clock; auxiliary cast/movement reads poll at
20 Hz between relevant events and stop when cues are off.

## Evidence and limits

Research checked September 23, 2026:

- [Blizzard: Auto-shoot Bug and Fix Incoming](https://us.forums.blizzard.com/en/wow/t/auto-shoot-bug-and-fix-incoming/2359185):
  Kaivax confirms the intended half-second hunter/wand wind-up is currently
  shortened by a bug and announces a future beta fix. Replies ask for cast and
  retry visibility. No exact current broken duration is published.
- [Forever hunter testers](https://github.com/classic-hunter/forever-hunter/wiki/Forever-Beta-Changes)
  report melee resetting ranged timing and a hidden retry mechanism. These are
  beta observations, not a stable server contract.
- [Player weaving report](https://www.reddit.com/r/classicwow/comments/1wjcl8w/feedback_hunter_weaving_removed/)
  describes inconsistent delays when alternating melee and ranged. It motivates
  retracting stale advice rather than assuming independent Classic Era timers.
- Pinned [native swing API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SwingTimerDocumentation.lua)
  and [stock implementation](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SwingTimer/Blizzard_SwingTimer.lua)
  supply duration/type and range state, but no wind-up or retry phase.
  The addon therefore does not claim frame-perfect server readiness.

Automated tests cover frame-rate interpolation, manual and auto ranged cycles,
movement/cast interruption, late shots, melee interaction, haste invalidation,
range loss and unknown/secret values, profile persistence, cleanup and stock
replacement. Layout audits cover the four presets at multiple aspect ratios.
Native acceptance is supplied by the user's standing policy; no agent-observed
gameplay test is claimed.
