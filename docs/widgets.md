# UI widgets

Native widgets share RikUI typography, cropped/framed icons and flat backing. Status, double-status and capture bars retain their specialized chrome. Other visualization types use a bounded six-level child/region walk: icon-and-text, texture-and-text, spell displays and pooled resource rows receive the same treatment after native setup. Late-created rows are included on subsequent manager updates.

Widgets fade in over 180ms on first display and pooled reuse. Value updates do not replay the entrance; hiding stops it. Native scripts, placement, tooltips, text colours and functional artwork remain intact.

Bar values are never read or rewritten. The pinned native `UIWidgetBaseStatusBarTemplateMixin` already eases via `fillMotionType` and `UpdateBar`; RikUI preserves that smoothing, including spark, text and partition synchronization. Instant state bars and capture zones retain their source-defined immediate behavior. Icon/shape-only graphics without public font strings or named Icon textures remain meaningful native graphics within the flat treatment; there is no claim that every registered visualization occurs on Forever.

Manager events and `DefaultWidgetLayout` trigger styling after setup. No frame or mixin method hooks are installed. Disable `widgets` in `/rik config` and reload for stock visuals.

Tests cover all three specialized bars, generic icon/text and nested spell/resource regions, late rows, entry/reuse/stop behavior, native Setup preservation, combat, failures and disabled modules. Native acceptance is supplied by the user's standing policy.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_UIWidgetTemplateStatusBar.xml and .lua: the Bar keys, Setup and the state glow](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIWidgets/Blizzard_UIWidgetTemplateStatusBar.xml)
- [Blizzard_UIWidgetTemplateDoubleStatusBar.xml: the two status bars and their border pieces](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIWidgets/Blizzard_UIWidgetTemplateDoubleStatusBar.xml)
- [Blizzard_UIWidgetTemplateCaptureBar.xml and .lua: zone textures, frame art, glows and arrows](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIWidgets/Blizzard_UIWidgetTemplateCaptureBar.xml)
- [Native widget base: fillMotionType, UpdateBar and public resource/spell regions](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIWidgets/Blizzard_UIWidgetTemplateBase.lua)
