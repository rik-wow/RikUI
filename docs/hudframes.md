# Small HUD frames

`src/modules/hudframes/hudframes.lua` covers two small stock frames that were left over: the queue
status tooltip and the framerate label. Disable the `hudframes` module in
`/rik config` and reload for the stock look.

## Queue status tooltip

`QueueStatusFrame` is the panel that appears when you hover the group finder
eye on the [minimap](minimap.md) while queued. It inherits
`TooltipBackdropTemplate`. On its first show the module fades its `NineSlice`,
adds the flat fill and one-pixel edge and creates a 0.15s fade-in, which is
replayed on every show.

The panel fills from `statusEntriesPool`, a pool of `QueueStatusEntryTemplate`
frames, one per queue. The pool hands entries out as queues come and go, so on
every show the active entries' `Title`, `Status`, `SubTitle`, `TimeInQueue`,
`AverageWait` and `ExtraText` get the RikUI typeface at their own sizes.
Colours and the role icons stay Blizzard's.

A skin that raises prints one `HUD frames skin QueueStatusFrame: <reason>`
line and the frame is not retried.

## Framerate label

`FramerateFrame` (Ctrl+R by default) is two font strings, `Label` and
`FramerateText`. They get the typeface at login. There is no art to remove.

## Quest navigation marker

`SuperTrackedFrame` is the on-screen marker that points at the tracked quest.
Only its `DistanceText` takes the typeface, once at login. The icon, its ring
and the arrow are the marker itself and stay.

## What is not written

Neither frame is moved, resized, reparented, shown, hidden or given a new
script. Only alpha, fonts and new child regions are written, none of which is
protected.

## Diagnostics

`/rik debug` prints `HUD frames hooked=<n> skinned=<n> fonts=<n>`.

## Verification

`tests/hudframes.test.lua` proves: nothing skinned before the tooltip shows;
the faded nine-slice with fill, edge and fade-in; entry typefaces at their own
sizes with colours untouched; a second show fading again with one fill and
restyling an entry made later; no move, resize or script; the framerate
strings restyled at login without the frame being shown; nothing printed; the
debug line; a refused skin reported once and not retried; a tooltip without a
pool; a tooltip already showing at login; missing frames; the disabled module.

The stub cannot settle whether Blizzard re-applies font objects to pooled
entries after the show hook runs. Beta checklist:

1. Fully restart the client (new TOC entries). Queue for a battleground or a
   dungeon and hover the eye: flat panel, RikUI typeface, fade-in.
2. Press Ctrl+R: the framerate label in the RikUI typeface.
3. `/rik debug` should print the `HUD frames` line.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Mainline/QueueStatusFrame.xml: QueueStatusFrame on TooltipBackdropTemplate and the entry template's strings](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_QueueStatusFrame/Mainline/QueueStatusFrame.xml)
- [Mainline/QueueStatusFrame.lua: statusEntriesPool](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_QueueStatusFrame/Mainline/QueueStatusFrame.lua)
- [Mainline/FramerateFrame.xml: Label and FramerateText](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FramerateFrame/Mainline/FramerateFrame.xml)
