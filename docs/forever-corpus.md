# Local Forever quest corpus

RikUI now uses a generated QuestieDB reference corpus for the current character's
quests. Hunting, drops, object collection, talking, events, exploration and turn-in
locations no longer require an entry in the three-quest reviewed guide. Live
objectives and completion remain authoritative. Explicit client waypoints and
reviewed interaction bindings retain priority.

The data identity is Forever **1.60.1.69913 / enUS / interface 16001**. The installed
client is **1.60.1.69977**, accepted through the independently verified identical-data
mapping in `quest-builds.lua`. New addon
folders and TOC modules require a **full client restart**. The installed RikUI
folder is a junction to this checkout. Generated provider data stays outside Git.

## Sources and measured coverage

QuestieDB is pinned to
[`b6f5b07b0acf1c820993cbb0ce2521c912bb4c92`](https://github.com/Questie/QuestieDB/tree/b6f5b07b0acf1c820993cbb0ce2521c912bb4c92),
the latest merged upstream revision checked on 2026-09-23.
The exporter resolves the supported Source reader, static corrections, dynamic
corrections and derived fields for both factions and all nine class selectors.
It verifies the clean checkout and hashes 147 source inputs before and after
extraction. All nine available localization sets and support data are retained
in the audit export; runtime matching currently requires enUS.

| Entity | Raw rows | Corrected rows |
|---|---:|---:|
| Quests | 4,244 | 4,257 |
| NPCs | 10,119 | 10,122 |
| Items | 14,889 | 14,899 |
| Objects | 6,645 | 6,666 |
| Total | 35,897 | 35,944 |

The exact-build QuestV2 table contributes 6,600 IDs. Its overlap with the provider
is 3,546, giving **7,311 distinct quest IDs**: 4,257 provider semantic records and
3,054 membership-only records. The 711 provider-only IDs are reference content;
their presence does not prove availability in this client. These are source
denominators, not a complete world-quest denominator.

| Semantic coverage, baseline persona | Populated | Denominator |
|---|---:|---:|
| Objectives with acquisition/action methods | 3,787 | 4,463 objectives |
| Objectives with mapped source areas | 2,440 | 4,463 objectives |
| Quests with starter relations | 4,173 | 4,257 quests |
| Quests with finisher relations | 4,181 | 4,257 quests |

Per-field and per-zone counts are in the generated `coverage.json`. The 117
zone-or-sort buckets consist of 89 positive geographic area IDs (3,261 quests)
and 28 negative quest categories (996 quests); they are not 117 geographic zones.
Field presence, nonempty values and nondefault values are reported separately.
Normalized zero values and empty tables are not treated as semantic completeness.

The source joins report 67 unique reciprocal-only links across 18 quests and
4,696 unique unknown issues: 532 acquisition, 1,548 location, 1,288 coordinate,
1,322 floor-map and six UI-map issues. Repeated diagnostics total 655 conflict
and 89,224 unknown occurrences across baseline plus 18 selectors (19 evaluations).
Explicit quest links win conflicting reciprocal entity links; all conflicts
and their variant provenance remain in the report.

The client inventory verifies the actual executable version and hashes, active
build/CDN configuration, exact QuestV2 CSV and all six available WDB caches.
The 2026-09-23 refresh admits 397 creature, 609 object and 62 quest cache records; three other
caches are empty. **WDB payload semantics remain unknown.** Four archived RIKQ
packets have valid checksums; one corrupt transcription is excluded. A sidecar
cannot restore counts from a corrupt packet. Archives are historical character
observations, never global facts or newly acquired live observations.

## Freshness audit (2026-09-23)

The [merged provider comparison](https://github.com/Questie/QuestieDB/compare/baa0998d49695c70a1fb8fec559fa9169e9adf33...b6f5b07b0acf1c820993cbb0ce2521c912bb4c92)
contains six newer commits. All 52 files under the Forever entity, correction and
localization directories are unchanged. The fresh export confirms zero changed
baseline quest/NPC/item/object rows and unchanged objective ordering/schema.
Shared enums and dungeon entrance support are newer; their complete producing
inputs are included in the export proof. The provider's explicit coordinate
conversion helper is not automatically applied again to already converted data.

The 18 faction/class correction selectors remain sufficient for this revision:
no new race-dependent callback was introduced. The provider still uses Classic
rules for inferred race masks; newly published Skyborne enum values do not prove
Skyborne quest restrictions are complete.

The freshly downloaded [69977 QuestV2](https://wago.tools/db2/QuestV2/csv?build=1.60.1.69977)
is byte-identical to the pinned [69913 table](https://wago.tools/db2/QuestV2/csv?build=1.60.1.69913):
6,600 rows, SHA-256
`07353cb935ef0907a71c2e51f2aeed4d6460712d4011cb3873f759af5536df4a`.
The refreshed inventory is `D:/RikUI-local/forever-inventory-20260923`.
QuestV2 establishes membership, not complete requirements, locations or offers.

The current consumer changes only Brewfest among the twelve holiday files.
Eight active IDs are removed and two added; none is present in exact-build
QuestV2. The exact-build intersection remains the same 161 event/quest pairs.
The compiler nevertheless consumes the current full 1,000-row membership list
and retains its provenance for provider-only reference quests.

[Upstream PR 49](https://github.com/Questie/QuestieDB/pull/49) remains unmerged.
It proposes Mulgore quests 95805, 96130 and 96659 with supporting entities;
those candidates are not part of the merged corpus and do not fix Tirisfal
eligibility. Their absence is explicit, rather than a claim of complete new
Forever coverage.

The refresh uses isolated checkout `D:/RikUI-local/QuestieDB-b6f5b07b`,
export `D:/RikUI-local/forever-provider-b6f5b07b.json`, and build output
`D:/RikUI-local/quest-corpus-refresh-20260923`. The prior working artifact
`D:/RikUI-local/adaptive-corpus-build` is retained for recovery. This distinguishes
the installed delivery from older experimental build directories.

Delivery verification: 420 owned addon folders and 1,260 files match the new
manifest byte for byte. Corpus revision is
`5f990a1129b4bd10d57dd369226ceb5049166684f8821aa11d05cd99470ab76c`.
The complete host replay admits all 7,311 records and 21,152 action transitions;
4,323 of 4,463 synthetic source objectives bind. These counts preserve the
documented source gaps. Restart the client to discard previously loaded pages.

## Embedded install (2026-09-25)

The same export, client index and holiday pin rebuilt with the page wrapper
into `D:/RikUI-local/quest-corpus-embedded-20260925` (corpus revision
`a3d8a6df152cc0367d73345de7882ae2ac02be356049325fbdbae4337b536843`; the
compiler hash is a revision input, so it differs from the 2026-09-23 build
while every record is the same). `install --rikui` placed 422 files under the
installed RikUI folder's `generated/corpus/` and moved the 420
`RikUIQuestCorpus*` companion folders out of AddOns. The full host replay over
the installed pages admits all 7,311 records and 21,152 action transitions
and binds 4,323 of 4,463 synthetic objectives, unchanged; compiling every page
took 1.17 s in total under stock Lua 5.1 on the build host (12 ms at most for
one page), which is the login cost of carrying the corpus in the addon.

## Compiler and artifact contracts

The compiler joins every corrected quest to known NPC/object/item identities,
drop and object-loot sources, vendors, containers and quest rewards. It retains
starts, ends, chains, exclusions, prerequisites, eligibility masks and supplied
or required source items. Unsupported fields remain in the raw audit with their
handling explicitly reported.

Objective tuple icon enums are actions, not quantities. Counts come from the
live quest log. Kill-credit alternatives retain their distinct NPC targets.
The compiler reproduces provider objective ordering and ObjectiveFirst overrides
before attaching runtime indices. Indexed extra hints are used only when the
unique semantic match agrees with that live slot; unassociated hints remain
quest-level references. See the pinned
[objective ordering](https://github.com/Questie/Questie/blob/454b9d072965ee8f1a881429260fcf1fac8d60f7/Database/QuestieDB.lua#L1535-L1661)
and [extra-objective association](https://github.com/Questie/Questie/blob/454b9d072965ee8f1a881429260fcf1fac8d60f7/Modules/Quest/QuestieQuest.lua#L1414-L1424).

Areas use actual spawn representatives and bounds, indexed by map. Phase groups
stay separate; unavailable coordinates, retired map overrides and unknown
floor mappings do not become invented entrances or floor identities. A spawn
cluster does not establish connected ground or current availability.

The build contains 225 logical quest-ID partitions, interning repeated target
graphs within each partition. Each page holds at most 240 KiB of generated Lua,
wrapped as `RikUI.QuestPlanner.SemanticData.Page("P<bucket>_S<n>", function() ... end)`.
The pages ship inside the RikUI folder as `generated/corpus/` (listed by
`corpus.xml`, which the committed `generated/index.xml` includes), so they
compile with the addon at login (about 55 MiB of source, under a second and
about 64 MB resident under stock Lua 5.1 on the build host) while their tables
are only built when the runtime runs a page. The runtime runs one page per
frame, sequentially, publishes only a completed partition and clears its
temporary construction pool. Loading defers during combat. Only active-log
partitions are requested; loaded partitions are retained for the session,
capped at 512. The corpus revision hashes source, compiler, provider proof,
client index, target identity and partition configuration. A changed catalog
revision requires restart instead of mixing old and new pages.

The build manifest binds every generated/audit file by size and SHA-256.
Installation (`install --rikui <Interface/AddOns/RikUI>`, a junction is followed)
verifies ownership and exact file hashes, stages replacements inside
`generated/`, moves the previous pages and any retired `RikUIQuestCorpus*`
companion folders beside RikUI to the stage's `previous/` directory, restores
them on failure, and preserves recovery files if rollback itself fails.
Unrelated addons and the road data are outside its ownership. Before
2026-09-25 the same pages were 420 load-on-demand companion addons.

## Runtime behavior and limits

Unique compatible live title/objective text and type bind source targets.
Class/faction selects the compiled variant; an unknown selector or mismatched
build/locale cannot silently use the baseline. Membership-only quests retain
live progress and existing client markers without fabricated targets.

Selection respects completion, failed/skipped quests, avoided maps, known
faction hostility, floor constraints, unresolved phases and carried source
items. Inventory reads are bounded to 80 relevant item IDs per refresh using the
pinned [C_Item.GetItemCount contract](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua#L424-L439);
bank and account holdings are excluded. A carried use item produces use
instructions instead of more acquisition. Exact spell/use targets remain unknown
when the source does not identify them. An already active live quest is evidence
of current acceptance; static restrictions never erase it.

At most 40 quests, 2,048 methods and 8,192 areas are admitted per refresh.
Shared areas reduce redundant travel preference. The bounded optimizer compares
up to eight promising areas against loaded terrain, with 32 search work units
per frame and 65,536 total. It distinguishes map-distance estimates, modeled
approaches and unknown inter-zone travel. Cross-zone targets remain visible
without a fabricated transport route or ETA. When loaded terrain cannot model
a source area, a live quest marker remains usable; mesh changes do not cause
the failed source choice to repeatedly displace that fallback.

Runtime progress owns objective and turn-in completion. Proximity never grants
credit. Existing productive-area observations can refine generic hunting with
the same bounded session evidence and connected-floor checks used by the
reviewed cases. Published views contain compact bindings, not copies of the
world target graph. Contradictions retract incompatible reference claims and
retain up to 128 session receipts containing build, generation, source revision,
field and observed value.

Missing active quest metadata uses RequestLoadQuestByID and
QUEST_DATA_LOAD_RESULT: two concurrent requests, two attempts per quest,
30-second timeout/retry and 40 requests per identity/session. Only a later
authoritative quest-log read supplies data. Removed quests and old identities
cannot accept late callbacks. Imported observations never request or load data.

Vendor links are preserved, but absent prices/affordability prevent selecting
buying over known collection. Container and quest-reward joins remain audited
when prerequisites are unknown. No source establishes universal quest
availability, race/class gameplay correctness, native entrances, door state,
escort timing, lifts, transport schedules or arbitrary spell-use targets.
Provider coordinate conversion targeted Forever 69893, while this consumer
targets 69913; reference locations are not native geometry proof.
Terrain installation still covers Dun Morogh only.

## Reproduction

Use Python and a clean checkout at the pinned revision. Extraction needs
`lupa==2.8` with its **stock Lua 5.1** module. LuaJIT's large-function constant
limit can silently drop the provider NPC table; the exporter now fails closed
on incomplete raw or composed inventories.

Example PowerShell commands from this repository:

```powershell
git clone https://github.com/Questie/QuestieDB D:/RikUI-local/QuestieDB
git -C D:/RikUI-local/QuestieDB checkout --detach b6f5b07b0acf1c820993cbb0ce2521c912bb4c92
python -m pip install --target D:/RikUI-local/questiedb-python-tools -r tools/requirements-forever-export.txt
$env:PYTHONPATH = "D:/RikUI-local/questiedb-python-tools"
python -B tools/export_forever.py --source-root D:/RikUI-local/QuestieDB --output D:/RikUI-local/forever-provider.json
python -B tools/quest_inventory.py --client-root "C:/Program Files (x86)/World of Warcraft" --observations D:/RikUI-local/observations --output-dir D:/RikUI-local/forever-inventory
git clone https://github.com/Questie/Questie D:/RikUI-local/Questie-consumer-review
git -C D:/RikUI-local/Questie-consumer-review checkout --detach 67c164d6e0aa4823ea26dad79a3ce54531b5b66c
python -B tools/quest_corpus.py build --export D:/RikUI-local/forever-provider.json --client-index D:/RikUI-local/forever-inventory/QuestV2-1.60.1.69913.csv --event-source-root D:/RikUI-local/Questie-consumer-review --output D:/RikUI-local/forever-corpus-build
python -B tools/quest_corpus.py verify --output D:/RikUI-local/forever-corpus-build
python -B tools/quest_corpus.py install --output D:/RikUI-local/forever-corpus-build --rikui "C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/RikUI"
python -B tools/quest_corpus.py verify-installed --output D:/RikUI-local/forever-corpus-build --rikui "C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/RikUI"
```

For an existing source checkout, verify its revision and cleanliness rather than
cloning over it. `export_forever.py --reuse` verifies all producing input hashes
and output hash before reuse. QuestV2 acquisition has bounded retries and
verifies cached exact-build content. Rebuild into a second external output and
compare manifests to check determinism. The CSV is pinned to SHA-256
`07353cb935ef0907a71c2e51f2aeed4d6460712d4011cb3873f759af5536df4a`;
a changed table requires deliberate review.

The composed export SHA-256 is
`95a1a209762db3ae510c402e7f1d0234b20609e71e4a5e7cd42b8abd490209fe`.
Current source notices are preserved in the audit.
[QuestieDB provenance](https://github.com/Questie/QuestieDB/blob/b6f5b07b0acf1c820993cbb0ce2521c912bb4c92/PROVENANCE.md)
identifies inherited Questie material, but a separate comprehensive QuestieDB
redistribution grant was not established. This delivery supplies local
acquisition/compiler code and a local installation; it does not commit or
redistribute the generated provider database.

## Starter quest selection correction (2026-09-23)

The Deathknell Paladin report exposed two planner errors. QuestieDB's
`friendlyToFaction` is faction affiliation, not permanent attackability:
[the consumer tests explicitly call AH neutral](https://github.com/Questie/Questie/blob/454b9d072965ee8f1a881429260fcf1fac8d60f7/Database/QuestieDB.test.lua).
The installed source gives both Mindless Zombie (1501) and Wretched Zombie
(1502) this value, while quest 364 explicitly requires killing them. Scripted
same-faction targets also exist: Alliance quest 434 requires NPCs 1754 and 1755,
whose source faction field is A. Kill/drop actions therefore use their bound
objectives and prerequisites; faction gates remain on NPC interactions.

An unconfirmed source pickup now yields to feasible active work substantially
closer on the same map (at least 40 yards and 20% of the pickup distance).
The existing sorted live recommendations make this choice stable. Exact
quest/giver offers and explicit pins retain control; nearby pickups remain
eligible. This local decision discards speculative itinerary, XP and time
estimates, and its reason identifies the unconfirmed pickup.

Current [Forever quest 8](https://www.wowhead.com/forever/quest=8/a-rogues-deal)
and [quest 590](https://www.wowhead.com/forever/quest=590/a-rogues-deal) listings
have minimum level 1, quest level 5 and no class restriction. That does not
prove the NPC currently offers either quest to a particular character. The
source prerequisite for 590 remains quest 8. No Rogue-only or invented
minimum-level restriction was added.

The automated regression reconstructs the reported level-1 Horde Paladin,
position 31.6,66.0, live 0/8 objectives, both source zombies and Calvin's chain.
All six planner flavors retain nearby active work, preserve interaction and
history gates, and replay the published decision. Native acceptance is supplied
by the user; these are automated results.

## Seasonal availability

Builds also read the twelve holiday membership tables from the pinned Questie
consumer commit. The parser now reads consumer
[`67c164d6e0aa4823ea26dad79a3ce54531b5b66c`](https://github.com/Questie/Questie/tree/67c164d6e0aa4823ea26dad79a3ce54531b5b66c/Database/Corrections/Holidays/quests),
including 1,000 active membership rows and excluding nineteen commented-out rows. Membership input and source-file hashes are retained
in the local audit and bound into the corpus revision. These are event
classifications, not a calendar or current availability feed.

The planner blocks source-only holiday pickups without a fresh exact quest-ID
offer from the matching giver. Closing the dialog, changing worlds, expiry or
identity mismatch clears that evidence. Goldwell the Elder (8653) is classified
as Lunar Festival. Generated membership also covers holiday quests whose
category is an ordinary area or SPECIAL. Existing compiled event categories
remain gated until the refreshed corpus is installed. Active quest instructions
remain visible; source coordinates do not prove a seasonal NPC is present.

## Verification evidence

`tests/test_quest_corpus.py` exercises joins, source icon semantics, ordering,
variants, provenance, deterministic revisions, tampering, ownership and rollback.
`tests/test_quest_inventory.py` exercises framing and corrupted archive rejection.
Lua unit cases cover source matching, conflicts, inventory, phases/constraints,
progression, stale results, sequential loading and missing-data requests.

`tests/quest-corpus-installed.lua` executes every installed partition and replays
source-derived objective cases across maps. These synthetic cases verify adapter
compatibility; they are not observations that all quests are playable.
`tests/quest-corpus-navigation.lua` combines actual archived objectives with
installed corpus and terrain, measures moving callback costs and verifies zero
moving route changes and no proximity completion. Its arguments match
`tests/quest-region-replay.lua`.

## Live guidance stability follow-up

The installed cold-start replay now starts corpus and terrain loading together,
as the client does. Previously the live marker could be replaced repeatedly
while source areas were still being compared. The provisional source choice is
now stable, and an available live marker remains the destination until a source
area has a usable modeled approach. Partial item counts do not restart that
comparison; finished objectives, source-item availability and actual constraint
changes still invalidate it. Source comparison work has a bounded frame budget.

Automatic recommendations now use a cheap same-map distance estimate, small
turn-in/progress preferences and shared source-area tie-breaks. Pins and manual
selection remain authoritative within exclusions; hysteresis prevents small
score differences from changing the current quest. Meaningful movement can
refresh recommendations. These are local heuristics, not an XP optimizer or
recursive planning over future chains. Unknown travel remains unknown.

The compact quest instruction shows the source action when available. Expanded
details explain the local recommendation. `/rik quests status` prints the
selected quest, recommendation, quest sequence searches and separate walking
search/window counters.

Run `tests/quest-corpus-live.lua <AddOns root> <archived packet> 315` for the
Perfect Stout regression. With the installed corpus, terrain and archived native
packet, the failing reproduction required 2,751 simulated frames (55 seconds),
24 walking searches and three terrain windows. The corrected replay obtained a
route in 146 frames (2.92 seconds), one search and one terrain window. Its
598.48-yard movement replay, including partial progress updates, required no
additional search or route publication and never completed the quest by
proximity. These are host results at a simulated 50 Hz, not measured client
latency or native gameplay acceptance. The main test suite covers recommendation
stability, pins, exclusions, progress, unknown travel and shared-area preferences.

The final delivery receipt records exact gate totals, artifact hashes, installed
counts, all-record replay results and route measurements. The user supplies
native/game-client acceptance. Unknown new-chain and lift timing/source facts
remain explicitly unknown; they do not create routine native-acceptance blockers.

