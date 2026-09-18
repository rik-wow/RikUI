# RikUI design doc

Status: draft 1, 2026-09-18. Nothing is built yet. This is the plan we agreed on
after a research pass and a bunch of back-and-forth. Expect it to change once the
probe addon (milestone 0) tells us what the beta client actually allows.

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

### 1. Secure handler snippets don't compile

On build 69893 `loadstring_untainted` is nil, so anything that goes through
`Blizzard_RestrictedAddOnEnvironment` throws "attempt to call a nil value":
`SecureHandlerWrapScript`, every `_onstate-*` attribute, `RunAttribute`,
`initialConfigFunction`. Bartender4 issue #303 confirms it, and ShadowedUF hits
the same error. Not yet checked on 69913 (the build I have). Might be a Blizzard
bug, might be intentional lockdown. Assume it stays broken.

What that kills: the normal way action bar addons do stance/form/stealth paging
(`RegisterStateDriver(bar, "page", ...)` plus an `_onstate-page` snippet).

What still works, as far as I can tell:

- `RegisterStateDriver(frame, "visibility", "[bonusbar:1] show; hide")`. The
  "visibility" state is special-cased inside Blizzard's own
  `SecureStateDriverManager`, which calls `Show()`/`Hide()` on your frame itself.
  No snippet involved, runs in combat.
- `SecureActionButtonTemplate` with `type="action"` and a fixed `action=N`
  attribute set out of combat.
- `PickupSpell`, `PlaceAction`, `PickupMacro`, `SetBinding`, `SaveBindings`,
  `CreateMacro`, `EditMacro`. All plain API, all fine out of combat.
- Native binding commands like `ACTIONBUTTON1` and `MULTIACTIONBAR1BUTTON1`.

So: **one overlay bar per stance/form, all at the same screen position, each with
buttons hard-wired to that page's action slots, and the visibility driver picks
which one shows.** Looks exactly like paging. Costs 12 extra buttons per form.

We decided *not* to keep a fallback that adopts Blizzard's own buttons. If the
visibility driver turns out to be blocked too, we wait for Blizzard.

### 2. Secret values, always on

The player's own health and power come back secret from `UnitHealth`/`UnitPower`
at all times on this client, not just in combat. Enemy health is secret. Auras
throw when read in combat. Secret numbers can't be compared, formatted, used as
table keys, or laundered through a StatusBar's `GetValue`.

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
loosens this we can add percent back.

Consequence for action buttons: `GetActionCooldown`, `IsUsableAction`,
`IsActionInRange`, `GetActionCount` might return secrets in combat. Unknown.
That's a probe item. If they do, our buttons inherit Blizzard's
`ActionBarButtonTemplate` so Blizzard's secure code draws cooldown/range/usable
state for us and we only skin it. If they don't, we draw everything ourselves.
Either way the frame is ours; only the internals of the button differ.

### 3. Saved variables might not load

The forever-addon-kit repo reports that on 69893 SavedVariables are written on
logout but never read on login, so every addon starts from defaults. My
`Untethered` addon's SV file exists on disk so writes definitely happen. Whether
reads work on 69913 I haven't checked. Probe item. If broken, the addon still
has to be usable: everything must be re-applyable from `/rik` in under a minute,
and the wizard must not nag on every login (we'll suppress it if the bars
already look applied).

### 4. Other beta gotchas

- Registering an event the client doesn't know (e.g. `LEARNED_SPELL_IN_TAB`)
  throws and aborts the whole file. Wrap registrations in `pcall`. The Mainline
  name is `LEARNED_SPELL_IN_SKILL_LINE`; fall back to `SPELLS_CHANGED`.
- After 100 Lua errors the client stops reporting them. `/reload` resets.
- `ReloadUI()` is protected; the user has to type `/reload`.
- Sound/texture files added after launch aren't seen until a client restart.
- Macro limits: 120 account + 18 per character, 255 chars each, 16-char names.
- Edit Mode owns the Blizzard frames. We hide them, we don't register with it.
  If the player opens Edit Mode with RikUI on, things will look wrong. We hook
  `EditModeManagerFrame` OnShow and print a warning.

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
    Execute = { icon = 5308, body = "#showtooltip Execute\n/cast [stance:1/3] Execute; [stance:2] Berserker Stance" },
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
works for unknown spells. `level` is the trainer level, shown on the ghost.

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

Bindings go to the native commands (`ACTIONBUTTON1`, `MULTIACTIONBAR1BUTTON1`,
`SHAPESHIFTBUTTON1`, `BONUSACTIONBUTTON1`, `STRAFELEFT`...), not to `CLICK`
bindings on our buttons. Reason: with overlay bars there are three "slot 1"
buttons for a warrior and a key can only go to one command. The native
`ACTIONBUTTON1` resolves the current page in C, so it hits whatever slot the
visible overlay is mirroring. Our buttons show the hotkey text and the pressed
flash by listening for the key themselves. Probe item: confirm native paging
matches our overlay mapping on the beta.

Saved with `SaveBindings(2)` (character-specific) so alts on other accounts
aren't affected until they run the wizard.

### Applying a preset

`RikUI.Setup.Apply(class, role, opts)` where `opts` is the set of checkboxes from
the wizard: `bars`, `binds`, `macros`, `cvars`, `layout`. Order:

1. Macros. `CreateMacro` for each, per-character where possible (18 slots),
   spilling into account macros only if the preset says so. Existing macro with
   the same name gets `EditMacro`'d, not duplicated.
2. Bars. For every slot: if the character knows the spell, `PickupSpell(highestRankID)`,
   `PlaceAction(slot)`, `ClearCursor()`. If not known, leave it empty and let the
   ghost layer draw it. Items by name via `C_Item`/`PickupItem` if in bags.
   Everything out of combat, guarded by `InCombatLockdown()`; if in combat, queue
   and run on `PLAYER_REGEN_ENABLED`.
3. Binds. Clear the keys we're about to use, `SetBinding` each, `SaveBindings(2)`.
4. CVars. `C_CVar.SetCVar` for the list in `cvars.lua`. Each one has a label so
   the wizard can list them.
5. Layout. Positions for our own frames, stored in the profile. Blizzard Edit
   Mode isn't touched.

Everything logs to chat one line per step, and there's a `/rik undo` that
restores the snapshot taken before Apply (bars, binds, macros, cvars).

### Keeping it applied while levelling

- `LEARNED_SPELL_IN_SKILL_LINE` (fallback `SPELLS_CHANGED`): look up the spell
  name in the active preset. If it has a designated slot and that slot is empty
  or holds a lower rank of the same spell, place it. If the slot holds something
  else (the player moved things around), don't touch it, print one line.
- Rank upgrades: same path. Highest known rank wins.
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
| `setup.lua` | Apply / Undo / role guess / level-up placement |
| `bindings.lua` | the global key scheme, clear/apply, hotkey label formatting ("s1", "M4") |
| `macros.lua` | create/edit/find macros, per-character first |
| `bars.lua` | overlay action bars, stance/pet bars, ghost layer, button skin, hide Blizzard bars |
| `unitframes.lua` | player, target, ToT, pet, party, raid; castbars; class colours; threat |
| `auras.lua` | player buffs/debuffs with timers, target debuffs on the target frame |
| `minimap.lua` | square minimap, clock, coords, tracking, zone text, hide Blizzard buttons |
| `chat.lua` | font, timestamps, copy button, URL detection, hide the side buttons |
| `bags.lua` | one-bag view with sort and search |
| `tooltip.lua` | reposition, class colours, item level, spell ID line |
| `wizard.lua` | the first-login flow |
| `options.lua` | `/rik config` panel, hooked into Settings too |
| `importexport.lua` | strings |
| `libs/LibDeflate.lua` | embedded, unchanged |

Hiding Blizzard: at `PLAYER_LOGIN`, reparent `MainMenuBar`, the `MultiBar*`s,
`StanceBar`, `PetActionBar`, `PlayerFrame`, `TargetFrame`, `PetFrame`,
`PartyFrame`, `BuffFrame`, `DebuffFrame`, `MinimapCluster`, `ChatFrame*`
side buttons, `ContainerFrame*`, to a hidden frame and `UnregisterAllEvents` on
the ones that would otherwise re-show themselves. Never in combat. Never on
frames that are also action-bar *logic* holders if we depend on that logic (see
the ActionBarButtonTemplate question in Constraints 2).

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
  auras.lua
  minimap.lua
  chat.lua
  bags.lua
  tooltip.lua
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

0. **Probe.** A throwaway `RikProbe` addon with `/probe` that prints:
   `type(loadstring_untainted)`; whether a visibility state driver toggles a
   frame when I swap stances in combat; whether a `type="action"` button with
   `action=73` fires the right thing; `GetBonusBarOffset()` per stance;
   `issecretvalue()` on `GetActionCooldown`, `IsUsableAction`, `IsActionInRange`,
   `GetActionCount`, `UnitHealth("player")`, `UnitHealth("target")`;
   whether a pre-seeded saved var survives a relog; whether native `ACTIONBUTTON1`
   pages with stance; whether `LEARNED_SPELL_IN_SKILL_LINE` registers. Half a
   day. Every later decision hangs on this output.
1. **Setup engine on the stock UI.** Warrior preset, bindings, macros, cvars,
   level-up placement, `/rik apply`, `/rik undo`. No skinning. Already useful
   on its own and I'll be playing with it during the beta.
2. **Bars.** Overlay bars with stance paging, skin, hotkey labels, ghost slots,
   hide Blizzard bars. This is where the secret-value question on button state
   gets settled.
3. **Unit frames, castbars, auras.**
4. **Minimap, chat, bags, tooltips.**
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
- Raid frames are a lot of work. Might ship v1 with party frames only and let
  Blizzard's CompactRaidFrames handle raids, styled.
- Nameplates. Not in scope for v1; we set the cvars and leave Blizzard's.
- Whether to bother with Blizzard's `ActionBarButtonTemplate` at all or draw
  buttons ourselves. Decided by probe results.

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
