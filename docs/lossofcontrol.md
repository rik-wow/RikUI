# Loss of control

`src/modules/lossofcontrol/lossofcontrol.lua` gives Blizzard's loss-of-control alert the RikUI look: the
"Stunned 3.2 seconds" banner in the middle of the screen. The frame stays
Blizzard's, so which effect is shown, for how long and with what text is still
decided by Blizzard's code. Disable the `lossofcontrol` module in `/rik config`
and reload for the stock alert.

## What you see

A flat dark panel, 256 by 58 like the shadow it replaces, with a one-pixel edge
and a thin red line along its top and bottom. The icon is cropped and has its
own one-pixel edge. The effect name and the countdown use the RikUI typeface at
Blizzard's sizes and keep Blizzard's colours. The cooldown sweep on the icon is
Blizzard's.

## Animations

- The panel fades in over 0.15s each time the alert appears.
- The two red lines pulse between full and 35% while the alert is up, and stop
  when it hides.
- Blizzard's own intro (the icon bumps, the text scales in) and the fade-out of
  short alerts are untouched.

## Why the frame's alpha is never written

`LossOfControlMixin:OnUpdate` calls `self:SetAlpha` every frame: 1 while an
effect lasts, a falling value while a short alert fades out. A fade-in tween on
the frame would fight that write, so the fade and the pulse run on RikUI's own
textures. Blizzard's red glow lines only have their scale animated, so fading
them once with `SetAlpha(0)` lasts.

## Secret values

None are read. The module never calls `C_LossOfControl`, never reads the icon,
the text or the time, and never compares anything. It writes region alpha, a
texture crop, fonts and new regions on a frame that is not protected.

## Known rough edge

The icon's edge is anchored to the icon. Blizzard's 0.2s intro moves and scales
the icon with an animation, and an animation does not move regions anchored to
the animated one, so the edge stands still for that moment while the icon
bumps.

## Diagnostics

`/rik debug` prints `LossOfControl skinned=<true|false>`.

## Verification

`tests/lossofcontrol.test.lua` builds the frame with its 69913 keys. It proves:
the three art pieces faded; the panel's size, anchor and edge; the red lines;
the cropped icon and its edge; the typeface with sizes and colours kept; fade
and pulse on show, pulse stopped on hide, fade again on the next show; the
frame's alpha, position, size and scripts never written; the debug line; a
client without the frame; one failure report with no panel; the disabled
module. The suite was seen red before the module existed.

The stub cannot show how it looks or whether the client's animation system
lets the pulse run while Blizzard's intro plays. Beta checklist:

1. Fully restart the client (new TOC entry). Get stunned, feared or silenced
   (a murloc net, a warlock in a duel, or an interrupt on your cast).
2. The banner should be a flat panel with two pulsing red lines, a cropped icon
   with a thin edge, and RikUI text with the countdown running.
3. An interrupt shows a short alert: it should fade out on Blizzard's timing.
4. Edit Mode still shows a sample alert; check it looks the same.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [LossOfControlFrame.xml: blackBg, RedLineTop, RedLineBottom, Icon, AbilityName, Cooldown, TimeLeft and the Anim group](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/LossOfControlFrame.xml)
- [LossOfControlFrame.lua: OnUpdate's SetAlpha, SetUpDisplay and UpdateDisplay](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/LossOfControlFrame.lua)
