# Screen text

`src/modules/screentext/screentext.lua` puts the RikUI font on the text Blizzard writes across the
middle of the screen: the zone name when you cross a border, the subzone and
PvP lines under it, the red error line ("Out of range"), the auto-follow
notice and raid warnings. Fonts only. No frame is moved, hidden or rescripted,
and Blizzard's fades and colours stay. Disable the `screentext` module in
`/rik config` and reload for the stock fonts.

## What is written

Zone and error text have font objects of their own, so the module restyles the
objects and every string that inherits them follows:

| Font object | Used by | Fallback size |
|---|---|---|
| `ZoneTextFont` | `ZoneTextString` | 32 |
| `SubZoneTextFont` | `SubZoneTextString` | 26 |
| `PVPInfoTextFont` | `PVPInfoTextString`, `PVPArenaTextString` | 22 |
| `ErrorFont` | `UIErrorsFrame` | 16 |

Each gets `SetFont(RikUI font, <its current size>, "OUTLINE")`. The size comes
from the object's own `GetFont`, so Blizzard's proportions stay; the fallback
is used only when the client reports no size. `AutoFollowStatusText` is a lone
font string and is restyled directly.

## Raid warnings

On this client `RaidWarningFrame` is a slot system: lines come from
`CreateFontStringPool` on `GameFontNormalHuge` through `AcquireOrEvictSlot` and
grow and shrink with `SetTextHeight`. `GameFontNormalHuge` is shared by
headings all over the UI, so it is left alone. `AcquireOrEvictSlot` is
post-hooked on the frame, and after each call the pool's active strings that
have not been seen before get the font, remembered in a weak table because the
pool reuses its strings. `SetTextHeight` scaling works on any font.

## Failure and combat

Font writes are not protected, so the module restyles at login even in combat.
Every write runs under `pcall`; a refused font prints one
`Screen text font <name>` line and the rest still restyle. A missing font
object, a missing `RaidWarningFrame` or one without `AcquireOrEvictSlot` is
skipped silently.

## Not covered

Floating combat text, chat bubbles and the boss emote frame are left stock.
None of them was examined for this module.

## Diagnostics

`/rik debug` prints `Screen text fonts=<n> warnings=<n>`.

## Verification

`tests/screentext.test.lua` proves: the four font objects and the auto-follow
text restyled with the outline at their own sizes; `GameFontNormalHuge`
untouched; a raid warning line restyled as it is handed out, a reused line
only once; silence on a clean restyle; the debug line; a combat login; a
refused font reported once with the rest restyled; the fallback size; missing
objects and a missing or different raid warning frame; a disabled module.

The stub cannot show the look. Beta checklist:

1. Fully restart the client (new TOC entry). Walk across a zone border: the
   zone and subzone names appear in the RikUI font at about the old size.
2. Cast something out of range: the red error line is in the RikUI font.
3. In a group with assist, send `/rw test`: the warning is in the RikUI font
   and still grows and shrinks.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_FrameXML/Mainline/ZoneText.xml: the zone strings and the font objects they inherit](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/Mainline/ZoneText.xml)
- [Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.xml: the message frame on ErrorFont](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.xml)
- [Blizzard_RaidWarning/RaidWarning.lua: the font string pool on GameFontNormalHuge and AcquireOrEvictSlot](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_RaidWarning/RaidWarning.lua)
