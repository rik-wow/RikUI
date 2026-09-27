# Detailed quest objectives and waypoints

Scheduled source refresh and private releases are documented in
[the quest-data automation guide](../automation/quest-data/README.md).

Research and implementation checked on **2026-09-27**. This supersedes the older
marker-precedence and installed-corpus figures in the historical quest documents.

## What is integrated

- The compiler retains every valid source spawn inside its original cluster.
  Cluster bounds still support terrain searches; destinations use actual source points.
- Direct guidance and the action planner share the same coordinate resolver.
  Planning considers all areas before selecting its nearest alternatives.
- The quest window represents every live objective, including completed objectives
  and objectives whose locations are missing. Known objectives show the action,
  target, item to collect, coordinates, source and alternative-location count.
- **Objective** switches the objective being browsed. **Route to objective** selects
  it. **Next location** cycles recorded spawn alternatives. The world map shows
  unfinished objectives for the selected quest; clicking a numbered pin routes to it.
- Live counters advance the guide after completion. Walking to a coordinate never
  completes an objective. Explicit client access waypoints and reviewed interaction
  annotations retain priority; general quest POIs no longer displace objective targets.
- No separate quest addon, TomTom dependency, or runtime network access is required.
  Generated data is installed inside RikUI and remains excluded from Git.

## Current source audit

| Source | Checked evidence | Integration decision |
| --- | --- | --- |
| [Forever UI source](https://github.com/Gethe/wow-ui-source/tree/forever) | Resolved HEAD `bd2470aed543f72697a044e989285b6c83e63f73`, commit 1.60.1 (70009); installed WowB.exe reports 1.60.1.70009. | Current source review. This is evidence, not a future build target. |
| [QuestLog API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua) | GetNextWaypoint and GetNextWaypointForMap take a quest ID and return coordinates without an objective ID. | Keep access waypoints; never assign the same quest POI to every objective. |
| [QuestieDB](https://github.com/Questie/QuestieDB/tree/365537a340473291f5af3b7a53a5eca94e2a5f1a) | Latest merged HEAD, dated September 26. [Diff from the previous input](https://github.com/Questie/QuestieDB/compare/b6f5b07b0acf1c820993cbb0ce2521c912bb4c92...365537a340473291f5af3b7a53a5eca94e2a5f1a) changes loading/tooling; entity and correction inputs are unchanged. | Re-exported all four corrected entity families, 18 personas and nine locale audits with stock Lua 5.1; 147 input hashes. |
| [QuestieDB Forever scope](https://github.com/Questie/QuestieDB/blob/master/docs/forever.md) | Owned Forever data includes converted coordinates and explicit unresolved map/floor cases; it does not claim complete new Forever content. | Preserve phase and unresolved coordinates. Retired instance aliases do not become valid floor maps. |
| [Current QuestV2 table](https://wago.tools/db2/QuestV2/csv?build=1.60.1.70009) | Current locally acquired index has 6,605 IDs; SHA-256 `4e9b81e10068d1077f145ead18bbe44068e30800646702564499e666a04d9319`. | Membership only. The build command now accepts the acquired version and hash explicitly. Five new IDs are retained without invented names or objectives. |
| [QuestieDB PR 49](https://github.com/Questie/QuestieDB/pull/49) | Still open, unmerged: proposed Mulgore corrections for 95805, 96130 and 96659. | Community submission, not confirmed client data. Not silently merged into the corrected provider. |
| [Forever GuideMate](https://github.com/TylerAkins/forever-guide-mate) | HEAD `34d74637cc674a6a4af96e0cf6ec36edd8f12852`. Its README labels coordinates unvalidated; authoring rules distinguish quest-wide completion from objective-text bindings and path dots from destinations. | Researched as a walkthrough source. Generic routes cannot safely fill every individual objective slot. |
| [QuestForever](https://www.curseforge.com/wow/addons/questforever) | September 27 release 0.4.1 identifies QuestieDB, GuideMate and Wowhead as inputs and describes missing new-quest giver coverage. | Useful corroboration of available source families; not an independent complete coordinate dataset. |
| [Wowhead Forever](https://www.wowhead.com/forever/quests/max-level:25) and [60.tools](https://www.60.tools/quests) | Current quest listings and descriptions. Catalog membership alone does not prove an objective's world position or floor. | Discovery/corroboration sources; no bulk scraped prose or guessed location import. |
| [wow-database](https://github.com/TylerAkins/wow-database) | GuideMate points to these compiled quest bundles. Its README explicitly prohibits reuse of the compilation. | No data or code imported. |

Community submissions and guide authors' coordinates remain reference claims.
The source review does not establish that every spawn is currently present or that
a route's floor/access is correct.

## Measured coverage

| Measure | Count |
| --- | ---: |
| Corrected provider quests | 4,257 |
| Current client quest IDs | 6,605 |
| Combined quest IDs | 7,316 |
| Client-only IDs with no provider semantics | 3,059 |
| Provider objectives | 4,463 |
| Objectives with acquisition/action methods | 3,787 |
| Objectives with mapped source areas | 2,440 |
| Unique source clusters, including starts/ends/extra hints | 26,818 |
| Exact spawn points retained in those clusters | 74,153 |
| Installed generated files | 447 |
| Logical runtime partitions | 225 |

The 74,153 points include giver, turn-in and extra-hint locations and phased source
points. They are not 74,153 independently verified objective locations. Counts above
describe the baseline selector; the corpus also retains character variants.

**A waypoint for every objective is not supported by the available data.** Missing
new-quest semantics, acquisition links, coordinates, phase and dungeon-floor mappings
remain explicit. Every observed objective is represented by the guide even when it
cannot offer a location. Existing reference-only quest IDs are not treated as live
quest offers.

## Architecture and behavior

`quest_corpus.py` owns acquisition normalization and immutable data. Packed
`area.spawns` retains normalized coordinate pairs; the original representative,
bounds and phase stay intact. Old corpus areas without this field still work.

`quest-waypoints.lua` owns coordinate selection. It inspects the packed points and
allocates only the selected view, leaving source records unchanged. Stable IDs include
the source cluster and spawn index. Explicit selections and current planner commitments
survive refreshes while their source remains admissible.

`quest-semantic-guidance.lua` owns strict source/live matching, faction/access policy,
inventory prerequisites and bounded candidate admission. An objective binds only when
its type/text and any known count agree uniquely. Index-only extra hints require the
compiler's source order to agree with that live binding.

`quest-objective-guide.lua` projects those candidates into per-objective instructions
and holds session-only user selection. It never writes completion state or source data.
Unknown and finished rows remain visible. An abandoned quest, changed identity,
mismatched objective or live completion invalidates the selection.

`quest-plan-graph.lua` consumes the shared resolver while retaining its bounded action
shortlist. The window and map use the same guide model. Explicit unknowns are retained
outside that shortlist; the planner does not materialize the entire corpus as actions.

## Reproduction and verification

Local source/export/build:
- `D:/RikUI-local/QuestieDB-20260927`
- `D:/RikUI-local/forever-provider-20260927.json`
- `D:/RikUI-local/quest-corpus-objectives-20260927`
- Corpus revision: `8522c25d74a6adf909105de54abe129786fe44a39d51b445ed02aa40d38204e5`

Use the existing exporter and compiler documented in [forever-corpus.md](forever-corpus.md).
For a new client-index acquisition, pass `--client-build` and
`--client-index-sha256` alongside `--client-index`. Resolve the current client and
provider sources again before a future refresh; the evidence above is not a target pin.

The required Lua gate passes 18,021 checks; all 25 compiler tests pass. The manifest
gate checks the TOC, icon inventory and Lua compilation. Installed-file verification
checks all 447 generated files against the final build.

Regression coverage includes lossless spawn retention, source immutability, objectives
beyond the old area cutoff, same-map marker precedence, manual spawn persistence,
multiple objectives, completion progression, unknown objectives, stale/imported data,
avoid policy, and the actual quest-window controls under UI stubs.

The all-record host replay loads 7,316 records, binds 4,323 of 4,463 synthetic
source-derived objectives, locates 1,690 quests across 45 maps, and exercises 21,152
planner transitions. Those are host fixtures, not agent-observed game results.
Native acceptance is supplied by the user's standing policy.

A **full client restart** is required after installation because the TOC and generated
file inventory changed.
