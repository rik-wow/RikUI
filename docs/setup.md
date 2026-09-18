# Applying a preset

After loading the addon, use `/rik apply` (DPS) or `/rik apply tank`.
The command uses the player's class and enables all five steps. It applies
macros, bars, bindings, CVars, then saved positions. This changes existing
designated slots and character bindings. Undo is a separate roadmap chunk
and is not implemented yet; a failed Apply can leave earlier steps applied.

Each completed step prints one `Setup <step>` line with placed, skipped and
edited counts. Disabled steps print one skipped-step summary. A failure is
included in that step's line and stops later steps. Unknown CVars, unlearned
spells, absent items and missing macros when macro creation is disabled are
expected skips. Standalone `/rik binds` and `/rik cvars` retain detailed output.

## Lua contract

`RikUI.Setup.Resolve(class, role)` returns a fresh preset with `class`,
`role` and resolved `bars`, or `nil, reason`. The default role is
explicitly `dps`. Whole-slot composition follows [the preset contract](presets.md):
main, role main, stance, role stance. Side bars inherit only their own
role override. All nested data is copied. Undeclared stance pages are omitted.

`RikUI.Setup.SlotToAction(page, index)` accepts integer indices 1–12:

| Page | Native action slots | Binding family |
| --- | --- | --- |
| main | 1–12 | ACTIONBUTTON (when not on a bonus page) |
| battle | 73–84 | ACTIONBUTTON via bonus offset 1 |
| defensive | 85–96 | ACTIONBUTTON via bonus offset 2 |
| berserker | 97–108 | ACTIONBUTTON via bonus offset 3 |
| bar2 | 61–72 | MULTIACTIONBAR1BUTTON |
| bar3 | 49–60 | MULTIACTIONBAR2BUTTON |
| bar4 | 25–36 | MULTIACTIONBAR3BUTTON |
| bar5 | 37–48 | MULTIACTIONBAR4BUTTON |

`RikUI.Setup.Apply(class, role, opts)` accepts optional boolean flags
`macros`, `bars`, `binds`, `cvars`, `layout`; omitted flags default on.
`strafe` and `mouse45` are forwarded to bindings. `cvarSelection` is the
existing name-to-boolean selection map. Invalid input returns `nil, reason`
before writes.

An accepted call returns a result table with `status`, `class`, `role`,
`steps`, and an `error` on failure. Status is `running`, `queued`,
`applied`, or `failed`. The same table updates when queued work finishes;
returning a table does not itself mean setup succeeded. A second Apply is
rejected while one is pending. The selected preset/options/profile are captured
for that invocation, so later caller mutations do not rewrite pending work.

All operations pass through the existing combat queue. In combat, one chat
line reports the queue; `PLAYER_REGEN_ENABLED` resumes the sequence. Completion
callbacks on macro/binding writes preserve order even when those services
enqueue nested work during queue draining. The core FIFO contract is unchanged.

On success, `RikUICharDB.applied` stores
`{ class, role, at = time(), presetVersion = preset.version or 1 }`.
Failed attempts leave the previous success record unchanged. Selective Apply
also records success when its enabled steps complete; it does not assert
disabled steps were applied.

## Placement and positions

Known spells use the highest learned rank from the spellbook resolver.
Only explicitly designated slots are written; unspecified slots are preserved.
Designated unlearned spells or unavailable actions clear any old action.
A lookup/API failure preserves the slot where lookup failed and stops Apply.
Only carried bags are searched for named items; bank and equipped items do not
satisfy a preset item. If metadata for a present bag item is unavailable and no
match can be established, Apply reports a retry instead of declaring it absent.

Pickup uses `C_Spell.PickupSpell`, `PickupMacro`, or `C_Item.PickupItem`.
Cursor type is checked before `PlaceAction`, the resulting action type/ID is
checked afterward, and the cursor is cleared even on a write exception.
Clearing an occupied slot uses `PickupAction` and `ClearCursor`, followed by
an empty-slot check. The internal `Setup.WriteSlot` refuses combat calls;
consumers should use the queued Apply entry point.

Layout writes copies of `preset.positions`, or `Setup.DefaultPositions`,
into `RikUI.Profile.positions`, preserving unrelated position keys.
Each record uses `point`, `relativePoint`, `x`, `y` relative to UIParent.
Defaults place main/bar2/bar3 at bottom center and bar4/bar5 on the right.
These are saved positions for future RikUI frames; this step does not move
Blizzard frames or change Edit Mode. Existing Blizzard extra bars must already
be enabled if the user wants to see those stock buttons.

## Supporting service extensions

- `Macros.Ensure(name, icon, body, scope, opts)` accepts `quiet` and
  `onComplete(index, reason, disposition)`; disposition is `placed` or
  `edited`. Existing synchronous/queued return values are unchanged.
- `Bindings.Apply(opts)` accepts `quiet` and
  `onComplete(snapshot, reason, count)`; the callback runs after actual writes.
- `CVars.Apply(selection, opts)` accepts `quiet` and returns
  `prior, stats`; stats contains placed/skipped/edited and `error` for lookup
  or setter failures. Unknown CVars remain ordinary skips.

## Evidence and beta smoke test

The existing build-69913 probe confirmed namespaced spell pickup plus placement,
and the bonus-page action ranges. Reviewed 2026-09-18 against Blizzard UI source:

- [Classic MultiActionBars.xml](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic/Interface/AddOns/Blizzard_ActionBar/Shared/MultiActionBars.xml)
  associates MultiActionBar1 with page 6 and MultiActionBar2 with page 5.
- [SecureHandlers.lua](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/SecureHandlers.lua)
  dispatches the global action/macro and namespaced item/spell pickup APIs.
- [Spell declarations](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua)
  and [item declarations](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua)
  declare no success return for pickup calls.
- [Container declarations](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua)
  provide carried-container enumeration;
  [Item.lua](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_ObjectAPI/Mainline/Item.lua)
  accounts for asynchronous item metadata loading.

`luajit tests/run_tests.lua` covers the real setup modules and combat queue
with simulated client APIs: composition, mappings, ordered writes, rank selection,
step flags, summaries, persistence, queued completion, failure and retry paths.
It cannot establish protected API behavior or rendering in the beta.

For live verification, reload, run `/rik apply dps`, inspect the five
summary lines, visible stock bars and learned spell/Hearthstone slots. Check
available stances, Shift/Ctrl bar bindings, and an Apply issued during combat
that completes after combat ends. Record any Lua errors and whether the saved
marker survives reload. Do not treat these instructions as completed evidence.
