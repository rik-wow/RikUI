# Mirror timers

`src/modules/mirrortimers/mirrortimers.lua` replaces the breath, fatigue and feign death bars. Up to
three flat bars stack at the top of the screen and `MirrorTimerContainer` is
parked through the shared hide helper once they exist. Disable the
`mirrortimers` module in `/rik config` and reload to get the stock bars back.

## What you see

Each bar is 220px wide and 16px tall on the dark backing with the 1px edge the
nameplates use. The label sits left and the time left sits right, both in the
RikUI font: seconds under a minute, `m:ss` above. Breath is blue, fatigue
yellow, feign death orange, anything else grey. A second and third timer stack
4px under the first; when one stops the rest move up.

## Motion

A bar fades in over 0.15s when its timer starts. A restart of a running timer
(the client sends one when the direction changes) reuses the bar without a
second fade. A draining timer with ten seconds or less left pulses a red
overlay until it stops or refills. The fill is set every frame from
`GetMirrorTimerProgress`, so it needs no easing.

## Events

`MIRROR_TIMER_START` carries the timer name, value, maximum, scale, paused
flag and label. The maximum goes into `SetMinMaxValues` in milliseconds and the
scale's sign decides whether the timer is draining. `MIRROR_TIMER_PAUSE` drops
or restores the bar's `OnUpdate`; `MIRROR_TIMER_STOP` frees the bar. A timer
that was already running at login sends no start event, so
`GetMirrorTimerInfo(1..3)` is scanned when the bars are built and on
`PLAYER_ENTERING_WORLD`.

## Layout

The holder is `RikUIMirrorTimers`, registered with the [shared layout](layout.md)
under `mirrortimers`: `/rik move`, `/rik move reset` and `/rik scale` apply.
The default is centred, 120px under the top of the screen.

## Stock frames and combat

The holder is built and `MirrorTimerContainer` parked inside one
`Combat.Queue` closure. The stock container's events are dropped when it is
parked, so it stops polling; they come back with a reload. At a combat login
nothing is touched until `PLAYER_REGEN_ENABLED`, and timer events before that
are ignored; the scan then picks up whatever is running. The bars are
unprotected, so they show, hide and restack in combat.

## Secret rules

Whether the progress is secret for addon code on 69913 is not verified. It
goes through `core.Secret.Apply` straight into `SetValue`, uncompared and in
milliseconds. The seconds text and the low-time check run under `pcall`: a
secret blanks the text and never pulses. A failing read prints one
`Mirror timers progress` line.

## Diagnostics

`/rik debug` prints `Mirror timers holder=<bool> active=<n>`.

## Verification

`tests/mirrortimers.test.lua` proves: the layout key and default; three hidden
bars; a start showing label, range, value, colour, media and fade; an update
feeding progress and seconds; a restart reusing the bar; stacking and
restacking; the low pulse starting once and stopping; pause and resume; a
refilling timer not pulsing; a secret progress reaching the sink silently; a
failing read reported once; unknown timers ignored; the stock container
parked; the debug line; a running timer picked up on entering the world; a
combat login deferring everything; a client without the progress read; a
disabled module.

The stub cannot show the look or settle whether the progress is secret. Beta
checklist:

1. Fully restart the client (new TOC entry). Swim under water: a blue `Breath`
   bar appears at the top, counts down and the stock bar does not.
2. Stay under until ten seconds remain: the bar pulses red. Surface: it
   refills without pulsing and goes.
3. As a hunter, feign death: an orange bar. Swim into fatigue water: a yellow
   one stacked under any other.
4. `/rik move`, drag the timers, lock, reload.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Mainline/MirrorTimer.lua: the three events, GetMirrorTimerInfo and GetMirrorTimerProgress](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_MirrorTimer/Mainline/MirrorTimer.lua)
- [Mainline/MirrorTimer.xml: MirrorTimerContainer and its three timer frames](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_MirrorTimer/Mainline/MirrorTimer.xml)
