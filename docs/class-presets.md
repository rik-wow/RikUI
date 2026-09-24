# Class presets and current research

## Learned starter spells on primary keys

Checked 2026-09-23. Spell slots can declare a single starter fallback from the same class catalogue. Apply chooses the highest learned primary rank, or the highest learned starter rank until the primary is available. The wizard shows the starter and names the planned upgrade. A spellbook error never counts as an unlearned spell.

Automatic updates can promote that declared starter to the primary, including inherited stance pages. They preserve unrelated spells, items and macros, never demote an existing primary because a spellbook scan is incomplete, and obey combat deferral and the automatic-placement preference. Explicit Apply can rebuild a layout after changing talents. These are action-bar choices, not an automated rotation or a claim that the spells are mechanically interchangeable.

[Current early-class experiences](https://www.reddit.com/r/classicwow/comments/1wmqsy3/how_are_you_feeling_about_your_class_in_wow/) and [feedback after several level-20 characters](https://www.reddit.com/r/wowforever/comments/1wnj0m8/feedback_after_getting_a_few_20s_in_the_beta/) motivate usable leveling controls. Fallback selection is our interface design, not a reported client mechanic. IDs, ranks and levels remain those in the verified catalogues below. Native acceptance is supplied by the user.


Checked 2026-09-23. All nine classes have ready-to-apply role presets. Eight new player-spell catalogues join the existing Warrior catalogue; this is coverage of the published sources below, not a claim that every unpublished beta ability is known.

The setup role page previews every resolved action page, including stance/form/stealth overlays, racial utility and displaced extra-page actions. Hover a slot for its name, proposed key and learned status. Unlearned talents remain dim even at maximum level, and missing acquisition levels are explicitly unknown. Mouse-key help names the selected class's actual actions and shows the keyboard fallback.

### Warrior leveling attacks across all stances — 2026-09-23

Arms keeps Rend until Mortal Strike; Fury keeps Heroic Strike until Bloodthirst; Protection keeps Heroic Strike until Shield Slam. Stance overrides keep their distinct attacks. No claim about rage tuning or talent availability.

Rechecked [class feedback](https://www.reddit.com/r/classicwow/comments/1wl4exp/forever_warrior/) and the [published spellbook](https://foreverchanges.pro/spellbook/warrior). Community discussion motivates accessible leveling keys; the catalogue remains pinned to verified build 1.60.1.69913, without newly inferred spell IDs, ranks or acquisition levels. Preset version 3. Learned-spell, resolved-page and regression checks cover selection; native acceptance is supplied by the user.

### Rogue leveling builders for talent roles — 2026-09-23

Assassination and Subtlety retain Sinister Strike on their primary builder until Mutilate or Hemorrhage is actually learned. Stealth openers, Kick, Sprint and poison crafting remain distinct; this does not recommend a damage build.

Rechecked [class feedback](https://us.forums.blizzard.com/en/wow/t/rogue-feedback-and-discussion/2355615) and the [published spellbook](https://foreverchanges.pro/spellbook/rogue). Community discussion motivates accessible leveling keys; the catalogue remains pinned to verified build 1.60.1.69913, without newly inferred spell IDs, ranks or acquisition levels. Preset version 3. Learned-spell, resolved-page and regression checks cover selection; native acceptance is supplied by the user.

### Warlock Destruction leveling rotation access — 2026-09-23

Destruction preserves Shadow Bolt, Corruption, Bane of Agony and Drain Life until its later primary abilities are learned. These fill deliberate damage/sustain keys; they do not imply identical mechanics. Pet control and Health Funnel targeting remain explicit.

Rechecked [class feedback](https://www.reddit.com/r/classicwow/comments/1widqqd/i_tested_warlock_for_10_hours_in_wow_forever/) and the [published spellbook](https://foreverchanges.pro/spellbook/warlock). Community discussion motivates accessible leveling keys; the catalogue remains pinned to verified build 1.60.1.69913, without newly inferred spell IDs, ranks or acquisition levels. Preset version 3. Learned-spell, resolved-page and regression checks cover selection; native acceptance is supplied by the user.

### Mage leveling casts in every school — 2026-09-23

Frost and Arcane can start with learned Fireball, then adopt their school's primary casts. Arcane Blast uses learned Arcane Missiles until trained; Fire's Scorch and Pyroblast keys use Fire Blast and Fireball. Control and mobility do not turn into damage fallbacks.

Rechecked [class feedback](https://www.reddit.com/r/classicwow/comments/1wi00u6/critique_my_fire_mage_build_for_leveling_in_pvp/) and the [published spellbook](https://foreverchanges.pro/spellbook/mage). Community discussion motivates accessible leveling keys; the catalogue remains pinned to verified build 1.60.1.69913, without newly inferred spell IDs, ranks or acquisition levels. Preset version 3. Learned-spell, resolved-page and regression checks cover selection; native acceptance is supplied by the user.

### Hunter leveling keys for ranged pet and melee roles — 2026-09-23

Ranged and Beast Mastery primary keys retain Arcane Shot until Aimed Shot or Summon Hawk is learned. Survival retains Raptor Strike on the later Lacerate key. Pet attack/follow, trap and mark controls stay explicit; no pet AI or balance fix is claimed.

Rechecked [class feedback](https://us.forums.blizzard.com/en/wow/t/ranged-pulling-pet-ai-changes-assistdefensive-auto-engage-boar-charge-micromanagement/2355253) and the [published spellbook](https://foreverchanges.pro/spellbook/hunter). Community discussion motivates accessible leveling keys; the catalogue remains pinned to verified build 1.60.1.69913, without newly inferred spell IDs, ranks or acquisition levels. Preset version 3. Learned-spell, resolved-page and regression checks cover selection; native acceptance is supplied by the user.

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

## Mage layout

Frost, Fire and Arcane roles share control and defensive positions. Mouse4/5 remain Blink/Counterspell. Conjuring, armor, buffs and wards use the Ctrl row; teleports and portals remain on side bars and are only placed when learned. All 60 published player families are catalogued. Forever Ice Block (11958) and Cold Snap (12472) were corroborated in SpellName; their unknown talent acquisition levels remain unknown.

Mage HTML SHA-256: `31e2cf872cf35af78a8f292aa7493617b56637d90fcef4c9e251f897b474064f`.

## Rogue layout

Stealth replaces five main slots with openers, Sap and Pick Pocket, while retaining Kick and shared utility. Native Stealth form 30 uses BonusActionBar 1 (slots 73–84), verified in [SpellShapeshiftForm](https://wago.tools/db2/SpellShapeshiftForm/csv?build=1.60.1.69913). No inferred form-index paging is used. Sprint/Kick stay on Mouse4/5; poison crafting recipes remain distinct from weapon enchant auras. All 57 published families are catalogued.

Rogue HTML SHA-256: `6e8f091cfe6d69064632e3915d3f2e5ca323d9460090754686ad098c718ef3e8`.

## Priest layout

Discipline/Holy and Shadow layouts preserve quick healing access. Targeted friendly healing uses living mouseover, living target, then self in both roles; resurrection and group/hostile-capable spells retain native targeting. All 57 published families include race-specific spells, which only become actions when learned. Shadowform has BonusActionBar zero in the exact-build form table, so role selection changes the main layout instead of inventing a protected page.

Priest HTML SHA-256: `a7c824429943f178f17dba3f20d1903ff8f77764507719cdec5ed02eb7201ab6`.

## Warlock layout

Affliction, Demonology and Destruction share Fear, Life Tap, drains and pet controls. Mouse4/5 use the Hunter pet attack/follow convention. The Ctrl row groups armor, stones and demon summons; side rows provide curses, Banes, ritual and travel utility. Forever's Bane of Agony/Bane of Doom names are retained. All 56 player families are catalogued; native pet-family actions are outside the source book and stay native.

Warlock HTML SHA-256: `3db22eb5db4c3c448fcb399f8677055b8c2c677240776b75364e3f21272c945b`.

## Shaman layout

Elemental, Enhancement and Restoration have separate rotations and common emergency controls. Earth Shock stays on Mouse5 and Ghost Wolf on Mouse4. Four Ctrl-row macros group Earth/Fire/Water/Air: keyboard or normal click casts the first listed spell; right click casts the second. They never cast multiple totems automatically. Direct totem alternatives remain on the side rows. Targeted friendly heals follow Priest's mouseover rule. All 56 source families include Forever Fire Nova, Calls, Recall and Projection.

Shaman HTML SHA-256: `3a2b09ccc5ea49f96622eec592a2086e77f2bc3b39b37c0cbcb2e1cc30dc560a`.

## Paladin layout and shared racials

Holy, Protection and Retribution share emergency healing and utility. Righteous Fury is explicit on the Ctrl row and tank main page; seals, blessings and auras retain separate actions. All 56 published families are catalogued. Targeted friendly heals follow the Priest convention; Holy Shock retains native hostile/friendly targeting.

Every class's resolved preset places its two supported active racials on Ctrl-C/V. Any displaced preset actions move to the first empty slots of manual page two (native actions 13–24), so no utility is lost. A full extra page preserves the existing action. Unknown races retain their original layout. Placement still requires the actual spellbook ID; the static racial list grants no ability.

Race selection uses UnitRace's numeric ID: 95 and 96 are distinct Skyborne factions even though both have the Skyborne token. Gnome Eureka! has a separate verified ID for Warrior, Rogue, Priest, Mage and Warlock. Undead Paladin and Dwarf Shaman need no outdated class allowlist.

Racial actives were joined from [the author's published racial descriptions](https://foreverchanges.pro/racials) to exact-build [ChrRaces](https://wago.tools/db2/ChrRaces/csv?build=1.60.1.69913) and [SkillLineAbility](https://wago.tools/db2/SkillLineAbility/csv?build=1.60.1.69913), using playable race bit masks and class masks, then verified against SpellName and non-passive SpellMisc attributes. Internal spell levels are not used to manufacture acquisition requirements.

Paladin HTML SHA-256: `22a7c476dca15b6a90ba9489099083e92b85f2edb1ad16bfd1eb09d8ba94ac80`.

## Druid layout

Feral/Cat, Balance, Restoration and explicit Bear-tank roles include all 60 published families. Talent inference defaults the shared Feral tree to Cat; tank remains a deliberate choice. Four role cards wrap inside the wizard. Cat uses native bonus offset 1 and Bear/Dire Bear offset 3. Travel, Aquatic and Moonkin have offset zero and keep the base page; no six-page assumption is retained.

Ctrl-1..5 are stable named form shortcuts: Bear/Dire Bear, Cat, Moonkin, Travel, Aquatic. The Bear macro uses the learned Dire Bear ID condition (9634). Other form actions use native spell behavior. Healing in every role follows the common friendly mouseover convention. Class-specific Nature's Swiftness and Lacerate IDs stay isolated from Shaman and Hunter.

Druid HTML SHA-256: `a33db4422c77b102b65b301ae57173cf3aa9bd52cd338d66a3d0ddbdbf31ffce`.

## Druid mana in forms

A movable blue mana strip accompanies Cat energy and Bear rage; caster form hides it. Toggle **Interface → Druid mana → Show mana in Cat and Bear** in `/rik config`. Its position participates in all four layouts and Move frames. It uses explicit player Mana and refreshes on resource/form events, with no polling. If mana is restricted, raw values go to supported StatusBar sinks and the text becomes “Mana”; failed reads clear the display instead of leaving old numbers.

This answers the [September 20 player request](https://us.forums.blizzard.com/en/wow/t/druid-mana-bar-in-bearcat-form/2355852); the [DruidForeverManaBar author's September 22 release](https://www.curseforge.com/wow/addons/druidforevermanabar) is additional demand/prior art, not API proof. Rechecked September 23. The pinned [Unit APIs](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) document explicit power types and possible secrecy; [StatusBar sinks](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua) accept opaque values. The native [secondary power mapping](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UnitFrame/Mainline/AlternatePowerBar.lua) lacks Druid Energy/Rage to Mana, so this is a separate addon strip.

## Automatic placement preference

Checked 2026-09-23. In Setup and support, disable Automatically update preset spell slots to stop learned-spell and rank events changing this character's bars. This also cancels queued automatic work when combat ends. Explicit Apply and Re-sync still work; Apply and Undo preserve the preference. Legacy characters default to enabled. The setting uses the existing character persistence transport.

[September 21 player rank-update reports](https://www.reddit.com/r/wowforever/comments/1wmc3uk/next_rank_skills_do_not_equip_automatically/) support keeping upgrades available; opt-out is our design choice for players who maintain their own bars, not a claim of a client bug fix.

## Hunter talent layouts

Checked 2026-09-23 against the [published exact-build spellbook](https://foreverchanges.pro/spellbook/hunter) and existing DB2-backed catalogue. [Current player experiences](https://www.reddit.com/r/classicwow/comments/1wmqsy3/how_are_you_feeling_about_your_class_in_wow/) highlight melee Survival and pet play; these are requests/context, not balance verification. Marksmanship retains the saved `dps` role; Beast Mastery brings Summon Hawk forward and Survival brings melee strikes forward. Displaced ranged attacks stay on the side row. Pet command keys and Freezing Trap stay fixed. Talent inference uses each separate tree. Spell availability still requires the actual learned ID; these layouts make no performance recommendation.

## Rogue talent layouts

Checked 2026-09-23: [Rogue player discussion](https://us.forums.blizzard.com/en/wow/t/rogues-in-forever/2349386) informs support for different playstyles; [author-published spellbook](https://foreverchanges.pro/spellbook/rogue) and existing 69913 catalogue establish the spell families. Combat keeps saved `dps`; Assassination promotes Mutilate and Subtlety promotes Hemorrhage. Sinister Strike stays on the side row, including before those talents are learned. Stealth openers, Kick, Sprint and poison access stay fixed. No talent availability or damage ranking is inferred from level alone.

## Warrior talent layouts

Checked 2026-09-23. [Warrior interface feedback](https://www.reddit.com/r/classicwow/comments/1wl4exp/forever_warrior/) motivates separate talent layouts. The [published spellbook](https://foreverchanges.pro/spellbook/warrior) confirms the existing catalogue's Mortal Strike, Bloodthirst and Shield Slam families. Arms keeps `dps`, Protection keeps `tank`, and Fury gains its own role. Primary pages expose the relevant strike; displaced Rend/Heroic Strike remain on side rows. Existing stance-specific controls remain. Six other talent-only families still need an ID/icon audit and are not guessed into this change.

## Priest targeted utility

Checked 2026-09-23 using [Priest feedback](https://us.forums.blizzard.com/en/wow/t/priest-feedback-lvl-1-20/2357230), [healer-control requests](https://us.forums.blizzard.com/en/wow/t/healer-assist-needs-work-in-wow-forever-client/2355387) and the [published spellbook](https://foreverchanges.pro/spellbook/priest). Penance and Dispel Magic prefer a living friendly mouseover, then a living current target (including enemies), then self. Power Infusion follows friendly healing targeting. Resurrection accepts only a dead friendly mouseover or target. All four remain gated by learned spells and work in both layouts. These are player-triggered native macros, not automatic dispel or healing decisions.

## Mage group utility

Checked 2026-09-23 against [Mage utility feedback](https://us.forums.blizzard.com/en/wow/t/beta-feedback-21-year-wow-vet/2356930) and the [published spellbook](https://foreverchanges.pro/spellbook/mage). Curse removal, Intellect, Dampen Magic and Amplify Magic now use living friendly mouseover, friendly target, then self in every role. Each macro is learned gated. Offensive targeting, Blink and Counterspell keep their existing controls. This supports deliberate group utility; it does not inspect auras or automatically choose a dispel target.

### Warlock control targets — 2026-09-23

[September 16 player testing and discussion](https://www.reddit.com/r/classicwow/comments/1widqqd/i_tested_warlock_for_10_hours_in_wow_forever/) emphasizes pet management and crowd control; this is community motivation, not confirmed client mechanics. The [author's extracted Warlock spellbook](https://foreverchanges.pro/spellbook/warlock) pins its data to 1.60.1.69913 and supports the existing Fear, Banish and Health Funnel families. No IDs or rank assumptions were added.

All three roles now use living hostile mouseover, then current hostile target, for Fear and Banish. Health Funnel explicitly addresses the living pet without changing the selected enemy. Existing pet attack/follow keys, damage rotations and learned-spell gates remain. Pet-family abilities, soulstone item ranks and unresolved scaling are outside this change. Version 2 marks the preset update. Automated role-composition and macro-contract checks cover these changes; native acceptance is supplied by the user.

### Shaman utility access — 2026-09-23

[September 20 community discussion](https://www.reddit.com/r/wowforever/comments/1wl5tog/with_all_of_the_changes_and_adjustments_how_is/) values situational totems; [class feedback](https://eu.forums.blizzard.com/en/wow/t/feedback-shaman-talent-tree-elemental-restoration/630172) asks for more active decisions. Those requests motivate access improvements, without claiming the requested talents exist. The [author's spellbook](https://foreverchanges.pro/spellbook/shaman) explicitly sources build 1.60.1.69913; existing verified names/ranks/icons are retained.

Grouped totem macros now accept Alt while activating their assigned action, as well as right-click, for their second spell. Normal activation keeps the first spell. Both choices are deliberate; an unlearned alternative is not granted or automatically replaced. Ancestral Spirit targets dead friendly mouseover/current target; Water Breathing and Water Walking use living friendly mouseover, target, then self in every role. Existing recall/projection and interrupt controls remain. Version 2, role-composition checks, macro size checks and user-supplied native acceptance cover this update.

### Paladin emergency and dual-use utility — 2026-09-23

[September 20 feedback](https://us.forums.blizzard.com/en/wow/t/paladin-feedback-1-20-beta/2355823) asks for smoother utility; [September 19 feedback](https://eu.forums.blizzard.com/en/wow/t/ret-paladin-still-bad/630021) specifically discusses Protection, Freedom and Sacrifice. These are community requests, not evidence that blessing replacement rules changed. The [author's Paladin spellbook](https://foreverchanges.pro/spellbook/paladin), sourced to 1.60.1.69913, describes both friendly and hostile uses of Holy Shock and Light's Vigil.

Those two talents now share friendly living mouseover, then living current target (including enemies), then self targeting. They remain separate deliberate casts. Protection and Freedom use friendly mouseover, target, self; Sacrifice requires a friendly mouseover or target with no self fallback. Redemption requires a dead friendly target. Version 2 updates every role and Holy's main-bar overrides while retaining learned-spell gates and native blessing rules. No automatic seal twisting or blessing restoration is introduced. Automated role/macro checks pass; native acceptance is supplied by the user.

### Druid support across roles — 2026-09-23

[September 21 Druid feedback](https://www.reddit.com/r/classicwow/comments/1wmgbtq/wow_forever_druid_feedback/) discusses healing and hybrid play; [healer-control feedback](https://us.forums.blizzard.com/en/wow/t/healer-assist-needs-work-in-wow-forever-client/2355387) requests better manual controls. A [September 23 powershift report](https://www.reddit.com/r/classicwow/comments/1wo75et/druid_powershift_macro_causing_formaction_bar/) is community evidence of a possible beta issue, not agent-confirmed behavior. This change adds no form-cancellation commands. The [author's Druid spellbook](https://foreverchanges.pro/spellbook/druid) explicitly sources 1.60.1.69913 and distinguishes Revive from Rebirth; existing verified families are used.

Innervate, Mark/Gift of the Wild and Thorns now use living friendly mouseover, target, self. Rebirth and Revive remain separate dead-friendly mouseover/target actions so the player chooses which resurrection to spend. All four roles receive the controls, including Restoration's main-bar Innervate. Cat/Bear native pages and named form controls remain intact. Version 2, automated composition checks and macro limits cover the update; native acceptance is supplied by the user. Spell tuning and unpublished future builds remain outside confirmed coverage.

