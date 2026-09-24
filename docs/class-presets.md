# Class presets and current research

Checked 2026-09-23. Hunter now has a complete player-spell catalogue and a ready-to-apply preset. Other class additions follow in separate commits.

## Source boundaries

Spell families and rank order come from the author-published [ForeverChanges spellbooks](https://foreverchanges.pro/spellbook/hunter). Their embedded data explicitly identifies **1.60.1.69913**, despite the site's header advertising 69977. IDs and names for all eight new classes (1,446 unique IDs) were cross-checked with Blizzard's extracted [SpellName](https://wago.tools/db2/SpellName/csv?build=1.60.1.69913) and [SpellMisc](https://wago.tools/db2/SpellMisc/csv?build=1.60.1.69913) records: no mismatches or missing records. Numeric icons come from SpellMisc, keyed by SpellID and default difficulty. Internal DB2 spell levels do not establish acquisition: unknown talent levels stay nil. Multiple unranked IDs in one family are retained and only a learned player spellbook entry can become an action.

Runtime catalogues are isolated in `SpellCatalogs[class]`; `Spells.Catalog(class)` and `Spells.Entry(name, class)` select one class. The legacy `SpellData` remains the Warrior table. This prevents names such as Lacerate and Nature's Swiftness colliding. Loading data never reads the spellbook. Automatic upgrades, ghost previews and validation use the same catalogue.

Published books do not enumerate native pet-family actions. Pet action buttons remain client-owned; no pet spells, availability, balance values or acquisition levels are invented. Talent/quest/race restrictions still apply; level alone never grants an action. Requested but unconfirmed spells are excluded.

## Player evidence shaping this work

- [Hunter auto-shot and wand feedback, Sep 23](https://us.forums.blizzard.com/en/wow/t/auto-shoot-bug-and-fix-incoming/2359185): readable shot state; existing weapon timer work already addresses this.
- [Hunter pet action disappearance, Sep 19](https://us.forums.blizzard.com/en/wow/t/hunter-pet-special-ability-disappeared/2354572): expose pet controls without pretending to repair beta pet data.
- [Warrior GUI feedback, Sep 20](https://www.reddit.com/r/classicwow/comments/1wl4exp/forever_warrior/): class-aware bar and key labels.
- [Druid mana in forms, Sep 20](https://us.forums.blizzard.com/en/wow/t/druid-mana-bar-in-bearcat-form/2355852): optional secondary mana display.
- [Paladin feedback, Sep 20](https://us.forums.blizzard.com/en/wow/t/paladin-feedback-1-20-beta/2355823): accessible blessings and Righteous Fury.
- [Priest feedback, Sep 21](https://us.forums.blizzard.com/en/wow/t/priest-feedback-lvl-1-20/2357230): healing, shields and mana matter while leveling.
- [Shaman feedback, Sep 20](https://eu.forums.blizzard.com/en/wow/t/feedback-shaman-talent-tree-elemental-restoration/630172): readable reactive abilities; suggested talents are not confirmed mechanics.
- [Emberwell Forever, Sep 20](https://www.curseforge.com/wow/addons/emberwell-forever): author-published prior art for accessible Warlock preparation and summons.
- [Official known issues, Sep 18](https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-known-issues-september-18/2352687): cooldown-manager coverage and pet scaling remain class-dependent beta limitations.

## Hunter layout

Main: ranged attacks, control, Freezing Trap, mark, pet healing and melee fallback. Shift: cooldowns and traps. Ctrl: aspects, pet care and training. Side bars: talent abilities and tracking. Mouse4 issues pet attack; Mouse5 orders follow and passive. Without mouse buttons the existing Shift-G/Ctrl-G fallback applies. These are explicit actions, never automatic pet combat commands.

Native/game-client acceptance is supplied by the user's standing policy; automated tests validate catalogue resolution, setup and UI contracts. No agent-observed native playtest is claimed.

## Reproducibility

Hunter HTML SHA-256: `35b9bef8778096a25c1f11df15116d0ec9af441678abb0ec910f9898a2dc29e1`.
SpellName CSV SHA-256: `ede393ee7dd2d8a7e9bacbf4f14a32a88ded7f67ba08b33d564e931a352773ab`.
SpellMisc CSV SHA-256: `f6ed1f30f53e311b231b4ae007f8ca5f605e1ad6c960a70f3fce871fb87583bd`.

