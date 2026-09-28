# Combat HUD

RikUI's combat HUD brings the information you act on into one area above the action bars. The character stays clear. Cooldowns belong in the middle, not the corners.

## What belongs here

| Information | Role in the HUD | What adapts |
| --- | --- | --- |
| Cooldowns | One RikUI strip in the centre: the client's configured entries, class aura cells (the paladin Seal cell), then the learned class list | The client's order and hidden choices, learned ranks, spell overrides, the client's aura slots over aura-backed cells |
| Primary resource | A narrow strip below the central rows | Current client power type, including Druid form changes |
| Player cast/channel | Directly below the resource strip | Existing native duration and cast events |
| Important personal buffs and target effects | Class effect rows either side of the cast bar and resource strip | The class catalogue, native aura filtering |
| Combo points, totems and form mana | Small supporting displays | Relevant class, form and native state |
| Weapon timers | Bottom of the central resource/cast stack | Native melee, ranged and wand events; existing kiting cues |
| Proc and loss-of-control alerts | Brief attention cues | Client-owned activation and lifetime |

Health, target/focus casts and pet status remain close enough to support the HUD. Party/raid frames have their own job, especially for healers. Chat, bags, quests and damage meters should not displace the main cooldown/resource column.

The middle is RikUI's own cooldown strip. It draws the client's configured
cooldown entries (the same list Blizzard's cooldown manager would show, in the
order and with the hidden choices saved in its **Tracked spells** window) and
then RikUI's learned class list, in one frame where the native Essential row
used to be; Blizzard's four viewer frames stay hidden while the module runs.
See [cooldowns](cooldowns.md) for the merge and dedupe rules. The class rows'
positions are the shared `CombatPositions` block in `data/layouts.lua`, applied
to every preset.

This composition is part of all four presets and the default interface. It reuses the addon's working class systems instead of requiring WeakAura imports for each character. Individual modules remain optional.

## Applying it

Fresh profiles get the shared combat layout. On an existing profile, use `/rik hud`
or **RikUI > Interface > Arrange combat HUD**. This arranges combat displays and
their supporting unit frames, keeping other frame positions, chat size, keybinds,
scale and module choices. A recognized preset keeps its unit-frame style;
a custom arrangement uses the HUD unit-frame style. Custom surrounding windows
keep their places, so the combat frames may need to fit around them.

Use `/rik layout hud` (or another preset name) to arrange the whole screen instead.
Both actions have one step of undo through `/rik layout undo`.

The column is 280 wide throughout: the cooldown strip, the resource strip, the
player cast bar and the weapon timers share that width (`COLUMN_WIDTH` in
`data/layouts.lua`), and the class effect rows flank it. The unit row above the
column depends on the class: `layouts.SupportingRows` names which classes use
combo points, totems and form mana, `layouts.CombatUnitRow(class)` stacks only
those rows plus the target cast bar's row, and `layout.PresetPositions` passes
the readable player class, so a paladin's unit frames sit just above the target
cast bar while a druid keeps room for combo points and form mana. The rows a
class shows close down onto the strip. No class shows all three rows, so an
unknown class keeps the tallest stack a class has (the druid's), and two rows
no class shows together may share a place. `tests/layouts.test.lua` audits
centered and hud for paladin, warrior, rogue, shaman and druid.

On a short screen (768 units high, the default UI scale) the recipes do not all
fit. The packer places the combat column, the player, the target and the smaller
unit frames first and leaves them where the recipe put them; `layouts.Compact`
moves the group frames to the top margin, puts the target of target above the
target where it would reach the minimap column, closes the HUD's player and
target in on 16:10, and gives the quest tracker the quest timers' place there.
What still does not fit (breath and feign bars, durability, combat timer,
stopwatch, debuffs, quest timers) goes to the nearest free place. The suite
pins this for nine classes on 16:9, 16:10 and 21:9. Classic and Healer keep the
earlier packing order.

The resource strip is enabled by default. It follows the player's current power
type; Druid mana remains a separate supporting display when shifted, configured
in the class settings area (`src/configuration/options/options-class.lua`). Turn
the strip off with `/rik module combatresource off`, then reload. Blizzard's cooldown
manager is kept off while the Cooldowns module is on; disable that module to get
Blizzard's viewers back.

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

## Rank twins

The user's 2026-09-25 15:28 screenshot showed two Immolate icons in the native
**Essential cooldowns** row: configured entries for spell 348 (rank 1) and 11668
(rank 7) on a level 3 character, both marked known by the client. The strip
collapses such twins itself: a native entry whose spell is in RikUI's class
catalogue is drawn as the highest rank the spellbook holds, in the client's
slot, and later entries of the same family are skipped; an uncatalogued entry is
drawn only when its spell ID is in the spellbook. Nothing is written to the
client's cooldown layout and no reload is needed.

## Verification

Automated checks cover all four presets at 16:9, 16:10, ultrawide and two 4K UI
coordinate models; runtime checks include 65%, 85%, 100% and 120% RikUI scales,
chat-input clearance and all registered HUD groups. Resource fixtures cover nine
classes, form/power changes, opaque values, unavailable data, combat login and
explicit opt-out. The scoped arrangement has combat, preference-preservation and
undo regression checks.
