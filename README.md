# RikUI

Use `/rik config` to customize appearance, readability, modules and layout. Setup Studio is temporarily hidden while its workflow is reconsidered; its implementation and saved setups remain preserved.


**Restart the game after installing or updating RikUI.** A `/reload` won't
pick up new fonts or textures.

RikUI is an interface addon for WoW: Forever. It gives the UI a flat, dark look
and includes an optional setup wizard for your action bars, keybinds and layout.

## Install

RikUI is in beta. Expect rough edges, and
[report what you find](https://github.com/rik-wow/RikUI/issues).

Use [Windows setup](https://rikwow.com/install) for quest guidance and navigation.
Setup obtains quest information from its publisher, reads your current Forever
client and prepares the supported guide and routes on your computer. Its tools
are included. It checks current compatibility, preserves settings and backups,
and registers daily update checks.

The manual addon ZIP contains the interface. Use Windows setup to prepare the
quest guide and navigation; an installed QuestieDB ZIP does not replace setup.

1. Download the installable RikUI ZIP from the
   [releases page](https://github.com/rik-wow/RikUI/releases). It is marked as
   a pre-release. You can also build a ZIP yourself with the
   [packaging guide](docs/packaging.md).
   GitHub's “Source code” download is not an installable addon ZIP.
2. Close the game and extract the `RikUI` folder into your Forever beta
   installation's `Interface/AddOns` folder.
3. Check that the file is at `Interface/AddOns/RikUI/RikUI.toc`.
   There shouldn't be another folder between `RikUI` and the TOC.
4. Start the game and enable RikUI in the AddOns list.

UI compatibility reviewed with WoW: Forever beta **1.60.1.70205**, interface `16001`,
on 2026-10-03 against the current UI source, installed client and reviewed Lua
renders. This records the build reviewed; future client updates are checked again.
Quest and road datasets require separate current-build validation; unsupported
builds remain unverified.
What changed in each version is in [CHANGELOG.md](CHANGELOG.md).

### Native Windows installer

Download the public Windows installer from [rikwow.com/install](https://rikwow.com/install).
Choose your current Forever game and **Prepare and install**. Setup displays
progress, supports pause and resume, verifies the prepared files, and retains a
backup before installation. The [installation guide](docs/player/installation.md)
explains requirements, supported regions, updates and recovery.

The public executable includes the interface, preparation tools and notices.
Quest information and navigation are prepared locally. See the
[installer documentation](installer/README.md) for packaging details.

## First login

Open `/rik config` to choose features, themes and readability. Under **Bars and layout**, select one bar and adjust its rows, button size and spacing. See the canonical [installation](docs/player/installation.md) and [settings](docs/player/options.md) guides.

Character setup opens once for each character, including alts. **Keep my setup**
is the default three-step route. **Set up character actions** adds visual ability
and role previews; changing bindings needs a separate selection. Positions and
account settings are kept unless chosen explicitly. After finishing, an optional
tutorial uses the actual player, action-bar and chat movers. See the canonical
[character setup guide](docs/player/wizard.md).

Nothing in the wizard is applied until you click **Apply**. Setup can replace
actions in the preset's slots, create macros, change character keybinds, apply
selected game settings and move frames. Turn off any steps you don't want
on the summary page.

Changed your mind? Use `/rik undo` to restore the last setup's bars, macros,
bindings, game settings and frame positions. Only the most recent setup is
saved for undo. Module on/off choices are managed separately in settings.

To come back later, type `/rik setup`.

## Using it

Click **RikUI** beside the minimap for settings and tools, or type
`/rik config`. It's also listed under **Options > AddOns > RikUI**.
You can turn individual modules on or off, adjust their appearance, and save
different profiles. Some changes need a UI reload; settings will tell you.

To move things, type `/rik move`, drag the frames, then type it again to lock
them. Frames snap to each other; hold Shift while dragging to move freely.
You can also hold the frame-lock key and unlock just one frame. Until you
assign that key in **Key Bindings > RikUI**, use Ctrl+Alt+Shift.

`/rik scale 0.8` makes the UI smaller. `/rik scale 1` returns it to normal.
Moving and scaling need to be done out of combat.

## Gear goals

Open **Gear goals** above the character window, in RikUI’s Tools menu, or with `/rik gear`. Choose an equipment slot, filter quest or dungeon sources, compare live stat tradeoffs, and pin up to eight goals per character. Pursuit feeds the existing quest planner without replacing your personal quest preferences. The optional compact tracker is movable through the normal RikUI layout controls.

Public source browsing requires an installed QuestieDB contract-3 provider with Forever data; private current-client compiled catalogs are also supported. See the [Gear goals guide](docs/player/gear-goals.md). Source relationships are maintained references; verify rewards and drops in game. Effects, set bonuses, weapon damage and class priorities require the item tooltip. No gear is equipped and no reward is selected automatically. See [data authority and coverage](docs/gear-goals-data.md).

## Combat HUD

Cooldowns, your current resource and cast bar sit together above the action bars.
Swing and wand timing share that central stack. Class buffs and target effects sit beside it. The displays follow
your class, learned abilities and form; you don't need to import a separate
WeakAura pack for each character.

The cooldown strip is RikUI's own. It shows the spells the game's cooldown
manager lists for your class, in the order you set in its **Tracked spells**
window, followed by RikUI's own list of learned class abilities, all in one
place. Blizzard's cooldown viewer frames stay hidden while the Cooldowns module
is on; turn the module off under Settings > Modules to get them back.

This is part of every layout preset. If you're updating an existing profile,
type `/rik hud` to arrange the combat area. It keeps your chat, other windows
and keybinds. `/rik layout undo` puts the old positions back. The
[combat HUD notes](docs/combat-hud.md) and [cooldown notes](docs/cooldowns.md)
cover what's tracked and where the beta client still limits it.

## What's included

- Action bars, player and target frames, party and raid frames, cast bars,
  auras and nameplates.
- A square minimap, combined bags with search and sorting, and chat with
  timestamps, history and copyable text.
- Matching styles for menus, tooltips, loot, the map and most game windows.
- A [custom auction house](docs/auction-house.md) with wider search and result
  tables, separate selling and comparison areas, and the game's auction backend.
- Cooldown displays, swing timers, experience and reputation bars, and quest
  tracking.
- A quest planner with map and route guidance where the supporting data is
  available. Open it from the minimap menu or with `/rik quests show`.
- Setup presets, profiles, and import/export for sharing them.

You can use the interface without applying the preset bars or keybinds.

## Commands

Type `/rik` or `/rik help` in game for the same list. Most people only need
the first few; the rest are there when something needs a closer look.

Setup and presets:

| Command | What it does |
| --- | --- |
| `/rik setup` | Open the setup wizard. |
| `/rik apply [role]` | Apply your class preset without the wizard, for a role if you name one. |
| `/rik undo` | Restore the bars, macros, bindings, game settings and frame positions from before the last Apply. |
| `/rik resync` | Fill empty preset spell and macro slots and upgrade older ranks, keeping unrelated actions in place. |
| `/rik role` | Show the role RikUI reads from your talents. |
| `/rik binds` | Apply the character keybind scheme on its own. |
| `/rik preset validate` | Check the bundled, community and imported presets. |
| `/rik ghosts on\|off` | Preview the preset's empty slots on the bars. |

Layout and frames:

| Command | What it does |
| --- | --- |
| `/rik move [reset]` | Unlock or lock every frame, or put them back where the layout has them. |
| `/rik scale <0.25-3>` | Scale every RikUI frame. |
| `/rik layout [list\|undo\|<name>]` | Show the arrangement state, list the layouts, apply one, or undo the last apply. |
| `/rik hud` | Arrange the combat HUD, keeping your other positions and settings. |
| `/rik chat lock\|unlock\|reset` | Lock, unlock or reset the main chat window. |
| `/rik gryphons on\|off` | Show or hide the main bar's end caps. |
| `/rik stockbars show\|hide\|status` | Show, hide or report Blizzard's bars, stance and pet bars, bag and menu buttons and XP bar. |

Settings and profiles:

| Command | What it does |
| --- | --- |
| `/rik config` | Open settings. |
| `/rik profile [exact name]` | List saved profiles, or select one by name. |
| `/rik module [name [status\|on\|off]]` | List modules, or change which ones load at the next reload. |
| `/rik export [role]` | Copy an action-bar preset to share. |
| `/rik import` | Import a shared preset. |
| `/rik profileexport` | Copy your UI preferences to share. |
| `/rik profileimport` | Import shared UI preferences. |

Everyday tools:

| Command | What it does |
| --- | --- |
| `/rik gear` | Compare equipment sources and manage per-character gear goals. |
| `/rik quests show` | Open the quest planner. Also `pin`, `skip`, `avoid`, `pause`, `map` and `export`. |
| `/rik bagsearch save\|use\|delete <name> [query]` | Save, use, delete or list named bag searches. |
| `/rik favorite <item link or ID>` | Mark an item as a favorite so bulk junk selling leaves it alone. |
| `/rik stopwatch start\|pause\|reset\|show\|hide` | A session stopwatch. |
| `/rik party test` | Fill the party frames with copies of you to check the layout. Run it again to leave. |
| `/rik raid test` | The same for the forty raid frames. |

Troubleshooting:

| Command | What it does |
| --- | --- |
| `/rik help` | List the commands available in your game. |
| `/rik support` | Open a report you can copy when reporting a problem. |
| `/rik errors [clear]` | Show the errors RikUI caught this session. |
| `/rik blocked [clear]` | Show the actions the game blocked RikUI from taking. |
| `/rik store` | Report the settings backup that survives reloads and restarts. |
| `/rik debug` | Report which values the game hides from each module. |
| `/rik bardebug <slot>` | Pick an action slot for `/rik debug` to inspect. |

## Preset keybinds

These are the keys offered by setup, in slot order. Installing RikUI alone
doesn't change your bindings.

| Buttons | Keys |
| --- | --- |
| Main bar, 1–11 | 1, 2, 3, 4, 5, Q, E, R, F, T, G |
| Second bar, 1–12 | Shift+1–5, Shift+Q, Shift+E, Shift+R, Shift+F, Mouse 4, Mouse 5, Shift+T |
| Third bar, 1–12 | Ctrl+1–5, Ctrl+F, Ctrl+T, Ctrl+G, Ctrl+Z, Ctrl+X, Ctrl+C, Ctrl+V |
| Stance buttons, 1–3 | Ctrl+Q, Ctrl+E, Ctrl+R |
| Pet buttons, 1–3 | Shift+G, Ctrl+B, Ctrl+N |

The scheme doesn't assign a key to main-bar slot 12. The wizard also lets you
choose whether A/D turn or strafe. If you turn off Mouse 4/5, those two bar
buttons use Shift+G and Ctrl+G instead, leaving the first pet button and
third-bar slot 8 without a scheme binding.

## A few beta limitations

These were checked in game on beta build 69913 in September 2026. A newer
build may loosen some of them.

**Hidden values.** The client keeps some numbers away from addons: your
health and power, the target's health, auras, and in combat the cooldown and
count on each action button. RikUI feeds those into the game's own display
objects, so it can't show them as text or reformat them, and aura rows are
laid out by the game rather than by RikUI.

**Saved settings.** The beta client has been seen writing addon saved
variables at logout but not reading them back at the next login. RikUI keeps
its own backup so your settings survive anyway: CVars that last through a
`/reload`, and up to twelve account macros named `RikUI data N` that last
through a full restart. Leave those macros alone. Deleting or editing one is
noticed and the backup is skipped rather than half restored. `/rik store`
shows whether the backup is working. The last setup's undo snapshot and the
chat history are not backed up.

**Party and raid frames** are fixed slots, four and forty, in unit order
rather than by subgroup. The secure code that regroups frames during combat
doesn't run on the beta.

**Edit Mode.** RikUI hides Blizzard's frames rather than registering them
with Edit Mode, so Edit Mode can't move them; use `/rik move`. If you open
Edit Mode anyway, its changes to the chat window, minimap and damage meter
are put back to RikUI's values when it closes.

**Lua errors.** After 100 errors the client stops reporting them until you
`/reload`. `/rik errors` keeps RikUI's own list of what it caught.

The quest planner doesn't have complete data for every quest, floor or route.
It shows when data is missing. The generated quest corpus and road networks
aren't in the RikUI ZIP (they're built locally from QuestieDB and client
files). Setup installs the quest guide under `RikUI/generated/` and supported
navigation in separate `RikUIQuestRoads_W*_P*` addon folders, loaded only when
needed. Restart the game fully after installation. See the
[quest planner notes](docs/questplanner.md) and [corpus notes](docs/forever-corpus.md)
for coverage details.

## Sharing and contributing

Preset exports share the preset definition, not every edit you've made to
your live action bars. Profile exports share UI preferences; they don't copy
your character's bars or bindings. The [sharing guide](docs/sharing.md) explains
both.

If you want to contribute a preset, start with the
[community preset guide](presets/community/README.md), run
`/rik preset validate`, and send a pull request with your preset and its TOC
entry.

For bugs, [open an issue](https://github.com/rik-wow/RikUI/issues)
with what happened, what you expected, your client build and a `/rik support`
report. A screenshot helps with layout problems.

Working on the code? See [CONTRIBUTING.md](CONTRIBUTING.md) and the
[architecture guide](docs/architecture.md). The [packaging guide](docs/packaging.md)
covers local builds and releases.

## Project infrastructure

Visit [rikwow.com](https://rikwow.com/) for the project home. See the
[Cloudflare architecture](docs/cloudflare.md) and the
[independent quest provider build](docs/upstream-provider.md) for development status.

## License

The code, original textures and icons are [MIT licensed](LICENSE).
The bundled Noto Sans font uses the SIL Open Font License 1.1.
See [media licenses](media/LICENSES.md) for sources and notices.
