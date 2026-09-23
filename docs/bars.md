# Overlay action bars

Buttons now have a 120 ms hover entrance, a brief press flash and a mint
cooldown-completion flash driven by the cooldown widget's own done callback.
Mouse feedback covers action, stance and pet buttons; native action-key feedback
also triggers the press tween. New page icons fade in over 160 ms. Native
visibility hides old secure pages immediately, so transitions never keep an
outgoing action clickable. Stance changes also fade the stance icons.
All animation work changes addon-created regions, with no cooldown-value reads.
Hidden buttons stop their effects. Native behavior is accepted by user policy.

`RikUI.Bars` owns five 12-button bars and hides the corresponding stock action
bars, bag/menu buttons and XP/reputation bars once their overlays are ready.
Manual paging adds five main-position overlays for selected pages 2–6.
Stance paging adds Warrior Battle (73–84), Defensive (85–96) and Berserker
(97–108) overlays, a known-form row and a ten-slot pet row. Each main overlay
shows the actions already stored in its stance slots, including the preset's
stance-specific spells and macros. Other-class bonus mappings and broader native
acceptance remain deferred. Base slots 1–12 are used on selected page 1 outside
the supported bonus conditions.

| Bar | Fixed slots | Native binding prefix | Default anchor (x, y) |
|---|---|---|---|
| main | 1–12 | ACTIONBUTTON (base page only) | BOTTOM (0, 40) |
| bar2 | 61–72 | MULTIACTIONBAR1BUTTON | BOTTOM (0, 82) |
| bar3 | 49–60 | MULTIACTIONBAR2BUTTON | BOTTOM (0, 124) |
| bar4 | 25–36 | MULTIACTIONBAR3BUTTON | RIGHT (-40, 0) |
| bar5 | 37–48 | MULTIACTIONBAR4BUTTON | RIGHT (-82, 0) |

The mapping comes from `Setup.SlotToAction`, the same source used by Apply.
Defaults come from `Setup.DefaultPositions`. Three horizontal rows use
36-pixel buttons with 6-pixel gaps; the two side columns run top to bottom.
The [shared layout registry](layout.md) reads `Profile.positions[name]` and
`Profile.scale` for every bar. `/rik move` exposes one labelled mover per key.
Apply and Undo refresh existing bars after changing saved positions.
All creation, attribute, position and scale writes run through the core combat
queue. Invalid saved
position fields or scale fall back to defaults without rewriting saved data.

## Empty-slot preset previews

Empty slots in the character's applied preset now show a 35%-opacity icon and a
small `Lv N` label where the preset supplies an acquisition level. Hovering names
the spell, macro or item and identifies it as a preset preview. Levels describe
the preset; learning may still require a trainer, quest or talent.

Previews follow the applied role and each absolute action slot, including stance
overrides and manual pages. An occupied slot always hides its preview, even when
the action's texture is unavailable. Unassigned slots and characters without an
applied preset stay empty. Clearing an action restores its preview; Apply, Undo,
profile changes and late item data refresh it automatically.

Use **Preset ghost icons** in `/rik config` under **Bars and layout**, or
`/rik ghosts off` / `/rik ghosts on`. The profile preference is saved
through the existing settings transport. Successful toggles produce no chat line.
Previews never place an action, capture clicks, alter bindings or change layouts.

The implementation uses plain mouse-transparent child frames below hotkeys and
press feedback. Refreshing in combat changes only cosmetic regions. It requires
an explicit readable `HasAction(slot) == false`; unavailable or opaque occupancy
suppresses the preview. Spell icons fall back to the local catalogue, and unknown
item icons use a question mark until data is available. Macro labels use the
lowest acquisition level among their alternative spells, matching setup's
placement rule.

API contracts checked against the project's pinned client source:
[spell textures](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua),
[item icons](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua),
and [action occupancy](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua).

Recording-renderer regressions exercise visibility, role/stance/manual slots,
combat write guards, hover refresh, icon failure and recovery, Apply/Undo,
profile switching and persistence. Native pixel layout and client protection
remain unverified in this session: desktop control is unavailable.
After `/reload`, inspect an empty applied slot, hover it, fill/clear it, change to
the available Battle page, and toggle ghosts in and out of combat. Confirm the
label stays clear of the keybind and the checkbox survives another reload.

## Module API

- `Bars.Create(name, firstAction, layoutOpts)` creates or returns a bar.
  Options: `size` (positive number, default 36), `spacing` (nonnegative,
  default 6), `vertical` and `fade` (booleans, default false).
  `positionKey` may name a `Setup.DefaultPositions` entry; manual and bonus overlays
  use `main` so saved position, scale, Apply and Undo move all main pages together.
  The same name/range is idempotent; a conflicting range is rejected.
  Returns the frame on immediate success, `nil, "queued"` when deferred,
  or `nil, reason` for invalid input or immediate creation failure.
- `Bars.Frames[name].buttons[i]` exposes the corresponding button. Its
  `action` field and secure `action` attribute are fixed to
  `firstAction + i - 1`. Frame names are `RikUIBar_<name>` and
  `RikUIBar_<name>Button<i>`.
- `Bars.ApplyLayout()` refreshes all existing frames from the current profile,
  coalescing requests during combat.
- `Bars.Refresh(slot)` refreshes matching slots; nil or zero refreshes all.
- `Profile.modules.bars = false` disables creation on the next reload.

## Clicks, dragging and visuals

Buttons inherit only `SecureActionButtonTemplate`. Their frame IDs stay zero:
positive IDs would make the secure mixin calculate paged actions instead.
Both AnyDown and AnyUp are registered; the inherited secure click handler selects
one edge using `ActionButtonUseKeyDown`. RikUI neither replaces OnClick nor
changes that CVar. Two PostClick notifications alone do not establish two casts.

The bare template has no drag scripts. Explicit handlers call PickupAction
and PlaceAction out of combat. Locked bars require the configured PICKUPACTION
modifier to pick up a button (normally Shift). A drop requires a nonempty cursor;
displaced actions stay on the cursor. Combat drags are rejected, never queued.

Icons, counts and empty-slot textures refresh on slot changes, world entry,
binding changes, spell icon/charge updates and inventory changes. Modern
C_ActionBar APIs are preferred, with legacy globals retained for beta
compatibility. Display-ready counts go directly to SetText; secret numeric
counts go directly to SetFormattedText without comparison or conversion.

Bar3 remains mouse-interactive at zero alpha. Hovering its frame or a button
reveals the row; a short delayed leave check prevents flicker between buttons.
An alpha animation fades it out in 0.2 seconds. Combat reveals it immediately
and combat exit reevaluates hover. No OnUpdate or restricted secure snippets
are installed.

Hovering any action, stance or pet button shows its tooltip the way the stock
bars did: `Bars.AttachTooltip(button, label, setter)` asks for the default
anchor (so the [tooltip module](tooltip.md) places and skins it) and runs
`GameTooltip:SetAction(slot)`, `SetShapeshift(index)` or
`SetPetAction(index)` under `pcall`; the button's `UpdateTooltip` method lets
`GameTooltip_OnUpdate` refresh it while hovered and `OnLeave` hides it. A
failing setter prints one `Bars <label> tooltip` line. The hooks sit beside
the fade hooks and are not protected, so they work in combat.

## Shared media and flat skin

`src/ui/media.lua` exports `RikUI.Media.font`, `statusbar`, `border`,
`checked` and `highlight` paths. The bundled font is static hinted Noto Sans
Regular; [media/LICENSES.md](../media/LICENSES.md) records the full provenance.
Fully exit and restart WoW when installing new media; a reload may not find it.

`src/modules/bars/bars-skin.lua` decorates every new fixed-slot, manual-page, bonus, stance and
pet button. Icons are inset one UI unit and cropped to 0.07–0.93; four
one-unit edges form the flat border. Buttons have no native normal art.
Hover and mouse press use the bundled translucent texture. Hotkey/count
text is 12 units, central cooldown 16 and recharge 11, all outlined in the
shared font. Profile scale applies to the complete row, including its art.

Current actions and auto-repeat each feed an independent gold checked border
through `SetAlphaFromBoolean`, refreshed by `ACTIONBAR_UPDATE_STATE`.
Opaque flags are not combined or tested in Lua. Empty slots/API failures
clear stale borders. Action borders and labels live above the cooldown frames.
Companion labels use `SHAPESHIFTBUTTON` and `BONUSACTIONBUTTON` bindings;
their active border stays distinct from the green autocast marker at bottom left.

`Profile.gryphons` defaults to false. Use `/rik gryphons on` or
`/rik gryphons off`; the command saves the profile preference and uses the
existing combat-queued layout refresh. Each main-position overlay owns its
own end caps, so native paging visibility hides its art with its buttons.
Secondary and companion rows never acquire end caps. Art is referenced
from the client, not copied into the addon.

### Skin verification

Automated recording widgets cover every action overlay's crop, font and border
layer, companion labels and secret flags, active/repeat/error/empty states,
new overlays, profile persistence, and combat-deferred end-cap changes.
They do not prove font loading, native pixels or protection behavior.

On 2026-09-18, the user replied "looko aight" to the full-restart checklist
covering the skin/readability, gryphon toggle with paging/reload, and combat
errors. This is recorded as user-reported native acceptance with no issues
reported, for the usual scale and available character/rows. Other scales and
unavailable stance/pet combinations are not claimed as independently observed.
No runtime code changed after that report.

Repeatable native check after a full client restart:

1. Check normal, empty, hover, pressed, active, range/resource and cooldown/count
   states on available action and companion rows.
2. Toggle gryphons on/off; select pages 1–6 and the available Battle overlay.
   Only the visible main row should show end caps. Reload and check persistence.
3. Repeat page changes, key presses and a gryphon toggle in combat; no Lua or
   protected-action error should occur, and the art toggle applies after combat.
4. Check readability at the normal profile scale, then 0.8 and 1.25 if practical.
   Out of combat, use `/run RikUI.Profile.scale=0.8; RikUI.Bars.ApplyLayout()`
   (substitute 1.25 for the other size), then restore the original scale.
   The existing multi-stance/pet beta follow-up remains separate where unavailable.

API methods are confirmed against the exact 1.60.1.69913 source commit.
The gryphon path is supported by current Classic XML and the user-reported
native acceptance above.

Primary API references used for the skin:

- [Blizzard end-cap references](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_ActionBar/Classic/MainActionBar.xml)
- [Button texture methods](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleButtonAPIDocumentation.lua)
- [Action state APIs and event](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua)
- [Native boolean alpha sink](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleRegionAPIDocumentation.lua)

## Action button state

`src/modules/bars/bars-state.lua` adds state to every fixed action-slot button in the five bars
and their bonus overlays. It uses per-slot `C_ActionBar.GetActionCooldownDuration`
and `GetActionChargeDuration`, so macro and item cooldowns do not depend on
guessing a spell ID. Objects go straight into `SetCooldownFromDurationObject`.
The main timer has a swipe and native center countdown; recharge has an edge
and a smaller countdown at bottom left. Stack/charge display counts continue
through the existing text sink at bottom right. No cooldown numbers are read,
compared, subtracted or formatted in Lua.

Range tint is red, resource shortage blue, other unusable actions grey, and
usable or unknown state neutral white, in that priority order. Both modern
boolean range and legacy 0/1 results are accepted only after a secrecy check.
Range notifications are enabled per owned slot; a guarded posthook restores
our slots after native OnHide disables the shared subscription. A visual child
above both cooldowns keeps hotkeys, counts and pressed feedback readable.
Target, range, usability and player-power events refresh tint; action cooldown
and charge events refresh timers. Empty slots clear old timers/tint/press
feedback. Missing or failing APIs clear stale timers and report one diagnostic
per operation.

Hotkeys use the real native command through `Bindings.Label`, including main
commands on bonus overlays, and refresh on `UPDATE_BINDINGS`. Unbound slots
show no label. Cosmetic posthooks on `ActionButtonDown/Up` and
`MultiActionButtonDown/Up` flash only a visible overlay matching the native
button's current slot and binding command. Releases and page/binding changes
clear the previous flash. No hook executes an action or changes a secure
attribute. Manual and stance pages flash only when their absolute slot matches
the native button's current slot.

These slot-based APIs apply to action overlays. Stance/pet companion controls
retain their existing active/autocast indicators and separate native API paths.

### Native diagnostic and acceptance

`/rik bardebug 1` selects absolute action slot 1 and samples it immediately.
Then `/rik debug` re-samples that slot, including during combat. Without an
explicit selection it uses native ActionButton1's current slot when readable.
The report names the slot, combat status and secrecy of every return from
GetActionCooldown, GetActionCount, IsUsableAction and IsActionInRange. It prints
the range result and HasRangeRequirements only when readable. Diagnostics
sample raw cooldown numbers solely to report secrecy, never to render them.

Native acceptance passed on 2026-09-18. The user's
`Screenshot 2026-09-18 212711.png` confirms slot 1 out of combat:
`hasRange=true`, `range=true`, all four APIs readable. The follow-up
`Screenshot 2026-09-18 213847.png` shows `combat=true` on the same range-bearing
slot. Cooldown returns 1/2/4 and the count are secret; cooldown return 3, both
usable returns and range remain readable. The range result is true.
The user then confirmed the updated cooldowns/countdowns, colors, hotkey labels
and keypress flashes work without Lua errors after reload.

The LuaJIT suite additionally covers duration handoff, failure/empty cleanup,
colour precedence, secret fallback, bindings, native press routing and page
changes, including combat write guards, native subscription ownership and
visual frame layering. The native confirmation covers the user's current
configuration; no separate pet/stance cooldown or exhaustive item/charge catalog
coverage is claimed.

Native check: reload, target an enemy in and out of range, use a cooldown action
and verify swipe/countdown, resource tint, label and held-key flash. Repeat in
combat and run `/rik debug` with `hasRange=true`; record secrecy and any Lua or
protected-action errors. Exercise a charge/item action when available.

### Exact-build sources

Reviewed against Forever 1.60.1 build 69913:

- [Action-slot duration, range and usable APIs](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua)
- [Cooldown widget sinks and countdown text](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPICooldownDocumentation.lua)
- [Main native keyboard execution](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua)
- [Multibar keyboard execution](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ActionBar/Shared/MultiActionBars.lua)

## Stance paging and companion rows

`data/bonus-pages.lua` records the bonus offset and first native action slot.
Warrior Battle, Defensive and Berserker use offsets 1, 2 and 3. These values
come from the extracted `SpellShapeshiftForm.BonusActionBar` client records
for Forever builds 69913 and 69977, not the player's learned-form indices.
The first slot is `(6 + offset - 1) * 12 + 1`, following the native six
normal pages of twelve buttons. Battle additionally has live RikProbe evidence.

The preset already writes all three stance pages through Apply and maintains
learned actions through Resync. Battle keeps Charge/Overpower, Defensive gets
Taunt/Revenge, and Berserker gets Intercept/Pummel, with the existing stance-aware
macros. The display fix exposes those slots without reapplying the preset or
replacing custom actions, bindings or saved layout. Empty assigned slots use
their own stance's ghost previews.

Druid, Rogue and Priest mappings remain unimplemented; `bars-stance-beta-coverage`
retains their mapping and native acceptance work. Defensive and Berserker
mappings are source-verified; live switching, click/key agreement and combat
protection have not been independently observed for these new overlays.

`src/modules/bars/bars-paging.lua` creates fixed overlays and registers only visibility drivers.
Its `[bar:1,bonusbar:N]` conditions respect the native controller's rule that
bonus pages apply only while selected page 1 is active. Each manual overlay
uses `[bar:N] show; hide`; the base hides whenever a manual or recorded bonus
overlay is selected. Driver failure removes partial registrations, hides every
extra overlay and restores the base row, reporting that paging is unavailable.

| Selected native page | Main overlay | Fixed slots |
|---|---|---|
| 1, outside recorded bonus condition | main | 1–12 |
| 1, Battle bonus offset 1 | battle | 73–84 |
| 1, Defensive bonus offset 2 | defensive | 85–96 |
| 1, Berserker bonus offset 3 | berserker | 97–108 |
| 2 | page2 | 13–24 |
| 3 | page3 | 25–36 |
| 4 | page4 | 37–48 |
| 5 | page5 | 49–60 |
| 6 | page6 | 61–72 |

Manual pages exist for every class, including classes without recorded bonus
mappings. They share the main position, scale and ACTIONBUTTON labels while
retaining immutable absolute slot attributes. Pages 3–6 share slots with the
four separate multibars; their labels and pressed feedback use the main binding,
while those multibars retain their own bindings. Slot changes update both copies.

Native paging commands stay intact. Page-up/down may skip a page when Blizzard
settings mark its separate multibar visible; RikUI preserves that native policy.
All page frames and drivers are installed out of combat through the existing
queue. Subsequent page transitions use the native visibility driver, with no
addon page-event handler changing protected attributes or showing/hiding bars.

`src/modules/bars/bars-controls.lua` uses the shared button art and validated profile layout.
The stance row shows learned forms and an active highlight; its left clicks
cast the spell ID returned by GetShapeshiftFormInfo. The pet row has ten fixed
pet actions, active highlights, an autocast-available border and an enabled
checkmark. It follows the build-69913 GetPetActionInfo tuple and resolves token
textures. Left click casts; right-click autocast toggling is not implemented.
Native stock pet controls remain available for toggling autocast.

The native Ctrl-Q/E/R stance and Shift-G/Ctrl-B/Ctrl-N pet binding commands are
unchanged. Forms 4+ gain clickable controls without new bindings. The profile's
`stance` and `pet` positions default to the left edge above bar3, at y=166
and y=202 with 30-pixel buttons. Apply/Undo and profile scale include both rows.
Creation, spell attributes, form visibility and layout are deferred in combat;
active and autocast flags go directly to alpha sinks during visual refreshes.

The stance visibility driver excludes possession/override bars. The pet driver
requires a living pet and excludes possession/override bars; exact behavior
with temporary guardians, pet dismissal and possession remains unobserved.
The controls preserve SecureActionButtonTemplate's click handler and both click
edges. No native frame is adopted and stock stance/pet suppression remains the
later hiding chunk.

Automated tests cover all three Warrior mappings, modeled visibility exclusivity,
all twelve slots, real DPS/tank Apply and Resync, stance ghost previews, native
keypress feedback, partial driver cleanup, combat login, shared layout, known/removed forms,
fourth-form clicks, current pet tuple/token handling, autocast and secret flags.
These tests do not execute the protected client renderer. Native multi-stance
transitions, click/key agreement, pet lifecycle and taint acceptance remain
unobserved and are tracked in `bars-stance-beta-coverage`. The user authorized
closing this implementation with those checks deferred and requested no more
prompts for later-stance testing.

Manual-page automated coverage checks all twelve slots on pages 1–6, page-1-only
bonus precedence, one modeled main overlay, classes without bonus data,
combat login, deferred shared layout and complete partial-driver cleanup.
Integrated state tests cover selected-page cooldown/count/labels, combat key
feedback, clearing flash on a page change and distinct bindings on shared slots.
Native manual-page acceptance passed on 2026-09-18. The user confirmed all
checks below: pages 1–6 show one main row with matching click/key actions,
page 1 restores Battle Stance, switching works both out of combat and in combat
without Lua/protected-action errors, and reloading while page 2 is selected
preserves the correct row. This verifies the current beta configuration.

For the manual-page beta check, reload the addon, then select pages directly
with `/changeactionbar 1` through `/changeactionbar 6`. Verify one main row,
matching click/key actions and no Lua/protected-action errors both out of combat
and in combat. Return to page 1 with Battle Stance active and verify the Battle
row returns. Also reload out of combat while page 2 is selected to check initial
visibility. These native commands avoid the preset's Shift bindings, which
belong to the separate multibar.

## Stock action bars

`src/modules/bars/bars-stock.lua` parks MainActionBar and the four replaced MultiBar roots
through the shared `RikUI.Hide.Frame` helper (see [core](core.md)), always
with `keepEvents` true. MainActionBar includes its gryphons (`EndCaps`) and
page arrows (`ActionBarPageNumber`); the legacy MainMenuBarArtFrame is parked
if present. On Forever the Mainline family loads, so MainActionBar is the main
bar and MainMenuBar does not exist; a missing MainActionBar global falls back
to ActionButton1.bar, the owner assigned by Blizzard's action-bar constructor.
Override and extra-action controls are not suppressed.

StanceBar and PetActionBar are parked once the RikUI stance and pet rows exist
(`bars.ControlFrames`), and return whenever a row is unavailable. The RikUI
pet row has no right-click autocast toggle yet; `/rik stockbars show` restores
the native pet bar for that until the row supplies it.

StatusTrackingBarManager belongs to the [XP bar module](xpbar.md) and MicroMenu
and BagsBar to the [micro menu module](micromenu.md). Each parks its stock
frames once its own replacement exists and follows `/rik stockbars show|hide`.
These stock modules load during game startup; world entry also rechecks targets.

Native events, attributes and click handlers stay intact. Reparenting runs only
through the combat queue; a posthook remembers native parent changes and
reapplies suppression, deferring if combat is active. Stock bars could briefly
reappear if Blizzard reparents them during combat, until the queue can run.

`/rik stockbars show` restores their saved parents; `/rik stockbars hide`
suppresses them again. The choice persists as `Profile.showStockBars`.
Disabling the bars module leaves the stock UI available after reload. Stock
bars without a complete matching overlay remain available.
`/rik stockbars status` prints each target, the frame it resolved to on the
live client and its state (hidden, hide queued, native, or native with no
RikUI replacement); use it to confirm the beta frame identity.

Opening Edit Mode prints one warning line: Edit Mode cannot show or move the
parked frames, and its layout changes are recorded by the parent posthook and
re-parked. RikUI does not register its own frames with Edit Mode.

## Verification

The LuaJIT suite covers fixed attributes and IDs, inherited click preservation,
profile positions and scale, Apply/Undo, queued creation/layout, rejected combat
drags, lock/modifier pickup, cursor drops, event refreshes, modern and legacy
APIs, secret count sinks, module disablement and hover/combat fade transitions.
Stock-bar tests cover parent restoration, native reattachment, combat deferral,
module disablement, furniture hide/restore, native menu relocation/layout refresh,
stance/pet parking gated on the RikUI control rows, the status report, and
preservation of native events, status-child hierarchy and unrelated controls.
The shared helper has its own suite for keepEvents, restore callbacks, combat
queueing and the Edit Mode warning line. The recording
renderer does not execute Blizzard's protected action handler.

Native beta acceptance passed on 2026-09-18. The user confirmed the expanded
stock UI cleanup, both right-side columns, one expected action per click,
Shift-drag out of combat, and third-row hover/combat reveal followed by fade,
with no Lua errors. This confirms the current client configuration; alternate
click-edge settings and temporary override modes were not separately reported.

Repeatable Warrior beta regression checks:

1. Reload with RikUI enabled and inspect the bottom stack and right columns.
   Stock main/extra bars, gryphons, page arrows, stance/pet bars, bag/menu
   buttons, and XP/reputation bars should be absent, also after zoning.
   Verify native keys still cast, bag/menu keys still open their panels, and
   /rik stockbars show|hide restores/hides the stock UI. Run
   /rik stockbars status and note the frame MainActionBar resolved to. Open
   Edit Mode from the game menu: expect exactly one RikUI warning line and no
   Lua error. Disable the bars module in /rik config, reload, and confirm the
   Blizzard bars are back.
2. With the Warrior preset placed, click a known non-toggle spell/action on an
   overlay and confirm the expected action fires once. Compare bar2 with its
   Shift binding. Check with ActionButtonUseKeyDown both 1 and 0, restoring
   the original setting afterward. Do not use Attack's toggle state as proof.
3. Out of combat, Shift-drag an action to an empty overlay slot and back;
   verify icons move and the action casts from its new slot.
4. Check bar3 at rest, over a button, in the gaps, during combat, and after
   combat. Confirm no Lua/protected-action errors.
5. Check saved position/scale persistence across reload. Apply/Undo should
   update positions immediately.

## Source evidence for stance/pet work

Warrior stance mappings were checked on 2026-09-23 against Blizzard's extracted
client records: [SpellShapeshiftForm, build 69913](https://wago.tools/db2/SpellShapeshiftForm/csv?build=1.60.1.69913)
and [build 69977](https://wago.tools/db2/SpellShapeshiftForm/csv?build=1.60.1.69977).
Both give Battle (form ID 17) BonusActionBar 1, Defensive (18) 2, and Berserker
(19) 3. This is client-data evidence, distinct from live beta acceptance.

Reviewed 2026-09-18 against the exact Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Six native pages, twelve buttons and slot-to-page mapping](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButtonUtil.lua)
- [Native multibar page assignments](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ActionBar/Shared/MultiActionBars.lua)
- [Native page-up/down selection](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua)
- [Native visibility driver](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua)
- [Native bonus-page precedence](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ActionBarController/ActionBarController.lua)
- [Secure action types](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua)
- [Stance API and events](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ActionBar/Shared/StanceBar.lua)
- [Pet API and events](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ActionBar/Shared/PetActionBar.lua)

## Source evidence for initial overlays

Reviewed 2026-09-18. The 12.1.5 ptr2 source reports build 69848; it supports
implementation choices but does not replace a check on beta 1.60.1.69913.

- [Secure template XML](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.xml)
- [Fixed action and click edge handling](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua)
- [Native multi-bar pages](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ActionBar/Shared/MultiActionBars.lua)
- [Action button drag and refresh events](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua)
- [Action-bar API documentation](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua)
- [Menu roots](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_MicroMenu/Mainline/MicroMenuContainer.xml) and [native relocation/layout](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_MicroMenu/Shared/MicroMenuContainer.lua)
- [Bag bar hierarchy](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_MainMenuBarBagButtons/Mainline/MainMenuBarBagButtons.xml)
- [Status bar manager hierarchy](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_ActionBar/Mainline/StatusTrackingBar.xml)
