# Moving and scaling frames

Use `/rik move` outside combat to show labelled blue overlays. Drag an overlay
with the left mouse button; the actual frame moves when you release it.
Use `/rik move` again to lock. One main-bar overlay moves every manual and
bonus page together. Bar 3 and absent stance/pet rows still have a visible
mover, so their anchors remain accessible.

`/rik move reset` restores the default positions of all registered frames.
It keeps the current scale. `/rik scale <0.25-3>` sets the shared profile scale;
for example, `/rik scale 0.8` or `/rik scale 1`. Positions and scale survive
reload. Invalid input prints usage without changing the profile.

Combat refuses move, reset and scale commands. Entering combat cancels an
unfinished drag and locks the overlays; its last saved position remains.
Profile selection, UI scale changes and display-size changes also lock and
cancel. Reset, Apply and scaling refresh the overlays and cancel stale drags.
Frames remain at their last applied position while their independent overlay
is being dragged.

## Module contract

Load after setup-apply.lua. `RikUI.Layout.Register(frame, key, defaults)`
registers a persistent frame and applies its current profile position.
Defaults are `{ point, relativePoint, x, y }`, anchored to `UIParent`.
The first registration owns the key's defaults; subsequent frames with that
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
profile when executed. `Layout.Reset()` and `Layout.SetScale(number)` return
`true`, or `nil, reason` on refusal. `Bars.ApplyLayout()` remains the
compatibility entry point that also refreshes gryphon art.

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

1. Reload, enter `/rik move`, and check readable overlays for all seven keys.
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
