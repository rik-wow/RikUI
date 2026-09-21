# Forever quest planning

## Current implementation

RikUI now has a quest evidence catalogue and a separate live-log observer.
This foundation does not yet calculate routes or ship a quest database.
The native Magistr roadmap tracks the remaining implementation; this document
defines the architecture and implemented contracts, not roadmap status.

The observer is the questplanner module, enabled through the ordinary module
lifecycle. After installing the new TOC entries and restarting the client,
`/rik quests` reports the detected build/locale, observation state, and observed
versus reported log counts. Disable questplanner in module settings and reload
to stop collection. The existing tracker and map continue their current behavior.

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
- quest-reader.lua adapts client APIs into detached character observations.
- questplanner.lua owns events, publication, session state and diagnostics.

The future eligibility engine and planner consume explicit world facts plus
character snapshots. They must not depend on tracker frames or map widgets.
Rendering must consume plan outputs rather than implement planning policy.

### World evidence

`RikUI.QuestPlanner.Evidence.New(identity)` returns a private catalogue, or
nil and a reason. Identity includes product, exact build and locale, such as
forever / 1.60.1.69913 / enUS. Each catalogue has one identity.

`catalogue:Add(questID, field, value, source)` returns true or nil and a reason.
A source has a stable revision ID, matching product/build/locale and authority
verified or reference. Authority is a declaration by the ingestion adapter;
it is not independently certified by the catalogue. Adapters must justify
verified with recorded evidence. Cross-identity assertions are rejected.

Supported fields are title, level, minLevel, baseXP, repeatable, startNPCs,
endNPCs, locations and prerequisites. Locations are mapID plus normalized x/y;
they do not establish traversability. Prerequisites use always, active,
completed, all and any expressions. Completed means a turned-in predecessor;
it is distinct from the reader's objectivesComplete flag. Always asserts no
prerequisite in this expression, not general quest availability. Race, faction,
class, reputation, exclusions and other eligibility rules still need their
own contracts before a route planner can infer availability.

`catalogue:Resolve(questID, field)` returns a detached result:

- unknown / missing: no evidence exists.
- unknown / unverified: references exist but no verified assertion exists.
- known: verified assertions agree, including a meaningful false or zero value.
- conflict: verified assertions disagree; no chosen value is exposed.

All retained evidence is included for inspection. References cannot override
verified facts. NPC sets and operands within each all/any expression are sorted
and deduplicated. This is structural normalization, not logical equivalence
proving. Location list order is retained.

The catalogue is append-only in this foundation. Repeating the same source and
value is idempotent; silently changing that source's value or authority is
rejected. A new source revision preserves both assertions and may expose a
conflict. Corrected corpus releases must currently build a new catalogue from
their declared active sources, retaining the prior manifest for audit. Explicit
supersession/retraction and manifest validation belong in corpus ingestion.

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
