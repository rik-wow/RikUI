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

Live observations are session-local. No quest corpus, history or snapshot enters
RikUI's profile/CVar/macro transport, whose codec is bounded to 21,600 bytes.
Explicit RIKQ1 exports can be archived and verified with the separate offline
importer; this does not provide automatic persistence on this beta.

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
- quest-objectives.lua compares complete objective definitions and edge counters.
- quest-evidence.lua owns exact-identity world evidence catalogues.
- quest-corpus.lua owns source revisions, retirement and coverage.
- quest-reader/context/gossip/journal.lua capture session character state and events.
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

Native captures establish repeated complete log reads and manual export, as
recorded below. Watched/header variants were not individually labelled. Actual
acceptance/progress/turn-in transitions, guidance interactions and native frame
cost remain unverified. Combat and disable/reload checks were not run; the user
has deferred them. No native route benchmark has been claimed.

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
module checks were explicitly not run. A later actual RIKQ1 packet establishes
one successful export/copy flow and durable offline round trip. Native guidance,
transitions and live performance remain acceptance obligations; synthetic tests
do not satisfy them.

## Durable observation acquisition

[tools/observations](../tools/observations/README.md) provides bounded offline
inspection, exclusive archive creation and read-only archive verification. It
retains exact RIKQ1 bytes, parser revision/hash, checksum, declared identity and
a lossless Lua-table representation, including numeric/string keys and arbitrary
bytes. Archives are capped at 2 MiB and live outside Git, the addon and settings.
Verification rereads the saved packet and compares derived content and hashes;
neither those hashes nor a declared build authenticate world facts.

The first user-supplied 69913/enUS packet passed the actual Lua/Python protocol
and durable reread checks: 7,699 wire bytes, checksum `06701554`, SHA256
`17db56a78cbefea8ce14acf351a807ff0c62d736d31f518b002e534877634acd`.
It records nine current quests, including the new IDs 96608, 98319 and 99158.
Quest 99158 has objectives complete, with historical turn-in false. Quest
96608's second objective has 1/1 count but a false finished flag; that distinction
is preserved. No locations or reward XP were returned by the earlier adapter.
The older initial observed-progress label is not evidence of a later transition;
the current journal explicitly labels the first snapshot initial-observation.
This is field-level character evidence, not verified world prerequisite data.

Protocol validation includes 39 adversarial Python tests, 460 acceptance
comparisons against the actual Lua codec, and 1,028 generated numeric cases.
The raw character packet is intentionally not a repository fixture. Future
exports retain explicit API statuses to diagnose absent target/reward data.
A second native packet (16,263 wire bytes, checksum `fcd0d8e1`, SHA256
`0df983793cab32e243a7cde4592c7c4546d8c69b6697c1ba893b12fb1ac029e5`)
confirms the POI fallback and passed both decoders plus durable reread. Its eight
map locations remain current-character observations. Quest 96608 has no map
result; reward XP is absent because no active quest was selected. The native
terrain addon reports an unknown location, which confirms loading but not a
successful route. Actual quest transitions remain unverified.

A third packet (17,371 wire bytes, checksum `8dbb9a00`, SHA256
`6ca7154c5b40a8a98a2713a647cda86e790f1223337a66a86cdaf7efa3634a97`)
passed the actual Lua decoder, Python import and durable reread. It includes two
journal entries (initial-observation and observed-change for quest 384), both
exported, with zero dropped or omitted entries. The unchanged current log and XP
do not establish progress or turn-in. The user confirms only export was run, so
no NPC dialog event was expected. Native dialog/transition checks remain pending;
the user has declined travel to a quest completion for testing. The newer player
point is outside generated walkable polygons, and raw vertical zero remains
explicitly unestablished.

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

Steering looks ahead along approximately 24 yards of portal geometry, retaining
a minimum 12-portal horizon and a hard 64-portal cap. This prevents dense mesh
subdivision from shortening the aim to a nearby breadcrumb. Progress follows
the currently occupied corridor polygon, including off-center movement; touching
a center or previous aim is unnecessary. Every forward shortcut still proves
ordered crossings through the actual portals and modeled surfaces.
Within that horizon, the preferred aim follows the destination direction clipped
to the visible portal interval, then continues along that ray inside the entered
polygon. Polygon centers are fallback candidates, not mandatory steering targets.
A bounded ten-step containment search and ordered crossing proof constrain the
ray. The active corridor and arrow refresh every frame to avoid stale aims after
lateral movement. If the final destination lies behind a visible portal, steering
uses the local corridor direction rather than its midpoint. A previously valid aim
is retained or adjusted within the checked visible window when a new choice would
reverse direction; every retained segment is re-proved from the new position.

Tracker instructions refresh every 50 ms and the arrow every frame: turn/bear/continue plus yards to the current steering aim, with estimated
remaining route length underneath. At the modeled endpoint they ask the player
to check the quest target; proximity never completes a quest. Missing facing
uses a compass direction in the tracker. Unavailable routes retain the diagnostic
status. The marker-only arrow shows compass direction and straight-line distance
(e.g. "Marker E · 120 yd") with "No walking route", "Route loading", or
"Finding walking route". It gives no walking instruction across an unknown gap.

Animated yellow dots follow the terrain route on both world map and minimap,
independently of the optional arrow. They never extend across an unverified
marker gap. World-map dots use canvas coordinates; minimap dots use the readable
[C_Minimap view radius](https://raw.githubusercontent.com/Gethe/wow-ui-source/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/MinimapDocumentation.lua),
map world size and current rotation, hiding when scale is unavailable.
Clipping respects RikUI's square minimap or the native circular boundary.
Pools cap at 256 world-map and 96 minimap dots, with at most 16 new textures per
surface per update; sampling caps at 2,048 segments and 1,024 candidate dots.

Widget replays exercise both maps, animation direction, rotation, changing
instructions, unavailable scale and invalidation. Installed-mesh movement replay
also exercises display projection on the archived quest marker. These establish
modeled calculations and widget calls, not actual native rendering or walking.


The controller reads bounded current attributes, up to 40 active quest waypoints
and completion flags, and the selected quest's contextual reward XP. It does
not change quest selection or assume an arbitrary-ID XP API. A read-only fallback
uses at most 256 POI rows from the character's current map. It requires a unique
active-quest row, matching map ID, no child depth, and explicit non-start and
non-map-indicator flags. A valid waypoint takes precedence. Duplicate POIs stay
ambiguous; a point never implies a particular objective, NPC or walkable route.

Target, map-POI and reward statuses separately report observed, no-result,
unavailable, rejected, ambiguous or query-limited results, with API/reason
provenance. Unknown reward stays absent; observed zero remains zero. The status
command reports location/reward counts and map-POI state. The fallback follows
[pinned Blizzard map-provider usage](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedMapDataProviders/QuestDataProvider.lua#L129),
and a second user-supplied 69913/enUS export confirms eight current-map POI
locations from this fallback. GetNextWaypoint returned no result for all nine
quests; reward status reported no selected active quest. Other map/quest contexts
remain unverified. Quest dialog and
turn-in events are stored in a 48-entry session journal with a dropped count.
Objectives-complete, historical completion and actual turn-in event XP remain
different observations.

On GOSSIP_SHOW, the reader observes available/active quest lists from the already
open NPC dialog. It verifies exact identity and an unchanged NPC GUID across the
reads. Lists are capped at 32 rows each, titles at 256 bytes, and the combined
journal entry at 512 nodes/8,192 string bytes/depth eight. Missing, duplicate,
secret, oversized or changing-NPC results are explicit; optional unknown flags
are never changed to false. A contextual offer is not a universal availability
rule. Player interaction coordinates are not NPC coordinates. No selection,
acceptance or turn-in is performed. The adapter follows the
[pinned gossip API contract](https://raw.githubusercontent.com/Gethe/wow-ui-source/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/GossipInfoDocumentation.lua);
actual Forever offer rows remain a native acceptance item.

Journal snapshots are recorded before planning, even if context acquisition or
replanning fails. Initial observations, newly seen quests, directional progress,
objective reductions, other changes and complete-log removals have separate
labels. A partial log cannot establish removal. Directional progress requires
matching complete objective definitions first; mixed movement or changed goals
remain generic changes. Only an edge current/required counter matching the
structured numeric fields is normalized. Other digits and goal text are retained.
Turn-in events retain received XP (including zero), exact snapshot identity and
readable event-time level; this does not establish base XP or reward-scaling level.
The status command reports the latest log-change label independently of log count.

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
latency bound. Repeated identical snapshots do not restart work. Change signatures
retain full objective text/type and quest level, separately from shortened UI
labels. Their 131,072-byte bound produces an explicit unavailable result and
clears actionable guidance rather than accepting a truncated signature.

The compact tracker row keeps the existing watched list and respects collapse
and available height. An explicit Arrow: on/off control in the tracker enables
or hides the optional direction guide; it is off by default and independent of
pinning a quest or calculating terrain. `/rik quests arrow on` enables it directly.
The guide appears near the top center of the screen when position and facing
are readable. `/rik quests show` opens details, with eight rows per page.
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
`Transfer.EncodeSession` preserves the current snapshot/context and selects the
largest fitting newest contiguous journal suffix, using at most seven encodes.
It reports available/exported/omitted entries separately from ring-buffer drops;
the copy window discloses omissions. The entire journal is validated before
selection, and live inputs are never changed. If the current snapshot/context
alone exceeds the protocol limit, export fails visibly without trimming it.
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

The current region combines exact source ADTs 32_42 and 33_42, cropped to the
original tile plus a 128-yard neighboring strip. Its 99 shards contain 6,213
convex polygons and 12,112 directed portals. An actual graph probe crosses the
source-tile boundary through baked portals. Framed WMO doodad records and
references have been independently checked; header-count differences remain
audit notes. Whole placement footprints with unmodeled liquid indications or
unsupported doodad flags remain excluded. This is partial Dun Morogh coverage.

The user's reported indoor point is now inside one modeled polygon, but its
14-polygon component has no connected exit in this model. Other observed POIs
are uncovered or disconnected. Expanding the source rectangle does not itself
establish a feasible quest leg or correct floor; missing paths remain missing.

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
containment. An explicitly established altitude could select a floor within
one yard. The observed UnitPosition third return is retained as `rawReportedZ`
with unestablished vertical status, never treated as a reliable altitude. The
user's indoor export reported zero while modeled surfaces are near 400 yards.
Without established altitude, exactly one containing polygon is required;
stacked surfaces and shared polygon boundaries remain ambiguous. Missing height
does not permit nearest-floor snapping. Map/world disagreement,
cross-build data and ambiguous or uncovered player positions suppress terrain guidance.
Exact destinations retain the same containment requirement; observed map markers
can use the explicitly bounded approach contract below.

The deterministic A* job yields between queue and edge operations, with 64
operations per frame, 32,768 work operations per request and at most 1,024
corridor polygons. Costs use polygon centers and declared portal midpoints.
The Euclidean heuristic is admissible for this graph, but the result is neither
a continuous geometric optimum nor a claim of real-world walkability.
Remaining guidance follows corridor order as the player moves; it does not
cut across nearby walls by selecting the closest later waypoint. Time uses
readable run speed or an explicitly modeled seven-yard/second default.

Map guidance draws the complete bounded corridor (at most 2,048 segments),
allocating at most 32 new lines per refresh until the full path is shown.
It never skips intermediate segments to connect a truncated path to the marker.
The optional arrow
points to the next corridor portal when terrain guidance exists and otherwise
labels its destination bearing. Pausing, stale plans and unavailable location
hide actionable terrain guidance. Native map projection, floors, movement,
visuals and performance remain unverified; no computer use was performed.

Region reproduction passes 52 parser/acquisition/geometry tests and eight
mesh-filter checks, with 101 identical rebaked files. The compiler passes 57
adversarial tests. Production Lua validates the real graph and checks its probe
routes against an independent Dijkstra calculation. All measurements are
headless model checks; native floor selection, traversal and frame time remain
unverified.

### Observed-marker approach endpoints

An observed current-map quest POI may identify an object or NPC rather than a
player standing point. `NavMesh:BeginMarkerApproach` preserves exact start
admission and first tries exact target containment. An ambiguous exact target
is rejected. Only an uncovered target can request a nearby modeled endpoint;
ordinary dataset destinations and current waypoints retain exact semantics.

The default one-yard displacement bound remains available to callers; live
quest-map POIs use an explicit eight-yard vicinity bound. This is assistance
policy, not measured marker accuracy, interaction range or permission to walk
through a gap. Candidate boundaries come from at most four existing spatial
cells, visited incrementally. The nearest endpoint is inset 0.005 yards, remains
inside the bound, and must have unique horizontal containment. Equally near
surfaces (within a .25-yard nearest-distance band) whose boundary heights differ
by more than the modeled step remain ambiguous. Distant hills elsewhere in the
vicinity do not compete with the nearest cave floor. Source bounds and excluded
footprints still constrain the entire vicinity. For an uncovered marker, the
nearest unambiguous endpoint must still connect through actual portals.

For an exactly resolved observed marker on an isolated component, live guidance
also enables `reachableApproach`. If the full directed search proves the exact
marker unreachable, it may retain a route to the closest reachable unique
endpoint within eight yards. Endpoint height must differ from the resolved
marker floor by no more than the existing modeled step; explicit target altitude,
ambiguous floors and excluded neighborhoods disable this fallback. Exact dataset
destinations remain strict. This is a partial approach, not repaired connectivity:
no final segment crosses the missing connection, and final-leg/interaction
verification remains false. The result records kind
`observed-marker-reachable-vicinity` and reason `exact-marker-disconnected`.
Candidate collection, graph search and final selection are sliced and cancellable;
work exhaustion never authorizes a partial-search fallback.

From the rounded Brewnall screenshot center 30.4,46.3, actual archived markers
317/384 previously resolved onto an isolated eight-polygon patch. The new route
ends 3.4573 yards from that marker through 208 real polygons. Eight of nine
rounding samples route; one start remains uncovered. Production movement replay
completes 2,961 off-center steps with zero reversals. The final portal aim turns
toward the endpoint before entering its polygon, avoiding an overshoot-and-return
at this approach. Bitter Rivals' current marker is absent from the archives:
these results do not establish that screenshot's exact destination or native
walking. Full-map terrain installation remains unfinished.

When an established unique floor becomes horizontally ambiguous during motion,
short displacements may preserve the previous modeled surface. Each displacement
is at most three yards, at most .5 seconds old, and must traverse explicit portals
in order, with a hard 64-polygon limit. Startup ambiguity, stale observations,
uncovered ground and unlinked walls cannot bootstrap a floor. Explicit native
altitude takes precedence. This is modeled continuity, never a native height read.
A fresh mesh, missing position, pause, invalidation or changed destination resets it.

Terrain search now uses available frame time: a two-millisecond threshold checked
between 64-operation batches, at most 16 batches per frame, or four when no clock
is available. These are scheduling bounds; an indivisible batch can exceed the
threshold. The total search-work limit and physical agent profile are unchanged.

The normal directed portal search must connect the admitted start to that
endpoint. It never connects disconnected components or adds a segment from the
endpoint to the marker. Results retain the original marker, API/scope provenance,
mesh revision, horizontal gap, and false final-leg/interaction verification.
The tracker says “Approach estimate; final gap unverified.” The arrow follows
the corridor and the original quest marker stays on the map. Arrival does not
complete an objective, turn in a quest, release a pin, or advance the selection.
No action, XP or quest-work duration is created. The physical bake profile is
unchanged, and a route near a marker is not a calculated leveling plan.

`tests/quest-marker-replay.lua <terrain-addon> <packet> [mapX mapY]` decodes an
external packet with the production Lua decoder, loads the actual companion,
and exercises both the mesh and production terrain coordinator. The optional
coordinate pair samples the center and eight corners/edge points inside the
rounding interval of a one-decimal-percent screenshot. Those are hypothetical
positions compatible with the display, not a recovered exact native position.

For the supplied Dun Morogh screenshot and latest archived quest markers, all
nine samples produced a 133-polygon modeled approach to Dawn in the Mountains.
The endpoint is 0.3773 yards from the marker; coarse center-graph paths are about
1,059–1,063 yards. Every corridor transition uses an exported portal. The
coordinator publishes the same endpoint and retains provenance. The earlier
indoor packet remains disconnected; the latest packet's older player start
remains uncovered; the first packet contains no observed destinations.
Thus this implements a route supported by the screenshot-area model without
claiming the archived starts have been repaired or that anyone walked it.
Headless timings and widget tests do not establish native performance, visuals,
floor selection, dynamic collision, or interaction reachability.

## Elevator travel

Elevators use explicit directed graph edges between distinct boarding and exit
stops. A lift record declares its transport and schedule revision, cycle period,
stop offset, boarding window, boarding duration, ride duration and exit duration.
The base duration must equal boarding plus riding plus exiting. Reverse travel
and connections to nearby floors are never inferred. Static terrain geometry
does not create moving-platform edges.

The character travel context must contain known lift availability and a matching
schedule phase with observation and expiry times in the same clock domain as
route departure. Missing phase is unavailable for this exact timing mode; zero
is never substituted. The phase must remain valid through predicted arrival.
If boarding cannot finish within the current window, the cost includes the next
cycle. The result retains ground wait, boarding, onboard wait, ride, exit,
absolute boarding/departure/arrival times, phase validity and an explicit lift
instruction. Published plans invalidate when their earliest boarding deadline
or phase validity expires; stale calculations cannot publish.
These are model outputs, not automated boarding or movement.

Synthetic checks cover missed/exact boarding deadlines, directedness, stale or
changed phase, expiry during travel, unavailable lifts, avoidance, and a safe
walking alternative. A sampled arrival-time sweep checks the FIFO property
required by earlier-label dominance in the travel search.

Target-build-query research found 1,016 TransportAnimation rows across 49 IDs,
but none joined the 1,514 GameObjects rows. Named lift markers are not evidence
of boardable instances. Rotation and physics exports were unavailable (HTTP 404),
not verified empty. No actual Forever lift edge is admitted. World placement,
rotation, reachable landings, direction, character availability, period and live
phase remain field-level acquisition obligations. Animation time range alone
does not establish a live repeating schedule.

Sources: [exact-build animation export](https://wago.tools/db2/TransportAnimation/csv?build=1.60.1.69913),
[object export](https://wago.tools/db2/GameObjects/csv?build=1.60.1.69913),
[pinned definitions](https://github.com/wowdev/WoWDBDefs/tree/83057bdc0cbe13062850ebf8ad530031e128a1cd/definitions).
The definitions' CC BY-SA 4.0 terms do not establish redistribution rights for
game data. Native boarding/traversal remains unverified.

## Current terrain status in guidance

The tracker, details window and `/rik quests` use the same current route status.
The status wraps across two reserved lines so the failure explanation fits the
compact tracker. Observed markers distinguish missing terrain, loading, missing
player position,
uncovered or ambiguous player/target locations, disconnected paths, search
limits and a modeled route estimate. Hovering retains the exact terrain failure
or estimated distance/time with traversal uncertainty. Calculated quest plans,
pause, unavailable observations and constraint conflicts keep their own status.

Terrain status changes refresh the view only when status or detail changes.
Material quest changes clear the previous corridor before publishing new
selection; unchanged signatures preserve the active request. Movement continues
to update map/arrow geometry through the existing navigation refresh. This
changes presentation and stale-state handling, not terrain physics or quest
facts. Widget and controller replays cover these states; native visual review
and an actual usable route from the supplied indoor points remain unverified.

## Breadcrumb anticipation replay

The installed western mesh and archived Frostmane marker were replayed from the
rounded 35.5,46.6 screenshot position. At a .35-yard stride, sub-three-yard steering
aims outside the final six yards dropped from five samples to one; both versions
completed with zero reversals. With the updated 50 ms terrain cadence, a 60 Hz,
seven-yard/second simulation completed 5,012 movement samples with zero reversals;
a delayed 200 ms update / 1.4-yard stride completed 418 samples with zero reversals.
These are modeled player inputs, not a capture of the user's movement. Tight-corner
fixtures sample off-center starts and reject segments through the missing quadrant;
portal winding and arrow-only refresh are covered separately. Native steering feel
and performance remain unverified. This Lua-only change loads with reload and adds
no terrain files or TOC entries.

## Corridor steering and offline visualization

The arrow now looks ahead within the selected polygon corridor instead of aiming
at every exit midpoint. A candidate segment must cross each directed portal in
order, away from its corners, and lie on both adjoining modeled surfaces.
Convex polygon containment keeps the intervening segments inside that corridor.
The horizon is bounded to 12 portals. For each future polygon, the follower first
tries its center (or the final endpoint). If that is occluded, it clips the entrance
portal to the angular windows of earlier portals, then tries an interior continuation
of up to six yards, halving it at most five times. Every candidate still passes the
ordered portal and surface checks. This can anticipate a bend before entering its
polygon without requiring the player to touch the old center breadcrumb. The old
quarter-yard continuation and exit midpoint remain conservative last fallbacks.
The maximum is 546 portal intersection tests plus angular clipping and one fallback;
there is no unbounded search in steering. This is local visibility, not a globally
shortest continuous path.

Terrain steering and arrow orientation refresh on a 50 ms cadence, with at most one
refresh per frame after a delay; map geometry stays on its 200 ms cadence. The map
shows the accepted leading shortcut followed by the remaining corridor.
A* still optimizes its center graph, not a globally shortest continuous route.

No polygon is added, no floor is selected by proximity, and the physical profile
is unchanged. Player admission and the one-yard observed-marker approach contract
remain strict. Looking ahead never draws the unverified final gap or completes a
quest. Native arrow visibility was reported by the user; native traversal and
post-change steering acceptance remain unverified.

For an isolated visual of the actual installed companion, run:

```text
luajit tests/quest-nav-visual.lua "<terrain addon>" "<archived packet>" 0.533 0.465 "<new external output prefix>" require-complete
```

This scenario replay decodes the external packet, loads production Lua and all
companion shards, and emits a standalone HTML viewer plus numeric JSON. It
simulates movement through the production terrain coordinator, checks unique
floor admission and monotonically advancing corridor membership, and records
arrow targets, sharp reversals and near-waypoint hides. Outputs contain mesh
geometry and scenario positions, not the character name or full quest log.
Keep them outside Git. The viewer provides playback, a time slider, pan/zoom,
polygon/height tooltips and route overlays; it makes no network requests.
Its source hash identifies the companion geometry.

Use `legacy` instead of `require-complete` to reproduce the old exit-midpoint
follower. An optional seventh argument sets simulated stride (.05–1.4 yards;
default .35). The replay uses .2-second refreshes; it is not native movement.
The strict zero-reversal assertion applies to this scenario, not every possible
route, since real corridors can require sharp turns.

```text
python -B tests/plot_quest_nav.py "<before.json>" "<after.json>" "<new comparison.png>"
```

The optional static renderer uses Matplotlib (verified with 3.11.1) and NumPy.
It refuses mismatched meshes/corridors or incomplete movement, and never
overwrites an existing image. For the rounded 53.3,46.5 start and archived Dawn
marker, both followers reached the modeled approach: the old one took 861
.35-yard steps with one reversal over 90 degrees and 108 near-waypoint hides;
lookahead took 783 with zero reversals and one hide near the endpoint.
The two extreme screenshot-rounding samples also completed at a 1.4-yard stride
without reversals. Desktop refresh timing was at most 1 ms at coarse clock
resolution; native performance is not established. Earlier archived indoor
starts still fail for their previously recorded coverage/connectivity reasons.

## Western Dun Morogh delivery (69913)

The user's 35.5,46.6 screenshot was outside the old Kharanos region (roughly
44.8–58.2% map X). The local companion now derives a west/central rectangle
from eight exact-build ADTs: X30–33, Y41–42. It includes the screenshot area
and archived Frostmane Hold marker, but is not complete Dun Morogh coverage.
See [terrain reproduction](../tools/terrain/WEST.md).

The shipping raster is .25 yard horizontally, .1 vertically; radius remains
.5 yard, height 1.8, climb .3 and slope 40°. Tiles remain 64 yards. Recast's generated
padding changes from 2 to 1.25 yards. This is a resolution change, not a calibration
of Forever player physics. The resulting local dataset has 37,644 polygons,
73,648 directed portals and 408 shards. Unknown structures and six encoded-liquid
cells retain full footprint exclusions, including agent radius.

Production Lua now admits a shared polygon edge only when matching modeled
heights are joined by actual incident portals. Disconnected coincident edges,
overlapping interiors and competing floors remain ambiguous. There is no player
position snap. Legacy WMO liquid type 15 with root flag 4 clear is correctly treated
as no liquid; an actual liquid chunk/flag still excludes the footprint.
Empty MODD may omit MODI; nonempty doodads still require valid reference tables.

The larger loader remains incremental. With a profiler it uses a 4 ms target,
checked after each 64-work batch, and never exceeds 32 batches in one frame.
Without a profiler it retains the conservative four-batch cap. This is a yield
target, not a hard wall-clock guarantee against a slow batch or garbage collection.
Polygon input uses a detached fixed-shape copy instead of recursive arbitrary-data
copying: only id/points/portals and to/left/right fields are admitted. The previous
31-bit positive-integer copy ceiling for IDs remains; all numeric, convexity, source-bound,
exclusion, target-boundary and vertical-step validation remains in force.
Cancellation never publishes a partially checked mesh. Quest invalidation does not
restart terrain preparation.

An installed-data replay with LuaJIT compilation disabled reduced preparation from
495 frames to 200–208 frames (about 8.3 seconds to 3.3–3.5 seconds at a hypothetical
steady 60 FPS). One measured run used 810 ms CPU with a 9 ms peak loading frame.
These are headless interpreter measurements, not native WoW load-time guarantees.
Reload still reconstructs the mesh; no unverified persistent cache was introduced.
Caps are 65,536 total polygons, 131,072 portals, 512 shards, 1,024 polygons per shard
or spatial cell, and 4,096 portals per shard. Search remains sliced and bounded.
Live searches budget at least twice the validated directed portal count plus one:
each edge is expanded once and can enqueue at most one heap entry. The old fixed
32,768-work cap could reject reachable destinations within installed coverage.
This changes total work allowance, not the per-frame slice or physical profile.

The 46.5,52.6 Kharanos screenshot toward archived Frostmane Hold marker 412
reproduces that failure: all nine rounding samples require 36,788 work and now
reach the target through 191 polygons. Production Lua movement replay completes
3,425 off-center steps with zero reversals; one near-waypoint arrow hide remains.
Headless peak search/display slices were 2 ms; native frame timing and traversal
remain unverified. These existing Lua changes load on reload.

Actual source replay at the rounded screenshot center 35.5,46.6 reaches the
archived 412 marker through 85 polygons. Simulated .35- and 1.4-yard movement
completes with zero reversals and zero near-waypoint arrow hides. Eight of nine
rounding samples can route; the southeastern corner remains uncovered. Prior
archived indoor starts still do not resolve. These are modeled results, not a
claim that the exact current native position, route or interaction is verified.

An optional eighth argument to both replay scripts selects an archived quest ID:
```text
luajit tests/quest-nav-visual.lua "<terrain addon>" "<packet>" .355 .466 "<new external prefix>" require-complete 1.4 412
```
The generated HTML visual uses actual polygons and production Lua movement.
`tests/plot_quest_coverage.py` renders the two resolutions and the simulated route.
The new companion TOC includes 408 shard files and therefore requires a full
client restart. No quest actions, eligibility, XP or interaction facts were added;
the Forever corpus, actual lift instances and native interface acceptance remain
separate outstanding work.
