# Banners

Event, boss, objective and side-history banners share a dark card, thin outline, gold accent rail and framed icon shelf. Native title/subtitle sizes and semantic colours remain intact. Disable `banners` in `/rik config` and reload to restore the stock appearance.

The accent fades in over 240ms. Blizzard owns frame entry, exit, duration, queues, dismiss clicks and pooled row acquisition; addon regions inherit those fades. No frame method is replaced or hooked. Animated stock ornaments are blanked. The centre manager's two gold lines are blanked and made transparent, so native atlas resets and scale animations cannot stretch them across the screen. The native soft shadow remains.

Centre toasts use manager and pooled-toast script hooks, with deferred styling after native setup. The September 23 screenshot exposed a card sized to the level-up text alone: centre cards now use a separate noninteractive host anchored eight pixels outside the full manager envelope (418px wide, minimum height 72px in the pinned source). The host is parented to the toast for native fades and pooled visibility, drawn below its text, and ignored by native layout measurement. Native text geometry stays unchanged; side-history cards retain their individual row bounds. Side history observes the published `lastToastFrame` from its visible-only update hook, styling each arriving row once. A hide resets that observation for pooled reuse. Boss loot rows keep native quality colours and gain the common typeface and icon crop.

Tests cover deferred setup, text-sized toasts, manager-bound card geometry, late atlas/show resets, native geometry and click preservation, side rows arriving during animation, reuse, missing frames and disabled/failing modules. Alerts and social toasts exercise the same shared card helper. Native acceptance is provided by the user's standing policy; no agent-observed game-client result is claimed.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [EventToastManager.lua: DisplayToast, SetupGLineAtlas, the template table](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/EventToastManager.lua)
- [EventToastManager.xml: toast templates and their keys, GLine, GLine2, BlackBG](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/EventToastManager.xml)
- [BossBannerToast.xml: banner art keys, Title, SubTitle, loot row template](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/BossBannerToast.xml)
- [Blizzard_BonusObjectiveTracker.xml: ObjectiveTrackerTopBannerFrame](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ObjectiveTracker/Blizzard_BonusObjectiveTracker.xml)
