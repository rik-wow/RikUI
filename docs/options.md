# RikUI settings

Modules now warns **After reload: needs …** when an enabled feature has a disabled direct or indirect requirement in the saved choices. Restoring the provider clears the warning. Disabling a feature still changes only that feature. This helps mix UI components without discovering a missing dependency only after reload. [Modular UI prior art reviewed 2026-09-24](https://www.curseforge.com/wow/addons/fcui-foreverclassicui).

Queued settings and destructive confirmations expire after a profile transition, including switching away and back. A queued profile selection also expires if its destination was deleted and recreated under the same name. Re-select or confirm again to act on the current profile.

Restored profiles now repair unsupported frame/text/tooltip scales, bag columns and capacity thresholds, castbar dimensions, nameplate emphasis, font choices and unit text modes to their defaults before features load. Valid limit values and unknown extension fields survive. This guards malformed data; it does not claim to fix the client's SavedVariables bug. [Settings-loss reports reviewed 2026-09-24](https://us.forums.blizzard.com/en/wow/t/can-we-get-a-response-about-addon-settings-not-saving/2359436).

**Reset frame** restores only the selected frame after confirmation. Both it and **Reset positions** keep the prior arrangement for **Undo layout change**, including the previous chat size. Scale and unrelated position keys are preserved. Recovery uses the same saved one-step history as layout presets; a later preset/reset replaces that history.

General now offers a **Frame to position** picker and Left/Right/Up/Down buttons. Each click moves one screen unit using the same collision and screen bounds as dragging, including at non-default scales. The controls work through existing keyboard navigation and refuse movement during combat or while a frame positions itself. This does not add native controller focus.

Research reviewed 2026-09-24: [Forever interface-editing feedback](https://www.reddit.com/r/wow/comments/1wkyhmn/wow_forever_summary_feedback/). Player requests motivate these controls; their behavior is verified against RikUI’s layout engine.

Protected settings changed during combat keep only the latest value per control. Deferred edits are cancelled if their profile changes or the control becomes unavailable before combat ends.

The shared dropdown renderer accepts both dynamic `values/text` and module-declared `choices/label` entries. This fixes empty quest-size, font and native combat-direction menus. Selection is tested through the rendered popup, including the zero-valued native-size choice.

Switching profiles now reliably requests **Reload UI**, including copied profiles whose module toggles happen to match. Positions apply immediately; reload applies all feature preferences. Returning to the profile loaded at login clears that profile-switch notice. Other changed settings can still require reload. The baseline is captured after backup recovery, and a rejected switch leaves it unchanged.

This closes a code-observed activation gap while addressing the dated settings-reliability feedback below; it does not claim that community reports were caused by this gap.

Modules now explains the actual running state, including disabled dependencies and activation failures. Failed or blocked modules have their feature controls disabled; their enable toggles remain available. Status descriptions refresh when the panel does, and dependency messages name the required feature. Detailed errors stay in Setup and support diagnostics.

Research reviewed 2026-09-24: [Forever players ask for individual classic components](https://www.reddit.com/r/wowforever/comments/1wkd32q/classic_ui_for_wow_forever/). This motivated clearer module choices; status itself comes from RikUI's actual lifecycle records.

The footer surfaces reload/restart backup failures when settings refresh. **Setup and support > Retry settings backups > Save now** retries both tiers out of combat and prints details. An account failure is no longer cleared by a successful character save. Macro failures remain visible until a successful retry; a reverted setting still retries an earlier failed write.

Research reviewed 2026-09-24: [Forever players report settings resets](https://www.reddit.com/r/WowUI/comments/1wkfntp/wow_forever_working_addons_addon/). Reports motivate recovery visibility; they do not establish current client-wide persistence behavior. Backup status reflects observed API writes, not a guarantee of disk durability. User native acceptance applies.

Click **RikUI** beside the minimap, then **Settings**. The same panel remains
available under the game's Options > AddOns > RikUI. If the Settings API is
unavailable it opens as a standalone window.

The nested sidebar groups pages under **Interface**, **Gameplay**, and
**System**. Click a group heading to collapse it. General opens with layout
and scale controls; individual module preferences stay on their own pages.
Modules, Profiles, and Setup and support are separate System pages.

Use **Search settings** to filter pages and controls by title, group, label or live help text. Every word must match, in any order, across those fields; for example, `bags columns`. Punctuation is treated literally.
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

- General: frame scale, layout preset, Move frames and Reset positions.
  Font chooses bundled Noto Sans or the game's locale-native font. Text size
  scales shared labels from 85% to 130% without resizing frames; chat retains
  its own size. Font, text size and Reduce cosmetic motion require a reload.
  Reduced motion removes RikUI fades, flashes and pulses while timers keep running.
  World damage-number fonts require returning to the character list.
- Unit frames: show current/maximum, current only, or hide health and power text.
- Nameplates: target enlargement and non-target opacity.
- Bags and vendors: the movable capacity indicator shows free general and
  specialized space with bags closed; click it to open inventory.
- Tooltips: independent 75–150% scale.
- Castbars: width, height and remaining-time visibility.
- Combat text: native visibility and scrolling direction where supported.
  These are client settings shared across RikUI profiles.
- Move frames closes settings and unlocks the existing drag handles. The
  minimap launcher changes to **Done**; clicking it locks the frames.
- Modules: enable or disable any registered module. Enabling also selects its required modules, including indirect requirements. Missing or cyclic requirements reject the entire change. Disabling changes only that module; dependent features may need it restored. Activation still waits for reload. A single **Reload UI**
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
Changes save automatically. Failed or refused preference changes and button actions report their setting name in chat, then refresh from the actual state. Failed setters do not request a settings save.

## Profiles

Choose an active profile, or enter a name and click Create or Copy. Copy makes
an independent copy of the active profile. Blank and duplicate names cannot
be created. Profile changes queue during combat; only the final selection is applied. Color-picker previews and cancellation belong to the profile and picker session that opened them, so stale callbacks cannot change a new profile or a newer picker.

Delete offers only inactive profiles. Delete and Reset positions first show
an inline confirmation naming the target. Click Confirm to apply or Cancel
to keep the current state; switching targets or hiding the row cancels it.
Characters pointing at a deleted profile
receive defaults when they next load. Use `/rik profileexport` and
`/rik profileimport` to share UI preferences under a new profile name; see
[sharing](sharing.md). Profile creation and deletion save immediately.

**Reset active UI profile** asks for confirmation, preserves an independent `Recovery N` profile, then restores UI defaults. Select that recovery profile to restore your preferences. Reload applies module and appearance changes; character setup is retained. Resets are refused during combat or pending setup operations.

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
