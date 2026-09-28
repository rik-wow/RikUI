-- Details of RikUI's settings panel: a page open and laid out, and a holder that shows a run of its
-- rows. RikUI builds and draws the rows; these only choose what the crop shows.

-- A settings page, open and laid out.
function RikRenderSettingsPage(pageId)
    RikUI.Options.Open(pageId)
    RikUIOptionsPanel:SetParent(UIParent)
    RikRenderCenter(RikUIOptionsPanel)
    RikUIOptionsPanel:Show()
    RikRenderResize(RikUIOptionsPanel)
    RikUI.Options.Open(pageId)
    return RikUIOptionsPanel
end

-- A row by its setting key, or a heading by its label.
local function findRow(rows, key)
    for _, row in ipairs(rows) do
        if row.spec.key == key or (row.spec.type == "heading" and row.spec.label == key) then return row end
    end
    error("No settings row " .. key)
end

local function page(pageId)
    for _, entry in ipairs(RikUI.Options.Panel().pages) do
        if entry.id == pageId then return entry end
    end
    error("No settings page " .. pageId)
end

-- A detail of a settings page: the rows from firstKey down, with pad units above and to the left, in a
-- holder of the given size (the rest of the panel lies outside the crop). A row below the visible part
-- of the page is scrolled to the top first, as the player would scroll to it. The simulator lays the
-- scrolled rows out when it draws, so the holder is offset by the distance scrolled.
function RikRenderSettingsRows(pageId, firstKey, name, width, height, pad)
    local panel, entry = RikUI.Options.Panel(), page(pageId)
    local first = findRow(entry.list.rows, firstKey)
    local below = entry.frame:GetTop() - first:GetTop()
    local scrolled = 0
    if below + height > entry.frame:GetHeight() then
        local before = entry.scroll.offset or 0
        RikUI.Scroll.SetOffset(entry.scroll, before + below)
        scrolled = (entry.scroll.offset or 0) - before
    end
    pad = pad or 8
    return RikRenderDetail(panel, name, first:GetLeft() - panel:GetLeft() - pad,
        panel:GetTop() - first:GetTop() - scrolled - pad, width, height)
end

-- A frame chosen in the General page's "Frame to position" dropdown, so the nudge buttons are enabled.
function RikRenderNudgeState(key)
    RikRenderSetOption("general", "layoutFrame", key or "player")
    RikUI.Options.Refresh()
end

-- A layout change to undo: applying the layout the screen already has records the undo without moving anything.
function RikRenderUndoReady()
    assert(RikUI.Layout.ApplyPreset(RikUI.Layout.MatchingPreset() or "centered"))
    RikUI.Options.Refresh()
end
