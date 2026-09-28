# Website UI renders

This tool runs RikUI's Lua in [wow-ui-sim](https://github.com/Osso/wow-ui-sim) and captures the resulting GPU output. The fixtures supply a sample character and open the addon's own windows. They do not draw substitute bars, labels or controls.

## Local setup

Keep the simulator outside the addon checkout. Build its `gui,client-wowforever` configuration with Rust and the simulator's documented ICU dependencies. Install Pillow 12.3.0 in an isolated Python environment for capture checks and image comparisons.

Before preparing Blizzard UI files, resolve the current head of Gethe/wow-ui-source's `forever` branch and cross-check its version with the installed `_classic_beta_/WowB.exe`. Refresh the simulator's Forever manifest and community listfile, then run `wow-cli casc sync-blizzard-ui`. Use the installed client's CASC files and the simulator's normal verified cache.

Apply `wow-ui-sim.patch` to a compatible simulator checkout before building (it also adds the nine Elwynn minimap tiles to the simulator's bundled listfile under `data/`; regenerate it with `git diff -- src data`). It loads addon fonts, corrects sRGB vertex colours, removes the simulator's brightness boost, supplies a plain or transparent capture background (`WOW_SIM_PLAIN_BACKGROUND`, `WOW_SIM_TRANSPARENT_BACKGROUND`) and writes lossless WebP. It also adds multiline EditBox sizing and wrapping, updates timer-bound status bars from duration objects, applies inherited text insets to XML and Lua-created EditBoxes, and gives headless screenshots the simulator's own clock so cooldown swipes and countdowns show the current moment instead of time zero. The patch was reviewed against simulator commit `6a1d81b1c5a1f9771a1b1a7aec6c1361753b3d3f`; this is tool provenance, not a Forever build target. The patch is GPL-3.0-only, matching the simulator; it is excluded from RikUI's MIT license.

Use this external directory structure:

- `source/target/debug/wow-sim.exe`: compiled simulator.
- `forever-source/`: clean checkout at the current upstream Forever head.
- `addons/RikUI/`: an unchanged copy of the current addon.
- `AddOns.txt`: enable RikUI and A_RikUIPreview; disable unrelated third-party addons.
- `WTF/Account/RENDER/Preview/Rikui/`: an empty sample account.

Every run resolves the current upstream Forever head, rejects a stale or modified source checkout, and checks its full version against the installed client executable before launching the renderer. An unavailable upstream or a version mismatch stops the run. Each new capture records the client version, source commit, executable hash and fixture seed hash; older captures keep their original provenance.

The runner verifies the addon's source and media (tracked files and untracked files that are not ignored, so a new file counts before its first commit) against the checkout, allowing only line-ending differences in text files. It creates the fixture addon in that isolated directory. It never reads the player's SavedVariables, and every simulator call uses `--no-saved-vars`.

## Capture

```powershell
python tools/site-renders/render.py --sim-root D:/RikUI-local/wow-ui-sim --wow-root "C:/Program Files (x86)/World of Warcraft"
```

Use `--only wizard,options` to select guides, or give individual scenario IDs. Output, logs and a hash manifest go into the checkout's `dist/ui-renders/` directory. Each capture has a 90-second timeout. A scenario error, unexpected Lua error or missing completion marker rejects the capture. The native frame dump supplies checks for visibility, text, dimensions and crop bounds without reading protected values through addon APIs. Pixel checks reject blank output.

A scenario in `scenarios.json` names its `frame`, `crop` and Lua, and may add:

- `fixtures`: calls from `common.lua` that run before the scenario's Lua (`RikRenderSpellbook("ROGUE")`, `RikRenderHUDState()`, `RikRenderCast()`, `RikRenderSwing()`, `RikRenderPlayer(class, level)`, `RikRenderHUDGroup(...)`). Fixtures supply game data the simulator lacks; RikUI still lays out and draws everything.
- `screen`: the simulated screen, default `2048x1152`.
- `world`: `{"plate": name}` composites the capture over a world plate (below). The UI renders alone on a transparent layer, that layer passes the blank-output check on its own, and the plate goes underneath afterwards; world captures are encoded at WebP quality 92, UI-only captures stay lossless.
- `sequence`: one frame per value of a setting. `apply` is Lua with `VALUE` replaced by each value and runs before the scenario's Lua, normally through `RikRenderSetOption(page, key, VALUE)`, which calls the same setter the settings panel uses. `control` (`slider`, `toggle`, `dropdown`), `label`, `labels` and `default` describe the control the website shows. Frames are named `id@value` and each one is reviewed and promoted like a capture; two values that render the same image fail the gate, because that is a finding about the setting.

`seed.lua` is the character fixture, loaded first. Besides the sample character it closes simulator gaps in Blizzard's own aura code: it runs an AuraContainer's private OnLoad, applies the PLAYER, RAID and CANCELABLE filter parts, marks the auras a fixture lists as the player's own, and gives aura data the flags the client sets (a debuff added by `A_Admin.AddDebuff` is harmful, an ordinary buff is not stealable), so Blizzard's nameplate lists route the player's debuffs to the list RikUI hides. It never adds auras or frames of its own.

Aura countdown digits depend on how long the simulator took to load, so a full render changes the aura-bearing captures by a digit or two; compare.py lists them and they need the usual look before promotion.

Review the generated images before promoting them to website assets. Check text, icon identity, bounds, state differences and the relevant reference capture. Do not count a renamed or recropped copy as a different state.

## World plates

The world behind the interface comes from [isometric-wow-sim](D:/Code/isometric-wow-sim), which renders the installed client's terrain, buildings, lighting and realm creatures in the browser. Nothing in that project is changed: `plates.mjs` drives the objects it exposes at runtime (the scene, its fly camera and its realm layer), hides the app's own chrome and nameplates, and screenshots the canvas at 2048x1152.

```powershell
node tools/site-renders/plates.mjs                       # every plate in worlds/plates.json
node tools/site-renders/plates.mjs elwynn-wolf           # one plate
node tools/site-renders/plates.mjs --probe 0 -47 9454    # ground height and the named creatures around a point
```

It needs the app's dev server (`npm run dev` there, port 5173) and the Playwright Chromium the site project installs. A plate is defined by map, hour, a camera position (`x`, `z` and height above the ground) and a point to look at, or an actor to follow. Each capture writes `worlds/<name>.jpg` and `worlds/<name>.json`: the app commit and its uncommitted files, the request, the resolved camera pose, and the named actors in frame with their screen positions, so a fixture can put RikUI's nameplates over a creature that is really there. The realm is a live simulation, so a regenerated plate is not byte-identical; captures record the plate's hash and the gate verifies the plate they were composited over.

## Required gates and review

`python tests/check_project.py` runs the manifest and render-evidence checks. Website builds, browser tests and releases also require `python tools/site-renders/check.py`. CI verifies the reviewed artifacts against every tracked addon source and media file. Running the GPU renderer requires the local game installation; CI does not redistribute the client or substitute hand-drawn images.

Run `python -B -m unittest discover -s tools/site-renders -p 'test_*.py'` for the failure checks. They exercise blank images, missing text, clipped roots, hidden frames, zero-height text, pixel differences and client/source mismatches.

Run `python tools/site-renders/compare.py` to compare new captures with the baseline. It writes a JSON report and pixel-difference PNGs under `dist/ui-renders/`, and exits with a failure status when images changed. Review those differences and captures at full size before promotion. The promotion command requires every scenario's exact reviewed hash:

```powershell
python tools/site-renders/promote.py --reviewed scenario-id=sha256 ...
```

Promotion validates the full set before copying it into `web/ui-renders/`. The website serves these exact images. Mixed render generations, stale fixtures, changed images, duplicate states and missing review records fail the gate. Tests never update baselines. When adding or changing a UI element, add or extend its scenario before reviewing the new output.

Keep browser layout and interaction tests alongside the Lua render checks. [Playwright documents](https://playwright.dev/docs/test-snapshots) that pixel output varies by platform; GPU captures therefore retain their renderer binary and client provenance instead of treating Linux browser screenshots as Windows game-render baselines.

## Capture limits

The simulator executes the addon; it is not the native game client. These images are documentation examples, not evidence of native gameplay or performance. The user's native acceptance remains separate.

Headless wow-ui-sim does not emit `OnSizeChanged`. The fixture delivers those callbacks using each frame's calculated dimensions, so RikUI's existing layout code can size scroll views and controls. It does not replace that layout code.

The reviewed startup has unrelated Gamepad and Forever Settings API gaps. The isolated addon copy also lacks optional generated road data. Keep their diagnostics in capture logs; do not alter Blizzard source or delete addon data to silence them. Any error in a scenario or RikUI's own error list rejects that scenario.

The cast-progress fixture uses the current duration-object API with a manual clock and the add-on option to hide remaining-time text. Native seconds-formatter defaults remain unverified in the simulator. Bag and loot fixtures supply two known current-client item identities; they do not read the player’s inventory.

The simulator's built-in spellbook, spell textures, display counts and cooldown durations belong to another game version, and its pet unit always exists. The combat HUD, cooldown strip and weapon timer scenarios therefore supply a Forever paladin's spells by level 10 from RikUI's own catalogue (`RikRenderSpellbook`), cooldown duration objects on the game clock (`RikRenderCooldowns`), one seal aura, a cast on a manual clock and a swing whose clock is frozen one second in, and they hide the pet frame. `RikRenderGroup` re-parents several top-level frames to one capture root because the simulator renders a single frame's subtree. The addon still resolves spell ranks, strip membership, layout and drawing itself.

The current 140 scenarios cover the wizard, options (including the class area), every unit frame including party and raid test mode, all cast bars, the RikUI menu, profile sharing, the combat HUD with rogue, shaman and druid variants and a scale sequence, the cooldown strip, all weapon timer states, seven nameplate states over the Elwynn wolf plate, player and unit auras, class effects, combo points, totems, every action bar row, column, page and stance state, the personal resource display, mirror timers, loss of control, proc cues, the combat timer and stopwatch, the zone ability button, the damage meter rows, the minimap over the client's own Elwynn tiles, experience and reputation with a compact sequence, durability, unit, item and aura tooltips with a size sequence, the micro menu and bag strip, chat history, input, scrolling, copy, search and resize, chat bubbles, the queue status, framerate and navigation labels, zone, subzone, error and raid-warning text, loot, money and achievement alerts, the objective banner, friend, play-time and voice toasts, bag filters, markers, capacity and merchant controls, and loot coins, rolls and confirmation. Surfaces the simulator cannot show yet, kept as documentation text or drawings: the weapon enchant slot (the enchant reader never populates a slot), the totem dismissal tooltip, the alternate power bar, combat text (the CombatText font object is missing), the extra action button (its icon stays hidden), pet action icons (SetPetActionSlot rejects numeric actions), the damage meter header menus and the minimap tracking menu (MenuUtil menus do not open), own-buff grouping on target aura rows (buffs added by the simulator carry no caster), spell tooltips (no spell tooltip data), the comparison tooltip (never shown; the equipped item is a retail item), the recipe alert (no trade-skill data), the level-up, event and boss banners (the event toast manager lays out 1439 pixels tall with its toast transparent; the boss banner shows only its art), the chat font-size sequence (MessageFrame:SetFont does not resize drawn lines), the settings help tooltip and saved bag searches (neither has a surface of its own). The simulator draws a running cooldown's edge fixed at the top of the icon rather than at the swipe head, and draws |4 plural tokens raw, so a few fixtures supply the resolved text. Full native-window and 3D-model coverage is not claimed.

On 2026-09-27 the installed client and current Forever UI source agreed on 1.60.1.70009, and 4,417 Blizzard UI files were synchronized. Resolve current versions again when refreshing captures.

These development notes are excluded from the website's player guides. Blizzard game artwork remains Blizzard's property; see [the artwork notice](../../web/ASSET-NOTICE.md).
