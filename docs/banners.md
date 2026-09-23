# Banners

Event, boss, objective and side-history banners share a dark card, thin outline, gold accent rail and framed icon shelf. Native title/subtitle sizes and semantic colours remain intact. Disable `banners` in `/rik config` and reload to restore the stock appearance.

The accent fades in over 240ms. Blizzard owns frame entry, exit, duration, queues, dismiss clicks and pooled row acquisition; addon regions inherit those fades. No frame method is replaced or hooked. Animated stock ornaments are blanked, and the centre manager's two gold bars become one-pixel lines.

Centre toasts use manager and pooled-toast script hooks, with deferred styling after native setup. Side history observes the published `lastToastFrame` from its visible-only update hook, styling each arriving row once. A hide resets that observation for pooled reuse. Boss loot rows keep native quality colours and gain the common typeface and icon crop.

Tests cover deferred setup, native geometry and click preservation, side rows arriving during animation, reuse, missing frames and disabled/failing modules. Alerts and social toasts exercise the same shared card helper. Native acceptance is provided by the user's standing policy; no agent-observed game-client result is claimed.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [EventToastManager.lua: DisplayToast, SetupGLineAtlas, the template table](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/EventToastManager.lua)
- [EventToastManager.xml: toast templates and their keys, GLine, GLine2, BlackBG](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/EventToastManager.xml)
- [BossBannerToast.xml: banner art keys, Title, SubTitle, loot row template](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/BossBannerToast.xml)
- [Blizzard_BonusObjectiveTracker.xml: ObjectiveTrackerTopBannerFrame](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ObjectiveTracker/Blizzard_BonusObjectiveTracker.xml)
