# Alert toasts

Notification cards now include a gold accent rail with a 240ms child-region entrance and a dark icon shelf. Native frame entry/exit and text hierarchy remain authoritative. References below to no tween concern native frame alpha. See [banners](banners.md) for shared card behavior and user-provided native acceptance.

`src/modules/alerts/alerts.lua` gives Blizzard's alert toasts the flat RikUI look: the "You won"
loot toast, money, new recipes, achievements where the client has them, and
every other toast the alert system shows. The toasts stay Blizzard's: their
position, stacking, queueing, click behaviour, tooltips and slide and fade
animations are untouched. Disable the `alerts` module in `/rik config` and
reload for the stock toasts.

## What you see

A flat dark panel with a one-pixel edge in place of the gilded toast art, the
icon cropped like an action button with its own one-pixel edge, and the text in
the RikUI typeface at Blizzard's sizes. Text colours are Blizzard's, so an item
name keeps its quality colour and the label stays gold. There is no glow burst
and no sheen sweep. The toast still fades in and out on Blizzard's timing.

## How it works

Every alert subsystem, queued or simple, ends in the global
`AlertFrame_ShowNewAlert(frame)`, which shows the toast and plays `animIn`,
`glow.animIn` and `shine.animIn`. The module post-hooks that one function, so
no template is named and a toast from a system added later is covered too.

Once per toast:

- a fill and four edge lines 8px inside the frame, because the toast art keeps
  a transparent margin around its panel;
- the icon cropped and framed. The icon is `frame.Icon`, `frame.lootItem.Icon`
  or, on achievement-style toasts, `frame.Icon.Texture`; the lines are created
  on the toast and anchored one pixel outside the icon texture, because they
  sit in a lower layer and the icon would cover them at its own bounds;
- `SetFont` with the RikUI font on every font string among the toast's and its
  `lootItem`'s regions, at the size each string reports. `SetTextColor` is
  never called.

On every show:

- `Background`, `PvPBackground`, `RatedPvPBackground`, `BGAtlas`, `IconBorder`,
  `Border`, `IconBG` and `Watermark` get alpha 0 where they exist, and the icon
  holder's `Overlay`, `Bling`, `IconBorder` and `Border` too. A `SetUp` may set
  a new texture or atlas on them; alpha survives that, and the repeat covers a
  `SetAlpha` a template may do.
- `glow` and `shine` get `SetTexture(nil)`. Blizzard animates their alpha, so a
  fade would come back; an empty texture cannot.

A toast is a pooled frame. Fill, edge and typeface are kept in a weak table so
a reused toast is decorated once. A skin that raises prints one
`Alerts skin: <reason>` line and that toast is left alone afterwards; Blizzard
has already shown it by then.

Nothing is moved, resized, reparented, shown, hidden or rescripted, and none of
the writes is protected, so a toast in combat is safe.

## Not covered

Group loot roll frames are part of the [loot](loot.md) module. The bonus roll
frame, the level-up banner and boss banners are not alert frames. Art on keys
other than the ones listed (leaves, light rays, mission portraits) stays, which
on this client should only matter for toasts Forever never fires.

## Diagnostics

`/rik debug` prints `Alerts hooked=<true|false> skinned=<n> failed=<n>`.

## Verification

`tests/alerts.test.lua` builds a loot toast with a `lootItem` child, a money
toast and an achievement-style toast with the 69913 keys. It proves: Blizzard's
show and intro still run; backgrounds faded with an inset fill and edge; glow
and shine blanked with no alpha write; the loot icon cropped, its border faded
and an edge anchored to the icon; the typeface at each string's size with the
colour untouched; no move, resize, script or tween; one fill on a reused toast
with restored art removed again; the icon on the frame itself; the icon frame
with overlay and bling; a toast with no optional key; a toast in combat; the
debug line; a refused write reported once, not retried and the toast still
shown; a client without the alert system; the disabled module.

The stub cannot settle these: which toasts Forever fires at all, whether 8px
matches the visible panel on each template, whether a `SetUp` re-applies a
font object after the first show, and whether `SetTexture(nil)` on the glow
survives `SetAtlas` calls in a `SetUp`. Beta checklist:

1. Fully restart the client (new TOC entry). Win a group loot roll or loot
   money in a group: flat toast, cropped icon, quality-coloured name, no glow.
2. Learn a profession recipe: flat recipe toast.
3. Let two toasts stack and hover one: it should pause and show its tooltip as
   before; right-click dismisses it.
4. `/rik debug` should print the `Alerts` line with `failed=0`.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_FrameXML.toc: AlertFrames and AlertFrameSystems load, with a camelot override file](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/Blizzard_FrameXML.toc)
- [Mainline/AlertFrames.lua: AlertFrame_ShowNewAlert and the intro animations on glow and shine](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/Mainline/AlertFrames.lua)
- [Mainline/AlertFrameSystems.xml: the money and loot toast keys and sizes](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/Mainline/AlertFrameSystems.xml)
- [Mainline/AlertFrameSystems.lua: the subsystem list](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/Mainline/AlertFrameSystems.lua)
