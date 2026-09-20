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

The header bar is flat with a one-pixel edge. The timer, the session and type
names and the "not active" line use the RikUI typeface. Each entry's bar uses
the RikUI statusbar texture, its name and value use the typeface, the shadow
art behind the bar is gone and the icon is cropped like the action bars. The
dropdowns and the scrollbar are flat through [window controls](controls.md).

Bar colours, class colours, values, bar height, text scale, window opacity and
background opacity are Blizzard's. They are settings of the meter, so RikUI
writes none of them and adds no fade.

## How it works

`DamageMeter:SetupSessionWindow` creates windows named
`DamageMeterSessionWindow<n>`. The module post-hooks that method on the
`DamageMeter` frame and also passes over the first eight names at login, so a
window that exists before RikUI loads is covered. A window is skinned once,
tracked in a weak table.

The flat header is a texture anchored to Blizzard's `Header` texture, so it
follows every resize; the stock header is faded. The strings are reached by
key path: `SessionTimer`, `SessionDropdown.SessionName`,
`DamageMeterTypeDropdown.TypeName` and `MinimizeContainer.NotActive`.

Entries are rows of `MinimizeContainer.ScrollBox` and of
`MinimizeContainer.SourceWindow.ScrollBox`. Each list is walked once with
`ForEachFrame` and then watched through
`ScrollBoxListMixin.Event.OnAcquiredFrame`, the event Blizzard's own
`ScrollUtil` uses, so rows handed out later are skinned too. The pinned
`LocalPlayerEntry` is skinned directly. An entry is read through Blizzard's own
getters (`GetStatusBar`, `GetName`, `GetValue`, `GetBackground`,
`GetBackgroundEdge`, `GetIconTexture`). `UpdateStyle` re-anchors an entry, sets
the background atlas and toggles the edge's shown state, but never resets the
bar texture or a region's alpha, so one pass lasts.

A window or entry that refuses the skin is reported once as
`DamageMeter skin` or `DamageMeter entry` and not tried again. A client without
the meter is skipped.

## Diagnostics

`/rik debug` prints `DamageMeter windows=<n> failed=<n>`.

## Verification

`tests/damagemeter.test.lua` fakes the owner frame, two windows and entries
that answer Blizzard's getters. It proves: header faded with a flat fill
anchored to it and an edge; the four strings with size and colour kept; window
alpha, background alpha, size, points and tween untouched; an existing entry's
bar texture, typeface, faded art and cropped icon with the bar colour
untouched; the local player entry; both lists watched once; a later row; a
window set up later skinned after Blizzard's setup; a repeated setup adding
nothing; the debug line; one failure report; a client without the meter; the
disabled module. The suite was seen red before the module existed.

The stub cannot show how it looks. Beta checklist:

1. Fully restart the client (new TOC entry). Turn the damage meter on in the
   game's settings if it is off and hit a target dummy.
2. The header should be flat, the bars flat with readable names and numbers,
   class colours intact.
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
