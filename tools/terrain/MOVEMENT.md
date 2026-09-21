# Movement profile and observed-marker approaches

## Scope

This is a static terrain model for Forever 1.60.1.69913, enUS. Model connectivity,
offline steering and native traversal are separate claims. Neither the former
0.3-yard step nor the reference profile below has been calibrated against this
client's movement physics. No coordinate arrival completes a quest.

## Why Bitter Rivals failed

The Adler 9c563e01 native packet places the player at nav x=-505.20001220703125,
z=-5682 and quest 310 at map 1426 (0.47717434167861938, 0.5268782377243042).
The latter projects to approximately (-548.00026431642, -5607.0000896038).
Raw UnitPosition Z=0 remains unestablished altitude. The packet contains 12 current
quests, ten map POIs, completed quest-310 objectives and no observed turn-in.

With the installed 0.25-yard grid and 0.3-yard step, the target's approximately
399.13-yard floor was a 19-polygon island. The building was included in collision
extraction. Missing WMO geometry or an inferred rooftop is not the explanation.
A source-preserving 0.125/0.05-yard grid experiment retained the same physical
limits; its target remained isolated (56 polygons, separate 82-polygon lobby).
It also exceeded runtime polygon limits. Its padding changed from 1.25 to 0.875
yards under the generator rule; it is diagnostic evidence, not a deployed build.

The old step limit has no native calibration evidence and rejects stair/lip rises
in this model. We selected an independently documented reference before testing
the new mesh, rather than increasing values until this route passed.

## Named reference profile

Primary reference: CMaNGOS Classic revision
[8ec338a1704e7dcb1c0213eb7ed58f9231ade40f](https://github.com/cmangos/mangos-classic/tree/8ec338a1704e7dcb1c0213eb7ed58f9231ade40f).
Its [MapBuilder.h](https://github.com/cmangos/mangos-classic/blob/8ec338a1704e7dcb1c0213eb7ed58f9231ade40f/contrib/mmap/src/MapBuilder.h)
sets BASE_UNIT_DIM to 0.2666666; default
[MapBuilder.cpp](https://github.com/cmangos/mangos-classic/blob/8ec338a1704e7dcb1c0213eb7ed58f9231ade40f/contrib/mmap/src/MapBuilder.cpp)
walkableClimb is four cells. This yields 1.0666664 world units. This is a server
navigation reference, **not Forever client physics evidence**.

The optional `bake_tile.mjs ... --half-cell --reference-step` profile
`classic-reference-step-v1` rounds that climb down to 1.0 yard on the retained
0.1-yard vertical grid. Horizontal grid 0.25, radius 0.5, height 1.8, slope 40
degrees and 64-yard core tiles stay unchanged. The compiler accepts climb 10 only
with this explicit profile and otherwise unchanged limits. Metadata and receipts
retain `agentProfileCalibrated=false` and a reference-only limitation. Default bake
behavior is unchanged.

Reference file SHA256 values:

- MapBuilder.h: 4bb4c06c0ced9685c7a5d5c3afc6b72ede35b2af8b92431904e69677002c0e18
- MapBuilder.cpp: 80ac2aecd8d38cdd2718ae6dfaa645cf0f8e371c1d9a783dfed40e5289e7ddb0

Synthetic Recast fixtures independently verify a 0.6-yard step changes from
blocked to connected, while a 1.4-yard ledge, wall, narrow opening and inadequate
headroom remain blocked. They establish model behavior only.

## Portal and endpoint contracts

Recast detail quantization exposed a portal endpoint 0.0206 yard beyond its
neighbor's polygon. Export now intersects the original portal interval with a
collinear neighbor edge. This only shortens the portal; separated or noncollinear
edges cannot create a connection. Existing compiler containment and height checks
remain in force. It is not a wider portal tolerance or a guessed link.

Exact navigation remains strict. For observed current-map quest POIs only:

- Two to four overlapping target floors may use a sliced Dijkstra tree. Every
  floor must be reachable. The endpoint is the last uniquely located common
  ancestor on their paths, within 64 horizontal yards of the marker and beyond
  the start. The route ends there; it does not choose a quest floor by path cost.
- An uncovered marker can use the existing eight-yard vicinity. If nearby
  surfaces compete in height, an explicit uncertain-vicinity policy permits the
  nearest boundary only when that endpoint itself resolves to one floor and a
  real portal route reaches it. It does not assert that this is the quest floor.
- Source bounds, excluded coverage, player-floor ambiguity, exact endpoint
  containment, finite budgets and disconnected-path failures remain enforced.
  No segment from approach to marker is added.
- Both uncertain outputs retain original marker provenance, an explicit kind and
  reason, and false final-leg/interaction verification. The arrow follows the
  corridor and ends with "Check the quest floor."

The rebuilt quest-310 marker overlaps floors around 399.35 and 393.10 yards.
Its shared approach is useful without guessing which floor contains the turn-in.
The quest's completed basement objective does not establish its turn-in floor.
For quest 313, a unique cave approach about 4.70 yards from the marker remains
distinct from a competing distant-height surface; guidance exposes that uncertainty.

Steering anticipates a polygon's exit and preserves a still-visible forward aim
through tiny boundary fragments. Passing that aim, a required turn or invalid
portal proof cancels retention. It never requires touching a breadcrumb or permits
a shortcut through an unmodeled wall.

Recent floor tracking is independent of quest route state. Quest refresh, selection
changes and planner pause/resume clear stale routes but preserve fresh floor
observations. Movement remains bounded to 0.5 seconds and three yards of continuity;
map/build changes, unavailable position, stale motion and explicit established
altitude still invalidate or supersede it. A short movement cannot jump to a
disconnected lower surface just because that surface is now the unique 2D match.

If a short observed movement bends between samples, continuity can follow existing
portals through a local corridor of at most three modeled yards. Each segment stays
inside its convex polygon; both pending queue and processed entries are capped at
64. This fallback requires an independently unique horizontal endpoint, so it cannot
select a competing floor by path cost. Exhaustion fails closed. It cannot create a
missing connection. Arrow shortcuts still require their straight crossing proof.

Portal crossing accepts only the existing numerical epsilon around edge endpoints.
This corrects a reproduced floating-point failure when starting exactly on an
oblique stair portal; source/target containment and real portal adjacency still
apply. The actual distillery test follows both target floors and returns: lower
393.0966 yards (1,630 samples each direction), upper 399.3549 (1,462 each).
Target heights are enumerated model test cases, not claims about the quest's floor
or observed player altitude. No height input is supplied during motion.

## Explicit destination-floor routing

`NavMesh.MarkerFloors` enumerates only exact marker overlaps with two to four
distinct, individually resolvable modeled surfaces. It retains boundary,
coverage and height-query ambiguity checks. It does not snap to nearby polygons,
label a surface as a basement, or change connectivity/physical limits.
`Terrain.SelectFloor` binds an explicit routing preference to the complete
quest signature, exact marker/source and installed revision. It cancels pending
guidance, then supplies the selected model height to the existing strict search.
An unreachable chosen floor remains unreachable; it never silently selects another.

The tracker/details Floor button cycles Auto → lower → upper → Auto (or up to
four height-ordered surfaces). Commands: `/rik quests floor 1` and
`/rik quests floor auto`. This is session-only state, not a verified target
binding or persisted character observation. Instructions identify the selected
floor; coordinate arrival still cannot complete a quest.

Missing automatic target evidence remains a separate obligation. The pinned
[Forever QuestInfoShared API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestInfoSharedDocumentation.lua)
has no POI altitude or NPC/object identifier, and
[GetNextWaypoint](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua)
returns only map ID and two coordinates. Local questcache.wdb at 2026-09-21
SHA256 `75e337a6185bed292235d29d82044b98ebd37b289b42678b00cbc49d5bba3f10`
contains record 310 (1,162 payload bytes; SHA256
`cd039bb85f50570c5acd84ca6d5efe4f827912da3e7536fa9255ca8227593dcc`).
Its visible basement objective text agrees with the export; no exact 3D
turn-in placement was established. No Classic target data is installed as Forever.

Actual production-controller/steering replay of the installed companion plus
the exact 9c563e01 packet now reaches both selected marker floors:
lower 393.0966 (1,199 movement steps / 150 distinct instructions), upper 399.3549
(1,041 / 143). Both have zero greater-than-90-degree steering reversals. The
replay follows the connected surface without supplying player height, uses
remaining route length as well as horizontal distance for arrival, and verifies
arrival on the selected model floor. Map-ant geometry remains bounded.
This proves modeled routing, not native walking or quest-target identity.

Retained external JSON and matching HTML:

- `D:/RikUI-local/nav-floor-final-1-310.json`,
  SHA256 `356648037a3c7b3460dcd531aa19f00499bfb2b2dd1783f6f54eac392f342faa`.
- `D:/RikUI-local/nav-floor-final-2-310.json`,
  SHA256 `d6e43180c4a10677ad92eab4f9f6e998fd833d61187457839cd65e272f478b17`.
- `D:/RikUI-local/nav-bitter-floor-routes-310.png`,
  SHA256 `7110518ef58dfd298194c9b31d2f9936ffb8f6301029fd430db59fc8e2766214`.
  Rendered by `tests/plot_quest_floors.py` and inspected as a static image.

Reproduce with the existing `tests/quest-nav-visual.lua` CLI: argument 12 is
`archived`, argument 13 is model-floor index 1 or 2. Use new external output
prefixes. Final replays used stride .15, frame delta .02 and no side perturbation.
Existing stair out-and-back replays and broader steering checks remain separate.
That explicit-floor delivery changed only existing Lua files and loaded on reload;
the automatic annotation delivery below adds a TOC entry.
Native visuals/interactions and performance were not automated or accepted.

## Automatic basement annotation

The user's 2026-09-21 clarification identifies an interaction dependency: have
Thunder Ale, give it to Jarven when he is guarding, then use the barrel after he
leaves. It does not establish an item/NPC/object ID, a timer, exact positions or
the character's current stage. Public 60.tools records for
[Bitter Rivals](https://www.60.tools/quests/310) and
[Distracting Jarven](https://www.60.tools/quests/308) label their details as Classic;
those details are not installed as verified Forever facts.

`quest-targets.lua` contains a reviewed, content-specific navigation annotation.
The generic matcher requires Forever 1.60.1.69913/enUS, quest 310, its exact title
and completed single log objective, and the archived map marker/source
(normalized-coordinate roundoff tolerance 1e-7). The geometry resolver additionally
requires revision d1981b5a... and exactly the two reviewed surfaces at
393.09662169989 and 399.3549 yards, each within 0.05 yard of its recorded height.
This supports an explicitly labeled **quest-text/model inference**: route to the
basement surface. It does not measure a target height, choose the nearest floor,
change geometry, or install a quest action/XP/duration.

Auto now selects that floor for this record; Lower/Upper remain explicit overrides.
Changed build/locale, stage/text, marker/source, mesh or competing surfaces reject
the annotation. An unreachable inferred floor cannot silently route to another.
The conditional reported Jarven/ale/barrel instruction is available in the quest
tooltip; temporary access is never inferred from proximity or historical completion.

Actual archived world-position replay, with no manual floor argument and no
player altitude during movement, reaches the lower floor in 1,199 steps, zero
reversals, 150 changing instructions. Its corridor, route points, movement samples
and modeled heights exactly equal the previously reviewed explicit lower route.
All nine nearby rounded-coordinate samples also produce the modeled basement route.
Overriding Auto with the upper floor still completes 1,041 steps / zero reversals.
These are headless model simulations, not native movement or interaction acceptance.

- Automatic JSON/HTML: `D:/RikUI-local/nav-auto-basement-310-v1.json` and matching HTML.
  JSON SHA256 `c68f1c5d28e9ade0db8c5f87955adb511283c2da4f75988fa7de289ddf26218d`.
- Explicit override replay: `D:/RikUI-local/nav-auto-override-upper-310-v1.json`
  and matching HTML.
- Reproduce with the same CLI above, omit argument 13 for Auto. The harness now
  selects through production `Guidance.Observed` before the terrain coordinator.

This adds a target module to RikUI.toc. The addon junction supplies its files,
but the client needs a full restart to discover the new TOC entry. Terrain
companion contents are unchanged. General target identity/3D acquisition, full
world coverage, corpus and native acceptance remain open.

## Retained delivery and replay evidence

External observation archive:
`D:/RikUI-local/observations/forever-69913-enUS-9c563e01-native.rikq`
(21,297 bytes; SHA256 042db64be2fffd28595a36e9d727962f77a81b0aa18f926f455ec091e8ebdf4c).
Production Lua decoding, Python import and durable JSON reread passed.
This archive is character observation, not a world-fact corpus.

Build: `D:/RikUI-local/terrain-reference-step-release-69913`.
It reuses the retained full geometry and original origin; 408 shards, 38,142
polygons, 74,568 directed portals, 414 delivery files / 14,304,073 bytes.

- Manifest SHA256: d1981b5ac045133c7f2db478e91774432a3eaa82c4e93295478a43bfea5e118e
- Compile receipt SHA256: dfd2507c9f54abf4987237d9c0bc1c5586c5d6dfde88671e033fd5ea20bf38b6
- Deployment receipt SHA256: 032730a418f240c48a7d9ccc1aa7d5a75333f90b5304fb35b6bbda614363cfde

Installed at the client's `Interface/AddOns/RikUIQuestTerrain`; all files compared
byte for byte. Backup: `D:/RikUI-local/RikUIQuestTerrain-before-reference-step-69913`.
File inventory and TOC bytes are unchanged; existing client sessions need a reload.

Before the automatic annotation, production Lua with the **installed copy and exact archived world position**
returned a quest-310 common approach: 43 polygons, 5,963 search operations,
287.305-yard center graph, 0.1323-yard horizontal marker gap. Center-graph length
is not a claim about the smoothed path's walking distance. The independent
movement replay completes 1,305 steps with zero greater-than-90-degree reversals,
155 distinct instructions and every step inside its connected floor corridor.
The replay includes small sideways deviations and overshoots waypoint positions.

Interactive artifact: `D:/RikUI-local/nav-bitter-release-exact-310.html`, with
the same-prefix JSON containing mesh, corridor and movement samples. Additional
replays: Grizzled Den (4,388 steps, zero reversals) and installed Frostmane
(3,888 steps, zero reversals); the latter two use rounded screenshot positions,
not exact archived native positions. These measure headless Lua, not native
rendering or client frame cost.

Remaining limits are explicit: quest 319's POI is outside this region; quest
98326 has no accepted shared approach; 96608/384 have no observed map marker.
Four of nine rounded Grizzled Den cold starts remain floor-ambiguous.
All-world terrain installation, complete Forever action corpus and native
walking/interaction/visual/performance acceptance remain outstanding.
