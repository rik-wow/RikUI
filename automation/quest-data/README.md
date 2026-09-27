# RikUI quest data

Private automated data releases for RikUI. This repository is compatible with
**GitHub Free for organizations**. It uses ordinary Linux Actions jobs and private
releases; no Enterprise attestations, paid environments, or cross-repository token
is needed.

## Schedule and publication

Every day at **09:23 UTC**, and on builder changes or manual dispatch:

1. Resolve current QuestieDB and Questie heads plus Gethe/wow-ui-source's
   `forever` head. Read that exact UI revision's version.txt.
2. Acquire QuestV2 for the resolved client build and validate its schema/hash.
3. Compare all source revisions, client bytes and builder hash with the last
   published receipt. Unchanged runs stop before dependency installation/build.
4. Export all four provider families, all 18 class/faction selectors and locale
   evidence. Compile every exact spawn and current holiday membership.
5. Run compiler/updater tests, full corpus integrity validation and the actual
   RikUI objective/planner host replay. Reject coverage drops greater than 5%.
6. Publish a draft with a deterministic ZIP and SHA-256 checksum, then make it
   the latest release. Commit `state/latest.json` only after successful publication.

Build jobs have read-only repository permissions and no persisted checkout
credentials. A separate job publishes using its repository-scoped GITHUB_TOKEN;
it never runs code from the downloaded artifact. A failed acquisition, changed
unsupported schema, failed replay or coverage regression preserves the last release.
Draft releases can be retried. Published releases are never replaced with different bytes.
GitHub schedules are best effort and can be delayed; use **Actions → Refresh quest
data → Run workflow** for an immediate check.

The daily timeout is 20 minutes for build and 5 for publish; unchanged checks use
far less. Artifacts expire after one day; durable payloads live in Releases.
The organization's shared free allowance is 2,000 Actions minutes/month. No billing
or spending settings are changed by this project.

## Install or roll back

Authenticate GitHub CLI with access to this private repository. With WoW closed:

```powershell
python -B tools/update_quest_data.py --rikui "C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/RikUI"
```

To roll back, add `--tag quest-data-<24-character fingerprint>` from an older release.
The updater downloads authenticated assets, checks the ZIP digest, rejects unsafe
archive paths and verifies every corpus file before the existing ownership-aware
installer replaces the data. A full client restart is required.

WoW addons cannot fetch GitHub data themselves. CI keeps releases current; this
external command installs them. Client API/build compatibility remains owned by
RikUI and is not inferred from new quest membership.

## Sources and coverage

- [QuestieDB](https://github.com/Questie/QuestieDB): corrected Forever quests, NPCs,
  objects, item acquisition relations, exact coordinates and localization.
- [Questie](https://github.com/Questie/Questie): literal holiday membership rows.
- [Forever UI source](https://github.com/Gethe/wow-ui-source/tree/forever): current
  client version discovery.
- [Wago DB2](https://wago.tools/db2/QuestV2): client membership only.

Revisions identify each acquisition; no Forever build is a future target pin.
A source change may need an adapter update when its structure, correction axes or
semantics change. Unknown objectives, coordinates, phases and floors remain unknown.
The pipeline cannot create missing upstream knowledge. No GuideMate/wow-database
compilation is imported. Keep this repository and its generated assets private:
inherited upstream redistribution terms remain unresolved.

## Builder ownership

`BUILDER_SOURCE.json` records the committed RikUI source snapshot and exact file
mapping. Shared exporter/compiler/runtime code comes from that snapshot, not a
second handwritten compiler. Maintainers update it by running
`tools/quest_data_repo.py --output <empty staging directory>` in RikUI, reviewing
the resulting snapshot diff, and committing those changes here. CI updates data,
not its own executable source.

References checked 2026-09-27:
[GitHub Free organization features](https://docs.github.com/en/get-started/learning-about-github/githubs-plans),
[Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions),
[schedule behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).
