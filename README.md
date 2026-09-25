# RikUI

**Restart the game after installing or updating RikUI.** A `/reload` won't
pick up new fonts or textures.

RikUI is an interface addon for WoW: Forever. It gives the UI a flat, dark look
and includes an optional setup wizard for your action bars, keybinds and layout.

## Install

1. Download the `RikUI-…-forever.zip` file from
   [Releases](https://github.com/AlrikOlson/wowforever-classicui/releases).
   Use the addon ZIP, not GitHub's “Source code” download.
2. Close the game and extract the `RikUI` folder into your Forever beta
   installation's `Interface/AddOns` folder.
3. Check that the file is at `Interface/AddOns/RikUI/RikUI.toc`.
   There shouldn't be another folder between `RikUI` and the TOC.
4. Start the game and enable RikUI in the AddOns list.

This is built for the Forever beta, currently interface `16001`.

## First login

The setup wizard opens the first time you use RikUI on a character. Pick a
preset, look over the bars and keybinds, and choose which parts to apply. You can
keep your current frame positions or skip setup altogether.

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

## Combat HUD

Cooldowns, your current resource and cast bar sit together above the action bars.
Swing and wand timing share that central stack. Class buffs and target effects sit beside it. The displays follow
your class, learned abilities and form; you don't need to import a separate
WeakAura pack for each character.

This is part of every layout preset. If you're updating an existing profile,
type `/rik hud` to arrange the combat area. It keeps your chat, other windows
and keybinds. `/rik layout undo` puts the old positions back.

Cooldown manager starts on by default. You can turn it off from the RikUI menu,
and it will stay off. The [combat HUD notes](docs/combat-hud.md) cover what's
tracked and where the beta client still limits it.

## What's included

- Action bars, player and target frames, party and raid frames, cast bars,
  auras and nameplates.
- A square minimap, combined bags with search and sorting, and chat with
  timestamps, history and copyable text.
- Matching styles for menus, tooltips, loot, the map and most game windows.
- Cooldown displays, swing timers, experience and reputation bars, and quest
  tracking.
- A quest planner with map and route guidance where the supporting data is
  available. Open it from the minimap menu or with `/rik quests show`.
- Setup presets, profiles, and import/export for sharing them.

You can use the interface without applying the preset bars or keybinds.

## Useful commands

Type `/rik` or `/rik help` for the full list available in your game.

| Command | What it does |
| --- | --- |
| `/rik config` | Open settings. |
| `/rik setup` | Open the setup wizard. |
| `/rik undo` | Undo the most recent setup. |
| `/rik resync` | Update preset spell slots after learning abilities or ranks, keeping unrelated actions in place. |
| `/rik hud` | Arrange the combat HUD above the action bars. |
| `/rik move` | Unlock or lock frames. |
| `/rik move reset` | Restore default frame positions. |
| `/rik scale 0.8` | Set the overall UI scale. |
| `/rik profile` | List saved profiles; add a profile's exact name to select it. |
| `/rik quests show` | Open the quest planner. |
| `/rik import` / `/rik export` | Import or export an action-bar preset. |
| `/rik profileimport` / `/rik profileexport` | Import or export UI preferences. |
| `/rik support` | Open a report you can copy when reporting a problem. |

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

Forever restricts some of the information addons can read, especially during
combat. RikUI uses the game's own displays where needed, which limits how
much some numbers and effects can be customized.

Use RikUI's movement tools for its frames. Blizzard's Edit Mode can't move
the stock frames that RikUI has hidden.

The quest planner doesn't have complete data for every quest, floor or route.
It shows when data is missing. Separate quest and terrain companion addons
aren't included in the RikUI ZIP. See the [quest planner notes](docs/questplanner.md)
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

For bugs, [open an issue](https://github.com/AlrikOlson/wowforever-classicui/issues)
with what happened, what you expected, your client build and a `/rik support`
report. A screenshot helps with layout problems.

Working on the code? See [CONTRIBUTING.md](CONTRIBUTING.md) and the
[architecture guide](docs/architecture.md). The [packaging guide](docs/packaging.md)
covers local builds and releases.

## License

The code, original textures and icons are [MIT licensed](LICENSE).
The bundled Noto Sans font uses the SIL Open Font License 1.1.
See [media licenses](media/LICENSES.md) for sources and notices.
