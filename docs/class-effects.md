# Class effects

Class effects adds two movable icon groups: **Class buffs** for the player and **Class target effects** for your effects on the current target. Use **Move frames** to position them. The four layout presets include both groups. Disable **Class effects** under System → Modules and reload to remove them.

Only curated spell families are shown. Each profile expands all published ranks from its own class catalogue. Helpful target effects belong to you; harmful target effects also use the native PLAYER filter. Player buffs may be supplied by another caster. Icons retain the client's countdown, stacks, tooltip and refresh-window cue. There are no empty icons, missing-buff warnings, fixed-duration predictions or automatic actions. The two groups remain independent of the general aura rows and native cooldown manager.

Blizzard owns aura reads, matching, updates and button visibility, including combat. RikUI configures native containers and never reads aura values or pooled button state. A target change explicitly refreshes the target container. Startup construction waits until combat ends. Unsupported classes or empty profiles create no rows; an unknown family rejects that row rather than accidentally displaying every aura. Missing templates leave existing aura displays intact. Weapon-enchant profiles use native main/off-hand slots and their actual duration/charge presentation.

Each group is capped at two lines of six icons. Player rows reserve two slots for weapon enchants when enabled. Target rows allow six harmful and six helpful effects, subject to the client's assistability rules. This is focused tracking, not a complete spellbook or rotation recommendation.

## Evidence and limits

Research checked 2026-09-23. Players in the [working-addons discussion](https://www.reddit.com/r/WowUI/comments/1wkfntp/wow_forever_working_addons_addon/) ask for buff, proc and target-effect trackers; this motivates the feature but does not verify spell mechanics.

The pinned [69913 native container API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua) supports candidateFilters.includeSpellIDs, native enchant slots and target refresh. Spell matching is permitted for helpful auras on assistable units and harmful auras on nonassistable units; the client rejects unavailable matches. Consequently an empty tracker does not prove an effect is absent.

Spell families reuse the verified [class catalogues](class-presets.md), pinned to 1.60.1.69913. Direct aura casts are selected from published spellbook tooltips. Indirect procs, trap victim effects and triggered buffs need separate effect IDs and are excluded where unknown. Newer beta builds may change coverage. Native behavior is accepted under the user's standing policy; no agent-observed game-client test is claimed.

Automated integration tests exercise real container configuration, all-rank filters, class isolation, native countdown/stack registration, weapon slots, target/world changes, combat deferral, disabled/missing-template behavior, invalid-data rejection and isolated refresh failures. Manifest and layout checks cover production integration.

## Class coverage

### Rogue — 2026-09-23

Track Slice and Dice, defensive/movement buffs, your bleeds and control effects, plus both native weapon-enchant slots.

Player: Slice and Dice, Evasion, Sprint, Stealth. Target harmful: Garrote, Rupture, Expose Armor, Cheap Shot, Kidney Shot, Gouge, Sap, Blind.

[Current feedback](https://www.reddit.com/r/WowUI/comments/1wkfntp/wow_forever_working_addons_addon/) motivates this interface; [published spellbook](https://foreverchanges.pro/spellbook/rogue) supplies the direct-aura families through the existing 69913 catalogue. Poison craft IDs are not target poison auras; indirect talent procs remain unknown. Automated tests verify actual native filters and rank expansion; native acceptance is supplied by the user.

### Warrior — 2026-09-23

Track defensive windows, rage buffs and shout uptime alongside your Rend, Sunder and control debuffs.

Player: Battle Shout, Shield Block, Bloodrage, Berserker Rage, Shield Wall, Retaliation, Recklessness. Target harmful: Rend, Sunder Armor, Demoralizing Shout, Thunder Clap, Hamstring, Disarm.

[Current feedback](https://www.curseforge.com/wow/addons/overpowerproc-wow-forever-beta) motivates this interface; [published spellbook](https://foreverchanges.pro/spellbook/warrior) supplies the direct-aura families through the existing 69913 catalogue. Overpower and Victory Rush proc IDs remain unverified; no combat-text inference or stance automation. Automated tests verify actual native filters and rank expansion; native acceptance is supplied by the user.

