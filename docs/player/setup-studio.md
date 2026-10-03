# Setup Studio

Development reference: Studio is temporarily hidden from the released addon and public website. Use `/rik config` for current configuration. The retained workflow below documents the implementation for future revision; it is not currently available through normal player entry points.

Copy a setup you like, fit your screen and keep personal changes. Open **/rik studio**, or start at [Setup Studio](https://rikwow.com/studio) before installing.

![Setup Studio review](preview:studio-controls)

Start with **Use my current UI**, a curated layout or **Import a code**. Use the numbered pages to select parts, choose appearance, fit and preview, then review and apply. The selected theme and readability are highlighted. Frame groups and settings use named choices instead of cycling through hidden values. Modules, fonts and themes can require reload. Geometry and activity changes use safe out-of-combat behavior.

![Handheld presentation](render:studio-handheld)

The browser’s **UI scale** slider and percentage sit beside the screen controls. They resize RikUI frames together and are saved in the exported pack; **Zoom** only enlarges the browser preview. Imported scales keep their exact percentage. **Reset** restores the setup’s scale, and Undo/Redo includes scale edits. The effective percentage explains any personal readability or theme-spacing minimum. Select **Appearance & chat** to adopt scale changes. WoW’s global UI scale remains an in-game setting.

Use **Fullscreen** for a larger editing workspace. **Hide controls** gives the preview the available width; **Show controls** brings the same settings back. **Zoom** runs from Fit to 400%; scroll the preview to reach a zoomed region. Escape or **Exit fullscreen** returns to the page and restores keyboard focus. Browsers that decline fullscreen still get an expanded workspace. On a phone, Parts and Appearance controls scroll above the preview; Layout puts its frame inspector below the canvas. Frame controls can be hidden in either layout workspace.

The **Backdrop** selector offers the supplied game screenshot, a dimmed view and a plain editing surface. The original 3840 × 2160 image is shared by every setup, device and sample scene. It automatically downscales and center-crops to your chosen screen aspect ratio. Its character and overhead names are part of the fixed image; it does not follow your camera or activity. The backdrop, browser zoom and fullscreen mode do not enter your addon export.

In the browser, **Parts → Turn features on or off** shows individual RikUI features with actual component pictures where available. Search by name or filter by area. Click a picture to select its frame, then use its switch below the preview or on its card. Window and situational features have a guide instead of a canvas sample. Switches participate in Undo/Redo, live imports and exported packs.

Area checkboxes mean **adopt these settings**; feature switches mean **enable RikUI for this feature**. Unchecked areas stay with your current UI. Shared unit frames require both Combat HUD and Party & raid before turning them off. Enabling target/focus/pet auras enables their required unit frames; blocked dependencies are explained in review. QuestTogether ownership disables RikUI nameplate editing while that optional addon is present.

Off features retain their source positions and can be selected as gray labeled movers; they reserve no RikUI fitting space. Re-enabling fits them from the same source without accumulating drift. Module choices activate after reloading the addon. Default game elements restored by disabling RikUI styling, and optional-addon interfaces, are outside the captured preview and fitting guarantees.

Desktop, ultrawide and handheld use the same source pack and preserve bindings. Handheld keeps readable controls and collapses secondary information. Personal readable, contrast and calm preferences remain in charge of imports and updates.

**Layout** opens a full-width canvas. Click a bar in the preview or select **Main**, **Bar 2–5**, **Pet** or **Stance** in the bar strip, including inactive bars. The floating inspector changes only that bar: choose a visual row arrangement, set an exact **Buttons per row**, choose **Button size**, and pick a named gap or an exact **Gap between buttons**. Hide frame controls for an unobstructed canvas; selecting a bar brings them back. On phones the inspector sits below the canvas. **Position & alignment** contains exact **X/Y**, nudges, centering and reset. The canvas toolbar has separate **Snap to frames** and **Snap to grid** switches, a 1–32-unit grid size and optional **Show grid**. Drag feedback shows the settled snapped position with alignment guides; hold Alt to drag freely. Arrow keys move **one unit** by default without snapping, so nudges remain precise even with an 8-unit grid. Choose a different **Move step**, or hold Shift for ten steps. At Fit zoom, very fine grids show spaced major lines to remain legible; the snap interval stays exact. These editor preferences stay out of the shared pack. **Show all labeled movers** is optional; normally only the selected bar and conflicts have persistent labels. Other bars reveal their names on hover or keyboard focus, and the named frame picker and full frame list keep inactive frames discoverable. Each of the five action bars, pet bar and stance bar has its own shape. The same controls are available under **Shape selected bar** in the addon, and under Action bars in Settings. Action slots retain their order and bindings; resizing waits until combat ends. Undo/Redo and export/import include these settings.

![Independent bar shape controls](render:studio-bar-shapes-editor)

**Find a better bar arrangement** tries a bounded set of column counts for unedited bars, then fits the resulting shapes around the character and other frames. It preserves your personal bar shapes, button sizes, spacing, readable minima and explicit frame positions. Review its suggested changes; Undo restores the previous arrangement. The browser performs this search in a worker so editing remains available. If you edit while it runs, the older result is discarded. This is a practical local search, not a guarantee of an optimal arrangement.

Fitting derives supported bar grids, cast-bar dimensions, chat chrome, bag-column capacity estimates, compact progress rows and tracker collapse from settings rather than treating every frame as a fixed rectangle. Gryphon decoration extends the occupied footprint without shifting the action-bar anchor. Content-driven windows retain their source observations or capacity reservations; changed inventory capacity, aura counts, party/raid membership, cooldowns and quest contents can require another review. Imported custom rectangles remain supported. Exact native button samples are available at sizes 30, 36, 42 and 48; other supported sizes use labeled geometry instead of stretching text or inventing a game widget. Old exports remain importable; packs using the new shape fields require RikUI **v1.0.0-beta.9 or newer**.

The preview marks **Character viewing area** at screen center. Automatic fitting prefers to keep it clear, independently of UI density. From **v1.0.0-beta.10**, deliberate placement in this area is advisory and permits export, try-on and Apply when the setup otherwise fits. It is an editor guide, not a rendered character or a camera guarantee. Floating inventory, loot and tooltips can cover it temporarily. Your personal frame positions are preserved; center coverage is shown as an amber advisory, while real frame collisions and off-screen placements remain blockers, and **Reset group** (browser) or **Reset frame** (addon) returns that group to its fitted default. On short desktop screens, full chat and raid panels can still crowd; choose handheld presentation or select fewer parts when review reports a conflict.

Open the **Share** page and choose **Export live** to edit an existing setup in the browser and import the result back. The copy window temporarily hides Studio and restores it on close. Copy the complete code; wrapped lines are accepted. Imported screen dimensions are preserved. Labeled movers and the accessible frame list include inactive groups. Red conflict outlines identify reserved footprints and neighbors, including the required 8-unit clearance. Town shows inventory; Show inactive samples reveals supported conditional fixture states. Preview components derive from actual Lua captures; unsupported imported appearance, unrepresented groups and dynamic contents remain explicit. Character bars, macros and bindings require separate review; imports never execute Lua.

![Complete live export copy window](render:studio-live-export)

![Unobstructed temporary try-on](render:studio-try-on)

Try-on hides the editor and leaves **Back to Studio** at the top of the screen. It is temporary and restores normal presentation on exit. **More tools** contains character operations, restoration and capture. Capture hides selected listed windows and restores their prior visibility on exit; names, world and external addons remain outside its privacy scope.

![Selective adoption and theme review](render:studio-theme-review)

![Frame adjustment and undo](render:studio-edit-undo)

Creator updates compare installed defaults, the incoming revision and your personal settings. Choose creator changes selectively. Three bounded restore points journal affected settings before mutation and refuse to overwrite newer personal edits. Export a portable code for full client restart recovery.

## Compatibility and optional integrations

The QuestTogether recipe assigns nameplates to its stock augmentation, disables RikUI nameplates after reload and reserves upper-left bubble space. Use QuestTogether's own controls to position the bubble; the recipe recommends icons on the left and quest health tint off. It uses no foreign settings or styling/data APIs. If the optional addon is missing or its API fails, RikUI ownership remains available.

## Storage and restart recovery

Pack codes are limited to 12,000 bytes. Studio keeps one installed source/state, three separate rotating restore banks and 20 session edit states. Storage or capacity failures stop before settings change. These banks do not form an unlimited library or get squeezed into the restart macro backup. Export a portable code before a full client restart; beta client CVar retention is not a permanent recovery guarantee.

## Publish a remix or update

Share creates a self-contained browser link with validated data in its fragment. Check selected character content and attribution before sharing. A remix records the original identity, revision and creator. Maintainers can submit or revise a gallery entry through the [gallery submission process](https://rikwow.com/setups/submit), including authentic captures, permission and compatibility review.
