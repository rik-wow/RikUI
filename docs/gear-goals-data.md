# Gear goals data

The bounded index joins current-client equipment slots to maintained quest and curated dungeon **references**. It does not claim verified Forever loot tables, drop rates, automatic versus choice rewards, complete new-dungeon coverage, or best-in-slot rankings.

## Reviewed inputs

Reviewed 2026-10-04 UTC. Gethe/wow-ui-source forever head `e3ecc27b64d30fdc735a3f6579b866858f9f9df1` reports 1.60.1 (70205); version.txt and local WowB.exe both report 1.60.1.70205. These identify this review, not a target for future refreshes.

Item (FDID 841626) and ItemSparse (1572924) were extracted from the current client through TACTTool with the client's current build/CDN configuration. The remote CSV returned 403; no historical cache was substituted. Fresh WoWDBDefs head `3e46d21a41a07ce7e63835fd79c561e0d5dce92b` selected the current layouts. The external MIT wow.export WDCReader was used unchanged (SHA256 eac685b1d0b7876d208895543b4e2c17f2848b112dc464c4001588d0d760ad62). Client binaries, DB2 files and artwork are not distributed.

QuestieDB Forever head `6e7aa495a087ad7d934c0fff800753ec24db5f9d` was freshly exported for eighteen faction/class personas. Export SHA256: 9f12f19de00021f7ccbb058fadc321fde936c8eff6c8aa0ce84ca5a95afc9ad9. Maintained source relationships can retain Era assumptions. A current repository revision does not verify every reward against the server. Only factual identifiers, names and requirements are compiled; descriptive quest prose, source code and client assets are excluded.

Current CollectableSourceQuestSparse and CollectableSourceEncounterSparse had no records. They cannot establish reward payouts. Live reward offers take precedence over references.

## Refresh

Resolve the latest Forever branch and compare WowB.exe before acquisition; stop on disagreement. Extract current Item and ItemSparse to an external directory labeled with the verified build and fetch definitions from the freshly resolved WoWDBDefs head. Export the freshly resolved provider with tools/export_forever.py.

Run tools/gear_db2.cjs with the external unchanged reader root, input directory, current version and definitions revision. Run tools/gear_catalog.py with --inputs, --build and an external --output. It verifies input hashes, preserves persona prerequisites, escapes literals, and enforces capacity. Apply reviewed parts.json entries through Workbench in order. The shipped identity includes raw/parsed hashes and compiler/provider provenance. Never execute submitted Lua or fall back to an older input directory.

Slot and level indexes are sorted during compilation. Broad world drops with over twenty distinct NPC sources are excluded from curated encounter recommendations. Classic dungeon areas are explicit in the compiler; additions require review. Current payload: 2,746 items, 4,097 source references and 2,342 base prerequisite quests, plus persona corrections.

## Runtime limits

Only displayed candidates and selected comparisons request item metadata. No tooltip scanning or remote requests are needed. Missing items, stat APIs, completion flags and equipment links remain unknown.

Tradeoffs compare the selected ring/trinket slot. Two-handed weapons compare main hand and off hand together. Effects, set bonuses, sockets, weapon behavior and class priorities still require the native tooltip. RikUI never equips gear or selects a reward automatically.

Up to eight compact goals per character are settings, not a library. Static catalog data, source observations and acquisition archives never enter the restart backup. Existing backup capacity/error reporting applies.

## Sources

- [Forever UI source](https://github.com/Gethe/wow-ui-source/tree/forever)
- [QuestieDB](https://github.com/Questie/QuestieDB)
- [WoWDBDefs](https://github.com/wowdev/WoWDBDefs)
- [wow.export](https://github.com/Kruithne/wow.export)

Current player-tool research also reviewed LootGoblin, Lootified and ForeverGear. No code, UI, weights or loot tables were copied from those addons. The feature connects comparisons and goals to RikUI's existing quest workflow.
