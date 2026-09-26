# Changelog

Versions follow [semantic versioning](https://semver.org/). The tags
`v0.0.1-beta.1` and `v0.0.1-beta.2` from September 2026 were packaging tests
and carry no notes. The BigWigs packager ships this file in the release ZIP
and uses it as the GitHub release text, so add the new version here before
tagging.

## Unreleased

- The locally built quest corpus and road networks now install inside the
  RikUI folder (`generated/`, pulled in by the committed `generated/index.xml`)
  and load with the addon. Only the mesh patches stay as separate
  load-on-demand folders, in 16 MiB packs: about sixteen folders instead of
  the 697 companion addons the previous layout needed. Reinstall both with
  `tools/quest_corpus.py install --rikui ...` and
  `tools/terrain/install_roads.py install --addons ...`, then restart the client.

## 1.0.0

First release, built for the WoW: Forever beta (interface 16001).

- Setup wizard with presets for all nine classes: action bars, macros,
  character keybinds, game settings and frame layout. Every step is optional
  and `/rik undo` restores what the last Apply changed.
- Level-up placement and `/rik resync` keep preset slots current as spells
  and ranks are learned, without touching slots you rearranged.
- A replaced interface: action bars with stance paging, player, target, pet,
  party and raid frames, cast bars, auras, nameplates, a square minimap,
  combined bags with search and favorites, chat with history and copyable
  text, tooltips, loot and roll frames, the micro menu, XP and reputation
  bars, the quest tracker, and a matching skin over the Blizzard windows and
  menus.
- A combat HUD that puts cooldowns, the current resource, the cast bar and
  swing or wand timing in one central stack, following class, form and
  learned abilities.
- Four whole-screen layouts, per-frame unlock and drag with snapping, and a
  UI scale command.
- A quest planner with map and route guidance where its data covers the area.
- Profiles, preset and profile import and export, and bundled community
  presets with attribution.
- A settings backup that survives `/reload` and a full restart on a beta
  client that has been seen not reading saved variables back.
- Release packaging through the BigWigs packager with archive verification
  before and after upload.
