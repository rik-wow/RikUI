# Edit Mode guard

`src/platform/editmode.lua` keeps Blizzard's Edit Mode from overriding RikUI. Some frames RikUI
sizes or places are Edit Mode systems. Whenever Edit Mode applies a layout (login,
a spec change, a layout switch, leaving Edit Mode) the system's `UpdateSystem`
runs `ApplySystemAnchor` and then every `UpdateSystemSetting`, which re-anchors
the frame and writes the values stored in the Edit Mode layout. For the main chat
window that is `SetSize` with the stored width and height, which is why a chat
window resized with RikUI's grip went back to Edit Mode's size.

## How it works

`RikUI.EditMode.Guard(frame, label, reapply)` post-hooks the frame's own
`UpdateSystem`, `ApplySystemAnchor` and `UpdateSystemSetting` with
`hooksecurefunc` and calls `reapply(frame)` afterwards through
`core.Combat.Queue`. The hooks sit on the frame, so Blizzard's call path is not
replaced. `rawget` decides whether a frame is a system: the client copies a
system's mixin onto the frame itself. A frame without those methods returns
`false` and is left alone.

While `EditModeManagerFrame:IsEditModeActive()` the guard writes nothing, so Edit
Mode's own sliders and drags work while it is open. An `EventRegistry` callback
on `EditMode.Exit` re-runs every guard: RikUI's values are back the moment Edit
Mode closes. RikUI's saved value always wins. In combat one re-apply per frame
waits in the queue. A failing `reapply` is reported once per frame and never
reaches Edit Mode's call.

## What is guarded

| Frame | Guarded value | Where |
| --- | --- | --- |
| `ChatFrame1` | the size saved by RikUI's resize grip | `src/modules/chat/chat-size.lua` |
| `ChatFrame1` | its place on the chat holder (a `SetPoint` post-hook that predates the guard) | `src/modules/chat/chat-move.lua` |
| `DamageMeter` | hung on `RikUIDamageMeterHolder` | `src/modules/damagemeter/damagemeter.lua` |
| `MinimapCluster` | `Minimap`, the mail indicator, the queue button and the tracking frame stay on the RikUI holder; the cluster's header setting re-anchors the indicator | `src/modules/minimap/minimap.lua` |

Without a saved chat size nothing is enforced and Edit Mode's size stands.

The chat size has a second line of defence, added after the first in-game
report that the size still reverted on reload: `src/modules/chat/chat-size.lua` post-hooks the
window's own `SetSize`, `SetWidth` and `SetHeight` and answers any size that is
not the saved one, whoever wrote it and by whatever route. RikUI's own write and
a drag of RikUI's grip are left alone. A size set while Edit Mode is open (its
resize handle or its width and height sliders) is adopted as the saved size:
the debug line from the game read `saved=none guarded=true`, which means the
size had been chosen in Edit Mode, where RikUI saved nothing, and Edit Mode
discarded it on exit (`ExitEditMode` runs `RevertAllChanges`; a Blizzard preset
layout cannot be changed at all). The revert is then answered like any other
foreign write. It is the mechanism
that has kept the window's place since `src/modules/chat/chat-move.lua` hooked `SetPoint`.
`/rik debug` prints `Chat size saved=WxH now=WxH guarded=<bool> answered=<n>`:
`saved=none` means the grip never saved a size, `guarded=false` means the window
did not carry the Edit Mode methods as its own fields, and `answered` counts
how often a foreign size was put right.

## What needs no guard

Every other Edit Mode system RikUI replaces is parked by `src/platform/hide.lua` (action
bars, unit frames, cast bars, buff frames, objective tracker, loot frame, micro
menu, bags bar, status tracking bars, durability, mirror timers). A parked frame
has a hidden parent; Edit Mode may move or size it without anything showing, and
`src/platform/hide.lua` re-parks a frame Edit Mode re-parents. Frames that are only skinned in
place (loss of control, extra and zone ability buttons, alerts, banners, the
vehicle and possess bars) have no RikUI position or size to lose.

## Verification

`tests/editmode.test.lua` fakes a system with the three methods: a layout apply
is answered, a single setting update is answered, a second `Guard` adds no hook,
nothing is written while Edit Mode is active, `EditMode.Exit` restores, a plain
frame and a missing frame are refused, a failing re-apply prints once, combat
defers to one run, and a client without the manager or the event registry still
guards. `tests/chat-nav.test.lua` applies a fake Edit Mode layout to `ChatFrame1`
with and without a saved size; `tests/minimap.test.lua` re-anchors the indicator
and the tracking frame; `tests/damagemeter.test.lua` runs on the shared guard.

The stub cannot show whether a post-hook on a system frame's method taints Edit
Mode on 69913. Beta checklist:

1. Resize the chat with RikUI's grip, `/reload`: the size holds.
2. Open Edit Mode and close it: the chat, the minimap indicator and the damage
   meter are where RikUI had them, and no "blocked action" message appears.
3. Switch the Edit Mode layout in the Edit Mode dropdown: same result.
