# Setup wizard

`wizard.lua` is the first-login flow: one window, a page per decision, and one
Apply on the last page. Nothing is changed before that click. It opens by
itself on entering the world for a character that was never set up
(`RikUICharDB.applied == nil` and `wizardDone` not set) and any time on
`/rik setup` or the options panel's "Re-run wizard" button. Disable the
`wizard` module in `/rik config` to stop it opening by itself.

## Window

`RikUIWizard`: 820x540, centred, `DIALOG` strata, flat fill and one-pixel edge,
the page title in gold over a 2px accent rule, "Step n of N" and one dot per
page top right (the current one in the accent colour, pulsing once when it
changes). The footer has Skip setup on the left, a status line in the middle,
Back and Next on the right; Next reads Apply on the last page and Close, or
Reload UI when a module was switched, once setup has finished. The window fades
in, each page fades in when shown, buttons and check boxes fade a highlight in
under the cursor. Escape closes it (`UISpecialFrames`). Nothing in it is a
secure frame.

Combat: opening waits in `core.Combat.Queue`, because Apply could not run
anyway. Entering combat hides the window, prints one line and keeps the page
and every choice; it returns when combat ends.

## Contract

| Function | Purpose |
| --- | --- |
| `Wizard.AddPage({ key, title, build(frame, state), refresh(frame, state) })` | Registers a page; pages show in registration order. `build` runs once, the first time the page is shown; `refresh` on every show |
| `Wizard.Open()`, `Close()`, `Skip()` | Open starts from a fresh state. Skip sets `wizardDone` and says how to come back |
| `Wizard.Go(index)`, `Next()`, `Back()` | Bounded; refused while setup runs |
| `Wizard.NewState()` | `{ class, role, strafe = false, mouse45 = true, keepPositions = false, layoutPreset, modules, cvars, steps }`: every module, setting and step on, the layout the screen has now |
| `Wizard.Options()` | The options for `setup.Apply`: the five step flags, `strafe`, `mouse45`, `cvarSelection` with only the chosen settings, `layoutPreset` (or `layout = false` when positions are kept), `allowEmpty` |
| `Wizard.Apply()` | Writes the module flags to the profile, then calls `setup.Apply(class, role, opts)` with an `onComplete` |

`wizard-controls.lua` holds the wizard's own controls (`RikUI.WizardControls`):
`Button`, a compact `Check` and `CheckGrid` for the long lists, a selectable
`Card` and a `KeyCap`.

Two additions to the setup engine serve the wizard. `opts.onComplete(result)`
is called when Apply ends, applied or failed, because Apply runs through the
combat queue and ends after it returns; a refusal before it starts is still a
return value. `opts.allowEmpty` lets a class without a preset through with
`setup.EmptyPreset(class)`: binds, settings and layout are applied, the bars
and macros steps find nothing, and `RikUICharDB.applied` stays nil so level-up
placement has no preset to look for.

## Verification

`tests/wizard.test.lua` fakes `setup.Apply` and three pages: first-login open
and no reopen, title, step text and dots, Escape, lazy page build, state shared
between pages, bounded Back, Apply on the last page, the exact options handed
to setup, no second Apply while one runs, the finished state and Close, kept
positions, a failed setup, module flags and Reload UI, Skip, `/rik setup`, a
character that was set up, a combat login, combat while open, the fresh state
and the debug line. `tests/layout-presets.test.lua` covers `onComplete` and
`allowEmpty` against the real engine.
