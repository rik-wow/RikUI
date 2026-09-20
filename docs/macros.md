# Macro service

`src/character/macros.lua` exposes `RikUI.Macros` after core loads. It reads or writes nothing
at load time. The service supports the target contract of 120 account macros
(indices 1–120) and 18 character macros (121–138).

## Calls

- `Find(name)` returns the current index for an exact, case-sensitive name,
  or nil when absent. If both pools contain the name, the character macro wins;
  within a pool, the first index wins. Read/input failure returns `nil, reason`.
- `Ensure(name, icon, body, scope)` edits the same-name macro in its current pool.
  If absent, it creates a character macro when space remains. Only
  `scope = "account"` permits account spill when the character pool is full;
  nil or `"character"` forbids spill. Account scope still prefers character space.
- `Snapshot()` returns a fresh sparse table of every existing macro in the
  target pools. Keys are the current indices; values are
  `{ name = ..., icon = ..., body = ..., scope = "account" | "character" }`.
  Empty pools return an empty table. A read failure returns `nil, reason`,
  never a partial snapshot.

Names must be nonempty strings of at most 16 UTF-8 characters; bodies must be
strings of at most 255 characters, including newlines and spaces. Empty bodies
are allowed. Icons are positive integer texture file IDs or nonempty texture
paths, passed to the native API unchanged; callers resolve spell IDs to textures.
Invalid requests return `nil, reason` and print a chat line naming the macro.
Full pools and unavailable, throwing or rejecting native APIs also fail this way.

## Combat and indices

Every create/edit goes through `RikUI.Combat.Queue`. When executed immediately,
Ensure returns the native index, or `nil, reason` on failure. Deferred calls
return `nil, "queued"`; this acknowledges pending work, not successful creation.
This also applies when Ensure is called while the queue is already draining.
Failures at execution time are reported in chat.

The callback resolves the name and available slots again when it runs. Thus two
queued requests for the same new name create once and then edit, and intervening
macro changes do not send an edit to a stale index. Create/edit return values
are retained because the client sorts macros. A later insertion may invalidate
a previously returned index; call Find again immediately before placing a macro.

Apply finishes queued macro work before placing macro actions. Its persistent
journal in `src/character/macros-undo.lua` captures only preset macro names, distinguishes
original macros from new ones, and records each mutation's pool before writing.
The Ensure `beforeWrite(index, pool, scope)` hook runs inside its queued callback.
Undo resolves unique name/pool identities again for each operation, restores
original bodies/icons, and deletes only setup-created macros whose post-write
body/icon still match. Unrelated macros and account/character name collisions
are preserved. Ambiguous names within the same pool stop snapshot capture.
Macros restore before action slots so restored buttons use current indices.
See [Setup](setup.md) for retry, combat and persistence behavior.

## Sources and verification

Reviewed on 2026-09-18:

- Blizzard's [macro frame](https://raw.githubusercontent.com/Gethe/wow-ui-source/beta/Interface/AddOns/Blizzard_MacroUI/Blizzard_MacroUI.lua)
  uses global GetMacroInfo and the account-capacity offset for character indices.
- The [icon selector](https://raw.githubusercontent.com/Gethe/wow-ui-source/beta/Interface/AddOns/Blizzard_MacroUI/Blizzard_MacroIconSelector.lua)
  uses indices returned by CreateMacro/EditMacro.
- The [shared name input](https://raw.githubusercontent.com/Gethe/wow-ui-source/beta/Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml)
  limits names to 16 letters; the [macro body input](https://raw.githubusercontent.com/Gethe/wow-ui-source/beta/Interface/AddOns/Blizzard_MacroUI/Blizzard_MacroUI.xml)
  allows 255 letters and counts invisible characters.
- The current public beta [UIParent constants](https://raw.githubusercontent.com/Gethe/wow-ui-source/beta/Interface/AddOns/Blizzard_UIParent/Mainline/UIParent.lua)
  specify 120 account / 30 character slots. This differs from our explicit
  SDD/roadmap target of 120/18. This service does not inspect character slots
  beyond 138. Verify the actual Forever build before expanding that contract.

The integrated Lua stub runner exercises both pools, limits, duplicate edits,
native failures, sorting, combat deferral and detached snapshots. These checks
do not establish live Forever write behavior or native Unicode truncation rules.
The retained probe confirmed CreateMacro/EditMacro presence on build 69913,
but this chunk has not exercised them in-game.

The general `Macros.Snapshot()` preserves the displayed GetMacroInfo icon.
Setup's `CaptureIdentity` instead prefers C_Macro.GetSelectedMacroIcon, following
Blizzard's [Classic Era icon editor](https://raw.githubusercontent.com/Gethe/wow-ui-source/classic_era/Interface/AddOns/Blizzard_MacroUI/Blizzard_MacroIconSelector.lua)
(reviewed 2026-09-18). If that API is absent, the displayed icon is the fallback;
exact question-mark icon restoration then remains uncertain. Native after-write
icons are recorded too, allowing texture paths to resolve to numeric IDs.
Stub tests cover selected versus displayed icons and macro index churn.
Live Forever capacity, Unicode limits and exact icon behavior remain in the
existing macro-beta-compatibility backlog.
