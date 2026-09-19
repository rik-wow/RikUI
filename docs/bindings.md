# Bindings service

`bindings.lua` exposes `RikUI.Bindings`; loading the file never changes bindings.
The TOC already loads it after core and setup. Native commands preserve the
client's action-page and stance resolution.

- `Scheme` is the read-only-by-convention command-to-key table from the SDD:
  11 main, 12 bar2, 12 bar3, three stance, three pet and two movement bindings.
  Mouse4/5 use the native key names `BUTTON4` and `BUTTON5`.
- `Apply(opts)` makes each resolved scheme key the native primary key. It clears
  the 43 scheme keys plus `CTRL-6` and each target command's existing aliases,
  assigns the new primary first, then restores aliases outside the scheme in
  their original relative order. Thus Q replaces 6 as the displayed main-slot-6
  key while 6 remains an alternate. Alt combinations and unrelated bindings
  retain their assignments. Slots marked unbound in the SDD receive no new key.
  Before `SaveBindings(2)`, native readback must confirm every preset primary
  and preserved alias; a mismatch fails the operation.
- Omit options for the default scheme. `strafe=false` assigns A/D to
  `TURNLEFT`/`TURNRIGHT`; `mouse45=false` assigns bar2 slots 10/11 to
  Shift-G/Ctrl-G and clears Mouse4/5. The fallback takes priority over pet
  slot 1 and bar3 slot 8, which receive no scheme key in that mode. No extra
  replacement keys are invented. Switching back restores the default scheme.
  Options must be a table and these two fields, when present, must be booleans.
- `Snapshot(opts)` returns a detached
  `{ bindingSet = 1_or_2, keys = { [key] = previousCommand }, commands = { [command] = orderedKeys } }`.
  It captures all 44 scheme/legacy keys plus aliases of resolved target commands
  and original owners of reassigned keys. `commands` preserves native primary
  and alternate order for rollback. Empty key commands mean previously unbound.
  Reads are guarded and cross-checked; an incomplete snapshot returns
  `nil, reason` and Apply writes nothing.
- Successful immediate Apply returns that pre-write snapshot. Failure returns
  `nil, reason` and prints a diagnostic. Rejected/throwing writes trigger
  best-effort restoration of original runtime assignments and primary/alternate
  ordering, including displaced source commands; rejected writes or failed
  restoration readback are reported as incomplete rollback. A write failure
  never saves a partial preset. If SaveBindings itself fails, persistence
  cannot be guaranteed; runtime restoration is
  attempted, with no second save.
- All writes, including failure cleanup and save, run through `Combat.Queue`.
  Deferred Apply returns `nil, "queued"`; it captures options now and reads
  the actual binding snapshot when the queue executes. It does not return a
  deferred snapshot later. Setup queues its whole ordered operation and captures
  its persistent snapshot inside that operation.
- `Restore(snapshot)` restores the saved runtime ownership and primary/alternate
  order, verifies readback, then saves character set 2. Setup queues this helper;
  direct combat calls are refused. New aliases on captured commands are appended
  after the original aliases and journaled in `snapshot.restore` before clearing,
  so a failed restore can retry without losing them. `ValidateSnapshot` checks
  persisted key/order consistency before Undo starts. The captured binding-set
  number is context; Undo does not switch back to or overwrite account set 1.
- `Label(command)` reads current native keys on every call, prefers the active
  scheme/fallback key when secondary aliases exist, and otherwise uses the
  primary native key. It formats `SHIFT-1` as `s1`, `CTRL-Z` as `cZ`
  and `BUTTON4` as `M4`; unbound/unavailable reads yield `""`.
- `/rik binds` applies the default scheme and prints one key-to-command line
  per assigned binding after a successful save. In combat it reports that
  the operation is queued. This command does not persist an undo snapshot.

## Native mapping and evidence

Bar2 uses `MULTIACTIONBAR1BUTTONn` (BottomLeft, page 6, slots 61–72);
bar3 uses `MULTIACTIONBAR2BUTTONn` (BottomRight, page 5, slots 49–60).
Future preset placement and overlays must use those pages. See Blizzard's
[command-to-frame mapping](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Keybindings.lua)
and [multibar page constants](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic/Interface/AddOns/Blizzard_ActionBar/Shared/MultiActionBars.lua).

Blizzard's [binding UI](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic/Interface/AddOns/Blizzard_BindingUI/Blizzard_BindingUI.lua)
uses nil commands to clear keys, empty strings for unbound lookups and truthy
SetBinding success. SaveBindings is treated as a void call; an explicit false
or exception is rejected here. Blizzard's
[settings implementation](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua)
documents that saving character bindings updates the active binding set.
Apply saves directly to set 2 without loading a different set or saving set 1.
Blizzard's [primary-key reassignment](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Keybindings.lua)
likewise clears a command's keys and rebinds the primary before its alternate.
The [stock action button](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua)
uses the first native `GetBindingKey` result for its label; it does not call
RikUI's `Label` helper. These sources were checked on 2026-09-18; native persistence
implementation is not public.

## Verification and live smoke check

The LuaJIT stub suite tests exact assignments, clear/set/save order, preserved
keys, native primary ordering, repeated application, detached ordered snapshots,
options, labels, rejected APIs, readback mismatches, ordered failure cleanup,
slash routing and the real core combat queue. It cannot establish native beta
persistence or protected-call behavior.

On a disposable beta character after `/reload`, run `/rik binds` out of combat.
Expect 43 binding lines and character-specific bindings selected. Main slots
1–11 should show 1/2/3/4/5/Q/E/R/F/T/G; existing number aliases should still work.
Check Shift-1, Ctrl-1, Mouse4/5, stance Ctrl-Q/E/R and A/D; confirm Alt and an
unrelated custom key still work. `/rik apply dps` uses this same binding service.
Reload and confirm persistence, then inspect
another character's account bindings. Verify combat invocation delays changes
until combat ends. Exercise the two false options through the service API.
No live beta execution of this module is claimed by automated tests.
