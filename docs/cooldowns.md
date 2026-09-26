# Cooldowns

**Cooldowns** is one strip above the resource strip and cast bar. It lists the
client's configured cooldown entries first, in the order the client's cooldown
manager keeps them (Essential, then Utility), then RikUI's own list of learned
class abilities. Every icon is drawn by RikUI: 36 px, seven to a row, up to
three rows, the first entries on the bottom row nearest the resource strip.
Use **Move** in the RikUI menu (or **Move frames**) to place it, or choose one
of the four layouts. Disable the module under System → Modules and reload to
remove it. Hover an icon for the spell's tooltip. The strip is a display; use
your normal action bars and bindings to cast.

The client's four cooldown viewer frames stay hidden while this module is on:
RikUI keeps the `cooldownViewerEnabled` setting off, says so once per session,
and turns the setting back on if you disable the module. Their **Tracked
spells** window is still the way to change the client's part of the list: RikUI
reads that window's data provider (the order and hidden choices you save there)
and rebuilds the strip whenever it reports a change. Before the window's saved
layout has loaded, or when the window does not exist, the strip reads the
client's default lists through `C_CooldownViewer`, minus unknown, invisible and
hidden-by-default entries. Entries without a spell (equipment slots) are left
out for now.

Rank twins are collapsed without any prompt or reload. The client marks every
rank of a spell as known, so a level 3 warlock's list held Immolate 348 and
11668. A native entry whose spell is in RikUI's class catalogue becomes the
highest rank the spellbook holds, in the client's slot, and later entries of the
same family are skipped; an entry outside the catalogue shows only when its
spell ID is in the spellbook. RikUI's class list then adds families the client
did not list. The strip caps at 21 icons.

Some cells watch an aura instead of, or as well as, a cooldown. A native entry
with an aura (Immolate, a tracked buff or bar) and a class **aura cell** (the
paladin's single **Seal** cell, which stands for every seal) host one of the
client's aura slots over the cell: while the aura is up the client draws its
icon, timer and stacks there; when it is not, the cell's own icon shows dimmed
(a tracked entry or class cell) or its cooldown state (a cooldown with an aura).
The slot watches every spell ID the client lists for the entry (base, override
and linked) or every rank of every family in the class cell, on the player for
self auras and on the target for the rest. The client only lets an include
list select helpful auras on the player and harmful auras on a hostile target,
so a harmful aura on the player cannot be shown this way.

The client supplies cooldown swipes, recharge edges, countdown text and charge
or reagent counts through duration objects, which stay valid while their values
are secret in combat. The global cooldown is excluded. Icons remain visible when
there is no duration; that does not establish range, resources, stance,
reagents or cast eligibility. A small **?** marks unavailable cooldown/count
data. Failed calls clear stale presentation and report one diagnostic.

Membership is resolved outside combat: training, unlearning, talents, forms,
world changes, the client's data-changed callback and spell overrides refresh
it; combat defers and coalesces those refreshes; cooldown/count events keep
updating the displayed spells. An incomplete spellbook scan or an unreadable
native entry preserves the last complete strip. Nothing learned hides the strip.

`/rik debug` prints the icon count, how many came from the client, from class
aura cells and from the class list, what was skipped (unlearned, duplicates,
item-only, capped), which
native source answered (`provider`, `provider-default-order`, `api`, `absent`)
and whether the native viewers are hidden.

The module never edits the client's cooldown settings, action slots or macros
and never reads live aura state; aura cells are the client's own secure aura
slots, positioned and decorated by RikUI. It does not infer
aura procs, reset timing, missing buffs or rotations, and never calculates
remaining time from secret values. Pets, item-use effects, racials and
unpublished abilities are outside the curated class lists below.

## Research and verification

Checked **2026-09-24**. Players report empty
[Hunter cooldown lists](https://us.forums.blizzard.com/en/wow/t/cdm-broken/2354115)
and [Paladin cooldown displays](https://us.forums.blizzard.com/en/wow/t/cooldown-manager-in-beta/2355039).
Blizzard's [known issues](https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-known-issues-september-18/2352687)
identify varying class coverage. These motivate the panel; player balance
requests are not evidence of spell mechanics.

The pinned 1.60.1.69913
[Spell API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua)
defines GetSpellCooldownDuration with ignoreGCD, GetSpellChargeDuration and
GetSpellDisplayCount. Duration objects pass directly into native cooldown
widgets, following the existing action-bar integration. No fixed cooldown
length is stored. IDs and rank order reuse the [class catalogues](class-presets.md);
source coverage remains pinned rather than claiming every beta build is known.

Blizzard's 69977 source (extracted locally with `tools/extract_ui_source.py`)
settles the native side: `CooldownViewerMixin:ShouldBeShown` checks the
`cooldownViewerEnabled` setting before the settings window's visibility, so an
off setting keeps the viewers hidden even while **Tracked spells** is open;
`CooldownViewerSettings` never reads that setting, and its data provider
answers before its layout data loads with the default order; every layout
write, spec switch, `SPELLS_CHANGED` and the initial load fire the
`CooldownViewerSettings.OnDataChanged` callback; and `Blizzard_CooldownViewer`
is not load-on-demand, so the provider exists at login whatever the setting.

Blizzard's 69977 `CustomAuraContainerTemplate` also offers aura slots
(`AddAuraSlot`): one frame per key that the container shows with the aura's
icon and duration while a matching aura is present and hides otherwise, left
for the caller to position. The strip anchors each slot over its cell. Slots
are never removed, only refiltered or disabled, so a rebuilt strip reuses them.

Automated tests exercise the merge order and both dedupe rules, item-only and
capped entries, aura cells (slot filters, placement, dimming, disabling and
class cells), provider and API reads, unreadable fields, the setting policy
in and out of combat, the data-changed callback, the flyout
controls, membership updates, combat login, coalescing, opaque native values,
module disablement and layouts (`tests/cooldowns*.test.lua`). Native behavior
is accepted by the user; no agent-observed client result is claimed.

## Class profiles

Each class section below records its current feedback, curated coverage and limits.

### Warlock — 2026-09-24

Priorities: Death Coil, Howl of Terror, Shadow Ward, Amplify Curse, Fel Domination, Shadowburn, Conflagrate, Bane of Doom, Bane of Havoc, Inferno, Ritual of Doom, Soul Fire.

[Current player feedback](https://www.reddit.com/r/classicwow/comments/1widqqd/i_tested_warlock_for_10_hours_in_wow_forever/): Current Warlock experiences discuss leveling flow and control; broader [addon feedback](https://www.reddit.com/r/WowUI/comments/1wkfntp/wow_forever_working_addons_addon/) requests class tracking.
These are community requests, not verified tuning or spell mechanics. The
[client-derived spellbook](https://foreverchanges.pro/spellbook/warlock) still
identifies source build 69913; the profile reuses the verified local catalogue
and actual learned ranks rather than assuming legacy IDs.

Only learned player spell cooldowns. Soulstone/Healthstone item-use timers, pet cooldowns, Nightfall and other proc auras are excluded. Native acceptance supplied by user.

### Mage — 2026-09-24

Priorities: Counterspell, Blink, Ice Block, Ice Barrier, Frost Nova, Cone of Cold, Evocation, Presence of Mind, Arcane Power, Combustion, Cold Snap, Fire Blast.

[Current player feedback](https://us.forums.blizzard.com/en/wow/t/im-worried-about-mage-pvp/2355422): Mage PvP feedback focuses on control, mobility and burst interactions.
These are community requests, not verified tuning or spell mechanics. The
[client-derived spellbook](https://foreverchanges.pro/spellbook/mage) still
identifies source build 69913; the profile reuses the verified local catalogue
and actual learned ranks rather than assuming legacy IDs.

Uses Forever catalogue Ice Block 11958 and Cold Snap 12472, not legacy-name assumptions. No Hot Streak, Fingers of Frost, Arcane stacks or reset prediction. Native acceptance supplied by user.

### Priest — 2026-09-24

Priorities: Power Word: Shield, Penance, Prayer of Mending, Fear Ward, Fade, Psychic Scream, Silence, Power Infusion, Inner Focus, Mind Blast, Devouring Plague, Shadow Word: Death.

[Current player feedback](https://us.forums.blizzard.com/en/wow/t/shadow-priest-feedback-for-wow-forever/2357561): Shadow feedback discusses Devouring Plague downtime and asks for a broader active toolkit.
These are community requests, not verified tuning or spell mechanics. The
[client-derived spellbook](https://foreverchanges.pro/spellbook/priest) still
identifies source build 69913; the profile reuses the verified local catalogue
and actual learned ranks rather than assuming legacy IDs.

Shield cooldown is distinct from Weakened Soul; Prayer of Mending cooldown is not a bounce tracker. No extra abilities or racial eligibility are inferred. Native acceptance supplied by user.

### Druid — 2026-09-24

Priorities: Bash, Growl, Feral Charge, Barkskin, Frenzied Regeneration, Berserk, Tiger's Fury, Dash, Innervate, Rebirth, Swiftmend, Tranquility.

[Current player feedback](https://us.forums.blizzard.com/en/wow/t/feral-druid-feedback-so-far/2356947): Feral feedback highlights combat flow and utility tradeoffs across forms.
These are community requests, not verified tuning or spell mechanics. The
[client-derived spellbook](https://foreverchanges.pro/spellbook/druid) still
identifies source build 69913; the profile reuses the verified local catalogue
and actual learned ranks rather than assuming legacy IDs.

All learned form utilities remain visible regardless of current form. No form page, rage/energy condition, powershift or proc eligibility is inferred. Native acceptance supplied by user.

### Shaman — 2026-09-24

Priorities: Earth Shock, Flame Shock, Frost Shock, Stormstrike, Grounding Totem, Earthbind Totem, Fire Nova, Mana Tide Totem, Riptide, Nature's Swiftness, Lava Burst, Rage of the Farseer.

[Current player feedback](https://us.forums.blizzard.com/en/wow/t/shaman-beta-feedback-high-order-skyborne-shaman-please/2358582): Current Shaman feedback requests earlier active melee tools and a smoother spell-leveling experience.
These are community requests, not verified tuning or spell mechanics. The
[client-derived spellbook](https://foreverchanges.pro/spellbook/shaman) still
identifies source build 69913; the profile reuses the verified local catalogue
and actual learned ranks rather than assuming legacy IDs.

Shared shock and totem cooldowns come from the client; no assumed shared-timer duration, imbue effect, totem lifetime or Maelstrom proc. Forever Fire Nova replaces the legacy totem entry; Riptide uses 408521, not the retail ID. Elemental Mastery is not in the verified catalogue. Native acceptance supplied by user.

### Paladin — 2026-09-24

Priorities: Judgement, Hammer of Justice, Blessing of Protection, Blessing of Freedom, Lay on Hands, Divine Shield, Divine Protection, Holy Shield, Holy Shock, Repentance, Exorcism, Holy Strike.

Judgement leads since 2026-09-25: it is the seal cooldown, learned at level 4, and
on the user's level 4 paladin the native cooldown manager configured no entries at
all (Essential, Utility and both tracked rows empty), so without it the HUD
showed no paladin cooldown until Hammer of Justice at level 8. Divine Favor, a
deep Holy talent, left the list to stay within the row's twelve slots.

[Current player feedback](https://us.forums.blizzard.com/en/wow/t/paladin-feedback-1-20-beta/2355823): Paladin feedback requests smoother utility blessings and more useful Protection/Holy Strike gameplay.
These are community requests, not verified tuning or spell mechanics. The
[client-derived spellbook](https://foreverchanges.pro/spellbook/paladin) still
identifies source build 69913; the profile reuses the verified local catalogue
and actual learned ranks rather than assuming legacy IDs.

Defensive/utility spell cooldowns are distinct from Forbearance, blessing duration and seal state. No inferred lockout, missing buff or tuning change. Native acceptance supplied by user.

### Hunter — 2026-09-24

Priorities: Feign Death, Disengage, Deterrence, Scatter Shot, Concussive Shot, Freezing Trap, Frost Trap, Summon Hawk, Rapid Fire, Bestial Wrath, Intimidation, Tranquilizing Shot.

[Current player feedback](https://us.forums.blizzard.com/en/wow/t/cdm-broken/2354115): Hunters report empty native cooldown-manager spell lists; current [pet-control feedback](https://us.forums.blizzard.com/en/wow/t/ranged-pulling-pet-ai-changes-assistdefensive-auto-engage-boar-charge-micromanagement/2355253) also asks for less micromanagement.
These are community requests, not verified tuning or spell mechanics. The
[client-derived spellbook](https://foreverchanges.pro/spellbook/hunter) still
identifies source build 69913; the profile reuses the verified local catalogue
and actual learned ranks rather than assuming legacy IDs.

Player-cast trap and pet-command cooldowns only. Trap victim auras, pet ability cooldowns and pet AI behavior are not inferred. Native acceptance supplied by user.

### Rogue — 2026-09-24

Priorities: Kick, Kidney Shot, Blind, Evasion, Sprint, Vanish, Gouge, Cold Blood, Blade Flurry, Adrenaline Rush, Preparation, Premeditation.

[Current player feedback](https://us.forums.blizzard.com/en/wow/t/combat-rogue-sprint-ability-suggestion/2356506): Players request better Sprint mobility and discuss cooldown reduction/reset options.
These are community requests, not verified tuning or spell mechanics. The
[client-derived spellbook](https://foreverchanges.pro/spellbook/rogue) still
identifies source build 69913; the profile reuses the verified local catalogue
and actual learned ranks rather than assuming legacy IDs.

Preparation and mobility resets follow the native duration events; no predicted reset, energy threshold, stealth or combo-point eligibility. Native acceptance supplied by user.

### Warrior — 2026-09-24

Priorities: Shield Bash, Pummel, Taunt, Shield Block, Shield Wall, Retaliation,
Recklessness, Berserker Rage, Bloodrage, Intercept, Charge and Intimidating Shout.

Current [DPS cooldown feedback](https://us.forums.blizzard.com/en/wow/t/dps-warrior-feedback/2356172)
and [level-20 tank feedback](https://us.forums.blizzard.com/en/wow/t/level-20-warrior-tanking-feedback/2358381)
motivate visible defensive and control options. These are player requests, not
verified tuning. The reopened [spellbook](https://foreverchanges.pro/spellbook/warrior)
still identifies its underlying data as 69913 despite a newer site header.
The profile reuses the verified Warrior catalogue and actual learned ranks.
Talent-only spells absent from that catalogue, Overpower/Victory Rush proc
eligibility and automatic stance changes are excluded. Cooldowns do not claim
an ability is usable in the current stance. Native acceptance supplied by user.

