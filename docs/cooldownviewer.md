# Cooldown viewer

The Essential, Utility, Buff Icon and Buff Bar cooldown viewers keep Blizzard's
layout and settings, with cropped icons, thin edges in the action-bar border
colour, and RikUI numbers. Buff bars use the bundled statusbar texture, a flat
track and the RikUI typeface. Disable `cooldownviewer` in `/rik config` and reload
to restore the stock appearance.

The module is `src/modules/cooldownviewer/cooldownviewer.lua`. It uses the shared
skin helpers and reads the bars' border colour when available; disabling bars
does not disable the viewer skin.

## Native ownership

RikUI changes textures and font strings only. Its weak caches live outside the
Blizzard item tables. It adds no item fields, scripts, attributes or layout
changes and never calls cooldown/aura data APIs or reads the protected aura map.
The statusbar's existing fill texture is changed directly; the bar widget,
duration bindings, values and texture identity remain Blizzard's.

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
and module disablement. Its Blizzard frames reject protected methods and new
fields, and snapshots verify existing fields remain unchanged.

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
