# RikUI architecture

RikUI uses explicit Lua services and feature folders. `RikUI.toc` is the production
composition root: the client executes each file in order, then the lifecycle
service restores settings and activates enabled modules. There is no runtime
filesystem scan, dependency loader, or third-party framework.

## Source ownership

| Location | Responsibility |
| --- | --- |
| `src/core/` | Namespace, diagnostics, events, profiles, module activation, commands, combat queue, lifecycle |
| `src/platform/` | Blizzard frame parking and Edit Mode integration |
| `src/ui/` | Media, drawing primitives, unit colors, motion and skin helpers |
| `src/layout/` | Geometry, group registry, placement, dragging and layout presets |
| `src/persistence/` | Bounded codec, CVar transport, macro transport and save scheduling |
| `src/character/` | Key bindings, macros and macro undo |
| `src/setup/` | Preset resolution, Apply/Undo and character setup |
| `src/configuration/` | Options and first-login wizard |
| `src/modules/<feature>/` | Feature-owned frames, events, state and client adapters |
| `data/`, `presets/` | Declarative catalogues and bundled presets |
| `media/` | Assets; their installed paths are stable |
| `tests/` | Stubbed behavior, source composition and manifest validation |
| `RikProbe/` | Separate client capability probe addon |

The repository root remains the installable addon root. Keep `RikUI.toc` and
`Bindings.xml` there and install the complete `src/` tree alongside the data and
media folders. Addon identity, SavedVariables names and media paths are unchanged.
The import/export file is still a reserved placeholder; LibDeflate is not bundled.

File boundaries follow responsibilities, not line counts. A feature can have a
registration file, frame factory, status readers and skinning helpers in its own
folder. Helpers used across unrelated features belong in an appropriate service.
For example, `RikUI.UI.Edges`, `HealthColor` and `PowerColor` do not require the
unit-frame feature. The old `UnitFrames` helper names remain compatibility aliases.

Profile selection delegates geometry and registered appearance work to `Layout`.
Features attach cosmetic refreshes through `Layout.Register(..., { onApply = callback })`;
the callback receives each frame after placement. Bars use this for gryphon art,
so the core profile service does not call the Bars feature and there is only one
layout refresh queue. Frame failures are isolated, including within a shared
group. Per-frame refreshes use `Runtime.InvokeOwned` with the group's first
registration owner (`opts.owner` can override it), so floating predicates and
appearance callbacks retain feature ownership across coalescing and combat
deferral. See [the layout contract](layout.md#module-contract) for callback ordering,
floating frames, reentry and completion behavior.

The [Forever quest planner](questplanner.md) separates exact-build evidence,
live character observations, eligibility, directed travel and action optimization.
A revision-safe controller supplies detached outputs to tracker/map guidance.
World facts and observation history never enter the settings transport.
Objective identity is separate from display formatting. Read-only gossip offers
and event-time context remain character observations; the bounded session journal
records changes independently of replanning. Manual export preserves the current
snapshot and discloses any older journal entries omitted to fit the wire limit.
Missing corpus and native validation coverage remain explicit. Offline terrain tools
produce a separate local companion addon; incremental mesh validation and A* own
modeled corridor guidance. Observed map markers can request a bounded approach
endpoint; routes stop on modeled ground and leave the final gap and interaction
unverified. Player admission and explicit portal connectivity remain strict.
Acquisition authenticity never certifies traversability,
and extracted assets/geometry are excluded from the repository and settings store.
The terrain compiler separates geographic source profiles, collision coverage
contracts and geometry validation. UnitPosition's raw vertical value is not an
established floor measurement; horizontal grounding remains ambiguous when
multiple modeled surfaces overlap. Explicit destination-floor choices are scoped
to the quest observation, marker and mesh revision. They select a strict modeled
route without asserting the quest target's actual floor or native altitude.
`quest-targets.lua` owns reviewed navigation annotations separately from world
facts and optimizer actions. Matching binds exact identity, quest stage and marker;
floor inference additionally binds mesh revision and every reviewed surface.
The initial Bitter Rivals annotation selects the modeled basement automatically,
retains an explicit inference/source tag and allows user override. Reported
interaction instructions do not establish inventory, temporary access or completion.

## Loading and activation are separate

Files define local functions and publish APIs under `RikUI`. The bootstrap also
publishes `namespace.Core` through the addon-private table supplied by the client.
`RikUI.Runtime` is internal coordination state; features should use the public
methods below rather than calling lifecycle internals.

1. The TOC loads the core services before their consumers. Each service's file
   dependencies must already exist before its top-level code runs.
2. `ADDON_LOADED` for RikUI restores the available store, repairs typed defaults,
   binds `DB`, `CharDB` and `Profile`, and configures module flags.
3. `PLAYER_LOGIN` offers late restore to the macro transport, rebinds settings,
   and starts modules in registration order, activating dependencies first.
4. A late module registration starts another activation pass. A hook that already
   succeeded or failed is never called again.

`RegisterModule(name, module, { dependencies = { "provider" } })` declares an
**activation** dependency. Use it when the consumer needs the provider's enabled
behavior: `unitauras` requires live `unitframes`. A helper defined at file load
only needs TOC order; do not require an enabled feature just to reuse a factory.

`GetModuleState(name)` returns `state, reason`. States are `registered`,
`disabled`, `enabling`, `enabled`, `failed` and `blocked`. Missing, disabled,
failed or cyclic dependencies block their consumers while unrelated modules
continue. A later provider registration can unblock a consumer that never ran.
An unknown name returns nil. Module enable flags and non-removable hooks require
a reload to change; profile switching does not implement live module teardown.

If `OnEnable` throws, the runtime reports the error and removes its owned event
subscriptions. It does not roll back created frames, post-hooks, timers or queued
service work. Shared services own pending flags and must finish accepted jobs.
Write activation in small, idempotent steps and check prerequisites before
installing irreversible hooks.

## Public runtime contracts

- `RegisterEvent(event, callback, owner?)` calls `callback(event, ...)` in
  subscription order. Duplicate callback/owner pairs are ignored. Omitting the
  owner inherits the module currently enabling or handling an owned callback.
  `UnregisterEvent(event, callback)` removes all subscriptions of that callback
  for the event; `UnregisterOwner(owner)` removes that owner's subscriptions.
  Additions start with the next dispatch, including a nested dispatch; removals
  take effect immediately. Each callback has its own error boundary.
- `Combat.Queue(callback, key?)` runs immediately when safe or appends work for
  after combat. Deferred work is FIFO. Reusing a nonempty string key replaces
  the pending callback at its original queue position. Use feature-prefixed keys
  such as `"example:layout"`. `Cancel(key)` cancels an outstanding keyed job;
  `Pending()` reports live queued jobs. Jobs added during a drain join its tail.
  Re-entering combat pauses the drain; a failing job does not stop the others.
- `RegisterCommand(name, callback, description, owner?)` adds a lowercase `/rik`
  command. The callback gets trimmed arguments with case preserved. Registration
  captures the current callback/module owner unless an explicit owner is supplied.
  Top-level registrations are unowned by default; pass the feature table as the
  fourth argument when its subscriptions should belong to that feature.
  `HasCommand(name)` supports configuration controls for optional features.
  `UnregisterOwner` removes event subscriptions, not commands or queued jobs.
- `Changed()` schedules persistence after modifying plain configuration.
  `SetProfile(name)` returns `true` or `nil, reason`, cancels dragging and
  applies the chosen layout outside combat and pending setup operations.
- `Secret.Read(reader, ...)` preserves all `pcall` return slots, including nil.
  `Secret.Apply(sink, reader, ...)` forwards successful results to a protected
  sink call. Neither turns unavailable data into zero. Inspect the success flag
  and `Secret.IsSecret(value)` before any operation on returned client values.

Module activation, events, commands, module diagnostics and combat work use the
internal `Runtime.InvokeOwned` boundary. It restores the previous owner after
success or failure, including nested dispatch. Subscriptions and combat jobs
created by a command inherit its captured owner; an unowned command does not
borrow its caller's owner. Diagnostic callbacks use their module as owner.
The helper retains `Runtime.Invoke`'s success flag and first-result contract;
use `Secret.Read` when every return slot must be preserved.

Use local functions for private behavior and publish only intentionally shared
methods. Keep feature state in its namespace or local upvalues. Namespaced
Blizzard frame globals and binding globals are intentional integration points.
Do not add global utility functions, mutate shared standard-library tables, or
pass opaque client values to persistence.

## Adding a feature

Create `src/modules/example/example.lua`:

```lua
local core = RikUI
local example = {}
core.Example = example

local function refresh()
    -- Read ordinary configuration from core.Profile here.
    -- Update only this feature's frames.
end

function example:OnEnable()
    core:RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
    core.Combat.Queue(function()
        -- Construct protected frames outside combat.
        refresh()
    end, "example:initialize")
end

core:RegisterModule("example", example)
```

Add its files to the TOC after the services it reads at file load. Add a dependency
option only if it requires another activated module. Register shared positions
through `RikUI.Layout`; use `RikUI.Hide` to park stock frames. Add settings to the
existing options conventions and persistent defaults to their owning schema.
Pair the change with a focused feature fixture. Add load-order edges to
`tests/architecture.test.lua` when introducing a new service dependency.

Protect client API boundaries that can be absent or fail. Keep secret-bearing
values flowing from readers into supported sinks; a Lua stub cannot emulate the
client's secret-value enforcement or protected-frame taint rules.

## Persistence boundaries

`codec.lua` owns the version-2 deterministic wire representation. Its dictionary
is append-only: reordering tokens changes existing saved data. Keys are sorted;
the encoder rejects cycles, non-finite numbers and excessive nesting or size.
The bounds are 32 table levels, 8,192 visited nodes and 21,600 encoded bytes.
Unsupported nested values retain the previous omission behavior. Encode/decode
return `nil, reason` on failure; decoded `false` is a valid result.

`store.lua` owns CVar chunking, checksums, registration and scheduling. It checks
header bounds before reading chunks, verifies chunk lengths and checksums, and
encodes each account/character payload once per flush. Reload backups alternate between two checksum-verified CVar banks; a bank header commits last, so interrupted writes preserve the other bank. Legacy v2 snapshots remain readable. The fallback poll still
detects direct DB mutations by older call sites.

`store-macros.lua` owns compact default-diff snapshots and the restart transport.
Its pruning is cycle/depth/node bounded. Snapshot construction does not mutate
the last accepted character snapshot before encoding succeeds. Invalid input
does not write partial payloads. A client write failure is reported, but the
client transport does not provide an atomic transaction across multiple writes.

Profile repair preserves valid false values and unknown settings, replacing
wrong types, non-finite defaulted numbers and cycles through known schema fields.
The core profile-schema service supplies shared constraints for restored settings and portable imports. Repair resets invalid known values, retains valid false values and unknown extensions, and permits compatible partial saved anchors; portable imports require complete anchors. This is not a general migration engine.
The existing settings names, dictionary and transport version remain compatible.

## Cost and verification

The event bus has one native frame and does not copy subscriber arrays on each
dispatch. Removed entries compact after the outermost dispatch only when needed.
The combat queue advances indices instead of shifting the entire array per job,
making drain bookkeeping linear in the queued entry count. Keyed coalescing
releases superseded callbacks. Hidden party/raid frames skip range queries only
when visibility is a readable false; unknown or secret visibility uses the
existing safe path. These are verified algorithmic changes, not an FPS claim.

From the repository root:

```text
luajit tests/run_tests.lua
python tests/check_manifest.py
git diff --check
```

The Lua suite compiles and loads the real TOC in an isolated environment, checks
file-load global ownership and prerequisite order, and exercises lifecycle,
events, queueing, settings and feature behavior. Reduced feature fixtures use
`tests/load_addon.lua` to compose the core from the production manifest.
The Python guard checks that every production Lua file under `src/`, `data/`
and `presets/` appears exactly once with canonical case and safe relative paths.
It also rejects leftover root runtime Lua files and checks the SVG/TGA inventory
against the literal icon registry, then compiles all runtime, probe and test Lua
files using LuaJIT without executing them. The Lua suite validates built TGA headers.
The project's standard `check` gate runs this guard. Developer verification needs
Python 3 and LuaJIT; the installed addon has no new runtime dependencies.

Native validation still requires the Forever client: restart after installing
the moved source tree, inspect `/rik help` and `/rik debug`, switch a profile,
exercise combat enter/leave, reload with a module disabled and inspect dependent
unit auras, then relog/restart to verify settings. Check party/raid visibility and
range changes in real groups, and inspect Lua/taint errors. Automated stubs do
not establish native secure behavior, client compatibility or visual correctness.
