# Forever quest planning

## Current implementation

RikUI has separate evidence ingestion, live observations, tri-state eligibility,
directed travel search, bounded action optimization and tracker/map guidance.
It calculates sequences when sufficient inputs exist. It does not yet ship a
verified world quest corpus or claim complete Dun Morogh coverage. With missing
travel/action evidence, guidance shows current quest observations without an ETA.
The native Magistr roadmap tracks the remaining implementation; this document
defines the architecture and implemented contracts, not roadmap status.

The observer is the questplanner module, enabled through the ordinary module
lifecycle. After installing the new TOC entries and restarting the client,
`/rik quests` reports the detected build/locale, observation state, and observed
versus reported log counts. Disable questplanner in module settings and reload
to stop collection. The tracker gains a compact guidance row; map markers and an
optional arrow identify destinations without inventing traversable paths.

Observations are session-local. No quest corpus, history or snapshot enters
RikUI's profile/CVar/macro transport, whose codec is bounded to 21,600 bytes.
Durable acquisition needs a separately validated transport on this beta.

## Product decisions

The default objective is fast leveling with sensible risk and travel limits.
Routes may cross zones but must respect pinned quests and avoided areas.
Useful class quests and travel unlocks participate; dungeons are optional.
Self-contained data and calculations, integrated tracker/map guidance, and an
optional arrow are working defaults from the architecture discussion.

WoWForever is its own content product. It includes new and changed content.
Classic Era is a possible reference source, not the definition of the world.
Identical quest IDs do not prove identical requirements, rewards or locations.
No Zygor implementation, guide text or data is copied into this feature.

## Ownership and interfaces

Files load in this order, with core services already available:

- quest-schema.lua creates RikUI.QuestPlanner and owns bounded input contracts.
- quest-evidence.lua owns exact-identity world evidence catalogues.
- quest-corpus.lua owns source revisions, retirement and coverage.
- quest-reader/context/journal.lua capture session character state and events.
- quest-transfer.lua owns a separate bounded observation wire format.
- quest-eligibility.lua evaluates three-valued conditions.
- quest-travel.lua searches explicitly declared directed connections.
- quest-actions/simulation/optimizer.lua calculate bounded hypothetical sequences.
- quest-dataset.lua validates compiled region packs and live objective bindings.
- quest-controller.lua schedules, cancels and publishes revision-matched jobs.
- quest-guidance/view/navigation/transfer-view/commands.lua present outputs.
- questplanner.lua owns module activation and coalesced event refreshes.

Eligibility, travel and action search consume explicit inputs and never depend
on tracker frames or map widgets. Rendering does not implement planning policy.

### World evidence

`RikUI.QuestPlanner.Evidence.New(identity)` returns a private catalogue, or
nil and a reason. Identity includes product, exact build and locale, such as
forever / 1.60.1.69913 / enUS. Each catalogue has one identity.

`catalogue:Add(questID, field, value, source)` returns true or nil and a reason.
A source has a stable revision ID, matching product/build/locale and authority
verified or reference. Authority is a declaration by the ingestion adapter;
it is not independently certified by the catalogue. Adapters must justify
verified with recorded evidence. Cross-identity assertions are rejected.

Supported fields include title, level, minLevel, baseXP, repeatable, startNPCs,
endNPCs, locations, prerequisites, requirements, zoneID and clientRecord.
Locations are mapID plus normalized x/y;
they do not establish traversability. Prerequisites use always, active,
completed, all and any expressions. Completed means a turned-in predecessor;
it is distinct from the reader's objectivesComplete flag. Always asserts no
prerequisite in this expression, not general quest availability. Race, faction,
class, reputation and exclusion conditions are evaluated by the eligibility
contract below; missing rules remain unknown.

`catalogue:Resolve(questID, field)` returns a detached result:

- unknown / missing: no evidence exists.
- unknown / unverified: references exist but no verified assertion exists.
- known: verified assertions agree, including a meaningful false or zero value.
- conflict: verified assertions disagree; no chosen value is exposed.

All retained evidence is included for inspection. References cannot override
verified facts. NPC sets and operands within each all/any expression are sorted
and deduplicated. This is structural normalization, not logical equivalence
proving. Location list order is retained.

An individual catalogue is append-only. Repeating the same source and
value is idempotent; silently changing that source's value or authority is
rejected. A new source revision preserves both assertions and may expose a
conflict. Corrected corpus releases must currently build a new catalogue from
their declared active sources, retaining the prior manifest for audit. Explicit
supersession/retraction and manifest validation are implemented in corpus ingestion.

Bounds: 4,096 assertions per catalogue, eight sources per field, 64 list items,
256 nodes and 8,192 string bytes per assertion value, depth ten, and 2,048 bytes
per string. Invalid IDs, nonfinite numbers, sparse lists, secrets, metatables,
cycles and unsupported fields are rejected before mutation. Inputs and outputs
are copied. No character observations are automatically promoted to world facts.

### Character observations

`RikUI.QuestPlanner.GetSnapshot()` returns a detached snapshot plus status.
Before the first successful read, the snapshot is nil. A successful snapshot
includes identity, generation, optional observedAt, quests keyed by ID, log
order, observedCount, reportedCount, coverage and hasUnknown.

Each quest has id, readable title/level, objectivesComplete, failed, a structured
objective list when available, and an unknown map for unavailable fields.
Objective text describes displayed progress; it is not parsed into target IDs.
There is no turnedIn history, reward XP or inferred prerequisite field.

The reader recognizes the current Forever 1.60 client family with interface
16001 and records the exact returned build and locale. An unfamiliar client or
unreadable identity is rejected rather than labelled Forever. Supporting a new
client family requires explicit capability research and tests.

A scan reads GetNumQuestLogEntries and every shown GetInfo row, including
unwatched quests and IDs absent from any reference dataset. It reads
GetQuestObjectives, IsComplete and IsFailed for readable quests, then checks
counts again before publishing. It never expands headers, changes log selection,
adds watches, accepts, abandons or turns in quests.

Coverage is log-complete only when observed and reported counts match;
otherwise it is log-partial. Neither value describes all available quests or
world content coverage. A quest absent from a partial snapshot is unknown.
Even a readable log absence does not distinguish abandonment from turn-in.
Stable counts do not prove the client stayed identical: publication is atomic,
but client APIs do not provide an atomic multi-call read transaction.

Nil, failing or invalid optional reads produce unknown fields and partial
status, without carrying old values forward. A malformed row, secret ID,
duplicate ID, unsupported identity, invalid count or count drift aborts the
scan: the previous snapshot remains available with stale status and a reason.
An initial failure reports unavailable. Empty objective tables remain distinct
from unavailable objective reads.

Events coalesce for 0.1 seconds. Work is capped at 256 shown entries and
32 objectives per quest; exceeding a cap produces an explicit unknown/stale
result. Pending callbacks check module enablement before reading. The scan is
synchronous and bounded; actual frame cost still requires native measurement.
Runtime module flags follow RikUI's reload-required lifecycle.

## Remaining architecture

Content acquisition must discover Forever-only quests and changed fields using
target-build sources and contextual client observations. A failed lookup must
not imply removal. Eligibility after an event does not prove that event was its
prerequisite. Coverage reports must identify unknown denominators and avoid
claiming that a visible log enumerates the world.

The future action graph distinguishes pickups, objectives, turn-ins and travel
unlocks. It models shared objective areas, requirements, quest-log capacity,
level progression and player constraints. Travel uses directed traversable
connections and known unlocks/cooldowns; coordinates alone never imply a route.

A bounded lookahead planner will compare feasible action bundles using expected
travel, combat, looting and downtime costs, with risk and route-change penalties.
Pins and avoided content are constraints. Class and travel unlock value needs
downstream evaluation. Replanning follows material state changes, preserving the
current action unless it is invalid or another route is materially better.
The result is a calculated feasible plan, not a claim of global optimality.

Validation should compare against nearest-quest and authored-route baselines,
use exact optima on small fixtures, and replay skipped quests, dungeon leveling,
shared objectives, changed chains, unknown transport and new Forever content.
Native checks must include frame time, map traversal and interaction behavior.

## Evidence and verification limits

The local Zygor Classic revision 37145 review found authored leveling steps,
FindStartingPoint in Code-Classic/QuestDB.lua, and destination travel search in
LibRover. These are architectural observations, not comparative performance
measurements.

Pinned extracted client source used for this adapter:

- [QuestLog API](https://raw.githubusercontent.com/Gethe/wow-ui-source/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua):
  nullable quest info/objectives, log counts and separate completion flags.
- [QuestMapFrame](https://raw.githubusercontent.com/Gethe/wow-ui-source/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua):
  native search expands/restores collapsed headers.
- [QuestInfo](https://raw.githubusercontent.com/Gethe/wow-ui-source/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/QuestInfo.lua):
  reward XP reads depend on selected-log or dialog context.

Tests use synthetic quest IDs and exercise evidence isolation, conflicts,
normalization, limits, full/partial/failed observations, secrecy guards,
copy isolation, event coalescing and disabled callbacks. Stub success is not
proof that these APIs return ordinary values on the live beta.

Native acceptance still needs a client restart, /rik quests with watched and
unwatched quests, collapsed/expanded headers, quest acceptance/progress/turn-in,
combat reads, and a reload with questplanner disabled. Capture build, counts,
status and any Lua errors. No native capture or route benchmark has been claimed.

## Corpus ingestion and local acquisition

The ingestion pipeline is implemented independently of content acceptance.
`Corpus.New(identity, sources, revision)` validates a maximum of 64 source
manifests. Each source pins raw bytes with SHA256, a parser revision, a source
revision, URI, terms/uncertainty and exact product/build/locale. The acquisition
tool also emits its actual parser SHA256. Checksums establish byte identity,
not source authority or redistribution rights.

A builder accepts detached batches of at most 64 assertions. Any failed batch
permanently invalidates the candidate; nothing is published until Finish.
The release has at most 32,768 assertions, 8,192 quests, 262,144 counted data
nodes and 4 MiB of string content including provenance. Each quest has its own
small evidence catalogue, avoiding a world-wide 4,096-assertion ceiling while
preserving the per-field eight-source bound. Batches bound validation/copy
work; the caller schedules batches. Finish sorts at most 8,192 IDs. Coverage
and full ID/source reports are explicit diagnostic/offline queries, not frame
update operations; native timing remains unmeasured.

Sources use complete-snapshot semantics with an exact declared assertion count.
A successor may explicitly supersede one revision of the same dataset; old
revisions must be marked superseded. Retraction requires a reason. Cycles,
missing predecessors, cross-dataset replacements and competing successors are
rejected. Delta releases are unsupported: unchanged assertions must be repeated
in a replacement snapshot. Published releases are immutable, so rebuilding
after correction never mutates a planner's existing release. Retired source
descriptors remain auditable; archive complete release manifests outside the
bounded runtime list instead of accumulating unlimited history in the addon.

Coverage reports known, conflicting, unknown and the reference-only subset for
each field among catalogued quests, plus records with unknown zone attribution.
The world denominator is always explicitly unknown. Known-empty values remain
known. `clientRecord=true` means membership in the exact client table, never
quest availability; `zoneID` also requires its own evidence.

`tools/quest_acquire.py` reads a local source or HTTPS response, checks raw-byte
SHA256 before parsing, and prints deterministic JSON. QuestV2 ingestion accepts
only the demonstrated ID/UniqueBitFlag/UiQuestDetailsThemeID schema; only
clientRecord assertions are emitted. Cache inventory validates the 69913 enUS
WQST record-version-12 framing and hashes opaque payloads; it deliberately
does not decode quest semantics. Both tools reject oversized, malformed or
unexpected input. No tool modifies the game cache.

Reproduced on 2026-09-20:

- Wago QuestV2 1.60.1.69913: 6,600 rows; raw SHA256
  `07353cb935ef0907a71c2e51f2aeed4d6460712d4011cb3873f759af5536df4a`.
  [Exact export](https://wago.tools/db2/QuestV2/csv?build=1.60.1.69913).
  This is a client-index count, not a world quest denominator.
- Local questcache.wdb now contains 14 records, including 98326; SHA256
  `be325f2f3aec16c33f277fd720b5787ca856768d263345bbdf6087a922d5cb4e`.
  The earlier 13-record file is a different observation.
- [Pinned framing reference](https://github.com/Marlamin/WoWFormatLib/blob/be7ee3015733628ee6cba163a2a9c20d086a8325/WoWFormatLib/FileReaders/WDBReader.cs)
  reverses the four-byte signature and locale. Its semantic reader skips this
  expansion family and has not been used to decode Forever quest fields.
- Wago POI data examined in source research contains no Dun Morogh map 1426.
  The three new local quest IDs have no demonstrated prerequisite/XP semantics.
  Public site values without individual build provenance remain references.

Direct Python HTTPS acquisition returned HTTP 403 in this environment.
PowerShell Invoke-WebRequest obtained the public CSV with the pinned raw hash;
the same parser successfully ingested that local file. Acquisition failure
never authorizes substituting another build or fallback dataset.

`Transfer.Encode(snapshot)` / `Decode(packet)` use a separate RIKQ1 printable
hex packet with an Adler32 corruption check. Bounds: 128 KiB wire, 16,384 nodes,
depth 16 and 2,048 bytes per string. Unsupported data, duplicate keys, malformed
lengths, nonfinite numbers, inconsistent log indices/counts and trailing bytes
are rejected. Decode labels packets imported-untrusted; imports cannot become
live observations or world evidence. This is manual export, not automatic durable
persistence. No data enters profiles, CVars, macros or SavedVariables.

Three additional user-supplied current 9/9 observations corroborate repeated
reads. Their counts do not verify objective transitions. Combat and disabled
module checks were explicitly not run. Copy-window/clipboard/restart behavior
and live performance remain acceptance obligations of the content/interface
workstream; synthetic tests do not satisfy them.

## Action eligibility

`Eligibility.Condition(condition, state)` evaluates bounded AND/OR/NOT expressions
with true/false/unknown semantics. False dominates AND; true dominates OR; NOT
preserves unknown. Predicates include active, completed (turned-in only), class,
race, faction, level bounds and explicit flags. Exclusions and breadcrumb choices
are expressions supplied by evidence, never inferred from quest order. The
schema normalizes distinct predicate values without collapsing class alternatives.

`Eligibility.Evaluate(action, state, catalogue)` returns eligible, blocked or
unknown and reason strings. Actions are pickup, objective and turnin. Pickups
require known prerequisites, complete additional requirements, log capacity,
known absence from the active log and explicit turn-in/repeat availability.
Known repeatability alone cannot authorize an immediately repeatable pickup.

An already accepted quest can progress or turn in using readable current
activity, failure and objective-completion flags without inventing its pickup
rules. Partial logs establish presence but not absence. Stale/imported state and
catalogue identity mismatches never produce eligible actions. The snapshot
adapter copies current activity and separately supplied historical flags; it
never interprets a vanished quest as a turn-in. All actions remain advisory.

The logic is tested on original synthetic rules, including changed/skipped chains,
class constraints, full logs and conflicts. Validation against real newly added
and changed Forever chains remains in the corpus acceptance requirements.

## Directed travel

`Travel.New(identity, revision, nodes, edges)` validates an immutable directed
graph of at most 512 nodes and 2,048 connections. Each edge declares verified
or reference provenance, traversed zones, mode, finite nonnegative time, risk
and uncertainty. Coordinates never add connections. Reference-only traversability
is excluded even when a policy accepts uncertain cost estimates.

`graph:Begin(from, to, state, policy)` creates a private incremental search.
`job:Step(work)` advances at most 128 queue/edge operations; default 64.
`Estimate` is the synchronous convenience for offline/tests. Runtime callers
must budget travel work within the enclosing replan. Defaults cap each leg at
1,800 seconds, cumulative risk/uncertainty at 0.5, 2,048 allocated labels and
8,192 work operations. Results include actual work/label counts.

A min-time heap retains nondominated time/risk/uncertainty labels separately for
used/unused hearth state. Nonnegative increments and FIFO waiting permit this
pruning. Periodic transport waits for the next departure; flights require known
unlocks at both ends. Hearth needs the actual bind and readable readyAt time.
All times share the supplied clock origin. There is no per-edge waiting cutoff:
waiting counts toward the total leg limit, avoiding unsound early-label pruning.
At most one hearth is admitted per leg. Its consumption time is returned; a
simulator must disable further hearth use unless it knows the new cooldown.

Results distinguish known, no-known-route, unknown input and budget-exhausted.
A limited result can carry a feasible incumbent, never a shortest-path claim.
A popped terminal is fastest only within the admitted graph/model and constraints,
not the real world or missing graph. Avoids apply to explicit intermediate zones;
starting inside an avoided corridor can leave no admitted escape. There is no
mutable-state cache: each request snapshots unlocks, cooldown and policy.

Fixtures verify directional gaps, locked flights, changed cooldowns, periodic
waiting, risk tradeoffs, intermediate avoids, zero-cost cycles, deterministic
slices and exhaustion. They do not establish a traversable Dun Morogh graph or
native frame cost.

## Calculated action search

`Actions.New` accepts at most 40 sourced, exact-build action bundles. Pickup
declarations can describe complete objective counters; shared progress requires
an explicit common key. A bundle executes once per hypothetical route, so its
progress and combat/looting/interaction/downtime estimates must cover that bundle.
The simulator carries log slots, historical turn-ins, consumable items, flight
unlocks, hearth consumption and known level thresholds. Effects never mutate
observations or evidence. Missing XP or thresholds cannot unlock a level rule.

`Optimizer.Begin` creates a cancellable coroutine job. `Step` consumes a work
budget; the synchronous `Plan` wrapper is for tests/offline use. Defaults are
six actions of lookahead, beam width 24, 5,000 transitions and 50,000 aggregate
travel operations. Depth is capped at eight. Candidate state copies are bounded
to 4,096 nodes/64 KiB of strings. Each beam has at most 24 states; old and new
layers plus the best/current-action candidates can coexist during expansion.
These are operation/allocation limits, not a measured millisecond guarantee.

Pins prioritize completion then progress within the horizon; infeasible pins
remain explicitly deferred. Avoids apply to actions and all declared traversed
zones. Skip is a persisted planning preference, never a quest abandonment.
Dungeons are excluded unless requested. Known reward plus configurable class
and travel-unlock value is divided by modeled elapsed time, with risk/uncertainty
penalties. These weights are policy, not XP facts. When no reward is known,
feasible completed work ranks ahead of a stranded partial sequence; the result
still reports unknown XP. Deterministic ties and a 15% material improvement
threshold retain a still-feasible current action.

Results expose bounded-search exhaustion, omitted eligibility/travel reasons,
unknown rewards, deferred pins, input generation and graph revision. They
describe calculated feasible sequences in the admitted model, with no global
optimality claim. Missing walk connections are never replaced by coordinate
distance.

An original three-turn-in fixture matches exhaustive enumeration of 15 feasible
states: 18.182 XP/second versus 15.000 for nearest-next and 14.000 for a fixed
original order (each baseline gets its best prefix). The graph search can use
indirect connections, so baseline time is shortest admitted travel, not the
direct edge. Additional replays cover skipped prerequisites, full logs, shared
objectives, consumables, level changes, optional dungeons, downstream flight
unlocks, cancellation and missing data. This is algorithm evidence, not a
Dun Morogh speed or native performance claim.

## Live controller and guidance

The controller reads bounded current attributes, up to 40 active quest waypoints
and completion flags, and the selected quest's contextual reward XP. It does
not change quest selection or assume an arbitrary-ID XP API. Quest dialog and
turn-in events are stored in a 48-entry session journal with a dropped count.
Objectives-complete, historical completion and actual turn-in event XP remain
different observations.

Compiled regional packs require active source manifests for action, travel,
binding and interaction-anchor records. Objective binding requires the complete
matching objective list, type, total and normalized localized text. Changed
Forever objectives cannot inherit a Classic mapping. A current NPC interaction
can locate the character only at an explicitly sourced, unambiguous graph anchor.
Coordinate proximity alone is not a location-on-graph test. A currently open
turn-in dialog can also supply a session-only interaction action without world
data; its three-second interaction cost is a model, not an observed duration.

Material quest/context changes cancel prior searches. Publication checks the
job revision, module state and pause state. Live search uses depth six, width
16, at most 1,200 transitions and 12,000 travel operations. A frame requests up
to 64 smallest search steps, stopping after a one-millisecond timer threshold
between steps when the API is readable. An indivisible step can exceed that
threshold; actual maximum slice duration is diagnostic, not a proven native
latency bound. Repeated identical snapshots do not restart work.

The compact tracker row keeps the existing watched list and respects collapse
and available height. `/rik quests show` opens details, with eight rows per page.
Map markers show up to eight destinations; they do not connect points with
invented walking lines. The optional arrow is explicitly a destination bearing
and hides when orientation or same-map location is unavailable.

Commands: `/rik quests` (status), `show`, `map`, `pin QUEST_ID`,
`skip QUEST_ID`, `avoid MAP_ID`, `pause`, `resume`, `arrow on|off`,
`dungeons on|off`, `reset`, `export` and `inspect`. Pins/skips/avoids
toggle; reset clears those constraints. Only preferences (at most 32 entries
per constraint map plus three booleans) use ordinary settings persistence.
The planner never automatically accepts, abandons, watches or turns in quests.
Pin conflicts suppress actionable guidance and deferred pins remain visible.

Export opens a separate printable copy window, bounded to 131,072 wire bytes.
It includes session observations/context/journal; oversized exports fail visibly.
Inspection labels pasted observations untrusted and cannot install them into
live planning. Copying data to a durable external file is an explicit user
operation; no observation history is stored in RikUI macros.

Automated API/widget replays exercise actual controller, optimizer, controls,
projection, cardinal arrow math, cancellation, changed objective bindings and
transfer quarantine. They do not establish native visuals, performance or
traversability. The user supplied three current 9/9 log snapshots; these do not
establish a progress/turn-in transition. Combat and disable/reload checks were
explicitly not run. The user requested no computer use, so native automation
is excluded and the roadmap retains real-client acceptance as unverified.
## Locally acquired terrain guidance

The offline pipeline in [tools/terrain](../tools/terrain/README.md) now extracts
and verifies a small exact-build Dun Morogh region from the installed client,
decodes terrain holes and static M2/WMO collision, and bakes a filtered polygon
graph. It uses pinned tools, source hashes and parser hashes. Raw assets and
generated geometry remain outside this repository and the settings transport.
The companion addon requires RikUI and contains only the local compiled mesh.

The initial region is one ADT tile, approximately map 1426 coordinates
47.42–58.25% X and 44.35–60.60% Y. Its 81 shards contain 4,322 convex polygons
and 8,484 directed portals. Three WMO header/count inconsistencies remain
unresolved: all polygons intersecting their full placement footprints, expanded
by the modeled radius, are excluded. Polygons outside the acquired tile are
also excluded. This is partial coverage, not a complete Dun Morogh graph.

Source authenticity, static decoding, modeled traversal and native verification
remain separate. Dynamic doors, phasing, spawned objects, enemies, swimming and
transports are not modeled. The sample radius/height/climb/slope parameters are
not calibrated Forever physics. Runtime status says terrain estimate and
traversal unverified. Terrain does not establish quest requirements, locations,
XP or availability, and never promotes observations into world evidence.

The compiler validates the exact supported profile, hashes, coverage gates,
bounds, exclusions, convex topology and cross-shard portals before writing an
exclusive new output directory. The raw Detour diagnostic binary is never
loaded by Lua: it includes geometry excluded from the runtime JSON graph.

At runtime, one regional mesh is validated incrementally, 32 polygons per
frame, with a second pass checking portal targets. Limits are 8,192 polygons,
32,768 portals, 128 shards, 512 polygons per shard and 4,096 spatial grid cells.
Each point-location cell has at most 512 candidates. Portal heights must agree
with their source edge and cross to the target within the declared 0.3-yard
modeled step plus quantization tolerance; horizontal adjacency cannot join floors. Location requires unique
containment; readable player world height selects a floor within one yard.
Missing height does not permit nearest-floor snapping. Map/world disagreement,
cross-build data and ambiguous or uncovered points suppress terrain guidance.

The deterministic A* job yields between queue and edge operations, with 64
operations per frame, 32,768 work operations per request and at most 1,024
corridor polygons. Costs use polygon centers and declared portal midpoints.
The Euclidean heuristic is admissible for this graph, but the result is neither
a continuous geometric optimum nor a claim of real-world walkability.
Remaining guidance follows corridor order as the player moves; it does not
cut across nearby walls by selecting the closest later waypoint. Time uses
readable run speed or an explicitly modeled seven-yard/second default.

Map guidance draws at most 128 actual corridor segments. The optional arrow
points to the next corridor portal when terrain guidance exists and otherwise
labels its destination bearing. Pausing, stale plans and unavailable location
hide actionable terrain guidance. Native map projection, floors, movement,
visuals and performance remain unverified; no computer use was performed.

Reproduction from committed tools passed 38 parser/acquisition/geometry tests
and matched all 83 rebaked files. The compiler passed 37 adversarial tests.
The real compiled dataset loaded through the production Lua pathfinder, and
three routes matched an independent Dijkstra calculation (maximum 8,100 search
operations). One headless LuaJIT run loaded it in 32 ms over 271 slices; the
coarse timer reported maximum load and search slices of 1 ms. These are local
test measurements, not native frame-time guarantees. After adding vertical portal
checks, a later run loaded in 42 ms with a maximum 2 ms load slice; the search
maximum remained 1 ms on that run.
