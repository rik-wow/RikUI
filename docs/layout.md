# Moving and scaling frames

After updating, use `/rik hud` to arrange the combat displays and supporting unit
frames while keeping the surrounding UI. For a whole-screen layout, use
`/rik layout hud`, or replace `hud` with `centered`, `classic` or `healer`.
Your saved custom positions stay until you choose to arrange them.
`/rik layout undo` restores the previous layout.

Every preset includes the [core combat HUD](combat-hud.md): central cooldowns,
a resource strip and cast bar, with class effects and supporting timers nearby.
Its main column gets priority when fitting windows into the available space.

All four presets now include bag capacity and the four native cooldown viewers.
The micro menu wraps into a compact column, with room above it for bag capacity
and the damage meter. Presets fit supporting widgets around the main controls
before applying positions; the setup preview uses that same fitted arrangement.
The HUD's combat frames sit above the action bars, anchored from the bottom so
they stay below the character on larger usable screens. Empty native cooldown
viewers keep a full-size mover instead of collapsing their labels at the edge.

The chat channel strip and input now follow the chat window's effective scale.
Opening the input restores its height and placement if the client changed them.
This applies to every preset and custom layouts. Automated fixtures cover 4K
at 85% UI scale, additional RikUI scales, and smaller display layouts.

Chat and the damage meter now apply the profile scale to their native windows as
well as their movers. Previously a non-unit scale could leave the blue highlight
smaller than the visible window. Chat tabs follow the same scale; profile changes
and Edit Mode recovery restore alignment. Combat defers these native frame writes.
Regression fixtures cover 85% and 120% scales, scaled UIParent, repeated application
and combat recovery. This fixes the user-reported screenshots from 2026-09-24;
native acceptance follows the standing user policy, not an agent-run playtest.

Hold the "Hold to show frame locks" key (Key Bindings, RikUI section). While
it has no key, hold Ctrl+Alt+Shift together. Every frame shows a small lock tag
on its top left corner and a master tag appears at the top of the screen.
Click a tag to unlock that frame; click the master tag to unlock or lock all.
Release the key: unlocked frames keep a blue overlay with a pulsing edge and a
sweeping band, and stay draggable until you lock them again, log out or enter
combat. `/rik move` does the same as the master tag without the key.

Every overlay has a small lock button in its top right corner that locks that
one frame. It is part of the overlay, so it is always clickable: the overlay
covers the whole frame, and a lock control the frame has of its own (the chat's
padlock) lies under it while everything is unlocked.

Drag an unlocked frame by its overlay. The frame follows at once. It snaps to
other frames' edges and centres, to a 4-unit gap beside them, and to the screen
edges and centre lines, with a blue guide line where it snapped; hold Shift to
drag freely. It cannot be dropped on another frame: it stops flush against it
(the overlay's edge turns red while it is blocked) and slides along it when the
move allows. The bag window's header and the chat window's tab drag through the
same engine. One main-bar overlay moves every manual and bonus page together.

`/rik move reset` restores the default positions of all registered frames.
It keeps the current scale. `/rik scale <0.25-3>` sets the shared profile scale;
for example, `/rik scale 0.8` or `/rik scale 1`. Positions and scale survive
reload. Invalid input prints usage without changing the profile.

Combat refuses move, reset and scale commands. Entering combat locks every
frame; a drag in flight ends where the frame stands, which is a free place by
construction. Holding the key in combat shows only the master tag, which says
the frames are locked. Profile selection, UI scale changes and display-size
changes lock everything too.

## Files

| File | Role |
| --- | --- |
| `src/layout/layout.lua` | Registry, saved positions, scale, `Apply`, `Reset` |
| `src/layout/layout-geometry.lua` | Rectangle arithmetic, no WoW API |
| `src/layout/layout-rects.lua` | Rectangles per group, anchor-preserving save, growth room, settle pass |
| `src/layout/layout-unlock.lua` | Hold state, lock tags, master tag, unlocked set, `/rik move`, `/rik scale`, `/rik layout`, combat locking |
| `src/layout/layout-drag.lua` | Overlay animation, `BeginDrag`/`EndDrag`, snapping, guides, live follow |
| `Bindings.xml` | The `RIKUI_UNLOCK` binding; `runOnUp` makes it a hold |

`layout.IsMoving`, `layout.StopMoving` and `layout.RefreshMovers` keep their
old names (`src/configuration/options/options.lua`, `src/core/core.lua` and `src/layout/layout.lua` call them): something is
unlocked, lock everything, and re-place tags and overlays. `/rik layout` prints
the group count, the unlocked count and the key bound to the hold.

Whether the client loads an addon's `Bindings.xml` on 69913 is unverified. If
the RikUI section is missing from the Key Bindings screen, the chord still
works; report it.

## Module contract

Load after src/setup/setup-apply.lua. `RikUI.Layout.Register(frame, key, defaults)`
registers a persistent frame and applies its current profile position.
Defaults are `{ point, relativePoint, x, y }`, anchored to `UIParent`.
The first registration owns the key's defaults and options; subsequent frames with that
key move together. Re-registering the same frame is idempotent; assigning it a
different key is rejected. Modules should register durable top-level frames
and leave position/scale ownership to Layout.

The five action bars, stance row and pet row register automatically.
Manual and bonus main pages use `main`, sharing one mover. Newly registered
keys add copied defaults to `Setup.DefaultPositions`, so future Apply
operations include them. Existing default bar anchors remain unchanged.

`Layout.Apply()` validates saved position fields, uses defaults for malformed
fields, and applies `Profile.scale` (invalid/nonpositive saved scale falls
back to 1). It runs at login, on registration and after profile selection.
Combat calls coalesce through the core queue and use the latest selected
profile when executed. Frames apply in registration order; a frame registered
during an appearance callback joins the end of that pass. A frame write,
floating predicate or appearance callback failure is reported with the group
key and does not stop other frames, including siblings in the same group.
Mover and growth-limit refreshes have separate error boundaries.

Use `opts.onApply(frame)` for feature-owned appearance such as bar gryphons.
It runs after that frame's geometry succeeds, or without geometry changes when
a functional `floating` predicate returns true. Boolean `floating = true` still
marks a nonblocking group whose saved anchor is applied. The callback receives
each actual frame sharing the key, including later registrations. Keep it
cosmetic: do not change profiles, saved positions or frame dimensions here.
Nested `Layout.Apply()` calls from appearance callbacks coalesce into the
current pass. Completion hooks may still request a new pass when resizing
and settling changes positions.

During `Apply`, the floating predicate and `onApply` run with the callback owner
captured by the group's first registration. This normally inherits the enabling
module or owned callback; pass `opts.owner = feature` to set it explicitly.
Top-level registrations are unowned by default. Later frames sharing the key
keep the first owner's context. Events, combat jobs and nested registrations
created during refresh inherit that context; the requesting caller's owner is
restored even when a frame or callback fails. Coalescing and combat deferral do
not transfer ownership to the module requesting `Apply`.

`Layout.Reset()` and `Layout.SetScale(number)` return `true`, or `nil, reason`
on refusal. `Bars.ApplyLayout()` delegates to `Layout.Apply()`; bar gryphon
refresh is registered through `onApply` and needs no separate feature queue.

`RikUI:SetProfile(name)` selects an existing profile, merges missing defaults,
cancels the mover and applies positions/scale. It refuses unknown profiles,
combat, and a pending Setup Apply/Undo. Module enable flags still take effect
after reload; profile creation and the selection UI live in the
[options panel](options.md).

Setup resolves a copy of all defaults plus preset position overrides when its
snapshot phase starts. The snapshot and layout writer share that fixed set,
so a registration during asynchronous Apply cannot overwrite an uncaptured
position. Undo restores the original profile's captured values. Unrelated
saved position keys remain untouched.

## Arrangement: every group is a rectangle

`src/layout/layout-rects.lua` gives the registry one rule: no two layout groups overlap.
A group's rectangle is computed from its saved position, its first frame's
size and the layout scale, never read from the screen, so a group that is
hidden right now (such as the target frame without a target) still has
one and still blocks. Temporary overlays such as bags, tooltips and loot do not
reserve permanent screen space.

`layout.Register(frame, key, defaults, opts)` takes options:

| Option | Meaning |
| --- | --- |
| `label` | Name shown to the player |
| `grow` | `UP`, `DOWN`, `LEFT` or `RIGHT`: the direction a frame that changes size grows in |
| `onLimit(room)` | Called after every layout pass with the room left along `grow`, in the frame's own units |
| `owner` | Optional ownership override for the floating predicate and `onApply` during `Apply`; otherwise captured from the first registration's context |
| `onApply(frame)` | Refreshes feature appearance for each frame after placement; the first registration owns the group's callback |
| `floating` | A reference place other things float over (the tooltip anchor): neither blocks nor is blocked. May be a function for a group that floats only some of the time (the loot list at the cursor); while it returns true, `Apply` does not position the group either |
| `overlay` | Ignores collisions while retaining saved-position placement; loot uses this together with its cursor-position predicate |
| `exclusive` | Groups with the same tag are never shown together (party and raid) and do not block each other |

| Function | Purpose |
| --- | --- |
| `layout.Rect(key)` | The group's rectangle in UIParent units; nil without a size or a screen size |
| `layout.Obstacles(exceptKey)` | Every rectangle that group must stay clear of |
| `layout.SaveRect(key, rect, profile)` | Saves on the group's own anchor point (the default's `point` and `relativePoint`), so a tracker anchored by its top right corner keeps growing downward after a move |
| `layout.SaveCenter(key, frame, profile)` | For a frame dragged with `StartMoving`; goes through `SaveRect`. A client that reports no screen size keeps the old centre-based save |
| `layout.Available(key)` | Room left along `grow` |
| `layout.Settle(key)` | Without a key: the whole screen in a fixed order (bars, unit frames, cast bars, party and raid, minimap and auras, chat, tracker, then windows that come and go); an earlier group keeps its place, a later one moves to the nearest free place. With a key: only that group gives way |

`Settle` runs on entering the world, on a UI scale or display size change, when
a registered frame changes size, and when a group registers after the world
was entered. A keyed call before the first full pass does nothing, because
frames are still registering. It waits out combat through `core.Combat.Queue`,
prints one line naming what it moved, and never moves a neighbour: the frame
that changed is the one that gives way. `/rik undo` does not cover these moves.

### Frames the player resizes

A group registered with `resize = { minWidth, minHeight, maxWidth, maxHeight,
apply(width, height) }` gets a grip on the bottom right corner of its overlay
(`src/layout/layout-resize.lua`). Dragging it keeps the group's top left corner and grows
or shrinks the rest, first the height and then the width, each stopping flush
at the first group in the way (`Geometry.FreeExtent`) or at the screen edge,
with the overlay's edge red while it is stopped. `apply` is the module's: it
sizes its own frames and keeps the size. The place is saved on the group's own
anchor on release, and combat ends a resize where it stands. The chat window is
the first user. `onUnlock(open)` tells a module with a lock control of its own
(the chat's padlock) when its group is unlocked or locked, and
`layout.SetUnlocked(key, open)` lets that control toggle the same state.

### Frames that change size

Two behaviours, chosen by whether hiding content costs the player anything.
The quest tracker caps itself: it declares `grow = "DOWN"`, takes the room from
`onLimit` and ends in `+N more` ([quest tracker](questtracker.md)). Everything
else keeps its full size: quest timers, the damage meter and the chat
window relocate, while bag and loot windows can overlay other frames, and the size-change hook in `Register` calls
`Settle(key)`, which moves that one frame to the nearest free place and saves
it there. The loot list is not capped on purpose: a hidden row would be an item
that cannot be looted. While it opens at the cursor (the default) it floats and
no layout pass touches it; without that, the resize hook could pull an open
list from the cursor to its saved place. Party, raid and aura holders reserve their largest size
up front and never change.

The defaults were audited by loading the whole addon on a 1365x768 UIParent
(16:9). That found and fixed: the focus frame over the player frame (now
`x=-340`), the loot list on the focus frame, the raid grid over the unit frames
(now top left), the buff rows 16 units into the minimap block (now `x=-220`),
bars 4 and 5 rising into the minimap block (now `y=-90`), and the quest
tracker, quest timers, bags and damage meter standing in the two right-hand
bars' column (now `x=-126`). `tests/layout-rects.test.lua` repeats the audit:
every default that registers under the stubs must settle without a move.
Groups that need a Blizzard frame the stubs lack are settled at login instead.

## Whole-screen layouts

`data/layouts.lua` holds four arrangements of every movable frame, in
`RikUI.Layouts.Order`: `centered` (unit frames above the bar stack, flush with
its ends; the default), `classic` (player and target top left, party under
them, the cast bar over the bars), `hud` (a combat cluster above the action bars,
with player and target flanking the cast bar) and `healer` (party and
raid over the bars, your own frames in rows above the group's left end).

Positions are written from constants, never bare numbers: `MARGIN = 16` to the
screen edge, `GAP = 4` between neighbours, 6 between bars. A frame anchors to
the edge or corner it sits nearest, or to the bottom centre, so a layout holds
on 16:10 and 21:9 as well as 16:9. Shared by all four: the bar stack bottom
centre; the two vertical bars at the right margin from the bottom up; one
column left of them sharing a right edge (quest timers, tracker, damage meter,
micro menu); the minimap top right under its zone line with the aura rows to
its left; the chat bottom left; durability and mirror timers top centre.

`Layouts.Sizes` is every key's nominal footprint: the real size for fixed
frames and the room kept for the ones that vary (tracker 240x120, chat 344x170,
damage meter 260x180, loot 228x174, bags 394x360). A layout may override one
(`healer.sizes`: the grid reaches under the tracker's column on 16:10, so it
keeps room for one quest and the tracker's own cap does the rest).
`Layouts.Pads` is room outside a frame: the minimap's zone line and clock and
the reputation row. The chat has no pad: its rectangle is everything you see of
it (`Layouts.ChatFootprint`: panel border, tabs, channel strip and input bar
around the message area), 344x214 nominal for a 336x136 message area, because
on 16:10 only 349 units lie between the margin and the bar stack and the pet's
cast bar starts at 236. On a 1024-wide screen the 604-wide raid grid has no free
place beside a full chat, so the 4:3 check leaves the raid grid out.

`src/layout/layout-audit.lua` has `Layouts.Rect(name, key, screen)` and
`Layouts.Audit(name, screen)`, pure arithmetic returning sorted issues: a key
not placed, off screen, under `MARGIN` from an edge, an overlap, neighbours
under `GAP` apart. Floating windows (tooltip anchor, bags) block nothing; party
and raid share a place.

The Centered layout is the one source for default places: `layout.Register`
takes a key's default from it, and the position a module passes is only the
fallback for a key it does not know. The bag window is now `floating`: it opens
over the screen like a tooltip, so it neither blocks a drag nor is moved.

### Applying one

`/rik layout list` prints the four with the current one marked, `/rik layout
<name>` applies one and `/rik layout undo` reverts the last apply (one step).
The options panel's General page has the same choice as a "Layout preset"
dropdown; it reads empty once a frame was moved by hand, because
`layout.MatchingPreset()` compares the saved positions with each layout instead
of remembering a name. `src/layout/layout-presets.lua` does the work:
`layout.ApplyPreset(name)` refuses combat and unknown names, keeps the old
positions and chat size in `profile.layoutUndo`, writes a copy of every
position, locks all frames, then runs `Apply` and the settle pass, so an unusual
screen still ends without overlaps.

The chat window is part of a layout. Its width is fitted to the screen
(`layout.ChatSize`: the room between the left margin and the bar stack, at
least 344 and at most 430; 413 on 16:9) and its holder is centred on that
width. A size the player chose with the grip is kept. The chat module adopts the
window when a layout gives it a position (`chat.Restore`), and the
[Edit Mode guard](editmode.md) keeps that size.

Setup takes the same layouts: `setup.Apply(class, role, { layoutPreset = name })`
merges the module defaults, then the layout, then the class preset's own
positions (`setup.LayoutPositions`). The snapshot captures exactly those keys,
so `/rik undo` puts the old positions back. `tests/layout-presets.test.lua`
covers apply, undo, refusals, the chat width on three screens, the slash
command, the dropdown row and the setup merge.

`tests/layouts.test.lua`: each layout places every key and audits clean on
1365, 1228 and 1820 wide screens; the audit's four kinds of issue on a broken
layout; named alignments (player and target flush with the bar ends, the right
column's shared edge, Classic's corner, Healer's grid and HUD's mirror); over a
whole-TOC load the nominal sizes equal the real ones and every registered
default equals Centered; on 1024 wide (4:3) each layout settles with no overlap
and nothing off screen.

## Geometry

`src/layout/layout-geometry.lua` is the arithmetic under the arrangement system. It has no
WoW API: a rect is `{ left, bottom, right, top }` in UIParent units and a screen
is `{ width, height }`, so the rule the system rests on, that no two layout
groups overlap, is proven by tests without a client. Rectangles that only touch
do not overlap.

| Function | Purpose |
| --- | --- |
| `FromAnchor(position, width, height, screen)`, `ToAnchor(rect, point, relativePoint, screen)` | Convert between a saved anchor position and a rectangle, for all nine points. Saving on the frame's own anchor is what keeps a growing frame growing in one direction |
| `Overlaps`, `AnyOverlap`, `Clamp`, `Move`, `Rect` | Basics |
| `Resolve(last, desired, obstacles, screen)` | The drag step: travel on x, then on y, stopping flush at the first obstacle in the path, so a blocked diagonal slides and a large move cannot tunnel. Needs a free `last`; otherwise falls back to `Nearest` |
| `Nearest(rect, obstacles, screen)` | Closest free place: where it is, else flush against an obstacle, else the closest free cell of an 8-unit grid. Second result is false when the screen has no room |
| `Snap(rect, obstacles, screen, threshold, gap)` | Per-axis offset to the nearest line within the threshold (screen edges and centre lines, obstacle edges, centres, and facing edges at the gap) plus the guide lines to draw |
| `FreeExtent(rect, direction, obstacles, screen)` | Room to grow `UP`, `DOWN`, `LEFT` or `RIGHT` before the next obstacle in the path or the screen edge |

`tests/layout-geometry.test.lua` checks each function with fixed numbers and
ends with a property test: 2,000 scenes from a seeded generator, up to 30
obstacles each placed through `Nearest`, five random moves through `Resolve`,
asserting that no result overlaps anything or leaves the screen.

## Verification and limits

Automated geometry tests use UIParent scale 0.75 and frame scale 0.8 to verify
center conversion and reload persistence. They cover shared keys, reset,
invalid settings, late registration, profile changes, missing geometry,
combat cancellation, late drag-stop callbacks, and snapshot/write-set parity.
Integrated bar tests cover all seven registrations, every main page's scale
and reset, preserved visibility drivers, and the existing action/fade behavior.
Protected-write sentinels fail on target hook, position, scale or visibility
mutations during combat.

On 2026-09-18 (local date), the user answered "looks good" to the requested
native drag, lock/reload persistence, scale 0.8/1, reset and combat-cancellation
checklist. Recorded as user-reported acceptance on the available beta character;
no screenshots or separate per-step measurements were supplied. Alternate
resolutions, every possible scale and other characters were not separately
reported. Automated tests model geometry/events; they do not themselves
establish native rendering or taint behavior.

Repeatable checks:

1. Reload, hold Ctrl+Alt+Shift, and check a readable lock tag on every frame; unlock two, release, drag one into the other (it must stop flush) and near a screen edge (it must snap; Shift must not).
   Drag the main row, a right column, bar 3 and stance/pet overlays. The frame
   should land under its overlay on drop. Main page changes should keep the
   same position.
2. Lock, reload, and compare positions. Repeat a drag at `/rik scale 0.8`,
   reload, then restore `/rik scale 1`. Confirm no jumps on drop or reload.
3. Run `/rik move reset` and compare the original bottom stack and right
   columns. Check normal clicks, keyboard bindings and bar 3 fading after lock.
4. Enter combat during a drag. Overlays should disappear, the unfinished drop
   should be discarded, and `/rik move`, reset and scale should refuse.
   After combat, the last saved position should remain with no Lua or
   protected-action errors.

## API evidence

Reviewed against Forever build 69913, commit
`70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e`:

- [Generated frame API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFrameAPIDocumentation.lua)
  marks moving/stopping and scale/visibility setters as protected operations.
- [Blizzard Edit Mode](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_EditMode/Shared/EditModeSystemTemplates.lua)
  pairs movement with explicit cleanup and adjusts anchor offsets for scale.

The mover therefore uses an independent UIParent proxy with no secure
descendants or anchors to the target. Only the proxy is stopped/hidden at
combat entry. Saved center offsets subtract UIParent's center converted into
proxy coordinates using their effective-scale ratio. This is an implementation
inference validated by geometry tests; native acceptance is still separate.
