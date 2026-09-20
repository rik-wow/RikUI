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

## Pages

`wizard-pages.lua` registers six; each only reads and writes the state.

1. Welcome: the detected class, what will be set up, that nothing is applied
   until the last page and that `/rik undo` reverts it.
2. Your role: one card per role in the class preset's `roleOrder`, preselected
   from `setup.GuessRole` (the preset's first role when talents say nothing).
   Under them the main bar that role gets, from `setup.Resolve`: twelve slots
   with catalogue icons and the key under each; a spell whose level is above the
   character's is drawn dim. A class without a preset gets a sentence saying so
   and no cards.
3. Keybinds: the three key tiers from `Bindings.Scheme` drawn as key caps (main,
   Shift, Ctrl), Mouse 4/5 and A/D caps that light up with their two check boxes.
4. Screen layout: one card per whole-screen [layout](layout.md), each with a
   picture drawn by `wizard-preview.lua` from `Layouts.Rect`, the rectangles the
   audit checks, coloured by kind with a legend. The chosen card carries the
   accent edge and its description shows below. "Keep my current positions"
   skips the layout step.
5. Modules and settings: every registered module except the wizard in three
   columns, every entry of the settings catalogue beside them, all from the
   profile and all on for a new character.
6. Summary: five check boxes for the steps and one line per step saying what
   Apply will change (`WizardPages.Summary(state)`): abilities and bar pages for
   the role, macro names, the key tiers with the two choices, how many settings,
   the layout, and the modules that were switched.

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
`allowEmpty` against the real engine. `tests/wizard-pages.test.lua` runs the
six pages against the real Warrior preset, key scheme, settings catalogue and
layouts: page order, role cards and preselection, the bar preview's icons, keys
and dimming, the key caps following their check boxes, layout pictures made of
the layout's scaled rectangles, the module and setting grids, every summary
line, a step switched off, the options Apply hands to setup, and a Priest.

None of it has run in the client. Beta checklist:

1. `/rik setup`: the window fades in centred; walk all six pages with Next and
   Back; check that text fits and nothing overlaps on the modules page.
2. Role page: click each role and watch the bar preview change.
3. Layout page: compare each picture with `/rik layout <name>` afterwards.
4. Apply: the status line shows the step counts, then Close or Reload UI.
5. `/rik undo`, then log in on a fresh character: the wizard opens by itself
   once, Skip keeps it away.
6. Enter combat with the wizard open: it hides and comes back on the same page.
