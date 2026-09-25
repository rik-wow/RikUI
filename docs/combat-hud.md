# Combat HUD

RikUI's combat HUD brings the information you act on into one area above the action bars. The character stays clear. Cooldowns belong in the middle, not the corners.

## What belongs here

| Information | Role in the HUD | What adapts |
| --- | --- | --- |
| Essential and Utility cooldowns | Main central icon rows | The native manager owns spell selection, charges, cooldowns and visibility |
| Primary resource | A narrow strip below the central rows | Current client power type, including Druid form changes |
| Player cast/channel | Directly below the resource strip | Existing native duration and cast events |
| Important personal buffs and target effects | Short rows beside the central displays | The character's verified class catalogue and native aura filtering |
| Learned class cooldowns | Nearby defensive/control/utility coverage | Learned ranks, talents and spellbook changes across nine classes |
| Combo points, totems and form mana | Small supporting displays | Relevant class, form and native state |
| Weapon timers | Bottom of the central resource/cast stack | Native melee, ranged and wand events; existing kiting cues |
| Proc and loss-of-control alerts | Brief attention cues | Client-owned activation and lifetime |

Health, target/focus casts and pet status remain close enough to support the HUD. Party/raid frames have their own job, especially for healers. Chat, bags, quests and damage meters should not displace the main cooldown/resource column.

This composition is part of all four presets and the default interface. It reuses the addon's working class systems instead of requiring WeakAura imports for each character. Individual modules and the native cooldown On/Off preference remain optional.

## Applying it

Fresh profiles get the shared combat layout. On an existing profile, use `/rik hud`
or **RikUI > Interface > Arrange combat HUD**. This arranges combat displays and
their supporting unit frames, keeping other frame positions, chat size, keybinds,
scale and module choices. A recognized preset keeps its unit-frame style;
a custom arrangement uses the HUD unit-frame style. Custom surrounding windows
keep their places, so the combat frames may need to fit around them.

Use `/rik layout hud` (or another preset name) to arrange the whole screen instead.
Both actions have one step of undo through `/rik layout undo`.

The resource strip is enabled by default. It follows the player's current power
type; Druid mana remains a separate supporting display when shifted. Turn the
strip off with `/rik module combatresource off`, then reload. Cooldown manager is
also default On, but a later Off choice stays Off.

## Coverage and limits

The class cooldown and effect modules already have Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Mage, Warlock and Druid profiles. Cooldown membership follows learned ranks and rebuilds after training, talents, forms and world changes; protected membership changes wait out combat. Effect rows use native class filters and let the client render durations, stacks and visibility.

Examples include Rogue Slice and Dice/bleeds and poisons; Warrior defensive windows/shouts/debuffs; Hunter aspects/stings; Paladin seals/blessings; Shaman shields/imbues/totems; Druid bleeds/HoTs/form resources; and caster DoTs, shields and defensive cooldowns. Exact lists and exclusions remain in [class effects](class-effects.md) and [class cooldowns](class-cooldowns.md).

This is not a complete replacement for every historical WeakAura. No new proc IDs, trinket effects, pet cooldown catalogue, missing-buff warnings or rotation recommendations are inferred here. Native manager availability and supported matching still depend on the client. An empty row is not proof that an effect is absent. Existing verified class data remains pinned to build 69913; later beta changes are not silently treated as verified.

## Assessment evidence — 2026-09-25

Community requests, not verified mechanics:

- [WeakAuras discussion](https://us.forums.blizzard.com/en/wow/t/im-considering-backing-out-due-to-weakauras/2355036): personal proc visibility and pet/aspect reminders.
- [Compact tracking feedback](https://us.forums.blizzard.com/en/wow/t/addonsweakauras-restricted/2350657): judgement timing close to the character and less empty space.
- [Druid](https://us.forums.blizzard.com/en/wow/t/feral-druid-feedback-so-far/2356947): resources and form gameplay.
- [Shaman](https://us.forums.blizzard.com/en/wow/t/shaman-beta-feedback-high-order-skyborne-shaman-please/2358582): mana use and melee/spell flow.
- [Paladin](https://us.forums.blizzard.com/en/wow/t/paladin-feedback-1-20-beta/2355823): seals, blessings and defensive upkeep.
- [Hunter](https://us.forums.blizzard.com/en/wow/t/cdm-broken/2354115): gaps in the native cooldown list.
- [Rogue](https://us.forums.blizzard.com/en/wow/t/combat-rogue-sprint-ability-suggestion/2356506): mobility cooldown visibility.
- [Warrior](https://us.forums.blizzard.com/en/wow/t/dps-warrior-feedback/2356172): active offensive/defensive tools.
- [Priest](https://us.forums.blizzard.com/en/wow/t/shadow-priest-feedback-for-wow-forever/2357561): DoT and cooldown flow.
- [Mage](https://us.forums.blizzard.com/en/wow/t/im-worried-about-mage-pvp/2355422): control and burst interactions.
- [Warlock player report](https://www.reddit.com/r/classicwow/comments/1widqqd/i_tested_warlock_for_10_hours_in_wow_forever/): DoTs, pets and the changed toolkit.

Primary code reviewed at pinned commit 70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e:

- [Unit API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua): UnitPower and UnitPowerMax select the current resource without a fixed class mapping. Values can be secret; they go directly to native display sinks.
- [Spell API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua): duration objects for cooldowns and charges, with no predicted timers.
- [Custom aura container](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua): native includeSpellIDs matching rejects effects unavailable under client restrictions.
- [Native cooldown viewer](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua): client owns pooled item state and internal layout.

The layout decision is a product inference from this evidence and the user's screenshots. Native behavior is accepted under the user's standing policy; automated tests do not constitute an observed game-client playtest.

## Native duplicate icons

The user's 2026-09-25 15:28 screenshot shows two Immolate-like icons inside
**Essential cooldowns**, with the separate class-effect row empty. Their exact
configured spell identities remain unknown; this is not evidence of cross-row
duplication. RikUI does not delete native entries based on matching artwork.
`/rik debug` now includes each category's configured entry, spell and override
IDs, without inspecting live aura state.

The [native viewer](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua)
allocates a minimum of two pooled items and can show filler icons during native
Edit Mode. That source behavior alone does not establish why these two icons
are visible in the screenshot. The [settings provider](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettingsDataProvider.lua)
provides the configured entries used by diagnostics.

## Verification

Automated checks cover all four presets at 16:9, 16:10, ultrawide and two 4K UI
coordinate models; runtime checks include 65%, 85%, 100% and 120% RikUI scales,
chat-input clearance and all registered HUD groups. Resource fixtures cover nine
classes, form/power changes, opaque values, unavailable data, combat login and
explicit opt-out. The scoped arrangement has combat, preference-preservation and
undo regression checks.
