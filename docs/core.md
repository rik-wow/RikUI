# Core module contract

The TOC loads core, spell/CVar data, the Warrior preset and the module files in
SDD order. The module files are placeholders until their roadmap chunks land.
LibDeflate and the remaining class presets are added with their owning chunks.

- `RikUI:RegisterModule(name, module)` registers one unique module in load order.
  `module:OnEnable()` runs once at login when the selected profile enables it.
  A module registered after login enables immediately. Failed hooks are reported
  in chat without stopping other modules. Enable flags take effect on reload.
- `RikUI.DB`, `RikUI.CharDB` and `RikUI.Profile` become available on this addon's
  `ADDON_LOADED`. Missing defaults are copied recursively into every profile.
  Existing values, including false flags, are preserved. A new character has
  no applied preset, asks about role changes and has not completed the wizard.
- `RikUI:RegisterEvent(event, callback)` calls `callback(event, ...)`.
  Registration failures return false and print once per event. Callback errors
  do not stop other subscribers. A subscriber added while dispatching starts
  on the next event. Register during `OnEnable` when a module is optional.
- `RikUI:RegisterCommand(name, callback, description)` adds a lowercase command
  to `/rik` help. The callback receives trimmed arguments with case preserved.
  The core provides `help` and `debug`.
- `RikUI.Secret.Read(reader, ...)` returns `ok, ...` from `pcall`, including
  nil return slots. Branch only on `ok`, never on a returned unit value.
  `Secret.IsSecret(value)` returns the client's secrecy boolean.
  `Secret.Apply(sink, reader, ...)` forwards successful results directly into
  the sink and returns its `pcall` results. On failure it returns false and the
  error; the caller must handle that failure. It never substitutes zero.
- A module's `Debug(report)` hook calls `report(label, reader, ...)` for each
  dependency. `/rik debug` calls hooks even on disabled modules and prints the
  secrecy boolean for each return slot, or an API-read error. It never prints
  the values. Labels are ordinary static strings.
- `RikUI.Combat.Queue(fn)` runs a closure immediately outside combat or queues it
  for `PLAYER_REGEN_ENABLED`. Deferred work runs FIFO, is removed before being
  called, and survives other callbacks' failures. Combat resumption pauses the
  drain. Work queued during a drain is appended. Capture arguments in the closure.
- `RikUI:Print(message)` prefixes a chat line. `RikUI.Data` and `RikUI.Presets`
  are the shared namespaces populated by later data chunks.

Run `luajit tests/run_tests.lua` from the repository root. The stub checks
behavior and loads every TOC entry, but cannot reproduce WoW's secret-value VM
or prove that the beta client loads the addon.

For a live smoke check, enable RikUI, log in (restart the client if the new addon
is not listed), and run `/rik` and `/rik debug`. Help should list help/debug/cvars;
debug should show profile Default and no module dependencies at this stage.
Check for Lua errors, then `/reload` and repeat.

## CVar settings contract

`data/cvars.lua` exposes `RikUI.CVars`; loading it never applies settings.

- `CVars.List` is the ordered catalogue of `{ name, value, label }` entries
  from the SDD. Treat the catalogue as read-only; the wizard can render labels
  and use each CVar name as its checkbox key.
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
  when `C_CVar.SetCVar` returns true. Values are sent as strings, preserving the
  trailing space in `"%H:%M "`. This follows the
  [Blizzard CVar API contract](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/CVarDocumentation.lua).

After `/reload`, `/rik cvars` applies all 13 settings for a live smoke check.
Expect one applied/skipped line per setting and no Lua error. This command
changes game settings; it does not persist its return snapshot. Persistent undo
belongs to the later setup/undo chunk. The stub suite covers command routing and
failure handling; it cannot establish which settings this beta build accepts.
