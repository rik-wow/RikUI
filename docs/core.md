# Core module contract

Restart recovery validates the decoded account/profile/library and character containers before adopting a snapshot. Packed layouts expand in detached data first; malformed geometry or an unavailable layout base rejects the backup without partially applying it. Read exceptions become backup diagnostics while normal UI startup continues. Valid older snapshots remain supported.

Restart backup writes are read back before being marked successful. Missing or truncated macro bodies keep **Restart backup needs attention** visible and remain retryable without another settings change. This confirms the API readback, not disk durability; multiple macro writes are still not atomic. The existing APIs were checked against the [69913 macro UI source](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_MacroUI/Blizzard_MacroUI.lua) on 2026-09-24.

Recovery selects account and character sources independently: loaded SavedVariables, then valid CVar tables, then restart macros. A recovered account no longer blocks missing character preferences (or the reverse), and a loaded side is never overwritten by the older macro copy.

Restart backups preserve named profiles even when every setting matches defaults. Empty profiles restore with independent default tables; malformed profile records refuse the save. Research reviewed 2026-09-24: [players report lost addon settings](https://www.reddit.com/r/WowUI/comments/1wl0hw4/wow_forever_established_addons_already_working_ui/). This fixes RikUI backup identity loss, not the client persistence subsystem.

`/rik errors` lists up to 20 distinct errors caught by RikUI's runtime, with occurrence counts. Repeats print once while retained; a cleared or evicted error can print again. `/rik errors clear` resets the session history. Setup and support also has **Show errors**. This covers RikUI runtime boundaries, not every client or addon error, and never changes the client's error settings. Details are bounded to 512 bytes and secret values stay opaque. History is session-only; `GetErrors()` returns detached records.

See [architecture](architecture.md) for source ownership, startup, extension
examples, lifecycle states, performance properties and verification boundaries.
The TOC loads explicit core services, shared UI services, data and feature files.

- `RikUI:RegisterModule(name, module, options?)` registers a unique module.
  `module:OnEnable()` runs at most once, after its declared activation
  dependencies and when the selected profile enables it. A late provider can
  unblock a consumer; failed hooks are not retried. `GetModuleState(name)`
  reports activation state and reason. Module toggles take effect on reload.
- `RikUI.DB`, `RikUI.CharDB` and `RikUI.Profile` become available during
  RikUI's `ADDON_LOADED` and are rebound after late restore at login.
  Defaults are copied recursively; wrong types and non-finite defaulted
  numbers are repaired. Valid false values and unknown settings are preserved.
- `RikUI:SetProfile(name)` selects an existing profile, cancels dragging and
  applies its layout/scale. Returns `true` or `nil, reason`; combat and
  pending Setup Apply/Undo refuse the switch. See [layout](layout.md).
- `RikUI:RegisterEvent(event, callback, owner?)` calls `callback(event, ...)`.
  Duplicate callback/owner pairs are ignored. Ownership is inherited during
  module activation and owned callbacks. `UnregisterEvent(event, callback)`
  and `UnregisterOwner(owner)` remove subscriptions. Errors do not stop other
  subscribers; additions wait for the next dispatch and removals are immediate.
  Failed activation removes its owned subscriptions, but does not undo hooks,
  frames, timers or pending shared service work.
- `RikUI:RegisterCommand(name, callback, description)` adds a lowercase
  command to `/rik help`; callbacks receive trimmed, case-preserved arguments.
  `HasCommand(name)` reports availability.
- `RikUI.Secret.Read(reader, ...)` returns `ok, ...` from `pcall`, including
  nil slots. Branch on success and check secrecy before inspecting values.
  `Secret.IsSecret(value)` returns the client's secrecy boolean.
  `Secret.Apply(sink, reader, ...)` forwards results to the sink and returns
  its protected-call results. On failure it returns false and the error;
  it never substitutes zero.
- A module's `Debug(report)` hook calls `report(label, reader, ...)`.
  `/rik debug` calls hooks even on disabled modules and reports secrecy per
  return slot or an API-read error, without printing returned values.
- `RikUI.Combat.Queue(fn, key?)` runs immediately when safe or queues FIFO
  work for after combat. A key coalesces pending calls at the original position.
  `Cancel(key)` cancels a keyed job and `Pending()` reports live queued jobs.
  Errors are isolated; combat resumption pauses draining. Newly queued work
  during a drain joins its tail. Each pass visits at most 100 queue entries,
  then continues through a one-shot OnUpdate callback. A continuation rechecks
  combat before executing anything; cancellation can remove the final pending
  job and its continuation. Nested jobs from an immediately executed callback
  join the same bounded pass, avoiding recursive queue calls. The immediate
  callback still returns its success flag and first result. This bounds queue
  scheduling work per pass, not the runtime of an individual callback or client
  FPS. Capture arguments in the closure.
- `RikUI:Changed()` schedules a save after configuration mutation.
  `Print(message)` prefixes a chat line. `Data` and `Presets` hold catalogues.
- `RikUI.Hide.Frame(frame, keepEvents)` parks Blizzard frames under the hidden
  `RikUIHiddenFrames` container through the combat queue. Latest request wins.
  `keepEvents` defaults to true; false unregisters native events until reload.
  `Hide.Restore(frame, onRestored)` returns a previously parked frame to its
  latest native parent; `Hide.IsHidden(frame)` reports requested state.
  Native reattachment, including Edit Mode, is tracked through post-hooks.

Run `luajit tests/run_tests.lua` and `python tests/check_manifest.py` from the
repository root. The stubs cannot reproduce WoW's secret-value VM or taint.
In the client, run `/rik help` and `/rik debug`, inspect Lua errors, exercise
combat transitions, switch profiles and verify reload/relog persistence.

## CVar settings contract

`data/cvars.lua` exposes `RikUI.CVars`; loading it never applies settings.

- `CVars.List` is the ordered catalogue of `{ name, value, label, bits? }` entries
  from the SDD. Treat the catalogue as read-only; the wizard can render labels
  and use each CVar name as its checkbox key. An entry with `bits` applies
  `value == 1` to each one-based bit index through `C_CVar.SetCVarBitfield`.
  Stacking sets enemy bit 1 and friendly bit 2, preserving all other bits.
- `CVars.Apply(selection)` accepts a map such as
  `{ autoLootDefault = true, showTimestamps = true }`. Only literal `true`
  selects an entry; false, absent and unlisted names are ignored. Omit selection
  to apply all entries; `{}` applies none. Other argument types raise an error.
- Apply captures all selected current strings before the first write and returns
  that name-to-value table for undo, including readable entries whose write was
  rejected. Unknown or unreadable entries are omitted and never written.
- `CVars.Snapshot()` returns a fresh name-to-current-string table for every
  readable listed CVar without writing. Empty strings are preserved. Unknown or
  failed reads are omitted with a skip line; successful reads are silent.
- Apply prints one applied/skipped line per selected listed entry. It guards
  lookups and writes separately, continues after errors, and reports success only
  when the setter returns true. A bitfield entry succeeds only if every bit
  write succeeds; a partial failure retains its original snapshot for undo.
  Scalar values are sent as strings, preserving the trailing space in
  `"%H:%M "`. Restore always writes the saved string, including the complete
  encoded bitfield. This follows the
  [69913 CVar API contract](https://raw.githubusercontent.com/Gethe/wow-ui-source/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/CVarDocumentation.lua).

After `/reload`, `/rik cvars` applies all 15 settings for a live smoke check.
Expect one applied/skipped line per setting and no Lua error. This command
changes game settings without persisting its snapshot; `/rik apply` saves one
for `/rik undo`. The corrected 69913 names, bit writes and undo pass harness
coverage; runtime acceptance still needs a client check.

## Settings store (`src/persistence/store.lua`)

On build 69913 the client was seen (2026-09-20) writing saved variables at
logout and never reading them back: `RikProbeDB` reported "fresh" on every
login, and RikUI's saved chat position was on disk while `/rik debug` after the
reload printed `saved=none`. Every reload started from nothing. RikProbe's
persistence section then showed three things that do survive a reload: a CVar
an addon registers, the client's cache for a named user-placed frame, and an
account macro. The store uses the first.

`Store.Save(name, table)` uses the version-2 codec from `src/persistence/codec.lua`
(see [persistence boundaries](architecture.md#persistence-boundaries)) and splits
the encoded letters, digits and underscores into 180-character chunks in CVars named
`rikuiStore_<name>_<n>` and writes a header `rikuiStore_<name>` with the
version, the chunk count, the length and a checksum. Every write is read back,
so a client that truncates a value is noticed at once. `Store.Load(name)`
checks length and checksum and refuses damaged text.

`src/core/lifecycle.lua` calls `Store.Restore()` before it merges defaults: `RikUIDB` and
`RikUICharDB` are taken from the store only when no usable table loaded, so saved
variables that did load always win. Successful restores are quiet; `/rik store`
reports which fallback restored the settings. The
account table is stored as `account`; a character's as `char<number>` made from
its name and realm, because CVar names are ASCII. Chat history and account
blocked-call/plan-switch diagnostic buffers are left out of the reload backup;
they remain in live state and normal SavedVariables. Writes happen at `PLAYER_LOGOUT` and from a
5-second ticker that writes only when the encoded text changed. `/rik store`
prints availability, saves, chunks, size, what was restored and the last
failure. A client without `C_CVar.RegisterCVar` has no store and nothing else
changes.

`tests/store.test.lua` covers the encoding round trip, damaged text, chunking,
the checksum, a truncating client, the logout-then-login case with no saved
variables, saved variables winning, the ticker writing only on change, the
slash command, a client without CVar registration and a core without the file.
The full-restart measurement below established that custom CVars do not persist
across client restarts. The CVar value length limit remains unverified; the
180-character chunk assumption is protected by a read-back check.

### Across a client restart (`src/persistence/store-macros.lua`)

Measured with RikProbe after a full exit and relaunch: the registered CVar came
back empty, while the user-placed frame cache and the account macro kept
counting. So CVars cover `/reload` only, and a second tier covers restarts:
account macros named `RikUI data N`, each one comment line
(`#rikui i/n <checksum> <text>`, at most 255 characters) that does nothing when
pressed. They show in the macro list; deleting or editing one is caught by the
checksum, said once, and nothing is half restored.

Macros are scarce and visible, so this tier keeps only what differs from the
defaults (`Store.Prune` against `core.Defaults`; a module that is on is the
default) and leaves out the undo snapshots and the chat history. A layout is
kept as the preset it is closest to plus the frames that were moved
(`layoutPacked = { base, moved }`, `false` for a frame the preset places but the
player had no saved place for), so a whole layout with a frame or two moved
fits in one macro. The store's text format helps both tiers: keys are written in
sorted order, so equal settings always give equal text and "did anything change"
is a string comparison; the words every position repeats (`point`,
`BOTTOMLEFT`, the layout keys) are two-character codes from an append-only
list; and the text is letters, digits and underscore throughout, so a saved
position is about 30 characters. One entry per character is kept under
`characters`, and a character's first save keeps the others'.

The twelve-macro budget reserves space for every character's user settings
before adding planner learning. Full learning is included when it fits;
otherwise a valid compact history retains up to 64 recent completed quest IDs.
If even that does not fit, only that optional learning backup is omitted.
Full learning remains in live state, SavedVariables and the CVar reload tier.
This also repairs oversized learning inherited from another character's backup.
Settings-only overflow stops before any macro write. `/rik store` reports
macro usage and how many learning snapshots were compacted or omitted.

The September 23 client settings reproduce a 2,676-byte character delta before
account overhead. `tests/store-client-replay.lua <account.lua> <character.lua>`
reads supplied SavedVariables in an isolated, instruction-bounded environment,
then exercises only stub CVar/macro APIs. The corrected backup used five macros
(1,095 body bytes), restored exact account/character settings and retained full
reload-tier learning. It does not write the supplied files or native macros.

Macros cannot be read while the addon loads, so `src/core/lifecycle.lua` asks
`Store.RestoreLate()` at `PLAYER_LOGIN`, before any module starts, and only
for each account or character side missing from SavedVariables and CVars; it then merges
defaults and binds the profile again. Writes come from the same five-second
change-only ticker and from `PLAYER_LOGOUT`, never in combat. A full macro list
is reported once and the reload tier keeps working. `tests/store-macros.test.lua`
covers pruning, macro shape, a restart, two characters, no write without a
change, combat, growing and shrinking, a damaged macro, a full macro list, the
layout packing round trip, and a client without the macro API.

### Restricted combat events

The planner now checks for a usable combat reader, readable restriction state,
and an ordinary valid frame event before subscribing to combat-log updates.
Clients exposing restricted callbacks continue quest guidance without attempting
the forbidden registration or inventing combat XP attribution. Supported legacy
frame events still register normally. The persisted September 23 `UNKNOWN()`
stack identifies this former registration attempt in `questplanner:OnEnable`.
The taint file was empty; diagnostics no longer promise it contains that first call.

The pinned Blizzard [combat-log definitions](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/CombatLogDocumentation.lua)
and [event capability definitions](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/EventUtilsDocumentation.lua)
provide the restriction/callback checks. Stub startup tests assert zero native
combat registration attempts on restricted, callback-only and missing-reader
clients, and successful subscription on supported clients. Native `/reload`
verification remains separate.
