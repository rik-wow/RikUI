# Popups and game menu

`popups.lua` and `popups-skin.lua` put the flat RikUI look on the frames that
interrupt play: the four static popups (`StaticPopup1` to `4`: confirmations,
name prompts, resurrect offers), the Escape game menu (`GameMenuFrame`) and the
release-spirit button (`GhostFrame`). Disable the `popups` module in
`/rik config` and reload for the stock look.

## What you see

The grey stone dialog border and background go. In their place is the dark
fill with the 1px edge the [panel skin](panels.md) uses. Popup text is in the
RikUI font, the smaller sub text under it. Buttons lose the red art and become
flat dark boxes with a 1px edge, gold text that turns white under the mouse
and grey when disabled, and the shared hover highlight. A popup's edit box is
a flat dark field. The game menu's metal header goes and its title is gold in
the heading size. The release-spirit button is flat with a cropped icon.

Every one of them fades in over 0.15s each time it shows.

## What is written, and what is not

Static popups gate protected actions: deleting an item, binding on equip,
accepting a resurrect. So the rule the panel skin follows is kept to the
letter. No frame is moved, resized, reparented, shown, hidden or given a new
script. The module writes only:

- alpha on Blizzard's art regions. Dialog art lives in a `Border` child frame
  (`DialogBorderTemplate`: nine slices plus `Bg`), so one `SetAlpha(0)` on that
  frame removes all of it; `BG`, the header's `LeftBG`, `RightBG` and
  `CenterBG`, a button's state textures and three-slice pieces, and the edit
  box's `NineSlice` go the same way. Art is faded and never hidden, so
  Blizzard's own `Show` calls on it change nothing.
- fonts on `Text`, `SubText`, the menu's `Header.Text` and the ghost frame's
  text.
- font objects on buttons. A button reapplies its normal, highlight and
  disabled font objects on every state change, so a `SetFont` on the font
  string would not last. Three shared objects (`RikUIPopupFontNormal`,
  `Highlight`, `Disabled`) go in through `SetNormalFontObject` and its
  siblings. A client without `CreateFont` keeps Blizzard's button font.
- new child textures: the fill, the edges, the button backing and highlight.

`OnShow` is post-hooked with `HookScript`. The skin runs once per frame on its
first show, under `pcall`, with the `Border` write first: a client that
refuses it leaves the frame fully stock, prints one `Popups skin <name>` line
and is not retried. All of this is plain region work and runs in combat.

## Game menu buttons

`MainMenuFrameMixin` builds the menu's buttons from a pool each time the menu
is initialised, so they do not exist when the frame is first hooked and can be
replaced later. On every show the module walks
`GameMenuFrame.buttonPool:EnumerateActive()` and skins the buttons it has not
seen, remembered in a weak table.

## Not covered

Dropdown and context menus (the new `Menu` system), the colour picker, the
settings window's own controls, alert toasts, the talking head and the loot
history are left stock. Popup text is user-scaled by Blizzard; if the client
reapplies its font on a text scale change the RikUI font is lost until reload.

## Diagnostics

`/rik debug` prints `Popups hooked=<n> skinned=<n> failed=<n>`.

## Verification

`tests/popups.test.lua` builds fake frames with the 69913 region names. It
proves: nothing skinned before a show; border and background faded, fill, edge
and fade on first show; text fonts; every popup button flat with a highlight;
shared font objects for the three states; the flat edit box; no move, resize,
reparent or script; a second show fading without a second skin; popups skinned
independently; the menu's border, header, gold title and pooled buttons; a
later pool button skinned on the next show and the first only once; the ghost
frame; silence on a clean skin; the debug line; frames missing every optional
region; a failed skin reported once, not retried and not faded; a popup already
showing at login; a first show in combat; a client without `CreateFont`;
missing frames; a disabled module.

The stub cannot show the look or settle the one question that matters: whether
child regions and an `OnShow` hook on a static popup taint its accept path on
this client. Beta checklist:

1. Fully restart the client (two new TOC entries). Press Escape: flat menu,
   gold title, flat buttons; Options, Logout and Exit must still work.
2. Drag an item out of your bags and drop it: the delete popup is flat. Type
   `DELETE` if asked and accept. **The item must be deleted with no "action
   blocked" message.** Do the same with a bind-on-equip item.
3. Die: the release popup and then the flat release-spirit button must work.
4. Leave a party, abandon a quest, and set a hearthstone to see more popups.
   Watch for errors.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_StaticPopup_Game/GameDialog.xml: StaticPopup1-4, the button template, ButtonContainer, ExtraButton, EditBox and BG](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_StaticPopup_Game/GameDialog.xml)
- [Blizzard_SharedXML/Shared/Dialog/DialogTemplates.xml: DialogBorderTemplate and DialogHeaderTemplate](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXML/Shared/Dialog/DialogTemplates.xml)
- [Blizzard_SharedXML/Mainline/Frame/MainMenuFrameTemplates.xml: the menu's Border, Header and three-slice button template](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXML/Mainline/Frame/MainMenuFrameTemplates.xml)
- [Blizzard_SharedXML/Shared/Frame/MainMenuFrameTemplates.lua: buttonPool, Reset and AddButton](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXML/Shared/Frame/MainMenuFrameTemplates.lua)
- [Blizzard_GameMenu/Shared/GameMenuFrame.xml: GameMenuFrame](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_GameMenu/Shared/GameMenuFrame.xml)
- [Blizzard_FrameXML/GhostFrame.xml: the release-spirit button and its text and icon names](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/GhostFrame.xml)
