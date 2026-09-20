# Banners

`banners.lua` covers the three banners Blizzard plays in the middle of the
screen: the event toasts (on 69913 this is the level-up display), the boss kill
banner and the objective tracker's top banner. Disable the `banners` module in
`/rik config` and reload for the stock look.

## What you see

The text uses the RikUI typeface at Blizzard's sizes and keeps Blizzard's
colours. An event toast's icon is cropped like the action bars, loses its ring
and gets a one-pixel edge; the two gold bars above and below the toast become
flat one-pixel gold lines, and the soft shadow behind the text stays. The boss
banner and the top banner lose their banner art, so the title stands alone with
its outline, the way [screen text](screentext.md) treats zone names.

Every fade, scale and slide is Blizzard's. RikUI adds no tween here.

## How it works

Event toasts are pooled frames without a global name.
`EventToastManagerFrame:DisplayToast` acquires one, stores it in
`currentDisplayingToast` and calls its `Setup`. A post-hook on that method
writes the typeface to `Title`, `SubTitle`, `Description`, `InstructionalText`
and `RarityValue`, whichever the template has, on every display. The icon edge
is made once per toast and tracked in a weak table, so a pooled toast is not
kept alive. A second post-hook on `SetupGLineAtlas` runs after Blizzard has put
the gold bar atlas back on `GLine` and `GLine2` and replaces it with a flat
texture of height 1. Blizzard's grow animation and colour tint still apply.

`BossBanner` and `ObjectiveTrackerTopBannerFrame` are skinned from an `OnShow`
hook. Their art has its alpha driven by animation groups, so a fade would come
back on the next play. The textures are emptied with `skin.Blank` instead. The
boss banner makes its loot rows while it plays, so a row is skinned from a
post-hook on `BossBanner_ConfigureLootFrame`, the global that fills one: it
gets the typeface and a cropped icon, and the quality ring and the row backing
stay.

The top banner is parented to `UIParent`, so it still plays although the
[quest tracker](questtracker.md) parks `ObjectiveTrackerFrame`.

Nothing is moved, resized, reparented, shown, hidden or given a new script. A
banner that refuses the skin is reported once as `Banners skin <name>` and not
tried again. A banner the client lacks is skipped.

Not covered: `EventToastManagerSideDisplay` (the clickable list of past
level-up toasts) and the scenario and challenge mode toast art, which Forever
is unlikely to fire.

## Diagnostics

`/rik debug` prints `Banners hooked=<n> failed=<n>`.

## Verification

`tests/banners.test.lua` fakes the manager with one pooled toast, the boss
banner with a loot row, and leaves the top banner out. It proves: nothing before
the first display; typeface with size and colour kept; icon cropped, ring faded
and edge one pixel outside; both bars flat at height 1 with the shadow kept; no
tween, point, size or script on the toast; a second display without a second
edge; boss art emptied and not faded; boss strings; a loot row untouched until
Blizzard fills it and skinned after Blizzard's own setup; a missing
banner skipped; the debug line; one failure report; the disabled module. The
suite was seen red before the module existed.

The stub cannot show how it looks. Beta checklist:

1. Fully restart the client (new TOC entry). Gain a level: the level-up text
   should be in the RikUI typeface between two thin gold lines, with Blizzard's
   timing.
2. Learn a spell or unlock something that toasts with an icon: the icon should
   be square-cropped with a thin edge and no ring.
3. Kill a dungeon boss: the boss name should appear without the banner art and
   the loot rows should read cleanly.
4. Watch for "action blocked" messages while a toast is up; the manager frame
   has two method post-hooks.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [EventToastManager.lua: DisplayToast, SetupGLineAtlas, the template table](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/EventToastManager.lua)
- [EventToastManager.xml: toast templates and their keys, GLine, GLine2, BlackBG](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/EventToastManager.xml)
- [BossBannerToast.xml: banner art keys, Title, SubTitle, loot row template](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/BossBannerToast.xml)
- [Blizzard_BonusObjectiveTracker.xml: ObjectiveTrackerTopBannerFrame](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ObjectiveTracker/Blizzard_BonusObjectiveTracker.xml)
