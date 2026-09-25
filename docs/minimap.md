# Minimap

**Click the coordinates** to put your current map name and position into chat input; you decide when to send. It uses a fresh position in the named map's coordinate system, or a map ID when its name is unavailable. Missing and protected positions are never copied. Hiding coordinates also hides the click target. API reviewed 2026-09-24: [69913 ChatFrameUtil draft insertion](https://raw.githubusercontent.com/Gethe/wow-ui-source/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua).

**Show FPS and world latency** adds a performance readout below the coordinates, opposite day/night. It is off by default, updates once per second while enabled, and stops performance polling when disabled. Missing or unreadable measurements show `--`. Latency is the world connection, not home/chat latency.

Visible minimap controls gain a 100ms gold hover wash. Changed public zone names fade in over 200ms; repeated zone events do not restart it. Native tracking, queue and ping actions remain intact. Motion is regression-tested; native acceptance is supplied by the user's standing policy.

`src/modules/minimap/minimap.lua` keeps Blizzard's `Minimap` (the client draws the map, blips,
pings and tracking) and moves it into a RikUI holder: a square with a
one-pixel border, the zone name above it and the local time and your
coordinates below it. The round border art, the zoom buttons, the native
zone button, the day/night indicator and the instance difficulty flag are
parked through the [shared hide helper](../SDD.md). Disable the `minimap`
module in `/rik config` and reload to get the stock cluster back.

In `/rik config` → Gameplay → Minimap, **Show server time** switches the clock from local time to realm time, marked `ST`. Both modes respect Blizzard's 12/24-hour preference. Missing, secret, or invalid server time shows `--:-- ST`; it never substitutes local time.

Click the zone name above the minimap to open or close the world map. Its hover
hint explains the shortcut. This uses the native map toggle and leaves minimap
ping and tracking clicks intact.

**Show coordinates** on the Minimap options page is saved per profile. Turning
it off clears the text immediately and stops position polling; turning it on
reads your current position immediately.

**Show day/night** displays a separate Day or Night label below the clock. It follows the client's `C_DateAndTime.IsDayTime()` result at creation, world entry, profile application and `DIEL_CYCLE_CHANGED`, with no timer polling or local/server clock inference. Missing, failed, secret or non-boolean data clears the label. The preference is included in profile sharing.

Decision recorded 2026-09-24: keep this optional information because [players report time-zone confusion](https://www.reddit.com/r/wowforever/comments/1wkr8jm/time_zones_at_launch/) and [ask how the world cycle works](https://www.reddit.com/r/wowforever/comments/1wilhcc/one_mega_realm_how_does_daynight_cycle_work/). These community reports do not establish the game's schedule or night-gated spawn rules. The client source's `Camelot/Diel.lua` at the pinned commit below was fetched and checked on 2026-09-24: it initializes with IsDayTime and subscribes to DIEL_CYCLE_CHANGED. RikUI retains that information using text while the round artwork stays parked.

Automated fixtures cover both states, events, no polling, toggles, and degraded API values. Native acceptance is supplied by the user; historical checklists below are reference scenarios only.

## What you see

A 198x198 square map at the top right with RikUI's flat border. The zone name
sits above it in the RikUI font, coloured the way Blizzard colours it: green in
friendly territory, orange in contested, red in hostile or arena zones, blue in
a sanctuary, gold anywhere else. Under the map the left label shows the local
clock (24-hour, or 12-hour when the Blizzard `timeMgrUseMilitaryTime` setting
is off) and the right label shows your position as `x, y` with one decimal.
The labels refresh five times a second and show nothing while the client has
no map position for you, for example inside an instance.

The mouse wheel zooms in and out within the client's zoom levels. Right-click
opens the tracking menu; left-click still pings the way it always did. The
mail indicator sits inside the top-right corner of the square and the queue
status button, when the client has one, in the bottom-left corner. Addon
buttons that attach themselves to `Minimap` come along with it.

## Layout

The holder is `RikUIMinimap`, a plain 200x200 frame registered with the
[shared layout](layout.md) under `minimap`, so `/rik move`, `/rik move reset`
and `/rik scale` apply to it. The default is `TOPRIGHT` of the screen at
`x=-16, y=-16`. `Minimap` is re-parented to the holder, anchored one pixel
inside its top-left corner and sized to 198. The square comes from
`Minimap:SetMaskTexture("Interface\\BUTTONS\\WHITE8X8")`; the quest and
dig-site blob rings get a zero ring scalar so they draw flat.

On this client Blizzard's `Camelot/Skin.lua` re-applies the round atlas mask
every time the `rotateMinimap` setting changes, so `SetMaskTexture` is
post-hooked and any mask other than the square one is answered with the
square one again.

## Hidden and moved frames

Forever is game type `camelot` in the Blizzard TOCs, which loads the Mainline
minimap cluster plus a Camelot skin and the day/night indicator, and skips the
calendar, the addon compartment and the queue status frame. The module parks
these frames with `RikUI.Hide.Frame(frame, false)` whenever they exist:

- `MinimapCluster.BorderTop`, `MinimapCluster.ZoneTextButton`,
  `MinimapCluster.InstanceDifficulty`, `MinimapCluster.DielFrame`
- `MinimapCluster.MinimapContainer.PlayerCoords` (the native coordinates)
- `Minimap.ZoomIn`, `Minimap.ZoomOut`, `MinimapBackdrop` (compass art)
- `GameTimeFrame`, `TimeManagerClockButton` and `MiniMapWorldMapButton` on
  clients that still have them

`MinimapCluster` itself stays where it is, empty. Three frames move into the
holder instead of being hidden: `MinimapCluster.IndicatorFrame` (mail and
crafting orders) top right, `QueueStatusButton` bottom left, and
`MinimapCluster.Tracking` top left at alpha zero with its button ignoring the
mouse. The tracking dropdown anchors its menu to that button, so right-click on
the map opens the menu next to the map without a visible button.

Every parent, anchor and mask write runs inside one `Combat.Queue` closure; at
a combat login nothing is touched until `PLAYER_REGEN_ENABLED`.

## Secret rules

`C_Map.GetBestMapForUnit` and `C_Map.GetPlayerMapPosition` are documented
`SecretArguments = "AllowedWhenUntainted"` and only work for the player and
party members. The reads run under `pcall`; a failure prints one
`Minimap coords` line and leaves the label empty. A secret or non-numeric
coordinate clears the label without printing. The zone name from
`GetMinimapZoneText` and the PvP type from `C_PvP.GetZonePVPInfo` (falling back
to the old `GetZonePVPInfo`) are guarded the same way; a secret name shows
nothing and a secret PvP type falls back to gold.

## Diagnostics

`/rik debug` prints `Minimap holder=<bool> parked=<n> adopted=<n>` and the
secrecy of `C_Map.GetBestMapForUnit("player")` and `GetZonePVPInfo()`.

## Verification

`tests/minimap.test.lua` runs against `tests/minimap_stub.lua`, a fake of the
69913 cluster (BorderTop, zone text button, tracking dropdown with an
`OpenMenu` recorder, mail indicator, day/night frame, instance difficulty,
the container with the native coordinates and a `Minimap` recording zoom,
mask, wheel and ping calls). It proves: the holder and its layout defaults;
the map re-parented, sized and square-masked, and re-squared after a
Skin.lua-style round reset; the eight art frames parked and the cluster and
mail indicator left visible; the mail indicator, queue button and tracking
frame moved into the holder; zone name and colour at login and on the three
zone events, an unknown PvP type and a secret name; clock and coordinate
text, throttling, a missing position, a secret coordinate and a failing read
reported once; the 12-hour clock; wheel zoom within both limits; right-click
opening the menu without a ping and left-click still pinging; the debug line;
a combat login queueing every write until regen; a missing tracking frame
printing once; an absent queue button; a disabled module leaving the cluster,
mask, hooks and click handler untouched.

The stub cannot show native rendering of the square mask, where the menu
appears, or whether the day/night indicator matters to you. Beta checklist on
the Warrior:

1. Reload: the map should be a square at the top right with the zone name
   above and the clock and coordinates below; no round border, no zoom
   buttons, no day/night ring. Run `/rik debug` and confirm
   `Minimap holder=true parked=8 adopted=3` (parked may be lower if a frame
   is missing) and no `Minimap ...` error line.
2. Scroll the wheel over the map to zoom both ways. Right-click the map: the
   tracking menu should open next to it. Left-click: a ping.
3. Walk across a zone border and into a contested zone: the name and colour
   should change. Enter an instance: the coordinates should go blank.
4. Get mail: the envelope should appear inside the top-right corner of the
   square. `/rik move`: drag the Minimap box, lock, reload. Disable the
   module in `/rik config`, reload, and confirm the round cluster returns.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_Minimap.toc: camelot loads the Mainline files plus Camelot/Skin.lua and Diel.lua, no GameTime or AddonCompartment](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Minimap/Blizzard_Minimap.toc)
- [Minimap.xml: the cluster hierarchy, parent keys and global names](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Minimap/Mainline/Minimap.xml)
- [Minimap.lua: Minimap_Update colours, the zoom buttons, MinimapPlayerCoordsMixin and the cluster events](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Minimap/Mainline/Minimap.lua)
- [Camelot/Skin.lua: the round mask re-applied on rotateMinimap](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Minimap/Camelot/Skin.lua)
- [Camelot/Diel.lua: the day/night indicator frame](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Minimap/Camelot/Diel.lua)
- [DropdownButtonMixin:OpenMenu](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Menu/DropdownButton.lua)
- [C_Map.GetBestMapForUnit and GetPlayerMapPosition secret rules](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua)
