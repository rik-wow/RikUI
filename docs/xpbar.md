# XP and reputation bar

Readable earned XP rises briefly above the right edge as `+N XP`. Duplicate events, login observations, corrections and unreadable gains do not celebrate. Compact mode, hidden labels and reduced motion suppress the floating text; disabling animations or hiding the row clears it.

Enable **Experience > Show session pace in XP label** to display session XP/hour and approximate minutes to level directly on the bar. It updates once per second, including idle time, after at least one minute and a readable gain. Gathering XP, unavailable clocks and unreadable gaps have explicit labels; reset the session after a gap. Compact mode or disabled progress labels hide the pace and remove its update callback. The preference is per profile; the observed session is shared across profile switches and clears on reload.

The XP tooltip includes observed session XP. After one minute with gains, it adds XP/hour and an approximate time to level at that pace, including idle time. **Experience > Reset session** clears this session and rebases the snapshot; reloading also starts over. Secret or failed reads leave an explicit gap and suppress the rate until reset. These are estimates, not predicted rewards.

Research reviewed 2026-09-24: [Forever leveling feedback](https://www.reddit.com/r/wowforever/comments/1wn45ic/wow_forever_the_good_the_concerns/) and [ForeverXP author feature description](https://www.curseforge.com/wow/addons/foreverxp). This implementation uses RikUI's existing readable gain detector.

The XP bar now has a detailed presentation: an 18px experience row with a level,
percent and remaining-XP label, plus a 12px watched-reputation row. Both use the
RikUI font, flat borders and optional 10% tick marks. Purple is XP, blue is rested
XP, and reputation uses the faction standing color.

Right-click either row to switch between detailed and compact (8px) bars.
Left-click the reputation row opens the native reputation panel outside combat.
The Experience page in /rik config offers compact mode, progress labels,
animations and tick marks. Preferences persist per profile and apply immediately.

## Motion and useful information

Visible fills ease toward new values; first appearances use an immediate value
and fade in. A real readable XP gain flashes once. Duplicate events, non-player
events, XP corrections and unreadable data do not trigger gain flashes. A level
up has its own longer gold highlight. Turning animations off stops current
effects and uses immediate fills.

The experience tooltip shows current/maximum XP, percentage, rested XP and its
percentage of a level, XP remaining, the last readable gain, and an estimate of
how many similar gains remain. The estimate uses the last reward, not an assumed
kill or quest value. It is session-only and intentionally omitted before a known
gain. One-level rollovers are accounted for when the new XP value has reset;
ambiguous multi-level changes are not counted as rewards.

Reputation shows the watched faction, standing and progress. Maximum standing
uses an explicit label and a full bar. Experience disappears at the level cap
or when XP gain is disabled; the watched reputation row can remain alone.

## Architecture and layout

xpbar.lua owns lifecycle, bar sinks, stock-frame visibility and tooltips.
xpbar-details.lua owns readable labels, gain detection, decorations and options.
Secret-bearing client values still flow directly through the existing protected
bar sinks. New comparisons and formatting first require ordinary finite numbers.
A failed/secret read does not become a fake gain or fabricated percentage.

RikUIXPBar stays in the shared xpbar layout group. Detailed mode reserves 32px
for both rows. Default presets raise the action stack to retain the 16px screen
margin, reposition HUD pet/cast frames and the loot anchor, and retain clearance
between the healer grid and tracker. Existing saved positions are preserved;
use /rik move if a custom position needs additional room.

/rik move, /rik scale and the preset selector continue to work. Profile switches
refresh presentation. Stock tracking bars are parked only after our holder is
created outside combat; /rik stockbars show restores them. Disable xpbar and
reload for the native bars.

/rik debug reports holder, XP-row and reputation-row visibility.

## Verification

The suite covers readable and opaque bar values, rested updates, error reporting,
genuine/duplicate/other-unit gains, corrections, detailed and compact geometry,
label/tick switches, reduced motion, level-up effects, both tooltips, level caps,
stock visibility, combat login and disabled modules. All four preset layouts are
audited at 16:9, 16:10 and 21:9.

Native behavior is accepted under the user's standing policy. No agent-observed native test is claimed.

Automated stubs cannot establish actual rendering, protected client behavior or
whether a particular build marks these values secret.

Client contracts were checked against Forever 1.60.1.69913:
[ExpBar](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_StatusTrackingBar/Shared/ExpBar.lua)
and [ReputationBar](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_StatusTrackingBar/Shared/ReputationBar.lua).
