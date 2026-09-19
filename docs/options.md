# Options panel

`/rik config` opens the RikUI page under Blizzard Options > AddOns. The same
page is registered at login through `Settings.RegisterCanvasLayoutCategory`
and `Settings.RegisterAddOnCategory`; the first-login wizard is not required.
If the client has no Settings API, the panel opens as a standalone window
with a close button instead.

Tabs run across the top: General, one tab per module that declares options
(currently Bars and layout), and Profiles. Controls use the shared font and
textures. Disabled controls are dimmed and ignore input.

Keyboard: Tab or Down moves to the next control, Up or Shift-Tab moves back,
Space or Enter toggles a checkbox, presses a button, opens a dropdown or
focuses a text field, and Left/Right adjusts a slider or cycles a dropdown.
Other keys, including Escape, pass through to the client. Keyboard capture is
never changed during combat because propagation writes are protected there.

## General

- Module toggles for every registered module. They write
  `Profile.modules[name]` and are labelled as needing `/reload`.
- Frame scale slider (0.25 to 3). It calls `Layout.SetScale`; in combat the
  change is queued and applied when combat ends.
- Move frames runs `/rik move` and closes the Settings window so the overlays
  can be dragged. Reset positions runs `/rik move reset`.
- Re-sync runs `/rik resync`. Re-run wizard appears only when a `setup`
  command is registered, so there is no dead button before the wizard exists.

## Bars and layout

Declared by the bars module: gryphon end caps, "Show stock Blizzard bars"
and the button border colour. The colour control opens the client colour
picker and retints every decorated button immediately; the value is saved as
`Profile.borderColor = { r, g, b }`. These controls are disabled while the
bars module is turned off (until reload).

## Profiles

- Active profile: a dropdown of every profile in `RikUIDB.profiles`. Selecting
  one calls `RikUI:SetProfile`. In combat the switch is queued.
- New profile: type a name, then Create (defaults) or Copy (deep copy of the
  active profile). The new profile is selected immediately, or queued in combat.
  Blank and duplicate names keep both buttons disabled.
- Delete: choose any profile other than the active one and press Delete.
  The active profile cannot be deleted. Other characters that pointed at a
  deleted profile receive defaults at their next load.

## Module contract

Any module may set `module.Options = { title, settings }`. Each setting is
`{ type, key, label, get, set }` plus optional fields:

| Field | Meaning |
|---|---|
| `type` | `heading`, `checkbox`, `slider`, `dropdown`, `colour`, `text` or `button` |
| `reload` | label the setting as needing `/reload` and print that after a change |
| `protected` | queue the setter through `Combat.Queue` when in combat |
| `disabled` | function returning true to dim the control |
| `min`, `max`, `step` | slider bounds |
| `values` | dropdown entries `{ { value, text } }` or a function returning them |
| `text`, `action` | button caption and callback |

`set` may return `nil, reason` to print a refusal. `RikUI.Options.Render(parent,
specs)` builds a list, `RefreshList(list)` re-reads every getter and predicate,
and `EnableKeyboard(panel, getRows)` attaches focus handling. Rows and focus
live in `options-widgets.lua`, the control types in `options-controls.lua`
(`RikUI.Options.Types[type] = { create, refresh, activate, adjust }`), and the
pages in `options.lua`. Modules that are not loaded declare nothing, so the
panel never shows dead controls.

## Verification and limits

`tests/options.test.lua` covers each control type, reload labels, disabled
predicates, combat queueing, keyboard focus, page generation from registered
modules, the conditional wizard button, Settings registration and the
standalone fallback, and every profile operation. The stub cannot show that
the beta client renders the canvas, that Blizzard's Settings window forwards
`OnRefresh`, or that `EnableKeyboard` inside the Settings window behaves as
expected; those need a native check:

1. `/rik config` opens Options > AddOns > RikUI with readable tabs and labels.
2. Tab, arrows, Space and Left/Right move and change controls; Escape closes.
3. Toggle gryphons and stock bars, pick a border colour, drag the scale slider,
   then `/reload` and confirm the values persist.
4. Create, copy, switch and delete a profile from the Profiles tab.
5. Repeat a scale change in combat and confirm it applies after combat.
