# Applying a preset

After loading the addon, use `/rik apply` (DPS) or `/rik apply tank`.
The command uses the player's class and enables all five steps. It applies
macros, bars, bindings, CVars, then saved positions. This changes existing
designated slots and character bindings. Before the first write, it saves the
previous state in `RikUICharDB.undo`. Use `/rik undo` to restore the last Apply,
including an Apply that failed after some steps. Successful Apply ends with
`type /rik undo to revert`.

Each completed step prints one `Setup <step>` line with placed, skipped and
edited counts. Disabled steps print one skipped-step summary. A failure is
included in that step's line and stops later steps. Unknown CVars, unlearned
spells, absent items and missing macros when macro creation is disabled are
expected skips. Standalone `/rik binds` and `/rik cvars` retain detailed output.

## Lua contract

`RikUI.Setup.Resolve(class, role)` returns a fresh preset with `class`,
`role` and resolved `bars`, or `nil, reason`. The default role is
the first `roleOrder` entry (`dps` for Warrior), with `dps` as the fallback
for older presets without that metadata. Whole-slot composition follows [the preset contract](presets.md):
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
returning a table does not itself mean setup succeeded. Apply and Undo are
rejected while another Setup operation is pending. The selected preset/options/profile are captured
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

## Keeping spell slots current

After a successful Apply for the player's class, RikUI listens for
`LEARNED_SPELL_IN_SKILL_LINE` and `SPELLS_CHANGED` through the core's guarded
event registration. A recognized learned ID selects its catalogue spell family;
the payload-free fallback (or an unrecognized/missing learned ID) scans every
spell slot in the applied role's resolved preset, including stance pages.

`/rik resync` explicitly runs that same full scan. `Setup.Resync()` returns a
result with `status` (`queued`, `running`, `complete`, `cancelled`, or `failed`)
and `placed`, `edited`, `skipped` counts, or `nil, reason` when refused.
The command prints a completion summary; per-slot skips include the spell,
native slot and reason. Repeated automatic events suppress identical skip lines.

Only empty slots and lower catalogue ranks of the same spell are written.
The highest known runtime spell ID is used; rank order comes from the catalogue,
not numeric ID or localized name order. Equal/higher ranks stay in place.
Different spells, macros, items and other occupied action kinds stay untouched.
Unlearned spells never clear a slot. Preset macro/item entries are not processed.
An occupied cursor is preserved; release it and use `/rik resync` to retry.
API/lookup failures report diagnostics and can be retried by a later event or
the command. A completed scan may still contain reported skips.

Combat bursts coalesce into one queued pass. Rank, slot contents and the applied
marker are checked when it runs; combat starting during a pass pauses it again.
An absent/wrong-class applied marker makes automatic handlers inert. Apply and
Undo suspend reconciliation. A failed or reloaded Undo with recorded progress
also suspends it until Undo finishes or a new Apply replaces that checkpoint,
so completed restoration steps cannot be refilled before an Undo retry.
Resync does not replace the Apply snapshot or alter the applied marker.
Apply step flags such as `bars=false` apply to that invocation; they are not
persistent opt-outs from subsequent automatic spell placement.

Reviewed 2026-09-18 against Blizzard's generated
[Classic Era spellbook API](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic_era/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua):
the learned event supplies a spell ID, while `SPELLS_CHANGED` has no payload.
The definitions provide no book-readiness or event-order guarantee. The existing
69913 probe confirms event registration and a broad-event observation; trainer
delivery/payload of the learned event has not yet been observed on that build.

For a beta smoke test, Apply, leave one designated learned-spell slot empty,
put unrelated spell/macro/item actions in other designated slots, and train a
new spell/rank. Check the empty slot and older ranks update, other actions stay
intact, and each conflict prints a clear line. Repeat `/rik resync`, then request
it during combat and verify placement only after combat. Check after reload,
with a held cursor, and after Undo. These live checks remain unperformed;
the automated suite covers those state transitions through simulated APIs.

## Role suggestions

`/rik role` reports the talent-based guess and tree totals. A changed guess can
offer one confirmation per login/reload; Yes applies bars and macros only.
See [role suggestions](roles.md) for thresholds, choices, API contracts,
recorded beta evidence and coverage limits.

## Snapshot and Undo

`Setup.Snapshot(class, role, opts)` returns a detached, read-only preview or
`nil, reason`. Omitted class uses the player and omitted role uses DPS.
It refuses combat; Apply instead captures through the combat queue at execution
time. A failed capture preserves the previous undo record and writes nothing.
A later accepted Apply replaces the single saved record.

The versioned saved record contains only enabled steps: designated action slots
(including explicitly empty slots), ordered binding snapshots, preset macro
before/after identities and write intent, selected known CVars, touched position
keys, the original profile name and the previous applied marker. Unsupported
occupied action kinds and ambiguous macro names within a pool stop Apply before
writes. Runtime IDs restore the exact captured spell/item, not today's highest
rank. Macro slots also capture name and pool because indices can change.

`Setup.Undo()` returns a result whose status becomes `running`, `queued`,
`undone` or `failed`; refusal returns `nil, reason`. Apply and Undo exclude
one another while pending. Undo restores layout, CVars and bindings, then macros,
then bars. Restoring macros before bars is a dependency exception to reverse
order: deletions can renumber macros, so each old macro slot resolves its final
index immediately before pickup. Layout restoration targets the original saved
profile even if the selected profile has changed.

Each step prints one `Undo <step>` line, followed by `Undo complete.`.
Success restores the prior applied marker and clears the snapshot. A second
`/rik undo` reports `nothing to undo`. In combat, it reports that it cannot run
yet and queues until combat ends; every subsequent operation is queued too.

Successful entries record persistent progress. Rejected writes, missing original
macros, changed setup-created macros, missing items, and readback failures keep
the snapshot for retry. A setup-created macro edited afterward is preserved;
rename it if you want to keep it, then retry Undo. Malformed or unsupported saved
snapshots are refused. Normal saved-variable reload persistence was established
by the existing build-69913 probe; the new undo reload path is covered by stubs.

Binding Undo saves restored runtime keys to character set 2, even if Apply began
with account bindings selected; it does not modify the account binding file.
Original primaries and alias order return, with later aliases retained afterward.
Macro Undo prefers `C_Macro.GetSelectedMacroIcon`; clients without that method
fall back to the displayed icon, so exact question-mark icon restoration on
those clients is not guaranteed. The existing 120-account/18-character macro
target remains unchanged. Standalone `/rik binds` and `/rik cvars` do not create
this Setup snapshot.

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

For Undo, start with recognizable spell, macro, item and empty designated slots,
an existing primary/alternate key pair, and an edited preset macro. Apply, reload,
then run `/rik undo`; compare those original states and verify a second Undo is
a no-op. Repeat with Undo requested during combat. Check character bindings after
reload and the selected question-mark macro icon. Automated integration covers
these state transitions, failures, sorting and retry behavior; live beta Undo
execution and protected native API behavior have not been observed here.
