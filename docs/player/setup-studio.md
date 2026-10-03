# Setup Studio

Copy a setup you like, fit your screen and keep personal changes. Open **/rik studio**, or start at [Setup Studio](https://rikwow.com/studio) before installing.

![Setup Studio review](preview:studio-controls)

Start with **Use my current UI**, a curated layout or **Import a code**. Use the numbered pages to select parts, choose appearance, fit and preview, then review and apply. The selected theme and readability are highlighted. Frame groups and settings use named choices instead of cycling through hidden values. Modules, fonts and themes can require reload. Geometry and activity changes use safe out-of-combat behavior.

![Handheld presentation](render:studio-handheld)

The browser’s **UI scale** slider and percentage sit beside the screen controls. They resize RikUI frames together and are saved in the exported pack; **Zoom** only enlarges the browser preview. Imported scales keep their exact percentage. **Reset** restores the setup’s scale, and Undo/Redo includes scale edits. The effective percentage explains any personal readability or theme-spacing minimum. Select **Appearance & chat** to adopt scale changes. WoW’s global UI scale remains an in-game setting.

Use **Fullscreen** for a larger editing workspace. **Hide controls** gives the preview the available width; **Show controls** brings the same settings back. **Zoom** runs from Fit to 400%; scroll the preview to reach a zoomed region. Escape or **Exit fullscreen** returns to the page and restores keyboard focus. Browsers that decline fullscreen still get an expanded workspace. On a phone, controls scroll above the preview and can be hidden.

The **Backdrop** selector offers an Elwynn world capture, a dimmed view and a plain editing surface. The source is a UI-free 3840 × 2160 capture of current-client scenery through the world renderer. It automatically downscales and center-crops to your chosen screen aspect ratio, keeping the center guide aligned. It is an illustrative static scene with native map textures, not your camera or a rendered character; advanced terrain layers, liquids and procedural grass are outside this capture. The backdrop, browser zoom and fullscreen mode do not enter your addon export.

In the browser, **Parts → Turn features on or off** shows individual RikUI features with actual component pictures where available. Search by name or filter by area. Click a picture to select its frame, then use its switch below the preview or on its card. Window and situational features have a guide instead of a canvas sample. Switches participate in Undo/Redo, live imports and exported packs.

Area checkboxes mean **adopt these settings**; feature switches mean **enable RikUI for this feature**. Unchecked areas stay with your current UI. Shared unit frames require both Combat HUD and Party & raid before turning them off. Enabling target/focus/pet auras enables their required unit frames; blocked dependencies are explained in review. QuestTogether ownership disables RikUI nameplate editing while that optional addon is present.

Off features retain their source positions and can be selected as gray labeled movers; they reserve no RikUI fitting space. Re-enabling fits them from the same source without accumulating drift. Module choices activate after reloading the addon. Default game elements restored by disabling RikUI styling, and optional-addon interfaces, are outside the captured preview and fitting guarantees.

Desktop, ultrawide and handheld use the same source pack and preserve bindings. Handheld keeps readable controls and collapses secondary information. Personal readable, contrast and calm preferences remain in charge of imports and updates.

The preview marks **Character viewing area** at screen center. Persistent frames fit around this viewing corridor, independently of UI density. It is an editor guide, not a rendered character or a camera guarantee. Floating inventory, loot and tooltips can cover it temporarily. Your personal frame positions are preserved; an obstruction is flagged for review, and **Reset group** (browser) or **Reset frame** (addon) returns that group to its fitted default. On short desktop screens, full chat and raid panels can still crowd; choose handheld presentation or select fewer parts when review reports a conflict.

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
