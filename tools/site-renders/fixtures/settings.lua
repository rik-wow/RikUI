-- States of RikUI's settings panel, utility menu and preset library: a search, a change waiting for
-- reload, a confirmation row, a second profile and an imported preset. RikUI builds and draws every
-- row; these only put the panel in the state a player would.

local function pageEntry(pageId)
    for _, entry in ipairs(RikUI.Options.Panel().pages) do
        if entry.id == pageId then return entry end
    end
    error("No settings page " .. pageId)
end

local function row(pageId, key)
    for _, candidate in ipairs(pageEntry(pageId).list.rows) do
        if candidate.spec.key == key then return candidate end
    end
    error("No settings row " .. key .. " on " .. pageId)
end

-- Text typed into the panel's search box.
function RikRenderOptionsSearch(text)
    local panel = RikUI.Options.Panel()
    panel.search:SetText(text)
    RikUI.Options.Search(text)
    panel.search.placeholder:SetShown(text == "")
    return panel
end

-- A setting that needs a reload (the font), with the panel filtered to changes waiting for a reload.
function RikRenderPendingReload(pageId)
    RikRenderSetOption("general", "font", "game")
    local panel = RikUI.Options.Panel()
    panel.onlyPending = true
    RikUI.Options.Search("")
    RikUI.Options.Refresh()
    return panel
end

-- A button that asks first, clicked once: the row shows its question with Confirm and Cancel.
function RikRenderOptionsConfirm(pageId, key)
    local target = row(pageId, key)
    RikUI.Options.Activate(target)
    RikUI.Options.Refresh()
    return target
end

-- A second profile, chosen in the Delete section.
function RikRenderSecondProfile(name)
    assert(RikUI.Options.CreateProfile(name))
    RikRenderSetOption("profiles", "deleteName", name)
    RikUI.Options.Refresh()
end

-- A preset imported from another player, chosen in the Imported presets section. The bundled paladin
-- preset stands in for the shared text a player would paste.
function RikRenderImportedPreset(name)
    local preset = RikUI.Setup.CopyState(RikUI.Presets.PALADIN)
    local ok, reason = RikUI.PresetLibrary.Add(name, preset)
    assert(ok, "Import failed: " .. tostring(reason))
    RikRenderSetOption("setup", "importedPreset", name)
    RikUI.Options.Refresh()
end

-- One group of the open utility menu, in a holder of the given size.
function RikRenderShellGroup(group, name, width, height, pad)
    RikUI.Shell.Open()
    local panel = RikUI.Shell.Panel
    RikRenderCenter(panel)
    RikRenderResize(panel)
    local surface = assert(panel.groupSurfaces[group], "No menu group " .. group)
    pad = pad or 6
    local x = surface.fill:GetLeft() - panel:GetLeft() - pad
    local y = panel:GetTop() - surface.fill:GetTop() - pad
    return RikRenderDetail(panel, name, x, y, width, height)
end

-- The launcher on the minimap, the way the player finds it.
function RikRenderLauncher(name, left, bottom, width, height)
    RikRenderMinimapTiles()
    RikUI.Shell.Anchor()
    local holder = RikRenderGroup(name, { RikUIMinimap, RikUI.Shell.Launcher }, left, bottom, width, height)
    RikRenderLayerBacking(holder)
    return holder
end
