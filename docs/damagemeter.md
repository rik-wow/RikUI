# Damage meter

Forever ships Blizzard's own damage meter: `Blizzard_DamageMeter` names the
`camelot` game type in its TOC and carries a Camelot override file.
`damagemeter.lua` gives it the RikUI look. Disable the `damagemeter` module in
`/rik config` and reload for the stock meter.

## Turning the meter on

The meter is off by default on 69913. Blizzard hides the whole `DamageMeter`
frame unless the `damageMeterEnabled` setting is on,
`C_DamageMeter.IsDamageMeterAvailable()` answers true and the Edit Mode
visibility setting allows it (always, in combat, in a group, hidden). RikUI
never hides it. Three ways to switch it on: `/rik apply` or `/rik cvars`
(the setting is in RikUI's list), the Damage Meter section of the Advanced
Options page in the game's options (it is defined in `AdvancedOptions.lua`), or `/console damageMeterEnabled 1`. If the checkbox's tooltip in
the options shows a reason under its text, the client itself reports the meter
as unavailable and no setting will show it.

## What you see

A flat header with a one-pixel edge and a two-pixel accent-blue rule under it.
The minimize and settings buttons are flat boxes with a gold glyph (`-`, `=`)
and a hover tween; the type dropdown's arrow is a gold `v`. The timer, the
session and type names and the "not active" line use the RikUI typeface.

Each row is a flat bar in the RikUI statusbar texture on a dark track with a
one-pixel edge. Blizzard's rounded bar art and the shadow behind it are gone.
The icon is cropped like the action bars and framed. Names and numbers use the
typeface. A newly created row fades in over 0.15s and a row under the cursor
fades its highlight in. The scrollbar and the session dropdown are flat through
[window controls](controls.md).

Bar colours, class colours, values, bar height, text scale, window opacity and
background opacity are Blizzard's. They are settings of the meter, so RikUI
writes none of them, and the window itself gets no fade: Blizzard sets its alpha.

Not done, and why. The bar fill does not ease: Blizzard calls `SetValue`
without an interpolation argument, a second call cannot add easing, and an own
bar would need the session's numbers, which may be secret. There is no rank
accent on the top row: rows are pooled and the rank lives in element data the
skin does not read.

## Moving it

The primary window is anchored to the `DamageMeter` frame, an Edit Mode system,
and `CanMoveOrResizeSessionWindow` refuses to move it anywhere else. RikUI hangs
that frame on its own holder, `RikUIDamageMeterHolder`, registered with the
[shared layout](layout.md) under the key `damagemeter`. `/rik move` drags it,
`/rik move reset` puts it back at the bottom right above the tooltip anchor, and
Apply and Undo include it. The holder follows the meter's size, which is still
set in Edit Mode. Edit Mode re-anchors its systems whenever a layout applies, so
the hang is repeated after `ApplySystemAnchor`, except while Edit Mode is open:
there the meter goes where Edit Mode puts it and returns to the holder when you
leave. Secondary windows are dragged by hand, as Blizzard built them.

Writing anchors on an Edit Mode system from addon code can taint Edit Mode. If
Edit Mode reports a blocked action, disable the `damagemeter` module and reload.

## How it works

`DamageMeter:SetupSessionWindow` creates windows named
`DamageMeterSessionWindow<n>`. The module post-hooks that method on the
`DamageMeter` frame and also passes over the first eight names at login, so a
window that exists before RikUI loads is covered. A window is skinned once,
tracked in a weak table, as are its buttons and rows.

The flat header and the accent rule are anchored to Blizzard's `Header`
texture, so they follow every resize; the stock header is faded. The strings
are reached by key path: `SessionTimer`, `SessionDropdown.SessionName`,
`DamageMeterTypeDropdown.TypeName` and `MinimizeContainer.NotActive`.

Rows belong to `MinimizeContainer.ScrollBox` and to
`MinimizeContainer.SourceWindow.ScrollBox`. For each list the module first
registers for `ScrollBoxListMixin.Event.OnAcquiredFrame`, the event Blizzard's
own `ScrollUtil` uses, and only then walks the rows the list already has, under
its own `pcall`. The order matters: the first version walked first, and an
error in that walk cost every row the list handed out later, which is what the
first look in game showed (flat header, stock rows). The pinned
`LocalPlayerEntry` is skinned directly. A row is read through Blizzard's own
getters (`GetStatusBar`, `GetName`, `GetValue`, `GetBackground`,
`GetBackgroundEdge`, `GetIcon`, `GetIconTexture`).

Two facts from Blizzard's code shape the row pass:

- `SetupEntry` runs on every acquire and calls `SetBackgroundAlpha`, whose
  `UpdateBackground` sets the shadow art to a constant alpha of 1. A one-time
  fade cannot last, so `UpdateBackground` is post-hooked on each row and fades
  the art again.
- The data provider is rebuilt on every change and rows are handed out again
  each time (Blizzard's own comment in `InitEntry`). A fade on every acquire
  would flicker through a whole fight, so only a row the list flags as newly
  created fades in.

The row template clips its children and the icon sits on the row's left edge,
so an edge one pixel outside the icon would be cut off. The icon edge is drawn
in the `OVERLAY` layer at the icon's own bounds; `skin.Outline` takes an
optional layer for this.

A window or row that refuses the skin is reported once as `DamageMeter skin`
or `DamageMeter entry` and not tried again. A client without the meter is
skipped and gets no holder.

## Diagnostics

`/rik debug` prints
`DamageMeter windows=<n> entries=<n> lists=<n> failed=<n>` and the last error
if there was one. With the meter showing three rows, expect `entries` of at
least 3 and `lists` of 2 per window. `entries=0` with rows on screen means the
row pass is not reaching them; send that line.

## Verification

`tests/damagemeter.test.lua` fakes the owner frame as an Edit Mode system, two
windows with header buttons, and rows that answer Blizzard's getters and put
their shadow art back in `UpdateBackground`. It proves: the flat header, edge
and accent rule; the four strings with size and colour kept; the three header
buttons; window alpha, background alpha, size, points and tween untouched; a
row's bar texture, track, edge, typeface and cropped icon with the bar colour
untouched; the in-bounds overlay icon edge; the shadow art faded and faded
again after `UpdateBackground`; the local player entry; both lists watched
once; a new row fading once and a re-acquired row not fading; the hover tween;
the holder registered with the layout and sized like the meter; the re-hang
after `ApplySystemAnchor`, not while Edit Mode is open; the holder following a
resize; a window set up later; a repeated setup adding nothing; the debug line;
a list that cannot be walked still being watched; one failure report with its
reason in debug; a client without the meter; the disabled module. The suite was
seen red before the rewrite.

The stub cannot show how it looks. Beta checklist:

1. `/reload` (the file is already in the TOC). Turn the damage meter on in the
   game's settings if it is off and hit a target dummy.
2. The header should be flat with a blue rule under it and three glyph buttons;
   the bars flat and square on a dark track, icons square with a thin edge,
   class colours intact. If the rows are still rounded, send the
   `DamageMeter` line of `/rik debug`.
3. `/rik move`: a mover labelled "Damage meter" should sit over the meter; drag
   it, lock with `/rik move` again, `/reload`, and check it stayed. Open and
   close Edit Mode and check it stayed again.
3. Change bar height, text scale, style and background opacity in the meter's
   settings: each should still apply.
4. Open a second window and the per-source breakdown and scroll both lists.
5. Fight something and watch for errors mentioning secret values. Entries
   receive combat numbers; the module only writes their bar texture, fonts,
   art alpha and icon crop. If errors appear, disable the module and report it.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_DamageMeter.toc: AllowLoadGameType standard, camelot](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_DamageMeter/Blizzard_DamageMeter.toc)
- [DamageMeter.lua: SetupSessionWindow and what it drives from settings](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_DamageMeter/DamageMeter.lua)
- [DamageMeterSessionWindow.xml: Header, strings, MinimizeContainer, ScrollBox, LocalPlayerEntry, SourceWindow](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_DamageMeter/DamageMeterSessionWindow.xml)
- [DamageMeterEntry.lua: getters and UpdateStyle](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_DamageMeter/DamageMeterEntry.lua)
