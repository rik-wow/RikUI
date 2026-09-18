# Warrior preset

`presets/warrior.lua` assigns only plain data to `RikUI.Presets.WARRIOR`.
It performs no API calls and contains no callbacks or computed values.
The TOC already loads it after the spell catalogue and before setup.

## Consumer contract

`roles.dps` covers Arms/Fury trees 1–2; `roles.tank` covers Protection tree 3.
The role table is keyed, not ordered: consumers should explicitly use `dps`
as this preset's default instead of relying on Lua `pairs` order.

Each bar is a sparse map from slot 1–12 to exactly one of
`{ spell = name, level = firstAcquisitionLevel }`, `{ macro = name }`,
or `{ item = name }`. A missing key inherits; it does not clear a slot.
Consumers must use `pairs` or an explicit 1–12 loop, never `ipairs` for
overrides. Replace entire slot records instead of merging their fields.

For a main/stance page, copy these layers in order into a fresh table:

1. `bars.main`
2. `roleOverrides[role].main`, when present
3. `bars[stance]`, when selecting battle/defensive/berserker
4. `roleOverrides[role][stance]`, when present

For bar2–bar5, copy only that bar and its matching role override.
Never mutate the preset while resolving pages. `RikUI.Setup.Resolve` implements
this composition; [the setup engine](setup.md) places the resulting actions.

Main preserves the SDD's rotation on 1–5, Charge/Overpower/Pummel/Bloodrage
on Q/E/R/F, Shield Block/Demoralizing Shout on T/G, and Hearthstone on 12.
Only stance-restricted positions change:

| Page | Sparse replacements |
|---|---|
| Battle | 8 Shield Bash; 10 Shield Block macro |
| Defensive | 4 Disarm; 6 Taunt; 7 Revenge; 8 Shield Bash |
| Berserker | 2 Slam; 3 Whirlwind; 6 Intercept; 7 Victory Rush; 10 Shield Block macro |

Protection's main overrides put Sunder Armor on 1, Taunt on Q, Revenge on E
and Shield Bash on R. Its Battle overrides restore Charge/Overpower, and
its Berserker override restores Pummel, so leaving Defensive does not strand
Taunt/Revenge/Shield Bash in incompatible stances.

Bar2 supplies cooldowns, situational abilities, Charge on Mouse4, and an
Interrupt macro on Mouse5. Shared utility/cooldown bars retain ordinary spell
requirements; they do not change with stance. Bar3 supplies the shout, utility,
stances and the three level-40 talent attacks. These talent slots stay unlearned
unless the character acquires the corresponding talent. Tactical Mastery is
passive and has no action slot. Bar4/bar5 are intentionally empty: mounts,
professions, food, racials and consumables depend on the character.

## Macros

The four bundled names fit the 16-character limit and every body is below
255 characters. Icons are catalogue texture fileIDs, ready for
`RikUI.Macros.Ensure`; they are not spell IDs.

- Execute casts in Battle/Berserker, or switches Defensive to Battle.
  Battle is already available when Execute is learned at 24; Berserker is not
  available until 30. This corrects the original SDD example.
- Shield Block casts in Defensive, otherwise switches to Defensive.
- Charge casts in Battle, otherwise switches to Battle.
- Interrupt casts Pummel in Berserker and Shield Bash in the other stances.

A stance-switching macro requires another press to cast the attack. It cannot
guarantee rage, equipment, range, cooldowns, target conditions or training.
Shield Block/Shield Bash need a shield; Charge still cannot be used in combat.
The Interrupt macro does not grant Pummel before level 38 or equip a shield.
Macro slots retain the SDD's `{ macro = name }` shape without a trainer-level
field. Spell slots carry levels; macro availability is conditional on its body.

## Validation

`RikUI.Setup.ValidatePreset(preset)` returns a fresh, sorted list of diagnostic
strings. An empty list means its slot references and spell levels match the
loaded catalogue. It visits all base/stance pages and every role override,
including sparse high slots, and reports the precise path of an unresolved
spell/macro, wrong spell level, malformed slot or out-of-range slot index.

`/rik preset validate` checks every loaded class preset in name order and prints
each issue, including unresolved spell names. A clean Warrior prints
`WARRIOR: preset valid (catalogue references and spell levels).`
The command reads data only and works without querying the player's spellbook.
Unknown subcommands show usage. An empty registry is reported explicitly.

This diagnostic does not validate full import schemas, parse arbitrary macro
bodies, resolve item names, check learned spells or create/place any actions.
Tests separately check the bundled macro cast operands against the catalogue
and their size/icon contracts. A successful diagnostic is not proof that a
character can currently cast every listed ability.

## Sources and checks

Reviewed 2026-09-18 against the
[ForeverChanges Warrior spellbook](https://foreverchanges.pro/spellbook/warrior)
(build 1.60.1.69913) and
[WoW Forever Talents Warrior spellbook](https://wowforevertalents.com/abilities/warrior/).
The existing [spell audit](spells.md) records the acquisition/rank evidence and
texture fileID mapping. The preset's spell levels match those first-acquisition
levels, including Slam and Victory Rush at 20. Quest and talent prerequisites
remain in effect; levels are not a claim of automatic training.

Client-derived Forever records corroborate restrictions for
[Charge](https://www.wowhead.com/forever/spell=100/charge),
[Overpower](https://www.wowhead.com/forever/spell=7384/overpower),
[Pummel](https://www.wowhead.com/forever/spell=6552/pummel),
[Shield Block](https://www.wowhead.com/forever/spell=2565/shield-block),
[Shield Bash](https://www.wowhead.com/forever/spell=72/shield-bash),
[Taunt](https://www.wowhead.com/forever/spell=355/taunt),
[Revenge](https://www.wowhead.com/forever/spell=6572/revenge),
[Rend](https://www.wowhead.com/forever/spell=772/rend),
[Thunder Clap](https://www.wowhead.com/forever/spell=6343/thunder-clap),
[Hamstring](https://www.wowhead.com/forever/spell=1715/hamstring),
[Intercept](https://www.wowhead.com/forever/spell=20252/intercept) and
[Whirlwind](https://www.wowhead.com/forever/spell=1680/whirlwind).
The alternatives [Slam](https://www.wowhead.com/forever/spell=1240193/slam) and
[Victory Rush](https://www.wowhead.com/forever/spell=402927/victory-rush)
have no stance restriction.
[Execute](https://www.wowhead.com/forever/spell=5308/execute) starts at 24,
before [Berserker Stance](https://www.wowhead.com/forever/spell=2458/berserker-stance) at 30.

`luajit tests/run_tests.lua` covers isolated data loading, catalogue references,
independent source levels, all six role/stance compositions, inheritance,
macro operands/limits/icons and slash diagnostics with unresolved-name fixtures.
No in-game macro execution or native action placement was performed for this
chunk. After reloading the addon, `/rik preset validate` is the read-only
live smoke check. Actual application is now available through `/rik apply`;
see [setup contracts and live verification status](setup.md).
