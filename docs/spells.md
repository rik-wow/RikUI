# Warrior spell data and lookup

`data/spells.lua` loads after core and exposes `RikUI.SpellData` and
`RikUI.Spells`. Loading the file performs no spellbook or texture queries.

- `SpellData[name]` uses exact English source names. Each entry has a contiguous
  `ranks` array of spell IDs, numeric `icon` fileID and `level` for first
  availability. Unranked abilities occupy `ranks[1]`. Treat the table as read-only.
- `Spells.HighestKnownRank(name)` returns `spellID, nil, rankIndex` on success.
  The third value is the catalogue rank index, including when the returned ID
  is a runtime override. Existing callers can continue using just the first ID.
  It scans the player spellbook each time, so training and unlearning need no
  cache invalidation. Matching uses IDs, independent of localized spell names,
  rank labels, numeric ID order or spellbook slot order.
- Only spell entries in active skill lines count; future, flyout, pet and
  off-spec entries are excluded. A recognized base `actionID` also matches when
  an override is active; the returned ID is the overriding `spellID`.
- Unknown/unlearned names return nil. Missing APIs or an incomplete/failed scan
  return `nil, reason`, never a partial lower rank. Callers should preserve their
  existing state on a diagnostic and retry after the spellbook settles.
- `Spells.Icon(name)` queries `C_Spell.GetSpellTexture` by the first-rank ID,
  including for unlearned spells. If unavailable or unsuccessful, it falls back
  to the catalogue icon; missing/throwing API also returns a diagnostic second
  value. Unknown names return nil.
- `/rik spells Heroic Strike` lists observed known ranks with IDs and the
  resolved highest ID in one chat line. Use the exact English catalogue name.
  Empty input shows usage; unknown names and failed lookups get explicit messages.

The scan follows Blizzard's generated
[SpellBook API](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua)
and [spellbook enums](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookConstantsDocumentation.lua).
Texture lookup follows the
[Spell API](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua).
This targets the SDD's Mainline-derived Forever beta, not the stock Classic API.

## Sources and verification

Checked 2026-09-18. The catalogue includes all **36 families / 111 ranks** in the
[ForeverChanges Warrior spellbook](https://foreverchanges.pro/spellbook/warrior)
(build 1.60.1.69913). Spell IDs, rank order, levels and icon names were read from
the page's embedded Next.js data at
`book.tabs[].spells[].ranks[].forever.{spell_id,level}` and each family's `icon`.

The [WoW Forever Talents spellbook](https://wowforevertalents.com/abilities/warrior/)
(build 1.60.1.69893) independently corroborates the rank-level sequences,
including all **47 ranks across 29 families available through level 30**.
Its rendered `data-tip` payloads carry name, rank and level, but not spell IDs;
spell ID verification therefore relies on ForeverChanges' client-derived data.
The talent site's omission of first-rank Mortal Strike, Bloodthirst and Shield
Slam follows its [documented talent-spell filtering](https://wowforevertalents.com/about/).
Those three rank-one entries are retained from ForeverChanges at level 40.
Their level is talent eligibility, not unconditional trainer access. Stances and
other quest-gated abilities likewise still require their normal acquisition.

All 36 icon names were matched to numeric fileIDs using wowdev's
[verified listfile release 202609181958](https://github.com/wowdev/wow-listfile/releases/download/202609181958/verified-listfile.csv),
mapping `interface/icons/<name>.blp` to its fileID. This is a name-to-file
mapping, not evidence that a particular character has learned a spell.

The source-specific differences are significant: Tactical Mastery is 1310185
at level 14, Victory Rush is 402927 at level 20, and Slam starts at 1240193
at level 20 before 1464 at level 30. Stock Classic rank tables are unsuitable.
Separate talent-tree-only abilities absent from these spellbook pages are not
part of this chunk; add them with verified source data when a preset needs them.

## Rank audit

Each cell lists `spellID@minimumLevel` in rank order. For unranked abilities the
single entry occupies rank 1 in the runtime table. Runtime `level` is the first
listed level; this audit preserves the level of every later rank.

| Spell | Rank IDs and levels | Icon fileID |
|---|---|---|
| Battle Shout | 6673@1, 5242@12, 6192@22, 11549@32, 11550@42, 11551@52, 25289@60 | 132333 |
| Battle Stance | 2457@1 | 132349 |
| Berserker Rage | 18499@32 | 136009 |
| Berserker Stance | 2458@30 | 132275 |
| Bloodrage | 2687@10 | 132277 |
| Bloodthirst | 23881@40, 23892@48, 23893@54, 23894@60 | 136012 |
| Challenging Shout | 1161@26 | 132091 |
| Charge | 100@4, 6178@26, 11578@46 | 132337 |
| Cleave | 845@20, 7369@30, 11608@40, 11609@50, 20569@60 | 132338 |
| Defensive Stance | 71@10 | 132341 |
| Demoralizing Shout | 1160@14, 6190@24, 11554@34, 11555@44, 11556@54 | 132366 |
| Disarm | 676@18 | 132343 |
| Execute | 5308@24, 20658@32, 20660@40, 20661@48, 20662@56 | 135358 |
| Hamstring | 1715@8, 7372@32, 7373@54 | 132316 |
| Heroic Strike | 78@1, 284@8, 285@16, 1608@24, 11564@32, 11565@40, 11566@48, 11567@56, 25286@60 | 132282 |
| Intercept | 20252@30, 20616@42, 20617@52 | 132307 |
| Intimidating Shout | 5246@22 | 132154 |
| Mocking Blow | 694@16, 7400@26, 7402@36, 20559@46, 20560@56 | 132350 |
| Mortal Strike | 12294@40, 21551@48, 21552@54, 21553@60 | 132355 |
| Overpower | 7384@12, 7887@28, 11584@44, 11585@60 | 132223 |
| Pummel | 6552@38, 6554@58 | 132938 |
| Recklessness | 1719@50 | 132109 |
| Rend | 772@4, 6546@10, 6547@20, 6548@30, 11572@40, 11573@50, 11574@60 | 132155 |
| Retaliation | 20230@20 | 132336 |
| Revenge | 6572@14, 6574@24, 7379@34, 11600@44, 11601@54, 25288@60 | 132353 |
| Shield Bash | 72@12, 1671@32, 1672@52 | 132357 |
| Shield Block | 2565@16 | 132110 |
| Shield Slam | 23922@40, 23923@48, 23924@54, 23925@60 | 134951 |
| Shield Wall | 871@28 | 132362 |
| Slam | 1240193@20, 1464@30, 8820@38, 11604@46, 11605@54 | 132340 |
| Sunder Armor | 7386@10, 7405@22, 8380@34, 11596@46, 11597@58 | 132363 |
| Tactical Mastery | 1310185@14 | 136031 |
| Taunt | 355@10 | 136080 |
| Thunder Clap | 6343@6, 8198@18, 8204@28, 8205@38, 11580@48, 11581@58 | 136105 |
| Victory Rush | 402927@20 | 132342 |
| Whirlwind | 1680@36 | 132369 |

## Checks and live smoke

`luajit tests/run_tests.lua` loads the TOC and exercises the resolver, catalogue,
icon fallback and slash routing. The source-derived fixture covers every rank
through level 30; catalogue checks cover family/rank counts and unique IDs.
Error tests reject partial scans, while ordering, override, future/off-spec and
training/unlearning cases protect the later setup engine.

No in-game spellbook validation was performed for this chunk. The API guards
make missing beta functionality visible; stub success does not establish that
build 69913 exposes every referenced member.

After `/reload`, run `/rik spells Heroic Strike`, `/rik spells Slam`,
`/rik spells Battle Stance`, and a not-yet-learned listed ability. Compare the
reported ranks to the character's spellbook, then repeat after training a rank.
An unlearned ability should report `known ranks: none; highest: none`.
For an unlearned texture check, run
`/dump RikUI.Spells.Icon("Shield Slam")`; expect a numeric texture ID.
These commands do not change bars, bindings, spells or settings.
