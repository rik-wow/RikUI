# Quest corpus licensing review

Reviewed 2026-09-27. This records evidence and the remaining decision; it is not
a legal opinion that redistribution is risk-free.

## What the sources say

| Input | Evidence | Disposition |
| --- | --- | --- |
| RikUI authored code and media | Repository MIT license; Noto Sans OFL notice | Keep existing licenses. |
| Questie | [Official project license](https://www.curseforge.com/wow/addons/questie/license) explicitly declares GNU GPL version 3. | A concrete copyleft route exists for covered Questie material; do not label it MIT. |
| QuestieDB | [Provenance](https://github.com/Questie/QuestieDB/blob/365537a340473291f5af3b7a53a5eca94e2a5f1a/PROVENANCE.md) traces imported tables, corrections and localization to Questie. The current repository has no root license; GitHub's license endpoint returns 404. | Inherited rights and later contributions need to be distinguished. Missing metadata alone does not prove that inherited GPL rights disappeared. |
| Current official combined release | [Questie 12.0.1 + QuestieDB 1.0.4](https://github.com/Questie/Questie/releases/tag/bundle/v12.0.1%2Bv1.0.4) bundles database revision 365537a340473291f5af3b7a53a5eca94e2a5f1a, matching RikUI's current private corpus input. | Strong evidence for a GPL distribution path, but a bundled independent component does not automatically acquire the aggregate's license. Ask the publisher to confirm scope. |
| QuestV2 membership | [Wago QuestV2](https://wago.tools/db2/QuestV2) supplies numerical membership records for the discovered client build. | No Wago software license is treated as a grant to Blizzard data. Keep this input's provenance separate. |
| Road and mesh data | Extracted client geometry and derived navigation in the local build; existing terrain source notices | No established grant for public asset redistribution. Existing local data is retained. |

The official combined ZIP's GitHub asset SHA-256 is
bd619dcca36f077a6767002db0d0e60212e5781897d91893a236a7f78ccd111d.
Its release.json SHA-256 is
a7c8c3c94445447391f617d35685f1a2afdd5b62e30dbd3d15028b01caa7a2e0.
These identify reviewed evidence, not future version pins.

## Transformative use

The compiler adds joins, objective associations, navigation and indexing. It
also retains extensive source data for the same general purpose of quest
guidance. Reformatting or adding functionality is not a dependable automatic
fair-use clearance. The [US Copyright Office](https://www.copyright.gov/fair-use/)
describes a case-specific four-factor inquiry, including amount copied and
substitution for the original use. A lawyer would need to assess a proposed
fair-use distribution; this review does not invent that conclusion.

## Usable path to public corpus distribution

1. Confirm that the official GPLv3 declaration covers the bundled QuestieDB
   data, corrections and subsequent contributions. A draft request is in
   [questiedb-license-request.md](questiedb-license-request.md); it has not been sent.
2. Preserve notices, add the complete GPLv3 text, mark RikUI's modifications,
   and distribute the matching editable provider inputs, exporter/compiler,
   exact build instructions and license notices beside every derived release.
   Do not offer only generated Lua or a moving link as corresponding source.
3. Keep MIT notices for RikUI's original files. Evaluate the combined
   distribution under GPL-compatible terms without pretending the imported
   corpus is MIT or that a GPL declaration licenses unrelated game assets.
4. Record a separate basis for QuestV2 and extracted road data. If necessary,
   acquire/build those on the user's machine rather than republish the assets.
   That alternative needs an actual supported local pipeline, not a silent
   omission disguised as a complete release.

## Upstream sources behind Questie

Primary-source review on 2026-09-27 confirms that gameplay reports are only
one part of Questie's acquisition process:

- [Merger instructions](https://github.com/Questie/Questie/blob/96cfdb0ac20953c1ef9e88d48a70b9bb913befbf/ExternalScripts%28DONOTINCLUDEINRELEASE%29/merger/README.md)
  describe MaNGOS and Trinity imports for Cataclysm, reusing TBC/WotLK spawns,
  and SQLua exports for MoP. This establishes the import approach, not the
  provenance of every current Classic or Forever record.
- [Item-drop extraction instructions](https://github.com/Questie/Questie/blob/96cfdb0ac20953c1ef9e88d48a70b9bb913befbf/ExternalScripts%28DONOTINCLUDEINRELEASE%29/scraper/item_drop/README.md)
  document both Wowhead scraping and direct CMaNGOS/MaNGOS3 SQL extraction.
- [Scraper instructions](https://github.com/Questie/Questie/blob/96cfdb0ac20953c1ef9e88d48a70b9bb913befbf/ExternalScripts%28DONOTINCLUDEINRELEASE%29/scraper/README.md)
  document Wowhead quest, item, NPC and object imports, currently for SoD,
  plus translations; item names can instead come from client ItemSparse data.
- [Forever conversion metadata](https://github.com/Questie/QuestieDB/blob/365537a340473291f5af3b7a53a5eca94e2a5f1a/data/Forever/conversion.json)
  records Era source tables and corrections converted to Forever geometry.
  Its exclusions include runtime corrections, dungeon entrances, new Forever
  content and race/class restrictions, and subzone/synthetic map routing.

[CMaNGOS Classic-DB](https://github.com/cmangos/classic-db) is a plausible
bulk input for an alternative provider. Its
[README](https://github.com/cmangos/classic-db/blob/master/README.md)
explicitly declares GPLv3, but also excludes some Blizzard material from that
grant. Its [copyright notice](https://github.com/cmangos/classic-db/blob/master/COPYRIGHT.md)
asserts its own intended fair use; that is not permission from Blizzard or a
legal determination for RikUI. It targets original 1.12 content, so Forever
coverage and coordinate compatibility cannot be assumed.

The practical alternative is a bulk importer with recorded source and license,
our own schema and conversion code, followed by targeted corrections and gap
collection. This can avoid depending on QuestieDB's later contributions for
records independently obtained from upstream. It does not automatically clear
the upstream game content, permit Wowhead republication, or reproduce all of
QuestieDB's corrections. Compare IDs, relationships and spatial coverage
before considering a switch; retain the present provider and all its data.

## Independent database alternative

RikUI can maintain its own schema and acquire observations independently:
quest IDs; observed objective targets and counts; NPC/object positions; observed
giver and turn-in relations; drop observations; and confirmed prerequisites.
Retain source, client identity, date, confidence and conflicts per fact. Use the
player's client for displayed quest text when available. Do not assume that
game-world content is free of Blizzard rights merely because it is numeric.

Existing compiler, packet inventory and runtime provider boundaries can support
this route. It does not require deleting or overwriting the present corpus.
A new provider would coexist until an explicit coverage comparison supports a
change. The current baseline has 7,316 IDs and 74,153 exact source points;
observation-only coverage will initially be smaller, especially for prerequisites,
phases, rare drops and unvisited locations.

A renamed or reformatted copy of QuestieDB is still derived from that source.
Independent acquisition needs actual independent evidence, not an assertion
that the transformation is large enough. See the Copyright Office's
[compilation guidance](https://www.copyright.gov/circs/circ14.pdf).
The bulk CMaNGOS route has now been built independently: 4,245 quests share IDs
with the 4,257 baseline semantic quests. Basic objective target sets differ for
897 shared quests; explicit giver/turn-in sets differ for 126. Matching IDs
do not establish parity. See the [build and comparison report](upstream-provider.md).
This experimental provider coexists with the current corpus; it is not yet a
runtime replacement or clearance for excluded game content.

## Current preservation and publication boundary

No quest records, generated files, road data or source inputs were removed.
The existing private rik-wow/quest-data repository and refresh workflow remain
private and unchanged. The full local installer bundle includes the current
quest corpus and all sixteen installed road patch packs.

The public RikUI source repository contains the authored addon, compiler and
installer source. Generated datasets were already outside Git and are not
silently added to public history. The complete data-bearing executable remains
local until the license scope is established. No reduced-data public installer
is substituted for the requested complete installer.
