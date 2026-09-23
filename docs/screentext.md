# Screen text

Zone and subzone notices keep native typography sizes and colours, with a 128px gold underline that enters over 200ms, holds briefly and fades out. Repeated zone entrances reuse the same accent. Raid warning strings receive the same treatment per native message order, including boss messages routed through that public pool. Native text growth, timing, eviction and placement remain intact.

`UIErrorsFrame` retains native per-message fading: two seconds visible followed by a 350ms fade. Overlapping errors never fade as one frame. Dedicated zone/error font objects and auto-follow text use the outlined RikUI typeface; the shared `GameFontNormalHuge` stays untouched.

Public pooled `RaidBossEmoteFrame` variants are handled when present. Private engine boss-emote regions are not exposed and remain native. Engine damage numbers similarly expose `DAMAGE_TEXT_FONT`, not animatable Lua regions; the combattext module changes their typeface only. Blizzard's scrolling combat-text font is supported separately.

Disable `screentext` in `/rik config` and reload to restore stock styling. Tests cover pooled reuse, accent replay, native frame/script preservation, error fade settings, combat login, refused fonts and missing/disabled systems. Native acceptance comes from the user's standing policy, with no agent-observed game result claimed.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_FrameXML/Mainline/ZoneText.xml: the zone strings and the font objects they inherit](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/Mainline/ZoneText.xml)
- [Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.xml: the message frame on ErrorFont](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.xml)
- [Blizzard_RaidWarning/RaidWarning.lua: the font string pool on GameFontNormalHuge and AcquireOrEvictSlot](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_RaidWarning/RaidWarning.lua)
