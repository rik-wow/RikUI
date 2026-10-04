# Quest guide and navigation acquisition plan

Reviewed 2026-10-04 UTC in response to the request to get past the data licensing blocker.

This document preserves the acquisition research and original delivery plan.
See [current implementation and delivery evidence](quest-navigation-current-evidence.md)
for executed generation, installation, operating updates and release verification.

## Recommendation

Deliver the complete guide and navigation through a supported local assembly
installer. Distribute RikUI's authored code and appropriately licensed build
dependencies; obtain the quest provider separately from its publisher and build
the corpus and navigation on the player's machine. This removes public
redistribution of the imported corpus and extracted geometry from the delivery
path. It preserves the available data and features rather than substituting an
interface-only installer.

This is an engineering distribution recommendation, not a new permission grant
for third-party data or a determination of client agreement terms. A ZIP or EXE
containing our prebuilt corpus and mesh is a different distribution decision.
Changing the format, host, or license label does not settle it.

No single verified source currently provides every Forever quest rule, spawn,
interaction, floor and transport condition. "All" must mean an inventoried
supported corpus with explicit gaps, not an invented complete server dump.

## Required Forever beta tracking

The target is **WoW Forever's latest beta**, continuously through the user's
November 4, 2026 release target. Compatibility with Era, another Classic flavor,
or a single reviewed beta snapshot does not satisfy this requirement.

- Before every acquisition, build, installer run, update and release, resolve
  Gethe/wow-ui-source's current forever head and version.txt. Cross-check the
  selected Forever client's WowB.exe and .build.info product/configuration.
  A mismatch stops dependent work until inputs are refreshed.
- The implementation must include a daily upstream-change check and an explicit
  check on each installer start/update. This plan records that requirement;
  it does not create a schedule or claim a background service is running.
- Track current provider and schema heads alongside the client. Require the
  Forever flavor and supported API contract. Provider freshness alone does
  not establish current server semantics; preserve authority per field.
- For each new beta, compare quest membership, map projection, topology,
  collision, liquids, transport inputs and relevant API/schema definitions.
  Reacquire current inputs and rebuild affected outputs. Cache reuse requires
  current-input hash verification and an explicit compatibility receipt;
  never admit an older build by changing its version label.
- Newly added or changed quests remain explicitly unknown until their targets,
  prerequisites and locations have current evidence. Provider lag and
  unsupported client/schema changes must be visible; preserve existing files
  while refusing stale data as guidance for the new build.
- Run affected automated semantic, navigation, packaging and interface checks
  before promoting outputs. Unchanged reviewed UI captures retain their
  provenance according to the project's dependency rules.
- At launch, freshly discover the release client's product, executable,
  installation directory and build instead of assuming the beta path remains
  valid. Verify and assemble for that release build using the same pipeline.
  November 4 is a delivery target, not an automatic compatibility approval or
  a permanent version pin after launch.

## Current evidence

- The freshly resolved [Forever branch](https://github.com/Gethe/wow-ui-source/tree/forever)
  head is e3ecc27b64d30fdc735a3f6579b866858f9f9df1, message
  1.60.1 (70205). Its version.txt and the installed
  C:/Program Files (x86)/World of Warcraft/_classic_beta_/WowB.exe agree on
  1.60.1.70205. Resolve again at execution; this is review evidence.
- [QuestieDB](https://github.com/Questie/QuestieDB) head resolved to
  6e7aa495a087ad7d934c0fff800753ec24db5f9d.
  Its [public API](https://github.com/Questie/QuestieDB/blob/6e7aa495a087ad7d934c0fff800753ec24db5f9d/docs/api.md)
  supports enumeration and composed reads of quests, NPCs, items and objects,
  objective-order hints, Forever selection and contract-3 race/faction masks.
  Current repository root still has no license file; its
  [provenance](https://github.com/Questie/QuestieDB/blob/6e7aa495a087ad7d934c0fff800753ec24db5f9d/PROVENANCE.md)
  traces imports to Questie and describes later owned changes.
- [Questie's license page](https://www.curseforge.com/wow/addons/questie/license)
  publishes GPLv3. GPL is a possible distribution basis for material it covers,
  not a reason to prohibit all addon development. Scope and matching notices/
  source matter for a prebuilt provider-derived release.
- Current [QuestLog API documentation](https://github.com/Gethe/wow-ui-source/blob/e3ecc27b64d30fdc735a3f6579b866858f9f9df1/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua)
  gives objective text, type, completion and counts, without target IDs or
  objective positions. Next-waypoint calls take a quest ID, not an objective ID.
  This establishes the documented surface, not agent-observed native behavior.
- Fresh WoWDBDefs head 3e46d21a41a07ce7e63835fd79c561e0d5dce92b:
  [QuestV2 definition](https://github.com/wowdev/WoWDBDefs/blob/3e46d21a41a07ce7e63835fd79c561e0d5dce92b/definitions/QuestV2.dbd)
  declares ID, UniqueBitFlag and optional UiQuestDetailsThemeID.
  It is not a table of quest objectives, rewards and world locations.
- [CMaNGOS copyright terms](https://github.com/cmangos/classic-db/blob/master/COPYRIGHT.md)
  explicitly reserve Blizzard material. Switching to it does not resolve both
  distribution questions.

## Data inventory and acquisition

The required semantic fields are grounded in tools/quest_corpus.py
(SEMANTIC_FIELDS, ELIGIBILITY and PREREQUISITES), not a generic database wish list.

| Data needed | Immediate acquisition | Independent acquisition and limits |
| --- | --- | --- |
| Quest inventory and current client identity | Installed client's build metadata/PE version; freshly extracted current QuestV2 | Membership does not supply quest semantics or prove live availability. |
| Objectives, target IDs, ordered slots, kill credits, spells, triggers and extra instructions | Composed Forever provider entities and ObjectiveFirst hints; existing exporter/compiler | Server quest/condition/script export with explicit redistribution permission, or independently sourced observations. Live objective text/counts alone cannot establish target IDs. |
| Giver, turn-in and item-start relationships | Quest startedBy/finishedBy plus NPC/object/item reverse links | Observed offers/acceptances/turn-ins with entity identity and character context; one offer does not prove universal eligibility. |
| Item acquisition methods | NPC/object/item drops, vendors, quest rewards and support tables | Server loot/reference-loot/conditions, vendor and reward tables; observations need attempts and denominators for drop estimates. |
| Eligibility and prerequisite logic | Level, race, class, skill, reputation, spell and specialization fields; all prerequisite relationships | Server conditions and chains or positive context-specific observations. Missing offers and signed emulator links do not prove AND/OR semantics. |
| Spawn positions, phases and floor/area mapping | Provider spawn points plus current Map/UiMap/UiMapAssignment projection | Current server spawn/phase exports or direct entity position observations. Player interaction coordinates are not exact entity spawn coordinates. |
| XP, seasons and localized display | Provider QuestXP/localization; current Questie holiday membership where used; live client display | Received XP is character-adjusted; calendars/names do not prove live offers. Keep prose local and separately source any shipped authored instructions. |
| Walkability and navigation | Current client WDT/ADT terrain, M2/WMO collision and dependencies, liquids and projection; existing bake and road compiler | Independently authored traversable route graph could avoid copying geometry, but is not a full collision mesh and needs its own coverage evidence. |
| Travel and special interactions | Current transport tables plus separately evidenced endpoints, access and conditions | Boat/lift timing, unlocks, dialogue outcomes and authored access anchors need actual source evidence; proximity is not completion. |

Every fact needs source identity, acquisition date, client build, hash/reference,
coordinate system, confidence/authority, known applicability and conflicting
observations. Provider reference data and live observations remain distinct.

## What is reusable and what is missing

The full private pipeline already exists: tools/export_forever.py exports four
entity families, eighteen class/faction personas and locale evidence;
tools/quest_corpus.py compiles methods, areas, restrictions and partitions.
tools/quest_data_refresh.py resolves moving upstream heads. These are reusable
components; they have not been executed by this research.

The current exporter requires a clean provider source checkout and stock
Lua 5.1. It does not accept an arbitrary installed baked ZIP as a source tree.
Support data also includes Lua strings for some map/drop tables. RikUI must
not loadstring these at runtime; retain offline normalization or implement a
bounded nonexecuting parser. Ordinary QuestXP tables can be read directly.
An installed-provider adapter must preserve composed corrections, nil semantics,
objective ordering, persona context and the explicit wide race masks.

The navmesh components exist in tools/terrain: world acquisition/geometry,
world_bake_parallel.py, road_network.py, quest_pockets.py and install_roads.py.
However, client_build.py admits only historical builds and portable_bake.py
contains historical tile filenames. They cannot be used for this current build.
refresh_sources.py also expects a completed comparison and fixed topology
evidence. The new installer needs discovery and a fresh acquisition entry point,
not a hidden fallback to those profiles.

tools/build_installer_bundle.py currently embeds the generated corpus and
roads; tools/build_installer.py builds that payload into the EXE. Neither
orchestrates consumer-side acquisition and compilation. The local-build route
is therefore concrete planned work, not an already working public installer.

## Delivery sequence

1. Make terrain acquisition/build admission dynamic: resolve Forever head,
   compare executable and .build.info, extract current topology/projection and
   recursive dependencies, and produce immutable current-input receipts.
   Retain historical data without treating it as a current input.
2. Add a local quest acquisition adapter. Prefer a verified installed Forever
   provider through its public contract; alternatively consume a user-obtained
   source checkout with the existing offline exporter. Explicitly handle the
   Questie holiday source used by the compiler. Do not rehost provider files
   from RikUI or silently discard unsupported fields.
3. Package the authored helper and licensed dependencies so users do not need
   Git, Python, Node or MariaDB setup. Inventory third-party tool licenses and
   any profile metadata; not every checked-in metadata file is automatically
   authored code. Preserve MIT notices and applicable GPL-compatible consumer
   obligations rather than assuming separate installation grants immunity.
4. Build locally with bounded worker count, disk checks, progress, cancellation,
   resumable jobs and hash-keyed caches. Benchmark current world generation
   before estimating install time. Regional-first completion can be progressive,
   but label unavailable regions until built; do not call it complete.
5. Verify semantic inventory, provider parity, projection, connectivity/seams,
   manifests and actual runtime replay. Install using existing ownership-aware
   staging/backups and rollback, then verify installed bytes. Do not replace
   working data with failed or incomplete output.
6. Release the installer only after clean-machine assembly is demonstrated.
   Addon UI changes use the project's actual Lua renders; Rust installer UI
   uses its interface checks. Native gameplay is accepted under the standing
   user policy; no native-playtest sign-off is required.

## If a fully self-contained data download is required

The local assembly route has a provider dependency and first-build cost.
For a prebuilt downloadable dataset, pursue one of these separate paths:

- Establish covered Questie/QuestieDB rights and ship the matching editable
  inputs, transformations, notices and corresponding source under applicable
  terms. Address geometry separately; a corpus grant does not license meshes.
- Obtain a current server-operator export with explicit rights for contributed
  quest/spawn/condition data. It must include the tables and scripts above,
  not only quest titles. The operator cannot grant rights it does not own.
- Develop an independent, minimal facts schema, authored guide instructions
  and observations with contributor terms and per-field provenance. Do not
  copy QuestieDB corrections or Wowhead descriptions into a renamed database.
  Start with targeted gaps; do not promise immediate global parity.

The existing [CMaNGOS importer report](upstream-provider.md) is historical
evidence that bulk acquisition works, not current Forever parity: its compared
objectives differed for 897 shared quests and relations for 126. Its normalizer
also leaves loot, conditions and events in the source archive. It needs both
semantic and spatial work before it could replace the present provider.

Copyright does not automatically cover every name or mechanically arranged
datum; see [Circular 33](https://www.copyright.gov/circs/circ33.pdf) and
[compilation guidance](https://www.copyright.gov/circs/circ14.pdf). Equally, a
numeric representation of fictional quest design or extracted geometry is not
automatically cleared. Neither extreme is a sound blanket release rule.

## Research receipt

This work reviewed code and current primary sources, verified the current client
identity, and recorded the implementation frontier in native Magistr.
It did not build a new corpus/mesh, publish data, contact maintainers, or claim
global quest coverage. Existing public code, private corpus, local geometry and
installer data are preserved. No addon/UI source changed.
