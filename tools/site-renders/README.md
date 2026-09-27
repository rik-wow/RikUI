# Website UI renders

This tool runs RikUI's Lua in [wow-ui-sim](https://github.com/Osso/wow-ui-sim) and captures the resulting GPU output. The fixtures supply a sample character and open the addon's own windows. They do not draw substitute bars, labels or controls.

## Local setup

Keep the simulator outside the addon checkout. Build its `gui,client-wowforever` configuration with Rust and the simulator's documented ICU dependencies. Install Pillow 12.3.0 in an isolated Python environment for capture checks and image comparisons.

Before preparing Blizzard UI files, resolve the current head of Gethe/wow-ui-source's `forever` branch and cross-check its version with the installed `_classic_beta_/WowB.exe`. Refresh the simulator's Forever manifest and community listfile, then run `wow-cli casc sync-blizzard-ui`. Use the installed client's CASC files and the simulator's normal verified cache.

Apply `wow-ui-sim.patch` to a compatible simulator checkout before building. It loads addon fonts, corrects sRGB vertex colours, removes the simulator's brightness boost, supplies a plain capture background and writes lossless WebP. It also adds multiline EditBox sizing and wrapping, updates timer-bound status bars from duration objects, and applies inherited text insets to XML and Lua-created EditBoxes. The patch was reviewed against simulator commit `6a1d81b1c5a1f9771a1b1a7aec6c1361753b3d3f`; this is tool provenance, not a Forever build target. The patch is GPL-3.0-only, matching the simulator; it is excluded from RikUI's MIT license.

Use this external directory structure:

- `source/target/debug/wow-sim.exe`: compiled simulator.
- `forever-source/`: clean checkout at the current upstream Forever head.
- `addons/RikUI/`: an unchanged copy of the current addon.
- `AddOns.txt`: enable RikUI and A_RikUIPreview; disable unrelated third-party addons.
- `WTF/Account/RENDER/Preview/Rikui/`: an empty sample account.

Every run resolves the current upstream Forever head, rejects a stale or modified source checkout, and checks its full version against the installed client executable before launching the renderer. An unavailable upstream or a version mismatch stops the run. Each new capture records the client version, source commit, executable hash and fixture seed hash; older captures keep their original provenance.

The runner verifies the addon's tracked source and media against the checkout, allowing only line-ending differences in text files. It creates the fixture addon in that isolated directory. It never reads the player's SavedVariables, and every simulator call uses `--no-saved-vars`.

## Capture

```powershell
python tools/site-renders/render.py --sim-root D:/RikUI-local/wow-ui-sim --wow-root "C:/Program Files (x86)/World of Warcraft"
```

Use `--only wizard,options` to select guides, or give individual scenario IDs. Output, logs and a hash manifest go into the checkout's `dist/ui-renders/` directory. Each capture has a 90-second timeout. A scenario error, unexpected Lua error or missing completion marker rejects the capture. The native frame dump supplies checks for visibility, text, dimensions and crop bounds without reading protected values through addon APIs. Pixel checks reject blank output.

Review the generated images before promoting them to website assets. Check text, icon identity, bounds, state differences and the relevant reference capture. Do not count a renamed or recropped copy as a different state.

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

The cast-progress fixture uses the current duration-object API with a manual clock and the add-on option to hide remaining-time text. Native seconds-formatter defaults remain unverified in the simulator. Bag and loot fixtures supply two known current-client item identities; they do not read the player’s inventory. The current 26 scenarios cover the wizard, options, player/target/focus frames, cast bars, bags, the RikUI menu, profile sharing, chat copy/search and loot. Remaining documentation illustrations have not yet been converted to Lua captures. Full native-window and 3D-model coverage is not claimed.

On 2026-09-27 the installed client and current Forever UI source agreed on 1.60.1.70009, and 4,417 Blizzard UI files were synchronized. Resolve current versions again when refreshing captures.

These development notes are excluded from the website's player guides. Blizzard game artwork remains Blizzard's property; see [the artwork notice](../../web/ASSET-NOTICE.md).
