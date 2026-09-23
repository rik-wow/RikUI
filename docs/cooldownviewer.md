# Cooldown viewer

Click **RikUI** beside the minimap to open the shared [utility shell](shell.md).
Its Tools section contains **Cooldowns: On/Off**, **Move groups/Done**, and
**Tracked spells**. There is no permanent cooldown toolbar on the HUD.
The launcher stays available when cooldowns are off.

- Click **Cooldowns: Off** to turn the native cooldown displays on; click
  **Cooldowns: On** to turn them off. The label reflects the actual setting.
- Click **Move groups**, drag any of the four labeled group handles, then click
  **Done**. Empty or hidden groups get a placeholder so you can arrange them
  before adding spells. RikUI saves each position.
- Click **Tracked spells** to choose spells and buffs in Blizzard's window.
- Close the flyout to clear the HUD. While moving, the minimap launcher reads
  **Done** and can finish placement without reopening the flyout.

During gameplay, the four groups show only their icons or buff bars: no group
panels, borders or titles. Empty groups leave no visible box. Labeled outlines
appear only while moving and disappear on **Done**, the individual lock button,
or combat. Icons retain their action-bar-colour rims with a highlight and accent;
buff bars use RikUI's statusbar texture and typeface.

Controls lock during combat and while native Edit Mode is open. Native
per-group visibility rules and spell availability still apply: an enabled
viewer can be empty or configured to appear only in combat. An unavailable
setting produces a message under the buttons. To restore stock appearance,
disable Cooldown viewer in the game's RikUI settings category and reload.

The module's main file handles discovery and pooled items; `cooldownviewer-style.lua`
owns decoration, `cooldownviewer-layout.lua` owns group placement, and
`cooldownviewer-controls.lua` owns the buttons. They use shared Skin, Motion,
Layout and EditMode helpers.

## Native ownership

Pooled items receive textures and font changes only. Weak caches live outside
Blizzard item tables. RikUI adds no item fields, scripts, attributes or internal
layout changes and never calls cooldown/aura data APIs or reads the protected
aura map. The statusbar's existing fill texture is changed directly; duration
bindings, values and texture identity remain Blizzard's.

Only the four viewer roots move. Outside combat, the native
`BreakFromFrameManager()` operation detaches managed roots, just as native
dragging does. `ClearFrameSnap()` releases any previous native snap target so
hiding that target cannot move the group or rewrite its native saved position.
Saved `SetPointBase`, `ClearAllPointsBase` and `SetScaleBase`
methods attach them to RikUI's Layout holders without changing native saved
layout records. Detachment prevents combat OnShow from returning a group to
the default manager. Only changed anchors/scales are reapplied. Hidden viewers
are positioned too; combat-deferred changes resume when combat ends.

Native Edit Mode temporarily gets its original root scale and anchors back through
`SetScaleBase()` and `ApplySystemAnchor()`; closing it restores RikUI positions. Native layout,
display-size and UI-scale updates also restore holders. Holders are transparent
anchors sized to the native content, without extra title space or a width floor.
The shared Layout overlay supplies temporary move labels and outlines. Hiding
that overlay never hides the native icons or bars.

Only the cooldown-manager mask and decorative icon overlay are removed.
Unrelated masks, dispel borders, range warnings, cooldown flashes, swipe effects
and the bar pip retain their native meaning. Buff-bar names keep their font size
and colour; duration text keeps Blizzard's visibility. Icon edges belong to the
icon's own container, so a buff bar in NameOnly mode hides its edge with its icon.

The exact-build shapes are:

| Viewer | Icon | Numbers / text |
| --- | --- | --- |
| Essential / Utility | `item.Icon` | `item.ChargeCount.Current`, `item.Cooldown:GetCountdownFontString()` |
| Buff Icon | `item.Icon` | `item.Applications.Applications` and cooldown font |
| Buff Bar | `item.Icon.Icon` | `item.Icon.Applications`, `item.Bar.Name`, `item.Bar.Duration` |

## Pool refresh and limits

Discovery runs at login and when `Blizzard_CooldownViewer` loads. Viewer
`OnShow` hooks trigger a scan of the public `itemFramePool:EnumerateActive()`
interface. One 250 ms timer continues while any viewer is shown and stops when
all are hidden. This covers new items, same-count refreshes and pooled reuse
without hooking Blizzard object methods, which caused a recorded client
regression in build 69977. Released pool items are skipped.

A newly acquired item can keep its native appearance until the next scan,
normally within 250 ms. Missing regions are skipped. Secret hierarchy results
are not inspected. A rejected item or pool is skipped for the rest of the
session, with one diagnostic per operation; other viewers continue.

`/rik debug` reports `CooldownViewer viewers=<n> items=<n> failed=<n>`.

## Verification

`tests/cooldownviewer.test.lua` checks all four shapes, startup and late load,
mask/overlay selectivity, text and semantic preservation, icon edge ownership,
combat discovery, hidden timer shutdown, duplicate-show scheduling, new/released/
reacquired pool items, colour refresh, missing/opaque pieces, isolated failures
and module disablement. Its pooled Blizzard frames reject protected methods and
new fields, and snapshots verify existing fields remain unchanged.

`tests/cooldownviewer-controls.test.lua` clicks the actual buttons and Layout
overlays. It covers off-state discoverability, rejected setting writes, external
setting changes, native Settings, four empty move handles, drag persistence and
reload, scale, unchanged scans, native manager resets, combat OnShow, combat
locking, Edit Mode scale/anchor handoff, stale snap release, isolated root
placement failures, missing viewers and module disablement. It also checks that
visible empty viewers have no permanent decoration, move bounds fit native
content, and Done, individual locks and combat remove all placement guides.

The manifest/syntax guard and Lua runner verify source composition and the hook
policy. These are automated model checks. Native/game-client behavior is
accepted under the user's standing policy; no agent-observed client result is
claimed. Source coverage is the pinned 69913 shape, with the existing 69977
method-hook restriction retained.

## Source evidence

Reviewed against Forever 1.60.1.69913, commit
[70ef1b2](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Viewer implementation](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua): pool reset/acquisition, same-count refresh, layout and NameOnly icon visibility.
- [Viewer templates](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.xml): nested icon, count, text and decorative atlas paths.
- [Secure viewer state](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSecure.lua): protected aura map kept outside the skin.
- [Pool API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXMLBase/Pools.lua): public active-frame enumeration.
- [Texture API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleTextureAPIDocumentation.lua) and [statusbar API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua): mask enumeration and direct fill texture access.
- [Edit Mode root methods](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_EditMode/Shared/EditModeSystemTemplates.lua): base geometry methods, native drag detachment and restoring native anchors.
- [Managed frames](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ManagedFrameSystem/Shared/ManagedFrameSystem.lua): manager membership and ignore flag on show.
- [Cooldown settings](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerSettings.lua): native settings window and Edit Mode transitions.
