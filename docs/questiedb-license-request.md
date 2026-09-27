# Draft licensing clarification request

Not sent. Intended destination: Questie/QuestieDB issue tracker.

**Title:** Clarify GPLv3 coverage for QuestieDB data and derived quest corpora

Hi Questie maintainers,

RikUI uses a local quest corpus generated from QuestieDB's corrected Forever
quests, NPCs, objects and items, including objective associations and locations.
We want to distribute the derived corpus with its corresponding source and
attribution, without stripping any data.

Questie's official CurseForge license page declares GPLv3. The current
Questie 12.0.1 + QuestieDB 1.0.4 release bundles QuestieDB commit
365537a340473291f5af3b7a53a5eca94e2a5f1a. QuestieDB's provenance document
traces its imported tables and corrections to Questie, but QuestieDB currently
has no root LICENSE file.

Could you confirm whether GPLv3 covers the QuestieDB data, corrections,
localization and subsequent contributions distributed in that bundle, and
whether any files have different terms? If so, would you add that declaration
and the relevant notices to QuestieDB?

Our intended distribution would retain attribution, mark our transformations,
include the applicable license, and provide the exact editable provider inputs,
our exporter/compiler, and reproducible build instructions with each corpus.
We would keep unrelated extracted Blizzard terrain assets outside that grant.

Thank you.
