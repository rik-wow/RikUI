# Independent upstream quest provider

Built and compared on 2026-09-27. The experimental database is acquired directly
from CMaNGOS Classic-DB and its matching core schema. QuestieDB is read only for
comparison; no rows or corrections from it are merged into the new provider.
The current addon corpus and installer data remain intact.

## Results

| Measure | Result |
| --- | ---: |
| Current baseline semantic quests | 4,257 |
| Independent quests, all sharing baseline IDs | 4,245 |
| Basic objective rows | 4,917 |
| Giver and turn-in relation rows | 8,459 |
| Original-world spawn rows | 113,866 |
| Shared quests with equal basic target sets | 3,348 |
| Shared quests with different basic target sets | 897 |
| Shared quests with equal declared relation sets | 4,119 |
| Shared quests with different declared relation sets | 126 |

Of the equal target sets, 2,334 are nonempty; of the equal relation sets,
4,045 are nonempty. Empty matches do not establish coverage. This compares
base records, sets of NPC/object/item targets and explicit giver/turn-in
declarations. It excludes counts, ordering, spell/kill-credit/event/reputation
objectives, variants, prerequisites, eligibility and geometry.

Missing baseline quest IDs: 5640, 5678, 7668, 7669, 7670, 65593, 65597,
65601, 65602, 65603, 65604 and 65610.

The baseline also includes client membership records for 7,316 total IDs.
Those are a different population from its 4,257 semantic quests. Spawn rows
are not directly comparable with the baseline's 74,153 exact source points:
upstream spawn-entry choices can represent alternatives and retain original
world coordinates. No Forever map conversion is asserted.

## Build inputs and outputs

Reviewed database revision:
`ec4f596146be6467ea93c57397858e329e2db852`.
Core schema revision:
`8ec338a1704e7dcb1c0213eb7ed58f9231ade40f`.
These identify this acquisition, not the current Forever client target.

The importer follows the upstream full-database sequence: base schema, full
database, content and instance updates, newer core schema migrations, DBC
tables, ScriptDev2, ACID and CMaNGOS custom SQL. Optional locale, development
and playerbot datasets are not part of this build. Every applied input gets
a relative path, role, byte count and SHA-256 in the manifest. The upstream
db_version description can retain its old base label after updates; the
revision and applied-input manifest identify the actual built snapshot.

Local output: `dist/cmangos-provider-1/`.

- `quest-data.sqlite`: 233,435,136-byte archive of selected source tables.
  Raw JSON rows preserve original fields, including loot, events and conditions.
  This is not an export of every upstream SQL table.
- `provider.json`: 56,241,026-byte normalized quests, entities, relations and
  spawn records. Signed links and unknown map compatibility remain explicit.
- `manifest.json`: source revisions, input/output hashes and license disposition.
- `coverage.json`: counts, optional-table absence and ID comparison.
- `comparison.json`: narrower semantic comparisons with differing quest IDs.
- Upstream LICENSE.md, COPYRIGHT.md and AUTHORS.
- `build-server/`: retained local build database; the temporary server is stopped.

Provider SHA-256:
`da7b088450fe21be14655dd48c9bccf9797aaa01d173a5eafa0c3243c82fb131`.

SQLite SHA-256:
`444331cb7c59c378919e25c5bbbeb2f227dcedb1b4a1cc8de1e5ee036d9f9d5a`.

## Reproduce on Windows

Requirements: Python, Git and MariaDB binaries. The tested default is
`C:/Program Files/MariaDB 12.1/bin`; override with `--mariadb-bin`.

```powershell
git clone https://github.com/cmangos/classic-db dist/upstream/classic-db
git clone https://github.com/cmangos/mangos-classic dist/upstream/mangos-classic
python -B tools/upstream/build_cmangos.py --source-root dist/upstream/classic-db --core-root dist/upstream/mangos-classic --output dist/cmangos-provider-new --baseline dist/installer-corpus/quest-data.zip
python -B tools/upstream/compare_provider.py --provider dist/cmangos-provider-new/provider.json --baseline dist/installer-corpus/quest-data.zip --output dist/cmangos-provider-new/comparison.json
python -B -m unittest discover -s tools/upstream -p test_*.py
```

Use the recorded source revisions to reproduce this snapshot; fresh clones
acquire current upstream content. The importer requires clean tracked files
and a new output directory. It starts its own Windows named-pipe database with
TCP disabled and a random credential, executes upstream SQL through a user
restricted to the build database, and stops that process in a finally block.
It never connects to an existing database service.

## Runtime integration and rights

This proves bulk acquisition is viable. It does not yet establish a compatible
runtime replacement. Next work is to classify objective/relation differences,
resolve loot/reference conditions, verify coordinate transforms against the
then-current Forever client, and cover the twelve missing quests using
independent evidence. Keep provenance per correction and do not copy baseline
differences into the independent provider.

[Classic-DB](https://github.com/cmangos/classic-db) explicitly licenses contributor
material under GPLv3, with exclusions for Blizzard content in its
[copyright notice](https://github.com/cmangos/classic-db/blob/master/COPYRIGHT.md).
Using its data avoids relying on QuestieDB's later contributors for these
records, but does not establish permission for excluded game material.
Public dataset redistribution remains unresolved. Full data stays local;
private Cloudflare storage is available for provenance receipts.
See [the licensing review](corpus-licensing.md).
