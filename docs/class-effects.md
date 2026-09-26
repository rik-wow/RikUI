# Class effects

Class effects adds two movable icon groups: **Class buffs** for the player and **Class target effects** for your effects on the current target. Use **Move frames** to position them. The four layout presets include both groups. Disable **Class effects** under System → Modules and reload to remove them.

Only curated spell families are shown. Each profile expands all published ranks from its own class catalogue. Helpful target effects belong to you; harmful target effects also use the native PLAYER filter. Player buffs may be supplied by another caster. Icons retain the client's countdown, stacks, tooltip and refresh-window cue. There are no empty icons, missing-buff warnings, fixed-duration predictions or automatic actions. The two groups remain independent of the general aura rows and native cooldown manager.

Blizzard owns aura reads, matching, updates and button visibility, including combat. RikUI configures native containers and never reads aura values or pooled button state. A target change explicitly refreshes the target container. Startup construction waits until combat ends. Unsupported classes or empty profiles create no rows; an unknown family rejects that row rather than accidentally displaying every aura. Missing templates leave existing aura displays intact. Weapon-enchant profiles use native main/off-hand slots and their actual duration/charge presentation.

Each group is capped at two lines of six icons, 28 px each, the same footprint as the class cooldown row; in the HUD layout the Class buffs row sits directly left of that row at the bottom of the central stack, so a seal's timer and Judgement's cooldown read as one strip, while Class target effects stay above the target frame. Player rows reserve two slots for weapon enchants when enabled. Target rows allow six harmful and six helpful effects, subject to the client's assistability rules. This is focused tracking, not a complete spellbook or rotation recommendation.

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

### Hunter — 2026-09-23

Track active aspects and Rapid Fire, with your mark, stings and slowing effects on ranged or melee targets.

Player: Aspect of the Monkey, Aspect of the Hawk, Aspect of the Cheetah, Aspect of the Beast, Aspect of the Pack, Aspect of the Wild, Rapid Fire. Target harmful: Hunter's Mark, Serpent Sting, Scorpid Sting, Viper Sting, Wing Clip, Concussive Shot.

[Current feedback](https://www.reddit.com/r/classicwow/comments/1wonh43/melee_hunter_macros_and_addons_for_wowforever/) motivates this interface; [published spellbook](https://foreverchanges.pro/spellbook/hunter) supplies the direct-aura families through the existing 69913 catalogue. Trap victim auras and pet ability effects are excluded until their separate IDs are verified; no pet-AI or Auto Shot timing claim. Automated tests verify actual native filters and rank expansion; native acceptance is supplied by the user.

### Paladin — 2026-09-23

Track Righteous Fury, seals and defensive buffs, with your blessings on allies and control effects on enemies.

Player: Righteous Fury, Seal of Righteousness, Seal of Fury, Seal of Command, Seal of Light, Seal of Wisdom, Seal of Justice, Seal of the Crusader, Divine Shield, Holy Shield. Target harmful: Hammer of Justice, Turn Undead, Repentance. Target helpful: Blessing of Might, Blessing of Wisdom, Blessing of Kings, Blessing of Salvation, Blessing of Protection, Blessing of Freedom, Blessing of Sacrifice, Greater Blessing of Might, Greater Blessing of Wisdom, Greater Blessing of Kings, Greater Blessing of Salvation.

[Current feedback](https://us.forums.blizzard.com/en/wow/t/paladin-feedback-1-20-beta/2355823) motivates this interface; [published spellbook](https://foreverchanges.pro/spellbook/paladin) supplies the direct-aura families through the existing 69913 catalogue. No inferred missing-seal or missing-Righteous-Fury warning. Judgement outcomes, Forbearance and indirect seal/talent procs are excluded. Automated tests verify actual native filters and rank expansion; native acceptance is supplied by the user.

### Shaman — 2026-09-23

Track shields and temporary buffs, both native weapon imbues, your shocks and Riptide/utility on allies.

Player: Lightning Shield, Water Shield, Ghost Wolf, Water Breathing, Water Walking, Nature's Swiftness, Rage of the Farseer, Riptide. Target harmful: Flame Shock, Frost Shock. Target helpful: Riptide, Water Breathing, Water Walking.

[Current feedback](https://us.forums.blizzard.com/en/wow/t/use-weapon-imbues-as-design-space-in-forever/2357167) motivates this interface; [published spellbook](https://foreverchanges.pro/spellbook/shaman) supplies the direct-aura families through the existing 69913 catalogue. Totem-applied effects, Maelstrom/Flurry and downstream Stormstrike or weapon proc auras remain unknown. Native enchant slots do not infer enchant identity. Automated tests verify actual native filters and rank expansion; native acceptance is supplied by the user.

### Druid — 2026-09-23

Track defensive and form-combat buffs, your bleeds and Balance effects, and your HoTs on friendly targets across all roles.

Player: Mark of the Wild, Gift of the Wild, Thorns, Barkskin, Enrage, Tiger's Fury, Dash, Nature's Grasp, Innervate, Berserk. Target harmful: Moonfire, Entangling Roots, Faerie Fire, Rip, Rake, Lacerate. Target helpful: Rejuvenation, Regrowth, Wild Growth, Innervate.

[Current feedback](https://us.forums.blizzard.com/en/wow/t/feral-druid-feedback-so-far/2356947) motivates this interface; [published spellbook](https://foreverchanges.pro/spellbook/druid) supplies the direct-aura families through the existing 69913 catalogue. Nature's Grasp self buff is distinct from its triggered root. Clearcasting, separate Pounce bleed and Feral Charge effects remain excluded. Automated tests verify actual native filters and rank expansion; native acceptance is supplied by the user.

### Priest — 2026-09-23

Track shields and defensive buffs, your healing and buff effects on allies, and Shadow DoTs or control on enemies.

Player: Power Word: Shield, Renew, Inner Fire, Inner Focus, Power Infusion, Shadowform, Fear Ward, Fade, Power Word: Fortitude, Divine Spirit. Target harmful: Shadow Word: Pain, Devouring Plague, Holy Fire, Vampiric Embrace, Shackle Undead, Psychic Scream, Silence, Mind Soothe. Target helpful: Power Word: Shield, Renew, Fear Ward, Power Infusion, Power Word: Fortitude, Divine Spirit, Abolish Disease, Shadow Protection.

[Current feedback](https://us.forums.blizzard.com/en/wow/t/power-word-shield-and-rage-generation-in-wow-forever/2354715) motivates this interface; [published spellbook](https://foreverchanges.pro/spellbook/priest) supplies the direct-aura families through the existing 69913 catalogue. Weakened Soul, Prayer of Mending bounce auras, Spirit Tap and other triggered effects remain unverified. Vampiric Embrace is a target debuff in the source. Automated tests verify actual native filters and rank expansion; native acceptance is supplied by the user.

### Mage — 2026-09-23

Track armor, wards, shields and burst-preparation buffs plus your periodic damage, Polymorph, roots and slows.

Player: Arcane Intellect, Frost Armor, Ice Armor, Mage Armor, Mana Shield, Fire Ward, Frost Ward, Ice Barrier, Presence of Mind, Arcane Power. Target harmful: Polymorph, Polymorph: Cow, Fireball, Pyroblast, Frostfire Bolt, Frostbolt, Frost Nova, Cone of Cold, Blast Wave.

[Current feedback](https://us.forums.blizzard.com/en/wow/t/im-worried-about-mage-pvp/2355422) motivates this interface; [published spellbook](https://foreverchanges.pro/spellbook/mage) supplies the direct-aura families through the existing 69913 catalogue. No guessed Fingers of Frost, Hot Streak, Missile Barrage, Clearcasting, Arcane Blast stack, Winter's Chill or Improved Scorch aura IDs. Ice Block aura identity is not inferred from legacy mappings. Automated tests verify actual native filters and rank expansion; native acceptance is supplied by the user.

### Warlock — 2026-09-23

Track armor and defensive/preparation buffs, your DoTs, Forever Banes, curses and control effects; retain target utility buffs.

Player: Demon Skin, Demon Armor, Unending Breath, Detect Invisibility, Shadow Ward, Amplify Curse, Fel Domination. Target harmful: Corruption, Bane of Agony, Immolate, Siphon Life, Bane of Doom, Wrack, Bane of Havoc, Curse of the Elements, Fear, Banish, Curse of Tongues, Curse of Weakness, Curse of Exhaustion. Target helpful: Unending Breath, Detect Invisibility.

[Current feedback](https://www.reddit.com/r/WowUI/comments/1wkfntp/wow_forever_working_addons_addon/) motivates this interface; [published spellbook](https://foreverchanges.pro/spellbook/warlock) supplies the direct-aura families through the existing 69913 catalogue. Nightfall, Decimation, Molten Core, Demonic Sacrifice, Soul Link and item-use Soulstone effects require separate verified aura IDs and are excluded. Six simultaneous target debuffs fit the focus row; general aura rows remain available. Automated tests verify actual native filters and rank expansion; native acceptance is supplied by the user.

