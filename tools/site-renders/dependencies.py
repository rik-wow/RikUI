"""Addon inputs for a capture, with conservative fallbacks for unclassified surfaces."""
# Module code affects its own surface. Shared source/media and unknown pages remain global.
PAGES = {
    "class-effects": {"auras"}, "auras": {"auras", "unitframes"},
    "unitframes": {"unitframes", "auras"},
    "damagemeter": {"damagemeter", "controls", "panels"},
    "dialogs": {"dialogs", "controls", "panels"},
    "toasts": {"toasts", "controls", "panels"},
    "combat-hud": {"castbars", "auras", "cooldowns", "combopoints", "totems", "swingtimer", "personalresource", "bars"},
    "proc-overlay": {"extrabuttons"}, "auction-house": {"auctionhouse", "panels", "controls"},
    "interiors": {"panels", "controls"}, "panels": {"panels", "controls"},
    "loot": {"loot", "popups"}, "questplanner": {"questplanner", "questtracker", "worldmap"},
    "questtracker": {"questtracker", "questplanner"}, "questtimers": {"questtimers"},
    "worldmap": {"worldmap", "questplanner", "panels"},
    "sharing": set(), "shell": set(),
}
DIRECT = set("""unitframes castbars bags chat cooldowns swingtimer nameplates combopoints totems bars
personalresource mirrortimers lossofcontrol combattimer extrabuttons damagemeter minimap xpbar
durability tooltip micromenu chatbubbles hudframes screentext alerts banners toasts dialogs popups
menus widgets controls combattext""".split())
GLOBAL_PAGES = {"wizard", "options", "layout", "overview"}
# These inputs supply navigation geometry/admission, not settings or UI construction.
NAVIGATION_FILES = {
    "data/map-terrain.lua",
    *("src/modules/questplanner/quest-" + name + ".lua" for name in (
        "builds", "terrain-packs", "nav-geometry", "nav-funnel", "nav-follow", "nav-search",
        "region-codec", "path-codec", "inflate", "regions", "nav-attach", "navmesh",
        "roads", "road-patches", "road-route", "road-follow", "road-navigate", "road-travel",
        "elevators", "journey-graph", "journey", "travel", "terrain")),
}
NAVIGATION_PAGES = {"questplanner", "questtracker", "worldmap"}

# Preset recipes/packing change top-level placement, not frame contents. Only
# reviewed fixture overrides may remove them; shared geometry stays global.
PRESET_FILES = {"data/layouts.lua", "src/layout/layout-audit.lua"}
# These surfaces use Blizzard/native anchors or fixture-owned holders, rather
# than registered arrangement groups. Their own module/fixture inputs still apply.
NATIVE_POSITION_PAGES = {
    "nameplates", "interiors", "panels", "dialogs", "controls", "widgets",
    "chatbubbles", "screentext", "alerts", "banners", "popups", "menus",
    "auction-house", "combattext", "worldmap",
}

def uses_preset_positions(case):
    import re
    page, root = case.get("page"), case.get("frame", "")
    if page in GLOBAL_PAGES | {"combat-hud", "unitframes", "auras", "castbars", "sharing", "chat", "swingtimer"} or root == "UIParent":
        return True
    lua = case.get("lua", "")
    setup = lua + "\n" + "\n".join(case.get("fixtures", [])) + "\n" + case.get("sequence", {}).get("apply", "")
    # Group holders preserve each child's screen anchors; centering the holder
    # does not isolate those children from preset placement.
    if any(name in setup for name in ("RikRenderGroup(", "RikRenderHUDGroup(", "RikRenderScreen(")):
        return True
    if page in NATIVE_POSITION_PAGES:
        return False
    if root and re.search(r"RikRenderCenter\(\s*" + re.escape(root) + r"\s*[,)]", lua):
        return False
    if page == "questplanner":
        if root == "RikUIQuestPlannerWindow" and "local window = RikUI.QuestPlanner.View.Window" in lua and "RikRenderCenter(window)" in lua:
            return False
        if root == "RikRenderArrow" and "RikRenderPlannerArrow()" in lua:
            return False
        # These card fixtures reparent and explicitly anchor the captured card.
        if root in {"RikRenderSummary", "RikRenderSelection"} and all(part in lua for part in (
                "card:ClearAllPoints()", 'card:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -8)',
                'hold("' + root + '", window.')):
            return False
    return True

def addon_inputs(case, files):
    page = case.get("page")
    scene = "\n".join([case.get("lua", ""), *case.get("fixtures", []), case.get("sequence", {}).get("apply", "")])
    # Settings declarations build no visible UI until a fixture opens settings or uses its setters.
    # Unknown surfaces stay conservative. Inspect scene calls and reached fixture text.
    settings = page == "options" or "RikUI.Options" in scene or "RikUIOptions" in scene or any(
        name in scene for name in ("RikRenderSettings", "RikRenderSetOption", "RikRenderPendingReload", "RikRenderNudgeState", "RikRenderUndoReady", "RikRenderSecondProfile", "RikRenderImportedPreset", "RikRenderOptions"))
    if page not in {"setup-studio", "studio-gallery", "studio-atlas", "options"} and not settings:
        # These files define Studio APIs without constructing visible UI at startup.
        # The ordinary options page also uses the shared Theme values.
        files = {name:value for name,value in files.items() if name not in {
            "src/setup/setup-pack.lua", "src/setup/setup-pack-library.lua",
            "src/setup/setup-studio.lua", "src/configuration/options/setup-studio-view.lua"}}
    if settings and page not in {"setup-studio", "studio-gallery", "studio-atlas"}:
        files = {name:value for name,value in files.items() if name not in {"src/setup/setup-studio.lua", "src/configuration/options/setup-studio-view.lua", "src/setup/setup-pack-library.lua"}}
    if page in DIRECT | GLOBAL_PAGES | set(PAGES) | {"setup-studio","studio-gallery","studio-atlas"} and not settings:
        files = {name:value for name,value in files.items() if name not in {"src/configuration/options/options.lua", "src/configuration/options/options-view.lua", "src/configuration/options/options-controls.lua"}}
    # Drag/unlock source constructs only hidden editor controls until a scene enters movement.
    # Layout, settings, Studio controls and unknown scenes retain it conservatively.
    movers = settings or page in GLOBAL_PAGES | {"setup-studio"} or any(
        name in scene for name in ("RikRenderUnlocked", "RikRenderHeldTags", "BeginDrag", "HoldKey(", "SetUnlocked", "UnlockAll", "SnapDrag", "RefreshGrid"))
    if page in DIRECT | set(PAGES) | {"studio-gallery", "studio-atlas"} and not movers:
        files = {name:value for name,value in files.items() if name not in {"src/layout/layout-drag.lua", "src/layout/layout-unlock.lua"}}
    # Known captures do not paint the wizard or optional coach unless opened.
    # Unknown scenes remain conservative.
    if page in DIRECT | GLOBAL_PAGES | set(PAGES) | {"setup-studio", "studio-gallery", "studio-atlas"} and page != "wizard" and not any(
            name in scene for name in ("RikUI.Wizard", "RikUIWizard", "BeginPractice", "RikUICharacterPractice")):
        files = {name:value for name,value in files.items() if not name.startswith("src/configuration/wizard/")}
    banner = any(name in scene for name in ("RikRenderObjectiveBanner", "RikRenderBossBanner", "RikRenderEventToast"))
    banner = banner or any(name in case.get("frame", "") for name in ("Banner", "Toast"))
    if page in GLOBAL_PAGES | {"setup-studio", "studio-gallery", "studio-atlas"} and not banner:
        # The settings/layout/overview and Studio fixtures display no banners unless invoked above. Hidden
        # banner hooks cannot paint the editor, layout scenes or filtered component roots.
        files = {name:value for name,value in files.items() if not name.startswith("src/modules/banners/")}
    # Reviewed screen-state fixtures never create nameplates. The simulator has no world
    # plate engine; only the explicit nameplate fixture or the atlas nameplates value can paint them.
    known = page in DIRECT | GLOBAL_PAGES | set(PAGES) | {"setup-studio", "studio-gallery", "studio-atlas"}
    plates = page == "nameplates" or "RikRenderNameplates(" in scene
    if page == "studio-atlas" and case.get("sequence", {}).get("apply") == "RikRenderStudioAtlas(VALUE)":
        values = [case["_captureValue"]] if "_captureValue" in case else case.get("sequence", {}).get("values", [])
        plates = "nameplates" in values
    if known and not plates:
        files = {name:value for name,value in files.items() if not name.startswith("src/modules/nameplates/")
                 or (settings and name == "src/modules/nameplates/nameplates.lua")}
    if page == "studio-atlas":
        # Ordinary atlases invoke native components only. Module variants also assert the
        # portable contract against native registrations, so those pack inputs must count.
        portable = "RikRenderStudioModules(" in case.get("sequence", {}).get("apply", "")
        unused = {"src/setup/setup-studio.lua", "src/configuration/options/setup-studio-view.lua"}
        if not portable:
            unused.update({"src/setup/setup-pack.lua", "src/setup/setup-pack-library.lua"})
        return {name:value for name,value in files.items() if name not in unused}
    modules = PAGES.get(page, {page} if page in DIRECT else None)
    if modules is None and page not in GLOBAL_PAGES:
        return dict(files)
    preset_positions = uses_preset_positions(case)
    return {name: value for name, value in files.items()
            if (name not in NAVIGATION_FILES or page in NAVIGATION_PAGES)
            and (name not in PRESET_FILES or preset_positions)
            and (page in GLOBAL_PAGES or relevant(name, modules, page)
                 or (settings and name == "src/setup/setup-pack.lua"))}

def relevant(name, modules, page):
    # Setup Pack operations do not construct ordinary addon UI until Studio is invoked.
    if name in {"src/setup/setup-pack.lua", "src/setup/setup-pack-library.lua", "src/setup/setup-studio.lua", "src/configuration/options/setup-studio-view.lua"}:
        return page in {"setup-studio", "studio-atlas", "studio-gallery", "sharing"}
    if name == "src/core/layout-metrics.lua":
        return bool(modules & {"bars", "castbars"})
    if name.startswith("src/modules/"):
        return name.split("/")[2] in modules
    # This validates serialized imports; it does not lay out ordinary UI regions.
    if name == "src/core/profile-schema.lua":
        return page == "sharing"
    return True

def compact_inventories(manifest):
    """Deduplicate authenticated inventories without changing pixels or source evidence."""
    from provenance import json_digest, capture_key
    history = inventory_history(manifest)
    captures = [record for parent in manifest.get("renders", []) for record in [parent, *parent.get("frames", [])] if "inputs" in record]
    for capture in captures:
        inputs = capture.get("inputs", {})
        files = inputs.get("addonFiles")
        if files is not None:
            if capture.get("key") != capture_key(inputs):
                raise RuntimeError("Changed capture provenance: " + capture.get("id", str(capture.get("value"))))
            key = json_digest(files)
            if key != inputs.get("addon"):
                raise RuntimeError("Changed addon provenance: " + capture.get("id", str(capture.get("value"))))
            history[key] = files
            inputs.pop("addonFiles")
            # The original addon digest already identifies this exact inventory.
            capture["key"] = capture_key(inputs)
    manifest["addonInventories"] = history

def inventory_history(manifest):
    """Keep original inventory evidence; never relabel old pixels with current source hashes."""
    history = dict(manifest.get("addonInventories", {}))
    files = manifest.get("addonFiles")
    if files is not None:
        from provenance import json_digest
        history[json_digest(files)] = files
    return history

def recorded_addon_inputs(case, capture, manifest):
    from provenance import json_digest
    inputs = capture.get("inputs", {})
    files = inputs.get("addonFiles")
    if files is None:
        files = inventory_history(manifest).get(inputs.get("addon"))
    if files is None or json_digest(files) != inputs.get("addon"):
        raise RuntimeError("Missing or changed addon provenance: " + case["id"])
    return addon_inputs(case, files)
