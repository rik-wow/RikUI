# Class cooldowns

**Class cooldowns** shows up to twelve learned abilities in two rows of six icons.
Use **Move frames** to place the group, or choose one of the four layouts.
Disable the module under System → Modules and reload to remove it.
Hover an icon for the learned spell's tooltip. The panel is a display; use your
normal action bars and bindings to cast.

The client supplies cooldown swipes, recharge edges, countdown text and charge
or reagent counts. The global cooldown is excluded. Icons remain visible when
there is no duration; that does not establish range, resources, stance,
reagents or cast eligibility. A small **?** marks unavailable cooldown/count
data. Failed calls clear stale presentation and report one diagnostic.

Only learned player spells from the selected class's verified catalogue are
shown, in a stable priority order. Training, unlearning, talents, forms and
world changes refresh membership. Combat defers and coalesces those refreshes;
cooldown/count events continue updating the displayed spells. An incomplete
spellbook scan preserves the last complete list. A successful unlearning removes
the old icon. Unsupported classes and empty profiles create no visible panel.

The module does not need a native Cooldown Manager spell list and does not edit
that manager's settings, action slots or macros. It does not infer aura procs,
reset timing, missing buffs or rotations, and never calculates remaining time
from secret values. Pets, item-use effects, racials and unpublished abilities
are outside these curated player-spell profiles.

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

Automated tests exercise membership, rank updates, unlearning, combat login,
coalescing, invalid profiles, atomic scan failures, opaque native values,
missing APIs, independent failures, tooltips, module disablement and layouts.
Native behavior is accepted by the user; no agent-observed client result is claimed.

## Class profiles

Each class section below records its current feedback, curated coverage and limits.

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

