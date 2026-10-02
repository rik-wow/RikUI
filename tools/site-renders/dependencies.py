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

def addon_inputs(case, files):
    page = case.get("page")
    modules = PAGES.get(page, {page} if page in DIRECT else None)
    if modules is None and page not in GLOBAL_PAGES:
        return dict(files)
    return {name: value for name, value in files.items()
            if (name not in NAVIGATION_FILES or page in NAVIGATION_PAGES)
            and (page in GLOBAL_PAGES or relevant(name, modules, page))}

def relevant(name, modules, page):
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
    for capture in manifest.get("renders", []):
        inputs = capture.get("inputs", {})
        files = inputs.get("addonFiles")
        if files is not None:
            if capture.get("key") != capture_key(inputs):
                raise RuntimeError("Changed capture provenance: " + capture["id"])
            key = json_digest(files)
            if key != inputs.get("addon"):
                raise RuntimeError("Changed addon provenance: " + capture["id"])
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
