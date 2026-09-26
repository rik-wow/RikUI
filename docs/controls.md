# Window controls

Slider and legacy scrollbar thumbs turn blue under the cursor and gold while dragging, including when the pointer leaves the track. Release and hide restore their idle colour; values and drag handlers remain native.
Disabled thumbs dim and discard stale hover/press state. Scroll-step arrows dim at
unavailable directions and regain contrast when enabled. Disabled controls do not
play hover fades. Slider tracks and thumbs follow the native horizontal or vertical axis.

Keyboard focus brings in a subtle blue field halo over 160ms. Focus loss and hiding clear it; reduced motion displays the same cue immediately.

Push buttons, check boxes, dropdowns and scroll steps now light gold while pressed, then release with a short fade. Hiding or disabling a button clears the feedback. Native click handlers and layout are preserved; reduced motion keeps the pressed cue without the fade.

`src/modules/controls/controls.lua` flattens the controls inside Blizzard's windows: push buttons,
check boxes, edit boxes, sliders, scrollbars and dropdown buttons. The
[panel skin](panels.md) only does a window's chrome; this module does what is
inside it. Disable the `controls` module in `/rik config` and reload for the
stock controls.

## What you see

- Push buttons: a flat dark face with a one-pixel edge, gold text in the RikUI
  font that turns white under the cursor and grey when disabled.
- Check boxes: a small flat box with Blizzard's tick.
- Edit boxes: a flat field in the RikUI font. The edge turns accent blue while
  the box has keyboard focus.
- Sliders: a thin flat track and a flat thumb.
- Scrollbars: no track art and a flat thumb. The old-style scrollbar also gets
  flat `^` and `v` step buttons.
- Dropdown buttons: a flat face with Blizzard's arrow and the RikUI font.

Buttons, check boxes, dropdowns and scrollbar thumbs brighten under the cursor
with a 0.12s fade instead of popping.

## How a control is recognised

A frame does not report the template it was built from, so the module looks at
the object type and the region keys the 69913 templates define:

| Control | Rule |
| --- | --- |
| Push button | `Button` with `Left`, `Middle` and `Right` (`UIPanelButtonTemplate`) |
| Dropdown | `Button` or `DropdownButton` with `Background` and `Arrow` |
| Check box | `CheckButton` without an icon key and at most 32 wide |
| Edit box | any `EditBox` |
| Slider | `Slider` without `ScrollUpButton` |
| Old scrollbar | `Slider` with `ScrollUpButton` |
| Scrollbar | any frame with `Track`, `Back` and `Forward` (`MinimalScrollBar`) |

The push button rule leaves item, spell and tab buttons alone because none of
them has the three slices. Action and spell buttons are `CheckButton`s, which
is why a check box must be small and have no `icon`, `Icon` or `IconTexture`.

## When it runs

`Controls.Walk(frame)` visits a frame and its children eight levels deep. The
panel skin calls it on every show of a skinned window, not only the first,
because windows build controls as tabs and lists fill. A weak table remembers
what is done, so a repeat walk only reads. [Small dialogs](dialogs.md) call the
same walk.

Rows a scroll list creates after the window opened are covered too. When a
walk meets a scroll box list (a frame with `RegisterCallback` and
`ForEachFrame`), it registers once for
`ScrollBoxListMixin.Event.OnAcquiredFrame`, the event Blizzard's own
`ScrollUtil` uses to decorate rows, and walks each row the list hands out.
The row goes through the same walk, so forbidden and protected frames stay
skipped and a control is still skinned once. Registered lists live in a weak
table. A list that refuses the registration is reported once as
`Controls watch` and not asked again. Beta check: open the auction house or
the friends list, scroll far down, and look for stock buttons inside rows; also
watch for "action blocked" in windows with scrolling lists.

## What is written

Region alpha, fonts, font objects, the thumb texture of a slider and new child
regions. Scripts are added with `HookScript`, never set. Nothing is moved,
shown, hidden, resized or reparented. Frames that answer `IsProtected()` or
`IsForbidden()` are skipped, so a walk in combat writes nothing protected.

A control that refuses the skin is reported once as `Controls skin <kind>` and
not tried again.

## Diagnostics

`/rik debug` prints `Controls skinned=<n> failed=<n>`.

## Verification

`tests/controls.test.lua` builds a window holding each control by its keys plus
an item button, an action check button, a secure button and a forbidden one.
It proves each flat piece, the hover fade from a hook, the focus edge, that the
four others stay stock, that nothing is moved or rescripted, that a second walk
skins only what is new, the depth limit, the single failure report, the call
from the panel skin on every show and the disabled module.

The stub cannot show how any of this looks. Beta checklist:

1. Fully restart the client (new TOC entry). Open the merchant, the auction
   house and the settings window: buttons, check boxes, sliders, dropdowns and
   scrollbars should be flat, with readable text.
2. Hover a button and a scrollbar thumb: the highlight should fade in.
3. Click into the auction house search box: the edge should turn blue.
4. Check that spellbook buttons, bag slots, talent buttons and the macro icons
   are untouched.
5. Open a window in combat and watch for "action blocked" messages.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [SecureUIPanelTemplates.xml: UIPanelButtonNoTooltipTemplate's Left, Middle, Right and Text](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXML/SecureUIPanelTemplates.xml)
- [MinimalScrollBar.xml: Track, Thumb, Back and Forward](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXML/Shared/Scroll/MinimalScrollBar.xml)
- [SecureScrollTemplates.xml: UIPanelScrollBarTemplate's step buttons and ThumbTexture](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXML/SecureScrollTemplates.xml)
- [InputBoxTemplates.xml: the edit box border keys](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml)
- [MinimalSlider.xml: the slider track and thumb](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXML/Shared/Slider/MinimalSlider.xml)
- [MenuTemplates.xml: WowStyle1DropdownTemplate's Background, Arrow and Text](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Menu/Mainline/MenuTemplates.xml)
