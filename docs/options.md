# RikUI settings

Click **RikUI** beside the minimap, then **Settings**. The same panel remains
available under the game's Options > AddOns > RikUI. If the Settings API is
unavailable it opens as a standalone window.

The nested sidebar groups pages under **Interface**, **Gameplay**, and
**System**. Click a group heading to collapse it. General opens with layout
and scale controls; individual module preferences stay on their own pages.
Modules, Profiles, and Setup and support are separate System pages.

Use **Search settings** to filter pages and controls by title, label or help text.
The clear button or Escape restores all results. Direct links to a page clear
the filter. Unmatched searches explain that no settings match.

Navigation and content scroll independently. Narrow windows stack larger
fields below their labels; checkboxes remain compact. Sliders reserve space
for their values, snap to their declared steps and show compact values; frame
scale uses a percentage. Secondary help text wraps below its control.
Dropdowns use a bounded scrollable popup above the content,
so the final control on a page can still open every choice. The current choice
is marked and scrolled into view; empty lists show a message. Scrollbar thumbs
reflect the visible fraction, with thin blue edge cues when more content exists.

## Motion and focus

The canvas uses the shared short rise/fade entrance, a gold title and fine accent
rule. Section pages and dropdowns fade in. Sidebar, footer and controls use the
same gold hover wash; keyboard and text-entry focus use a blue row fade.
Hidden rows cancel their animations. Standalone close fades briefly and can
be cancelled by reopening; native Settings controls its own hide timing.

## Everyday controls

- General: scale, layout preset, Move frames and Reset positions.
- Move frames closes settings and unlocks the existing drag handles. The
  minimap launcher changes to **Done**; clicking it locks the frames.
- Modules: enable or disable any registered module. A single **Reload UI**
  button appears when saved choices differ from the currently loaded modules.
  Reverting a choice or switching back to the original profile clears it.
  Gold sidebar counts show which pages need a reload; the footer identifies
  the active profile and total pending changes. Reload waits until combat ends.
- Setup and support: setup wizard, preset re-sync, undo and diagnostics.
- Bars and layout: gryphons, stock bars, ghost icons and border colour.
- Gameplay > Quest planner: journey style, session, rewards, advanced goals,
  recovery and timing. The planner's Preferences button opens this page.

Module settings are disabled while that module is off. Protected scale changes
queue during combat; layout and maintenance buttons are disabled during combat.
Changes save automatically.

## Profiles

Choose an active profile, or enter a name and click Create or Copy. Copy makes
an independent copy of the active profile. Blank and duplicate names cannot
be created. Profile changes queue during combat.

Delete offers only inactive profiles. Delete and Reset positions first show
an inline confirmation naming the target. Click Confirm to apply or Cancel
to keep the current state; switching targets or hiding the row cancels it.
Characters pointing at a deleted profile
receive defaults when they next load. Profile import/export is not yet implemented
and has no launcher entry.

## Keyboard

Tab/Down and Shift-Tab/Up move between controls and scroll the focused row into
view. Space/Enter activates it. Left/Right adjusts a slider or cycles a dropdown.
Home/End jump to the first/last enabled matching control; PageUp/PageDown
switch pages. In an open dropdown, Up/Down and Home/End preview choices,
Enter/Space selects, and Escape cancels. Text fields retain normal typing
and caret keys; Tab leaves the editor for the next control.
Other keys pass through to the client. Combat does not change protected keyboard
propagation flags.

## Extension contract

Modules declare `module.Options = { title, group, settings }`. Optional group is
Interface, Gameplay or System; unknown groups fall back to Interface. Each setting
has `type, key, label, get, set`, with optional `disabled, protected, reload, pending, description`.
Types are heading, checkbox, slider, dropdown, colour, text and button. Sliders use
min/max/step and optional format(value); dropdowns use values (a table or function);
buttons use text/action and may supply confirm() returning a target-specific
confirmation message. A changed message cancels an armed confirmation.
A reload setting may supply `pending()` to compare against runtime state.

Declarations and profile operations live in `options.lua`; `options-view.lua`
owns the canvas and sidebar. Shared rows, responsive placement and keyboard focus
live in `options-widgets.lua`; control behavior lives in `options-controls.lua`.
The shared `RikUI.Scroll` helper confines navigation, pages and dropdown content.

## Verification

`tests/options.test.lua` covers controls, profile operations, native Settings
registration, standalone fallback, combat, long pages, narrow and wide canvases,
collapsible navigation, keyboard scrolling, bounded dropdowns, empty-page layout and pending reload
state across profile changes. These are automated model checks. Native behavior
is accepted under the user's standing policy; no agent-observed game-client
result is claimed.
