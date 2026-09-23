# Utility shell

The compact **RikUI** button sits at the minimap's lower-right corner. It opens
a grouped flyout and stays available when cooldowns are off. Without the RikUI
minimap, it uses the screen's top-right corner.

| Section | Entries |
| --- | --- |
| Interface | Settings, Profiles, Move frames, party preview, setup wizard |
| Tools | Cooldowns On/Off, Move groups, Tracked spells, quest planner |
| Support | Report an issue, Setup and maintenance, Reload interface |

Entries appear only when their tools exist. Setup and maintenance opens the
config page containing re-sync, undo and diagnostics. Scale, layout presets,
module switches and profile editing remain within Settings. Contextual gameplay
controls (quest guidance, map actions, chat copy, bags and the micro menu) remain
beside their content.

The flyout starts closed. Escape, its close button or an outside click dismisses
it. Dismissing it preserves active frame movement. While moving, the launcher
reads **Done**, so there is no permanent toolbar in the middle of the HUD.
Cooldown viewer roots remain independent of the flyout and continue displaying
when it closes. Controls that write protected state recheck combat when clicked.

## Adding a utility

`RikUI.Shell.Register(id, entry)` accepts a group (Interface, Tools or Support),
order, label (string or function), action, optional enabled/visible predicates,
and keepOpen. A custom section supplies build(parent), height and refresh(frame)
instead of action. Register after the shared UI files load; late registration
updates the flyout. Replacing an id hides its previous row. Provider failures
are isolated and diagnosed once so Settings remains reachable.

The panel keeps a fixed width and scrolls as tools grow. `shell.lua` owns the
surface, `shell-tools.lua` connects existing APIs, and `scroll.lua` provides
the bounded viewport used by both the shell and settings.

## Native issue reporter

When the PTR reporter is ready, the shell dispatches its existing
UIButtonClicked event with the current context and payload. A missing payload
is forwarded unchanged. It opens the native survey; it never submits a report.

The original launcher becomes transparent and stops receiving mouse input.
Its root stays shown with its native OnUpdate script intact; the survey form
and event handling stay native. The integration targets the normal UIParent
gameplay surface; native customization-mode placement is not modeled here.

Source: pinned Forever build
[reporter launcher and native click](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback_Frames.lua#L904),
[event dispatch](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_PTRFeedback/Blizzard_PTRFeedback.lua#L484).

## Verification

`tests/shell.test.lua` covers launch and dismissal, fallback/late minimap,
combat login and transitions, actual action dispatch, party preview, reporter
readiness and payload forwarding, growing tool lists, replacement and provider
failures. Cooldown integration also verifies that the old cooldowncontrols
layout key is no longer registered. Native/game-client behavior is accepted
under the user's standing policy; these results are automated model checks.
