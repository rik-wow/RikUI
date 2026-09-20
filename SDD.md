# RikUI design doc

Status: draft 2, 2026-09-18. Milestone 0 (the probe) is done and the Constraints
section below now says what build 69913 actually does, not what we guessed. The
raw probe output is at the bottom under "Probe results". Nothing of RikUI itself
is built yet.

## What it is

A full UI replacement for WoW: Forever, in the pfUI mould, whose main trick is
that it sets up a fresh character in one go: action bars filled with the right
spells in the right slots, keybinds, macros, game settings and the frame layout,
all from a per-class/per-role preset. As you level, newly trained spells land in
their designated slot and rank upgrades swap in automatically. Empty slots show a
ghost icon of what will go there and at what level.

Look is "Classic but better": flat class-coloured unit frames, cooldown numbers,
range/mana colouring on buttons, buff/debuff timers, square minimap, one-bag,
cleaner chat and tooltips. Classic bottom stack for bars (2 rows centre, 2 side
bars, stance/pet bar above).

Public from day one. No dependencies on other addons. MIT.

Name: RikUI. Slash command: `/rik`. Folder/TOC/Lua/SavedVariables all `RikUI`.

## Why bother, given what's out there

Four "Classic UI for Forever" addons already exist (ClassicUI Forever, Forever
ClassicUI, Classic UI Forever, Forever Classic UI Reframed) and Blizzard ships a
"Classic (Preset)" layout in Edit Mode. All of them are reskins of the Blizzard
frames. None of them touch what's *on* the bars, keybinds, macros or settings.
That's the gap. The skinning is table stakes; the setup engine is the product.

Also, Bartender4/Dominos/ElvUI are all dead on the beta right now (see Constraints),
so there's a window where a bar addon that doesn't need secure snippets is the
only bar addon that works.

## Target environment

| Thing | Value |
|---|---|
| Client | `C:\Program Files (x86)\World of Warcraft\_classic_beta_\`, WowB.exe 1.60.1.69913 |
| TOC Interface | 16001 |
| API | Mainline 12.1.5 architecture with vanilla content. Classic globals (`GetSpellInfo`, `UnitAura`, `GetItemInfo`) are gone. Edit Mode, mixins, `C_Timer`, `C_Spell`, `C_UnitAuras`, `C_Macro`, `C_CVar` exist |
| Beta window | Sep 17 to Oct 21 2026, level cap 30. Launch Nov 4 2026 |
| Classes | Warrior, Hunter, Mage, Rogue, Priest, Warlock, Paladin, Shaman, Druid |
| Races | Human, Dwarf, Night Elf, Gnome, Skyborne (A), Orc, Undead, Tauren, Troll, Skyborne (H) |
| Spell ranks | Yes, still there. Frostbolt goes to rank 11 |
| Specs | Three talent trees, no `GetSpecialization()`. Role has to be inferred from where points are |

Race matters only for racials (which get a slot in the utility tier) and for
new combos like Undead Paladin or Dwarf Shaman that people will roll on day one.

## Constraints that shape everything

These are the things that will bite. Read this before the module list.

### 1. Secure handler snippets don't compile (verified on 69913)

`loadstring_untainted` is nil on 69913, same as on 69893. Running a snippet
through `SecureHandlerExecute` dies at `RestrictedExecution.lua:79` with
"attempt to call a nil value". So everything that goes through
`Blizzard_RestrictedAddOnEnvironment` is dead: `SecureHandlerWrapScript`, every
`_onstate-*` attribute, `RunAttribute`, `initialConfigFunction`. Bartender4
issue #303 has the same error. Might be a Blizzard bug, might be intentional.
We build as if it stays broken.

Gotcha found by the probe: the error is raised inside a script handler that
Blizzard's `SetAttribute` calls from C, so wrapping the call in `pcall` does
not catch it. `pcall` returns true, the error still lands in the error frame
and still counts toward the 100-error cap. Don't touch the secure handler API
at all, not even guarded.

What that kills: the normal way action bar addons do stance/form/stealth paging
(`RegisterStateDriver(bar, "page", ...)` plus an `_onstate-page` snippet).

What works, all verified in-game on a warrior:

- `RegisterStateDriver(frame, "visibility", "[bonusbar:1] show; hide")`. The
  "visibility" state is special-cased inside Blizzard's own
  `SecureStateDriverManager`, which calls `Show()`/`Hide()` on your frame itself.
  Verified: `[bonusbar:N]`, `[stance:N]` and `[combat]` all evaluate correctly,
  and the `[combat]` frame toggled while `InCombatLockdown()` was true.
- `SecureActionButtonTemplate` with `type="action"` and a fixed `action=73`
  attribute. Clicking it fired the Attack in slot 73. It registers `AnyUp` and
  `AnyDown` so `PostClick` runs twice per click. Current secure source selects
  one action edge from `ActionButtonUseKeyDown`; the new overlays preserve
  that handler and both registrations. The user confirmed the bars-overlay
  once-per-click beta check on 2026-09-18, with no Lua errors.
- `PlaceAction`, `PickupMacro`, `ClearCursor`, `SetBinding`, `SaveBindings`,
  `CreateMacro`, `EditMacro`, `C_CVar.*`, `C_Macro`. All present.
  **`PickupSpell` and `PickupItem` are gone**; use `C_Spell.PickupSpell(id)` and
  `C_Item.PickupItem`. `/probe fill` placed a spell with `C_Spell.PickupSpell`
  plus `PlaceAction`, so that path is confirmed.
- Native binding commands. In Battle Stance the `ACTIONBUTTON1` key resolved to
  slot 73, which is exactly page 7 slot 1, the vanilla bonus-bar layout our
  overlay mapping assumes. Bonus bar offset 1 = slots 73-84, 2 = 85-96,
  3 = 97-108.
- A keypress on `ACTIONBUTTON1` runs `ActionButtonDown(1)` (hookable with
  `hooksecurefunc`) but does *not* run `ActionButton1`'s `PostClick`. Hotkey
  flash on our buttons therefore hooks `ActionButtonDown`/`ActionButtonUp`, not
  click scripts.

So: **one overlay bar per stance/form, all at the same screen position, each with
buttons hard-wired to that page's action slots, and the visibility driver picks
which one shows.** Looks exactly like paging. Costs 12 extra buttons per form.
Decision: go. No fallback to Blizzard's buttons, no waiting.

The delivered stance-paging implementation uses the recorded Battle offset
only, shared main layout and native visibility drivers. Stance and pet controls
use the exact build-69913 APIs. The user authorized closure with later stance
mappings and native multi-stance/pet acceptance deferred to backlog
`bars-stance-beta-coverage`; see [bar implementation status](docs/bars.md).
The player does not yet have a second stance; do not repeat requests for those
observations.

### 2. Secret values, always on (verified on 69913)

Measured with `issecretvalue()` on a warrior, out of combat and in combat:

| Call | Out of combat | In combat |
|---|---|---|
| `UnitHealth("player")`, `UnitPower("player")` | secret | secret |
| `UnitHealthMax("player")` | readable | readable |
| `UnitHealth("target")`, `UnitHealthMax("target")` | secret | secret |
| `GetActionCooldown(slot)` | readable | start, duration, modRate secret; enable readable |
| `GetActionCount(slot)` | readable | secret |
| `IsUsableAction(slot)` | readable | readable |
| `IsActionInRange(slot)` | readable | readable, including a range-bearing action (slot 1, 2026-09-18 follow-up) |
| `C_Secrets.ShouldAurasBeSecret()` | false | not sampled |

So the player's own health and power are secret at all times, target health
too. Secret numbers can't be compared, formatted, used as table keys, or
laundered through a StatusBar's `GetValue`.

Rules for every module:

- Never branch on a unit value. Feed it into a sink: `StatusBar:SetValue`,
  `FontString:SetFormattedText`, `Texture:SetAlphaFromBoolean`,
  `Cooldown:SetCooldownFromDurationObject`.
- Timers use duration objects from `C_UnitAuras` / `C_Spell`, never
  `expirationTime - GetTime()`.
- Wrap every unit read in `pcall` inside event handlers.
- `/rik debug` prints `issecretvalue()` for the values each module depends on.

Consequence for unit frames: the bar fills correctly, "1234 / 5000" text works
via `SetFormattedText`, but a percent for your own health is not computable in
Lua. We show current/max, not percent, on the player frame. If a later build
loosens this we can add percent back. The delivered player/target/ToT/pet
frames follow this exactly: `SecureUnitButtonTemplate` buttons, values fed only
through `Secret.Apply` into bar and text sinks, class/reaction/power colours
and the threat border guarded by `issecretvalue` with neutral fallbacks, and
target/ToT/pet visibility through `RegisterStateDriver`. See
[unit frames](docs/unitframes.md). Castbars follow the same rule with the
client's cast duration object fed into `StatusBar:SetTimerDuration` and a
duration text binding for the time, so no cast time is subtracted in Lua; see
[castbars](docs/castbars.md). Auras go one step further: on 69913 every
`C_UnitAuras` read throws for addon code while auras are secret (combat), so
the aura rows are Blizzard `CustomAuraContainerTemplate` containers that read,
assign and lay out auras in secure code and drive RikUI-supplied regions
through the `CustomAuraButton` API (`SetIcon`, `SetApplicationCount`,
`SetDurationCooldown`, `AddDispelTypeTexture`); own versus other casters is a
filter string (`HARMFUL|PLAYER`, `HARMFUL|!PLAYER`); see
[auras](docs/auras.md). Tooltips never read health either: the bar under a
unit tooltip is Blizzard's GUID-watched `GameTooltip.StatusBar`, whose
`SetWatch` the source marks safe for tainted callers, tinted with the unit
frame colour; see [tooltips](docs/tooltip.md).

Consequence for action buttons, decided: **we draw button state ourselves and do
not inherit `ActionBarButtonTemplate`.** Reason: the two things you branch on,
usable and range, stay readable in combat, so mana/range colouring is plain
Lua. The two things that go secret, cooldown and count, both have sinks:
cooldown sweeps come from a duration object (`C_Spell.GetSpellCooldownDuration`
or the `C_ActionBar` equivalent, whichever gives one per slot) fed into
`Cooldown:SetCooldownFromDurationObject`, and counts go through
`FontString:SetFormattedText`. Nothing needs Blizzard's secure button code,
and skipping the template keeps the buttons free of Edit Mode and of the
paging attributes we can't drive anyway. Button state now uses the slot-owned
`C_ActionBar.GetActionCooldownDuration` and `GetActionChargeDuration` objects.
Range and usability are checked with `issecretvalue` before any comparison;
unknown values retain a neutral tint.

Native ranged-action follow-up: `Screenshot 2026-09-18 212711.png` records
`/rik debug` on slot 1 with `combat=false`, `hasRange=true`, `range=true` and
readable returns from all four action APIs. The follow-up
`Screenshot 2026-09-18 213847.png` records the same slot with `combat=true`,
`hasRange=true` and `range=true`: GetActionCooldown returns 1/2/4 are secret,
return 3 is readable; GetActionCount is secret; both IsUsableAction returns and
IsActionInRange remain readable. This closes the ranged combat sample that the
original Attack-only probe lacked. The user also confirmed the updated
cooldowns/countdowns, colors, hotkey labels and keypress flashes work without
Lua errors after reloading.

### 3. Saved variables load (verified on 69913)

The forever-addon-kit repo reported that on 69893 SavedVariables were written on
logout but never read on login. Not true on 69913: `RikProbeDB` and
`RikProbeCharDB` both came back after `/reload` with the seeded timestamp and
`loads=2`, on two different characters. Decision: **rely on saved variables
normally.** No defaults-on-every-login assumption, the wizard runs once and
stays suppressed via `RikUICharDB.wizardDone`. `/rik apply` stays re-runnable
anyway because that's useful in its own right. Only `/reload` was tested; a
full logout is the same code path in every client I know of, so I'm not
spending a chunk on it.

### 4. Other beta gotchas

- Registering an event the client doesn't know throws and aborts the whole
  file. Verified: `LEARNED_SPELL_IN_TAB` is unknown on 69913 and throws.
  **The learned-spell event is `LEARNED_SPELL_IN_SKILL_LINE`**, which registers,
  as do `SPELLS_CHANGED`, `CHARACTER_POINTS_CHANGED`, `PLAYER_TALENT_UPDATE`,
  `UPDATE_BONUS_ACTIONBAR`, `UPDATE_SHAPESHIFT_FORM`, `ACTIONBAR_PAGE_CHANGED`
  and `ACTIONBAR_SLOT_CHANGED`. Still wrap every registration in `pcall`; the
  next build could rename something.
- `MainMenuBar` is nil on this client because Forever is the `camelot` game
  type inside the Mainline UI family: `Blizzard_ActionBar.toc` (commit
  70ef1b2) loads `MainMenuBar.xml` only for `AllowLoadGameType classic`. The
  main bar is **`MainActionBar`**, a `UIParent` child inheriting
  `EditModeActionBarTemplate`, with the gryphons under its `EndCaps` child and
  the page arrows under `ActionBarPageNumber`. `StanceBar` and `PetActionBar`
  are `UIParent` children driven by plain `SetShown`/`Show`/`Hide`, not state
  drivers. `/rik stockbars status` prints the frame each target resolved to on
  the live client; `ActionButton1.bar` is the owner fallback if the global is
  ever renamed.
- After 100 Lua errors the client stops reporting them. `/reload` resets.
- `ReloadUI()` is protected; the user has to type `/reload`.
- Sound/texture files added after launch aren't seen until a client restart.
- Macro limits: 120 account + 18 per character, 255 chars each, 16-char names.
- Edit Mode owns the Blizzard frames. We hide them, we don't register with it.
  If the player opens Edit Mode with RikUI on, things will look wrong. We hook
  `EditModeManagerFrame` OnShow and print a warning.

### Talent reader (level-1 beta path verified)

The 1.60.1 Camelot UI source reads the three vanilla trees as trait groups:
`C_ClassTalents.GetActiveConfigID()`, `C_Traits.GetConfigInfo`,
`C_Traits.GetGroupDisplayInfoByTreeID` and `C_Traits.GetGroupCurrencyInfo`.
RikUI follows the native group display order and matches currency records by
`traitNodeGroupID`, using `currencyInfos[1].spent`. Reads are guarded; staged
talent edits suppress inference via `C_Traits.ConfigHasStagedChanges`.
[Source links, contracts and beta check](docs/roles.md) record the implementation.
The implemented path is now **verified in-game for a level-1 Warrior with no
talents spent**, as recorded below. Nonzero allocations and native popup
interactions remain automated-test coverage rather than observed beta behavior.

User beta observation, 2026-09-18 18:49:05: `/dump GetTalentTabInfo(1)`
raised `attempt to call a nil value` in the dump expression, confirming that
legacy global is unavailable. The user reported no visible output from
`/dump GetNumTalentTabs()`; its availability and return value remain
inconclusive. Neither observation verifies the implemented `C_Traits` path.

User screenshot `Screenshot 2026-09-18 185018.png` shows
`C_SpecializationInfo.GetSpecializationInfo(1)` returning ID `1491`, name
`Warrior`, empty description, icon `626008`, role `DAMAGER`, primary stat `4`,
points spent `0`, preview points `0`, and unlocked `true` (return 8 omitted).
This is a class specialization record, not an observed three-tree point breakdown.
At 18:51:13, `C_SpecializationInfo.GetNumSpecializations()` raised
`attempt to call a nil value`, confirming that requested method is unavailable.
RikUI's implemented reader uses neither of these calls.

User screenshot `Screenshot 2026-09-18 185546.png` shows the loaded reader
failing in `/rik role` at `setup-talents.lua:40` with `talent points unavailable
or unreadable`. Active-config and three-group metadata validation completed,
but that generic error did not identify the currency response shape. Review
found that the native Camelot header renders zero for an omitted currency
group, a case the initial reader incorrectly rejected. The reader now follows
that behavior while still rejecting malformed present records and secret
points; errors name the affected tree. Regression tests cover sparse and empty
currency arrays.

User screenshot `Screenshot 2026-09-18 190910.png`, after reload, shows
`RikUI: Role guess: dps (Arms=0, Fury=0, Protection=0).` The user confirmed
that this is a level-1 character. This verifies the active trait-config path,
three native tree labels, empty-allocation handling and below-10 default in
the beta. The screenshot does not establish spent-point totals, role-change
event delivery or the native popup. Those behaviors pass the LuaJIT tests;
follow-up live coverage is tracked as `setup-role-beta-coverage`.

## How the setup engine works

This is the part that matters. Everything else is furniture.

### Preset data

One Lua file per class under `presets/`. A preset is plain data, no code, so it
can be serialised for import/export and edited by people who don't write Lua.

```lua
-- presets/warrior.lua (shape, not final content)
RikUI.Presets.WARRIOR = {
  roles = {
    dps  = { label = "Arms / Fury", trees = { 1, 2 } },
    tank = { label = "Protection", trees = { 3 } },
  },
  -- shared across roles unless a role overrides a slot
  bars = {
    main = {                      -- page 1, slots 1..12
      { spell = "Heroic Strike", level = 1 },
      { spell = "Rend",          level = 4 },
      { spell = "Thunder Clap",  level = 6 },
      { spell = "Hamstring",     level = 8 },
      { macro = "Execute" },     -- refers to macros[] below
      { spell = "Charge",        level = 4 },   -- Q
      { spell = "Overpower",     level = 12 },  -- E
      { spell = "Pummel",        level = 38 },  -- R
      { spell = "Bloodrage",     level = 10 },  -- F
      { spell = "Shield Block",  level = 16 },  -- T
      { spell = "Demoralizing Shout", level = 14 }, -- G
      { item = "Hearthstone" },  -- 12, mouse only
    },
    battle    = { --[[ overrides for the Battle stance page ]] },
    defensive = { ... },
    berserker = { ... },
    bar2 = { ... },  -- Shift tier + mouse buttons
    bar3 = { ... },  -- Ctrl tier
    bar4 = { ... },  -- side, unbound: mounts, professions, food
    bar5 = { ... },
  },
  macros = {
    Execute = { icon = 135358, body = "#showtooltip Execute\n/cast [stance:1/3] Execute; [stance:2] Battle Stance",
                spells = { "Execute" } }, -- slot stays empty until one listed spell is known
    ...
  },
  roleOverrides = {
    tank = { main = { [1] = { spell = "Sunder Armor", level = 10 }, ... } },
  },
}
```

Spells are referenced by name, not ID, so rank handling is "find the highest
rank of this name in the spellbook". Spell IDs only appear where we need an icon
for a spell the character hasn't learned yet (ghost slots); `C_Spell.GetSpellTexture(id)`
works for unknown spells. `level` is the first acquisition level, shown on the
ghost; quest/talent requirements still apply. Macro `icon` values are texture
fileIDs for `CreateMacro`, not spell IDs. The Execute example switches to Battle
so it works before Berserker Stance is learned at level 30.

Stance pages are sparse. Resolve a fresh page by replacing whole slots in this
order: `bars.main`, `roleOverrides[role].main`, `bars[stance]`, then
`roleOverrides[role][stance]`; missing layers are skipped and missing slots
inherit. For bar2–bar5, use that bar and its matching role override only.
Use `pairs` or a 1–12 loop for sparse overrides, never `ipairs`.
The Warrior declares `roleOrder = { "dps", "tank" }`: the first entry supplies
its default role and resolves talent-score ties, never dictionary iteration order.
The concrete layout and read-only `/rik preset validate` diagnostic are
documented in [docs/presets.md](docs/presets.md).

The data has to be typed in by hand from the Forever spellbook sites
(foreverchanges.pro, wowforevertalents.com). That's a chunk of grunt work, about
40 to 60 spells per class. Warrior first because that's what I'm playing on the
beta, and because stance paging is the hardest case.

### Keybind scheme

One global scheme, same for every class, so muscle memory transfers between
alts. Class presets decide *which spell* goes in each slot; the slot decides the
key. Tiers:

| Slot range | Keys | Meaning |
|---|---|---|
| main 1-5 | `1` `2` `3` `4` `5` | core rotation, by priority |
| main 6-9 | `Q` `E` `R` `F` | situational: gap closer, interrupt, stance-locked ability, resource |
| main 10-11 | `T` `G` | defensives |
| main 12 | none | mouse-click only (hearth, etc.) |
| bar2 1-5 | `Shift-1..5` | big cooldowns |
| bar2 6-9 | `Shift-Q/E/R/F` | more situational |
| bar2 10-11 | `Mouse4` `Mouse5` | the two abilities you press most under pressure (Charge/Pummel, Blink/Counterspell, Sprint/Kick...) |
| bar2 12 | `Shift-T` | spare |
| bar3 1-12 | `Ctrl-1..5`, `Ctrl-F/T/G`, `Ctrl-Z/X/C/V` | buffs, utility, consumables, racial |
| bar4, bar5 | none | side bars, click only |
| stance/form 1-3 | `Ctrl-Q` `Ctrl-E` `Ctrl-R` | forms 4+ unbound |
| pet bar 1-3 | `Shift-G`, `Ctrl-B`, `Ctrl-N` | attack, follow, passive. Open question, see below |

Movement: `A`/`D` become strafe, turn keys unbound, so Q/E are free. Blizzard's
defaults on R (reply), F (assist), T (target), G (?), and the Ctrl-1..6
shapeshift binds get cleared. Alt is left alone for self-cast.

With Mouse4/5 disabled, bar2 slots 10/11 take Shift-G/Ctrl-G. Pet slot 1 and
bar3 slot 8 then receive no scheme key, avoiding duplicate key ownership.
Disabling A/D strafe assigns A/D to turn left/right. Apply makes each scheme
key the native primary so stock bars display the preset key. It clears the
scheme keys plus Ctrl-6 and temporarily clears target-command aliases, then
binds the primary first and restores aliases outside the scheme in their
original relative order. Unrelated bindings remain assigned. Failure recovery
restores original ownership and key order before reporting the error.

Bindings go to the native commands (`ACTIONBUTTON1`, `MULTIACTIONBAR1BUTTON1`,
`SHAPESHIFTBUTTON1`, `BONUSACTIONBUTTON1`, `STRAFELEFT`...), not to `CLICK`
bindings on our buttons. Reason: with overlay bars there are three "slot 1"
buttons for a warrior and a key can only go to one command. The native
`ACTIONBUTTON1` resolves the current page in C, so it hits whatever slot the
visible overlay is mirroring. Verified on 69913: in Battle Stance `ACTIONBUTTON1`
resolves to slot 73, which is what the overlay for bonus bar 1 mirrors. Our
buttons show the hotkey text and the pressed flash by hooking
`ActionButtonDown`/`ActionButtonUp` with `hooksecurefunc`, since the keypress
does not reach the Blizzard button's click scripts.

Saved with `SaveBindings(2)` (character-specific) so alts on other accounts
aren't affected until they run the wizard.

### Applying a preset

`RikUI.Setup.Apply(class, role, opts)` where `opts` is the set of checkboxes from
the wizard: `bars`, `binds`, `macros`, `cvars`, `layout`. Order:

1. Macros. `CreateMacro` for each, per-character where possible (18 slots),
   spilling into account macros only if the preset says so. Existing macro with
   the same name gets `EditMacro`'d, not duplicated.
2. Bars. For every slot: if the character knows the spell,
   `C_Spell.PickupSpell(highestRankID)`, `PlaceAction(slot)`, `ClearCursor()`.
   (The global `PickupSpell` doesn't exist on this client.) If not known, leave
   it empty and let the ghost layer draw it. Items by name via
   `C_Item.GetItemInfo` and `C_Item.PickupItem` if in bags. A preset macro
   goes on the bar only once the character knows one of the `spells` its
   record lists (Execute, Shield Block, Charge, Pummel/Shield Bash); until
   then its slot stays empty too, so a level-1 character never sees a
   button for an attack it cannot train yet.
   Everything out of combat, guarded by `InCombatLockdown()`; if in combat, queue
   and run on `PLAYER_REGEN_ENABLED`.
3. Binds. Clear the keys we're about to use, `SetBinding` each, `SaveBindings(2)`.
4. CVars. `C_CVar.SetCVar` for the list in `cvars.lua`. Each one has a label so
   the wizard can list them.
5. Layout. Positions for our own frames, stored in the profile. Blizzard Edit
   Mode isn't touched.

Everything logs to chat one line per step, and there's a `/rik undo` that
restores the snapshot taken before Apply (bars, binds, macros, cvars, touched
layout keys and the prior applied marker). It persists in RikUICharDB.undo.
Undo restores macros before re-placing bars so macro indices are resolved after
any deletions; failures retain the snapshot and completed-entry progress.

### Keeping it applied while levelling

- `LEARNED_SPELL_IN_SKILL_LINE` (fallback `SPELLS_CHANGED`): look up the spell
  name in the active preset. If it has a designated slot and that slot is empty
  or holds a lower rank of the same spell, place it. If the slot holds something
  else (the player moved things around), don't touch it, print one line.
- Rank upgrades: same path. Highest known rank wins.
- Preset macros: same path. A learned spell also fills the empty designated
  slot of every macro that lists it, using the macro's current index.
- `CHARACTER_POINTS_CHANGED` / talent events: recompute role guess. If it
  changed, popup "Looks like you went Protection. Switch to the tank preset?"
  with Yes / No / Stop asking.
- Role guess: tree with the most points. Under 10 points, default to the first
  role in the preset (DPS everywhere).

### Ghost slots

A non-secure overlay frame per button, above the action button, showing the
designated spell's icon at 35% alpha with a small "Lv 12" tag. Hidden when the
slot has an action. Purely visual, no secure anything, so safe in combat.
Toggle: `/rik ghosts off`.

### Import / export

Serialise the preset table with our own small serialiser (no Ace libs, to keep
the addon dependency-free), deflate with an embedded LibDeflate copy, base64,
prefix `!RIK1!`. Same as the WeakAuras pattern. The export box is a read-only
EditBox with select-all on focus. Import validates shape and spell names before
applying and lists anything it couldn't resolve.

Community presets: people submit a Lua file under `presets/community/` via PR,
or paste a string on the CurseForge page. The ones that hold up get bundled and
show up in the wizard's role dropdown under a "Community" heading.

## Modules

Each module is one file, registers itself with the core, has an `enabled`
toggle in the profile, and can be turned off without breaking the others. In
load order:

| File | Does |
|---|---|
| `core.lua` | saved vars, profile defaults, event bus, `/rik` router, `Print`, `Debug`, secret helpers, combat queue |
| `data/spells.lua` | spell name -> {id per rank, icon, level} for ghost icons. Generated table |
| `data/cvars.lua` | the cvar list with labels and default values |
| `presets/*.lua` | one per class |
| `setup*.lua` | preset resolution, ordered Apply, persistent snapshots and Undo; future role guess / level-up placement |
| `bindings.lua` | the global key scheme, clear/apply, hotkey label formatting ("s1", "M4") |
| `macros.lua`, `macros-undo.lua` | create/edit/find macros, per-character first; scoped undo identities and restoration |
| `bars.lua` | overlay action bars, stance/pet bars, ghost layer, button skin, hide Blizzard bars |
| `unitframes.lua`, `unitframes-status.lua` | player, target, ToT, pet (delivered); class colours; threat; shared range fade |
| `unitframes-raid.lua` | forty fixed frames for raid1-40 from the shared factory in one holder, eight columns of five in raid index order (delivered); parks `CompactRaidFrameContainer`, leaves the raid manager |
| `unitframes-party.lua` | four fixed `SecureUnitButtonTemplate` frames for party1-4 from the shared factory (delivered). No `SecureGroupHeaderTemplate`: its `initialConfigFunction` is a secure snippet, and RikProbe showed snippets cannot run on 69913. Leader icon, role letter, range fade through `SetAlphaFromBoolean` |
| `castbars.lua`, `castbars-status.lua` | player and target castbars (delivered): duration-object fill, shield, interrupt state |
| `auras.lua`, `auras-button.lua`, `auras-units.lua` | player buffs/debuffs, weapon enchants, target and pet aura rows on Blizzard's CustomAuraContainer with our button skin and own-aura emphasis (delivered) |
| `minimap.lua` | Blizzard's Minimap in a square RikUI holder with zone text, local clock and coords, wheel zoom and right-click tracking; cluster art parked, mail and queue frames kept (delivered) |
| `chat.lua`, `chat-copy.lua`, `chat-move.lua` | main chat window lock/unlock and tab drag on a saved holder without Edit Mode; RikUI font at the profile size, flat docked edit box, timestamps, faded tabs, side buttons and scroll controls parked; per-window copy button and address links through the message filter registry and the `addon` link type (delivered) |
| `chat-lines.lua`, `chat-history.lua`, `chat-scroll.lua`, `chat-size.lua`, `chat-input.lua`, `chat-strip.lua`, `chat-tabs.lua`, `chat-clicks.lua` | the 2026-09-19 chat upgrade, every piece behind a live Chat option: class colours through `chatClassColorOverride`, short tags through a secret-safe `AddMessage` wrapper keyed on the event argument, mention and repeat filters keyed on the line id; 1000-line scrollback with the last 200 readable lines restored dimmed per character, jump button with unread count, Ctrl and Shift wheel, corner resize grip with saved size, arrow-key history and sticky chat types; channel strip through `OpenChat`/`SetChatType`/`ReplyTell`, channel-coloured edit box from an `UpdateHeader` post-hook, visible tabs with unread dots, Alt-click invite and Ctrl-click who from a `SetItemRef` post-hook (delivered) |
| `bags.lua`, `bags-items.lua` | one frame for bags 0-4 on `ContainerFrameItemButtonTemplate` buttons (slot in the button ID, bag in a per-bag parent's ID, no Blizzard-read field written), quality borders, counts, cooldowns, name search, `C_Container.SortBags`, money line; Blizzard's bag functions post-hooked and the stock container frames parked (delivered) |
| `tooltip.lua`, `tooltip-data.lua` | movable anchor, flat skin and font, class/reaction colours, Blizzard's GUID-watched health bar, item level and spell ID lines, hide in combat (delivered) |
| `micromenu.lua` | flat micro menu and bag slot strip, hide MicroMenu and BagsBar (delivered) |
| `xpbar.lua`, `motion.lua` | experience row with a rested segment and a watched-faction reputation row, values reader-to-sink with sums under `pcall`, eased fills, gain flash, hover numbers, layout key `xpbar`; `StatusTrackingBarManager` parked once the bar exists; `motion.lua` holds the shared tween and easing helpers (delivered) |
| `mirrortimers.lua` | up to three flat breath, fatigue and feign death bars from the `MIRROR_TIMER` events, progress reader-to-sink in milliseconds every frame, seconds text and low-time pulse under `pcall`, running timers picked up from `GetMirrorTimerInfo`, layout key `mirrortimers`; `MirrorTimerContainer` parked with its events dropped once the bars exist (delivered) |
| `combopoints.lua` | five pips for rogues and druids on layout key `combopoints` between the player and target frames: pip i is a StatusBar with range i-1..i and every pip receives the raw `GetComboPoints` value reader-to-sink, so a secret count needs no comparison; shown with an attackable target, eased fills, flash on the `COMBO_POINTS` power event (delivered) |
| `durability.lua` | flat alert pill on layout key `durability` counting `GetInventoryAlertStatus` over Blizzard's eleven slots on `UPDATE_INVENTORY_ALERTS`: yellow worn count, red broken count with a pulse, fade-in, hover list with percents under `pcall`, hidden under the `RepairArmorDisabled` rule; `DurabilityFrame` parked with its events dropped (delivered) |
| `swingtimer.lua` | flat main hand, off hand and ranged bars on Forever's `PLAYER_SWING(duration, swingType)`, filled from the clock with no unit read, shown only while swinging with a 0.6s linger, swing flash, spark, range dimming from `PLAYER_SWING_RANGE_UPDATE` with the range check requested through `C_SwingTimer`, layout key `swingtimer`; the three stock `SwingTimer*Frame`s parked with their events dropped (delivered) |
| `nameplates.lua`, `nameplates-skin.lua`, `nameplates-target.lua` | flat layout over Blizzard's plates, reapplied after `UpdateAnchors`: 14px own StatusBar fed reader-to-sink with the client's easing, name and Blizzard's percent text inside it, level box, elite marker, flat cast bar frame; target arrows and a pulsing accent line copy `selectedBorder`, a threat line copies `aggroHighlight`, target scale and dimming go through the client's nameplate CVars; a `HARMFUL|PLAYER` aura container per pooled unit frame; forbidden plates are skipped (delivered) |
| `loot.lua`, `loot-rolls.lua` | compact loot list on the loot globals and `LootSlot`, at the cursor or layout key `loot`; `LootFrame` parked with its events dropped because its hide and open paths call `CloseLoot`; `GroupLootFrame1-4` skinned with buttons untouched (delivered) |
| `questtracker.lua`, `questtracker-blocks.lua` | watched quest list at layout key `questtracker`: quest log reads under `pcall` coalesced to one render per event burst, collapsible flat header, level-tagged difficulty-coloured titles, fixed-height truncated objective lines, complete and failed states, fade for new quests, flash on progress, glow on completion, click opens the quest log and shift-click unwatches; `ObjectiveTrackerFrame` parked once the list exists (delivered) |
| `panels.lua`, `panels-skin.lua` | flat skin on first show over `CharacterFrame`, `PlayerSpellsFrame` (spellbook and talents, load on demand), `WorldMapFrame.BorderFrame` (quest log, no fill), merchant, bank, mail, trade, quest and gossip windows: shared chrome keys faded, flat fill and border, font on titles, flat close button, inset and tabs with a selected accent, fade-in; only region alpha, fonts and new child regions are written, each window under `pcall` (delivered) |
| `popups.lua`, `popups-skin.lua` | flat skin on first show over `StaticPopup1-4`, `GameMenuFrame` and `GhostFrame`: the `Border` child frame faded in one write, flat fill and edge, fonts on text, shared font objects on buttons so state changes keep the font, flat buttons and edit box, pooled game menu buttons skinned on every show, fade-in; only alpha, fonts, font objects and new child regions are written because popups gate protected actions (delivered) |
| `wizard.lua` | the first-login flow |
| `options.lua` | `/rik config` panel, hooked into Settings too |
| `importexport.lua` | strings |
| `libs/LibDeflate.lua` | embedded, unchanged |

Hiding Blizzard: `hide.lua` owns `RikUI.Hide.Frame(frame, keepEvents)`,
`Hide.Restore(frame, onRestored)` and `Hide.IsHidden(frame)`. Every Blizzard
frame RikUI suppresses is parked under the shared hidden `RikUIHiddenFrames`
container through the combat queue; a parent posthook records native
reattachment (including Edit Mode moves) and re-parks. The first hidden frame
installs an `EditModeManagerFrame` OnShow hook that prints one warning line.
`bars-stock.lua` uses the helper for MainActionBar (source-verified name;
ActionButton1.bar is the owner fallback) and the multibars with `keepEvents`
true: the native binding path still calls those buttons, so their events,
attributes and handlers are never unregistered. /rik stockbars show restores
the latest native parents, hide reapplies the saved preference, and status
prints each target's resolved frame and state.

StatusTrackingBarManager is parked by xpbar.lua once its own bar exists
(delivered), keeping its child hierarchy. MicroMenu and BagsBar are parked by
micromenu.lua once its strip exists (delivered): micro buttons are secure click
delegates to the stock buttons, bag buttons call the client's bag toggles.
MicroMenuContainer, its queue-status sibling and bag inventory windows stay
available. Native menu layout is refreshed on restoration to its default
container. Bag/menu keys and /rik stockbars show retain access.

StanceBar and PetActionBar are parked only once the RikUI stance and pet rows
exist. The RikUI pet row has no right-click autocast toggle yet, so
/rik stockbars show remains the route to native autocast until it does. The unit
frame module parks PlayerFrame, TargetFrame, PetFrame and TargetFrameToT with
`keepEvents` false once its four replacements exist, and the castbar module
parks PlayerCastingBarFrame the same way once both bars exist, and the aura module
parks BuffFrame and DebuffFrame once both aura containers exist. The minimap
module keeps `Minimap` itself (re-parented into `RikUIMinimap` with a square
mask) and parks the cluster's border, zone button, zoom buttons, backdrop,
native coordinates, instance difficulty flag and day/night indicator with
`keepEvents` false; the mail indicator, queue button and tracking dropdown
move into the holder so they stay reachable. The chat module parks each chat
window's button frame, scroll bar and scroll-to-bottom button plus the
channel, voice, text-to-speech and quick-join buttons with `keepEvents` false;
the chat windows, tabs and edit boxes stay Blizzard's. Other modules will hide
PartyFrame and
container frames through the same helper, only when replaced, passing
`keepEvents` false where no native handler must keep running.

## Wizard (first login)

Runs when `RikUICharDB.applied == nil`, or on `/rik setup`. Five pages, a
Back/Next footer, a summary at the end with one Apply button.

1. Welcome. "Warrior detected. RikUI will set up bars, binds, macros, settings
   and layout. Nothing is applied until the last page." Skip button.
2. Role. Dropdown of the class's roles plus any bundled community presets. Shows
   a preview of the main bar with ghost icons.
3. Keybinds. Picture of the keyboard tiers. Checkbox: "Also rebind A/D to
   strafe". Checkbox: "I have Mouse 4/5" (unchecked moves those two to Shift-G
   and Ctrl-G).
4. Layout and settings. Two columns of checkboxes: every UI module on the left,
   every cvar on the right, all on by default.
5. Summary and Apply. Lists exactly what will change. Apply, then a chat line
   with "type /rik undo to revert".

## Layout defaults

Unit frames go centre-bottom above the bar stack, player left, target right,
ToT to the right of target, pet under player. Party frames left edge, middle
height. Raid frames same spot, grid. That's the ElvUI/pfUI placement and it's
what most UI-replacement users are used to; the reason is you never look away
from the middle of the screen. Classic top-left isn't offered in v1; it's a
profile position so anyone can drag frames there in `/rik move`.

Bars: main bar and bar2 stacked bottom-centre, bar3 above them (fades unless
hovered or in combat), bar4 and bar5 vertical on the right edge, stance/pet bar
above bar3 on the left. Gryphon art is a toggle, off by default.

The base overlay implementation uses the setup engine's corrected native pages:
main 1–12, bar2 61–72, bar3 49–60, bar4 25–36, bar5 37–48. Fixed action
buttons keep frame ID zero and their inherited secure OnClick. The bare secure
template has no drag scripts; explicit PickupAction/PlaceAction handlers run
only out of combat. Profile layout, event-driven visuals and bar3 alpha fading
are implemented. The user confirmed beta click/drag behavior, both right-side
columns, hover/combat reveal and fade, and the stock UI cleanup on 2026-09-18,
with no Lua errors. See [overlay contracts and beta checks](docs/bars.md).

## Settings we apply

All toggleable in the wizard. Values are what I run on the beta.

```
cameraDistanceMaxZoomFactor 2.6
cameraSmoothStyle           0
nameplateShowEnemies        1
nameplateShowFriends        0
nameplateMotion             1        -- stacking
autoLootDefault             1
SpellQueueWindow            400
floatingCombatTextCombatDamage 1
floatingCombatTextCombatHealing 1
showTimestamps              "%H:%M "
chatBubbles                 1
chatBubblesParty            0
screenshotQuality           10
```

Some of these names might differ on 12.x. `data/cvars.lua` checks
`C_CVar.GetCVarInfo` before setting and skips unknowns with a chat line.

## Saved variables

```lua
RikUIDB = {            -- account
  version = 1,
  profiles = { Default = { modules = {...}, positions = {...}, scale = 1 } },
  community = { ["Some preset"] = <preset table> },
}
RikUICharDB = {        -- per character
  applied = { class = "WARRIOR", role = "dps", at = 1758200000, presetVersion = 3 },
  profile = "Default",
  askRole = true,
  wizardDone = true,
}
```

Defaults merged on `ADDON_LOADED`, deep-merge, one function, no library.

## File layout

```
RikUI/
  RikUI.toc
  core.lua
  setup.lua
  bindings.lua
  macros.lua
  bars.lua
  unitframes.lua
  castbars.lua
  auras.lua
  auras-button.lua
  auras-units.lua
  minimap.lua
  chat.lua
  chat-skin.lua
  chat-copy.lua
  chat-move.lua
  bags.lua
  bags-items.lua
  tooltip.lua
  tooltip-data.lua
  wizard.lua
  options.lua
  importexport.lua
  data/
    spells.lua
    cvars.lua
  presets/
    warrior.lua ... druid.lua
    community/
  libs/
    LibDeflate.lua
  media/
    statusbar.tga, font.ttf, button borders
  .pkgmeta
  .github/workflows/release.yml
  README.md
  SDD.md   (this file)
  LICENSE
```

Repo root is the addon root because the BigWigs packager wants the TOC there.
`package-as: RikUI`. GitHub repo `rikui`, CurseForge project "RikUI".

## Milestones

0. **Probe.** Done 2026-09-18. The throwaway `RikProbe` addon (in this repo,
   delete it once RikUI has its own `/rik debug`) answered every question in
   Constraints 1 to 4. Raw output under "Probe results" below.
1. **Setup engine on the stock UI.** Warrior preset, bindings, macros, cvars,
   level-up placement, `/rik apply`, `/rik undo`. No skinning. Already useful
   on its own and I'll be playing with it during the beta.
2. **Bars.** Overlay bars with stance paging, skin, hotkey labels, ghost slots,
   hide Blizzard bars. Button state is drawn by us (Constraints 2).
3. **Unit frames, castbars, auras.**
4. **The rest of the in-game UI.** Tooltips, minimap, chat, bags, party and
   raid frames, micro menu and bag bar, XP and reputation bar, nameplates,
   loot window and roll frames, objective tracker, and a skin pass over the
   Blizzard windows. Decided 2026-09-19: this whole pass ships before any
   polish on already replaced pieces (ghost slots, wizard).
5. **Wizard, options panel, import/export.** Remaining eight class presets.
6. **Ship.** GitHub release via packager, CurseForge, README with the restart
   gotcha up top.

Order is chosen so each milestone is usable without the next one. If Blizzard
fixes secure handlers mid-beta, nothing here needs to change; if they *don't*
fix them by launch, nothing here breaks either.

## Open questions

- Pet bar keys. Hunters and warlocks press pet attack constantly. `Shift-G` is a
  stretch. Might steal `Mouse4` for pet attack on pet classes and shift the
  preset's Mouse4 ability to Q.
- Druids have up to six forms. `Ctrl-Q/E/R` covers three. Travel and aquatic
  can stay click-only, but Moonkin players will want a key.
- Do we want `[@mouseover]` on *every* heal, or only the healer roles? Leaning
  every heal, since a Paladin DPS still Flash-of-Lights the tank.
- How aggressive is level-up placement when the player has rearranged things?
  Current answer: never overwrite a slot that holds a different spell. Might
  need a "re-sync" button.
- Nameplates. Not in scope for v1; we set the cvars and leave Blizzard's.

Closed by the probe: Blizzard's `ActionBarButtonTemplate` is not used, we draw
our own buttons (Constraints 2). Saved variables load (Constraints 3). The
learned-spell event is `LEARNED_SPELL_IN_SKILL_LINE` (Constraints 4). Native
`ACTIONBUTTON1` paging matches the overlay mapping (Keybind scheme).

Closed on raid frames: RikUI draws its own grid, forty fixed
`SecureUnitButtonTemplate` frames for `raid1`-`raid40` in `unitframes-raid.lua`.
Once the party frames existed the grid was cheap, because the same factory
gives every slot its bars, class colour, clicks and secret-safe updates with no
new reader code. Restyling `CompactRaidFrames` was the other option and I
dropped it: it means tainted code writing into frames that read health and
auras in combat, and on this client tainted aura reads throw in combat. The
cost of the choice is ordering. Slots follow the raid index, not the
subgroups, since re-pointing units in combat needs a secure header and header
snippets cannot run on 69913. `CompactRaidFrameContainer` is parked and
`CompactRaidFrameManager` stays.

## Things I'm not doing

- Retail-style anything. No Edit Mode integration, no Blizzard bar art.
- Supporting Classic Era or Retail. TOC is 16001 only.
- Nameplates, threat meters, damage meters, boss mods, quest helpers.
- Talent presets. The addon reads your talents, it doesn't set them.
- Account-wide binds. Always character-specific.

## License

MIT for the code. Blizzard art isn't ours; anything under `media/` that's a
Blizzard texture stays referenced by path, not copied. Fonts and statusbar
textures will be ones with permissive licenses, listed in `media/LICENSES.md`.

## Probe results (build 1.60.1.69913, 2026-09-18)

Raw `/probe` output, transcribed from screenshots. Two characters: a non-warrior
for the first run, then a low-level warrior with only Battle Stance. Chat
timestamps are local. The RikProbe source is in `RikProbe/`.

Error frame at login, from the snippet smoke test (raised inside a C-called
handler, so `pcall` did not catch it):

```
Message: ...d_RestrictedAddOnEnvironment/RestrictedExecution.lua:79: attempt to call a nil value
Stack: RestrictedExecution.lua:79 <- :119 <- :463 <- SecureHandlers.lua:456
       <- [C] SetAttribute <- SecureHandlers.lua:698 <- [C] pcall <- RikProbe.lua:127
Locals: loadstring_untainted=nil
```

Login and report, non-warrior, after one `/reload`:

```
RikProbeDB survived: seeded 2026-09-18 13:15:40 by Rank Stank-Classic Beta PvE, loads=2
RikProbeCharDB survived: seeded 2026-09-18 13:15:40 by Rank Stank-Classic Beta PvE, loads=2
[13:17:04 safe] visibility [bonusbar:1] show; hide -> hidden
[13:17:04 safe] visibility [bonusbar:2] show; hide -> hidden
[13:17:04 safe] visibility [bonusbar:3] show; hide -> hidden
[13:17:04 safe] visibility [stance:1] show; hide -> hidden
[13:17:04 safe] visibility [stance:2] show; hide -> hidden
[13:17:04 safe] visibility [stance:3] show; hide -> hidden
[13:17:04 safe] visibility [combat] show; hide -> hidden
[13:17:04 safe] login GetShapeshiftForm()=0 GetBonusBarOffset()=0 GetActionBarPage()=1
[13:17:04 safe] secret snapshot taken: login
[13:17:04 safe] SPELLS_CHANGED
report: client 1.60.1 build 69913 toc 16001 (safe)
secure snippets: loadstring_untainted is nil; SecureHandlerExecute: returned without effect
API presence (type):
  loadstring_untainted = nil
  issecretvalue = function
  hooksecurefunc = function
  RegisterStateDriver = function
  UnregisterStateDriver = function
  SecureHandlerExecute = function
  SecureHandlerWrapScript = function
  ActionButton1 = table
  ActionButtonDown = function
  MainMenuBar = nil
  GetActionBarPage = function
  GetActionCooldown = function
  GetActionCount = function
  GetActionInfo = function
  GetBonusBarOffset = function
  GetShapeshiftForm = function
  HasAction = function
  IsActionInRange = function
  IsUsableAction = function
  C_ActionBar = table
  C_Spell.GetSpellCooldownDuration = function
  C_Spell.GetSpellName = function
  C_Spell.GetSpellTexture = function
  ClearCursor = function
  CreateMacro = function
  EditMacro = function
  PickupItem = nil
  PickupMacro = function
  PickupSpell = nil
  PlaceAction = function
  GetBindingKey = function
  SaveBindings = function
  SetBinding = function
  C_CVar.GetCVarInfo = function
  C_CVar.SetCVar = function
  C_Item.GetItemInfo = function
  C_Macro = table
  C_Secrets.ShouldAurasBeSecret = function
  C_UnitAuras.GetAuraDataByIndex = function
  C_Timer.After = function
  EditModeManagerFrame = table
  C_Secrets.ShouldAurasBeSecret() = false
visibility state drivers:
  [bonusbar:1] show; hide: registered, shown=false, toggles=1
  [bonusbar:2] show; hide: registered, shown=false, toggles=1
  [bonusbar:3] show; hide: registered, shown=false, toggles=1
  [stance:1] show; hide: registered, shown=false, toggles=1
  [stance:2] show; hide: registered, shown=false, toggles=1
  [stance:3] show; hide: registered, shown=false, toggles=1
  [combat] show; hide: registered, shown=false, toggles=1
stance: GetShapeshiftForm()=0 GetBonusBarOffset()=0 GetActionBarPage()=1
  offsets seen so far: form 0 -> offset 0
fixed action button: created at top centre; slot 73 holds empty; clicks=0
native ACTIONBUTTON1 paging: hooked
[13:17:06 safe] ACTIONBUTTON1 now: resolved slot 1, expected 1, MATCH (GetShapeshiftForm()=0 GetBonusBarOffset()=0 GetActionBarPage()=1)
event registration (count seen):
  ACTIONBAR_PAGE_CHANGED: ok (0)
  ACTIONBAR_SLOT_CHANGED: ok (0)
  CHARACTER_POINTS_CHANGED: ok (0)
  LEARNED_SPELL_IN_SKILL_LINE: ok (0)
  LEARNED_SPELL_IN_TAB: error: RikProbeEvents:RegisterEvent(): Attempt to register unknown event "LEARNED_SPELL_IN_TAB" (0)
  PLAYER_LOGOUT: ok (0)
  PLAYER_REGEN_DISABLED: ok (0)
  PLAYER_REGEN_ENABLED: ok (0)
  PLAYER_TALENT_UPDATE: ok (0)
  SPELLS_CHANGED: ok (1)
  UPDATE_BONUS_ACTIONBAR: ok (0)
  UPDATE_SHAPESHIFT_FORM: ok (0)
  UPDATE_SHAPESHIFT_FORMS: ok (0)
```

Warrior in Battle Stance, event log:

```
[13:20:36 safe] visibility [bonusbar:2] show; hide -> hidden
[13:20:36 safe] visibility [bonusbar:3] show; hide -> hidden
[13:20:36 safe] visibility [stance:2] show; hide -> hidden
[13:20:36 safe] visibility [stance:3] show; hide -> hidden
[13:20:36 safe] visibility [combat] show; hide -> hidden
[13:20:36 safe] login GetShapeshiftForm()=1 GetBonusBarOffset()=1 GetActionBarPage()=1
[13:20:36 safe] secret snapshot taken: login
[13:20:36 safe] SPELLS_CHANGED
[13:21:02 safe] ACTIONBUTTON1 now: resolved slot 73, expected 73, MATCH (GetShapeshiftForm()=1 GetBonusBarOffset()=1 GetActionBarPage()=1)
[13:24:28 safe] fill: slot 73 now holds spell 6603 (Attack)
[13:28:35 safe] action 73 button clicked (LeftButton); slot holds spell 6603 (Attack). Did that cast?
[13:28:35 safe] action 73 button clicked (LeftButton); slot holds spell 6603 (Attack). Did that cast?
[13:28:42 safe] ActionButtonDown(1): the ACTIONBUTTON1 key was pressed
[13:31:03 combat] visibility [combat] show; hide -> shown
[13:31:04 combat] secret snapshot taken: in combat
[13:31:22 safe] visibility [combat] show; hide -> hidden
[13:31:22 safe] secret snapshot taken: out of combat
```

Both the button click and the `1` keypress cast Attack (user confirmed).
`[bonusbar:1]` and `[stance:1]` stayed shown, so they are absent from the
hidden list. No `PostClick` line followed the keypress.

Warrior secret values:

```
login (13:20:36, slot 1, target none):
  GetActionCooldown(slot) secret=false values=0, 0, true, 1
  IsUsableAction(slot) secret=false values=true, false
  IsActionInRange(slot) secret=false values=nil
  GetActionCount(slot) secret=false values=0
  UnitHealth(player) secret=true values=<secret>
  UnitHealthMax(player) secret=false values=70
  UnitPower(player) secret=true values=<secret>
  UnitHealth(target) secret=true values=<secret>
  UnitHealthMax(target) secret=true values=<secret>
out of combat (13:31:22, slot 1, target none):
  (identical to login)
in combat (13:31:04, slot 1, target present):
  GetActionCooldown(slot) secret=true values=<secret>, <secret>, true, <secret>
  IsUsableAction(slot) secret=false values=true, false
  IsActionInRange(slot) secret=false values=nil
  GetActionCount(slot) secret=true values=<secret>
  UnitHealth(player) secret=true values=<secret>
  UnitHealthMax(player) secret=false values=70
  UnitPower(player) secret=true values=<secret>
  UnitHealth(target) secret=true values=<secret>
  UnitHealthMax(target) secret=true values=<secret>
```

Not tested: stance switching in combat (the warrior had no second stance yet),
`IsActionInRange` on a spell that has a range, `ShouldAurasBeSecret()` in
combat, and a full logout/login for saved variables.
