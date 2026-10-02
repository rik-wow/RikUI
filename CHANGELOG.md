# Changelog


Versions follow [semantic versioning](https://semver.org/). The tags
`v0.0.1-beta.1` and `v0.0.1-beta.2` from September 2026 were packaging tests
and carry no notes. A version with `beta` in its name is a prerelease. The BigWigs packager ships this file in the release ZIP
and uses it as the GitHub release text, so add the new version here before
tagging.

## Unreleased

## 1.0.0-beta.3

2026-10-02. UI compatibility reviewed with WoW: Forever beta **1.60.1.70170**
(interface 16001), using the current UI source, installed client and authentic
Lua-rendered examples. The build number records reviewed inputs.

- Keep Classic and Healer combat frames in their preset positions on short screens. Healer's party and raid grid now clears the central combat column; supporting windows fit around the combat frames.

- Adaptive nameplate labels give Forever's long names and surnames more room above compact health bars. Settings > Nameplates offers minimum and maximum label widths and a fixed-width toggle. Labels shrink when a plate is reused; protected text measurements keep the fixed layout.

- Scope visual verification to each capture's relevant inputs. Navigation changes no longer require a full image rebuild; unchanged captures retain their reviewed client and renderer provenance.

The public ZIP contains the addon without quest and road datasets. Existing
locally installed data and settings are preserved. This release does not refresh
navigation dataset admission for the current client; unsupported data remains
explicitly unverified. The Windows installer is not part of this release.

## 1.0.0-beta.2

2026-09-29. Compatible with WoW: Forever beta **1.60.1.70124** (interface
16001), verified against the current Blizzard UI source and installed client.

- Admit the current build to the supported quest subset and the locally installed
  road network. Its 6,605 QuestV2 records, 14,291 extracted navigation assets and
  ten geometry/travel DB2 tables are unchanged from the previous reviewed inputs.
  Historical data provenance is preserved; unknown future builds remain unverified.
- Refresh and review the Lua UI captures using the current client inputs; run the
  addon, render and packaging checks before publication.

The public ZIP still contains the addon without quest and road datasets; their
public distribution remains pending [licensing review](docs/corpus-licensing.md).
No gameplay regression was reported for this update.

## 1.0.0-beta.1

2026-09-28. The first public build: a beta for the WoW: Forever beta (interface
16001, checked against client 1.60.1.70009). It passes the project's automated
checks, which do not replace play testing. Expect rough edges and
[report them on GitHub](https://github.com/rik-wow/RikUI/issues).

The ZIP holds the addon. The quest planner's quest and road data are not in it:
their public distribution waits for a licensing review, so the planner shows
guidance only where that data is installed locally.

What the addon includes is listed under "In this release" at the end.

### Changes since the packaging tests

- Centered and HUD layouts keep the combat frames in place on small screens. At the default UI scale on 1366x768, 1280x800 and ultrawide 768-high screens, the layout used to move the player frame, and on some classes the target, away from their places because the raid grid's room overlapped them. Now the cooldown column, player, target, focus, pet and their cast bars stay where the layout puts them. On those screens the party and raid frames sit at the top left margin, the target of target sits above the target where it would reach the minimap, and the HUD's player and target stand closer together on 1280x800. Smaller frames that still do not fit (breath bar, durability, combat timer, stopwatch, debuffs, quest timers) move to the nearest free place. Re-apply the layout with `/rik layout centered` or `/rik layout hud` to get the new places; `/rik layout undo` reverts it.

- Quest route patches take less disk space: 29.7 MB for the Eastern Kingdoms and 39.0 MB for Kalimdor, down from 112.9 MB and 145.4 MB, in five folders instead of sixteen. The geometry is the same, cell for cell. Reinstall them with `tools/terrain/install_roads.py install --addons ...` and restart the client; packs in the older format still load.

- Added a Class area to the settings, between Interface and Gameplay, with a class chooser on every page so any class can be set up before you log over to it. Overview holds the class display switches and the class-only options (combo points, totems, form mana with its Cat and Bear option); Cooldown strip and Class effects let you add, remove and reorder the spells in the strip's class list and the three effect groups from RikUI's catalogue, per class, saved in the profile, with a reset to RikUI's lists. The separate Druid mana page is gone.

- Tightened the combat HUD. The player cast bar and the weapon timers now take the combat column's width, so the strip, resource bar, cast bar and swing bars line up and the class effect rows sit beside them. The unit frames now sit directly above the target cast bar and only above the supporting rows your class uses, instead of leaving an empty band reserved for combo points, totems and form mana on every class.

- Checked marks are a real check glyph. The old mark texture was a hollow square, so enabled toggles, chosen dropdown entries, completed wizard steps, native check buttons, menu checks and finished quest objectives all looked unticked. The setup wizard's check boxes use the same glyph. Active stance and pet buttons keep their square outline.

- Cast bars now ask the game's seconds formatter for the one-letter unit ("1.5 s"), so the remaining time no longer gets clipped in the time field. Aura cells in the cooldown strip draw their countdown in RikUI's font at the same size as the cooldown cells.

- Added a coordinated visual polish pass across ten areas: layered window chrome, inset utility and quest controls, clearer scrollbar grips, settings cards, utility sections, a recessed bag grid, compact quest guidance, separate clock readouts, stronger progress milestones, and cooldown icon/count badges. Existing layouts and interactions remain in place.

- Individual auction listings now show an Item / enchantment column with each listing’s exact linked name and random suffix. Names wrap, retain quality colors and clear on recycled rows; missing client details are explicit. Native bidding, buying and tooltips keep their original auction data.

- Removed the fade-in from native tooltips. Auction rows periodically hide and rebuild their tooltip while hovered; replaying the fade on each rebuild caused persistent flickering even with a stable layout.

- Fixed auction tooltip flicker from repeated presentation refreshes. Stable control anchors stay attached, native forms are laid out once by the skin, and pooled-row shows no longer queue a whole-window refresh.

- Rebuilt the auction house layout with top navigation, a wide search bar, category sidebar, larger result tables, separate selling and comparison areas, and clearer auction/bid management. Dark cards, selection rails and readable status messages follow the native controls; search, prices, transactions and confirmations keep the game's existing backend.

- Fixed dark NPC quest text when accepting or completing quests. Description, objectives, reward and turn-in prose now use light ink after native updates, including the turn-in progress page.

- Collection and choice interiors now use warm section bands for direct and nested headings, with dark pagination badges. Hidden and late-created headings refresh cleanly; models, item names and native selection remain intact.

- Loss-of-control alerts now separate the ability name, countdown and icon with dark text backing and an inset icon compartment. A steady red side rail remains visible with reduced motion while native timing and fades remain in control.

- Status and double-status widgets now give bar and heading labels dark contrast backing above colored fills. Empty or hidden labels clear their backing, while native progress, colors and sparks remain unchanged.

- Alert, banner and social notification cards now have inset top highlights and framed icon compartments. Reused alerts refresh their typeface and recover dark text restored by native setup.

- Quest titles, description/objective headings and reward headers now use warm inset section bands with fine rules. They follow native wrapping and clear when hidden; quest prose sizing stays configurable.

- Calendar days now have inset tile borders and dark date badges. Native event art and today/selection indicators stay visible; month refreshes reuse the same regions.

- Mail inbox subjects now sit in warm reading bands with a fine left accent; duration labels have dark backing. Sender colors, native mail actions and row geometry remain intact, and reused rows clear hidden subjects.

- Character stat values now sit in recessed numeric cells with right-aligned text. Native values and red/green modifiers remain visible, and empty values clear their backing.

- Native lists now have inset separators and blue selection rails. Selection remains visible independently of hover and follows the client's own Show/Hide state on recycled rows.

- Native item counts now have dark inset badges above the icon art. Badges follow count visibility and clear on empty/reused slots; native quantities and quality colors remain intact.

- Static popups now separate secondary text with quieter ink and an inset top rule. Input fields show focus outlines; actions gain press feedback and recessed disabled surfaces, including pooled game-menu buttons.

- Damage-meter names and values now sit on subtle dark contrast plates above the colored bars. Plates follow the native text bounds and are reused on refresh; native values, font sizes, bar colors and window opacity remain authoritative.

- Chat bubbles now have an inset top highlight and a compact speech pointer, giving the dark cards a clearer silhouette. Pooled bubbles reuse their details, and chat text and colors remain client owned.

- Window and dialog close controls now use a warm hover face, shared press feedback and muted disabled glyphs. Repeated skinning reuses regions and leaves native close handlers intact.

- Selected native tabs now have a slate-blue face and brighter outline alongside their persistent underline. Selection changes restore the inactive surface. Horizontal scrollbar arrows follow the current client's orientation field.

- Native dropdowns now use crisp bundled chevrons in dark inset compartments, with muted disabled states. Modern scrollbar steps also suppress their atlas texture so only one arrow is visible.

- Modern scrollbars now have recessed tracks, outlined thumbs and matching directional buttons. Thumb hover and drag states stay visible, and disabled step arrows dim.

- Native sliders now show a slim blue value fill that follows horizontal or vertical geometry, range changes and resizing. Empty or invalid values clear the fill, and disabled tracks stay muted.

- Native checkboxes now use crisp inset bundled checkmarks, with warm selected ink and a muted disabled mark. The client still controls checked visibility.

- Native push buttons now have a subtle raised top edge, a recessed disabled face and quieter disabled borders; enabling restores the surface without replacing native handlers.

- Castbars now separate long spell names from bounded countdown columns, with dark text backing. Hiding time text immediately returns its space to the name, and resizing recomputes the reservation.

- Bag slots now show free capacity on dark inset badges. Full bags gain red counts and borders; absent, invalid or unreadable counts clear both the badge and warning.

- Quest tracking now uses padded cards, taller objective rows, completion checkmarks and an inset icon header. Long text stays bounded, and the existing height limit still reserves the overflow summary.

- Group loot rolls now have layered card chrome, cropped item icons with inset backing and dark outlined countdown tracks. Repeated skinning reuses regions and preserves native roll handlers.

- XP and reputation captions now have dark backing above an exposed progress edge. The backing follows compact/text settings, and 10% ticks follow the row width when resized.

- Timed quests now use recessed countdown badges with room for hours, bounded quest titles and steady urgency rails that remain visible with reduced motion.

- Breath and fatigue bars now reserve a dark countdown badge, constrain long labels and soften the fill behind text. A steady severity rail keeps low time visible between pulses.

- The stopwatch now has separate Run, Pause and Reset states, a bright bounded clock, a state-colored rail and hover feedback. Its maximum duration fits in a dedicated column.

- Combat timing now separates a warm Combat or muted Last label from a bright right-aligned clock, with a steady state rail and bounded columns.

- Durability now has a repair glyph, a steady severity rail and a bounded caption. Healthy percentages use a calm green; worn and broken gear keep yellow and red alerts.

- Minimap status now sits in an inset two-row footer: clock and coordinates above day/night and optional performance. Queue and RikUI controls remain on the map; layout presets include the entire 200×270 card.

- The minimap zone label now sits inside a layered header with a map glyph. Its layout bounds include the header, and native indicators remain aligned to the square map after Edit Mode changes.

- Tooltips now use larger headings, a quiet inset top accent and clearly outlined dark health tracks. Native GUID watching continues to own all health values.

- Chat copy now has separate header, transcript and footer bands, a wider focused search field, styled actions and empty-result guidance outside the copied text.

- Chat channel buttons now keep a persistent active-channel underline, stronger selected opacity and descriptive hover help while retaining native channel switching.

- Loot item cards have larger cropped icons, room for two-line names, dark quantity backings and consistent inset spacing; reused rows clear old stack visuals.

- Loot now has a layered title bar, remaining-item count, close glyph and an explicit empty state that follows slot updates.

- Bag search now retains a focus outline and shows a readable empty-result panel with reset guidance when a query or category finds nothing.

- Bag filters now show a persistent gold underline and selected fill, with brighter inactive labels for easier scanning.

- Bags have a layered window, larger controls and clearer separation between searching, filtering, inventory and equipment.

- Redesigned utility and settings chrome with layered headers, recessed navigation,
  group icons, selection rails and clearer keyboard focus. Settings now show explicit
  On/Off toggles, filled slider tracks and distinct dropdown selection states.
- Setup now has a numbered progress track, reviewed-step checks and a clearer
  primary action; its page content retains the same available height.

- UI polish: faded panel text retains its opacity; panel and button fonts recover
  if the selected font cannot load. Disabled controls clear stale hover and press
  effects, scrollbar arrows and thumbs dim correctly, and vertical sliders keep
  their native orientation. Panel item buttons regain visible pressed feedback.
- Reduced motion now also covers cached effects and notification accents.
  Hidden notifications stop animating, reused cards update their icon backings,
  and resizing wrapped settings content preserves the current scroll position.

- Readable window text. Labels Blizzard colours dark brown or black for its
  parchment windows (spellbook names and subtexts, the page counter, talent
  and achievement text) now take the skin's pale ink; red, green, gold and
  grey states keep their colours.
- One cooldown strip. The new Cooldowns module draws the game's configured
  cooldown entries (the order and hidden choices you save in Blizzard's
  Tracked spells window) followed by RikUI's own list of learned class
  abilities, in one 280 px strip above the resource strip, with rank twins
  collapsed to the rank you know. Blizzard's four cooldown viewer frames stay
  hidden while the module is on and come back when you disable it. This
  replaces the separate Class cooldowns row, the cooldown viewer skin, its
  On/Off toggle and the `/rik cooldownranks` prompt; saved settings for those
  (module flags, the old layout positions, per-character rank choices) are
  ignored. Paladins get Judgement there from level 4, since Judgement now
  leads the paladin list. Run `/rik hud` on an existing profile to place the
  strip and the class effect rows.
- Aura cells in the strip. Entries with an aura (Immolate, Blizzard's tracked
  buffs and bars) show the aura's icon and timer in their cell while it is up,
  the way the native rows did, and their own icon dimmed when it is not.
  Paladins get one Seal cell next to Judgement: dim until a seal is active,
  then whichever seal it is, with its timer. The seven seals leave the Buffs
  row. The class effect rows are now labelled Buffs and Target effects.
- The locally built quest corpus and road networks now install inside the
  RikUI folder (`generated/`, pulled in by the committed `generated/index.xml`)
  and load with the addon. Only the mesh patches stay as separate
  load-on-demand folders, in 16 MiB packs: about sixteen folders instead of
  the 697 companion addons the previous layout needed. Reinstall both with
  `tools/quest_corpus.py install --rikui ...` and
  `tools/terrain/install_roads.py install --addons ...`, then restart the client.

### In this release

- Setup wizard with presets for all nine classes: action bars, macros,
  character keybinds, game settings and frame layout. Every step is optional
  and `/rik undo` restores what the last Apply changed.
- Level-up placement and `/rik resync` keep preset slots current as spells
  and ranks are learned, without touching slots you rearranged.
- A replaced interface: action bars with stance paging, player, target, pet,
  party and raid frames, cast bars, auras, nameplates, a square minimap,
  combined bags with search and favorites, chat with history and copyable
  text, tooltips, loot and roll frames, the micro menu, XP and reputation
  bars, the quest tracker, and a matching skin over the Blizzard windows and
  menus.
- A combat HUD that puts cooldowns, the current resource, the cast bar and
  swing or wand timing in one central stack, following class, form and
  learned abilities.
- Four whole-screen layouts, per-frame unlock and drag with snapping, and a
  UI scale command.
- A quest planner with map and route guidance where its data covers the area.
- Profiles, preset and profile import and export, and bundled community
  presets with attribution.
- A settings backup that survives `/reload` and a full restart on a beta
  client that has been seen not reading saved variables back.
- Release packaging through the BigWigs packager with archive verification
  before and after upload.
