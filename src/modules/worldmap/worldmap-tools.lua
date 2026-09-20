-- Compact map toolbar and paged quest drawer. All new interaction belongs to addon frames.
local core, map = RikUI, RikUI.WorldMap
local nav, skin, media = map.Navigation, RikUI.Skin, RikUI.Media
local ROWS, WIDTH, ROW_HEIGHT = 6, 296, 42
local toolbar, drawer, frame, pending
local page, lastMap = 1, nil
local function settings() return core.Profile.worldmap end
local function text(parent, label, role)
    local region = parent:CreateFontString(nil, "OVERLAY")
    media.Font(region, role or "small")
    region:SetText(label)
    region:SetJustifyH("LEFT")
    return region
end
local function tooltip(owner, title, detail)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    GameTooltip:AddLine(detail, 1, 1, 1, true)
    GameTooltip:Show()
end
local function button(parent, label, width, action, hint)
    local control = CreateFrame("Button", nil, parent)
    control:SetSize(width, 24)
    skin.Fill(control, skin.CONTROL)
    skin.Outline(control)
    control:SetHighlightTexture(media.highlight)
    control.label = text(control, label)
    control.label:SetPoint("CENTER")
    control:SetScript("OnClick", action)
    if hint then control:SetScript("OnEnter", function() tooltip(control, label, hint) end) end
    control:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return control
end
function map.SetOption(key, value)
    if type(settings()[key]) ~= "boolean" or type(value) ~= "boolean" then return end
    settings()[key] = value
    core:Changed()
    page = 1
    map.RefreshTools()
end
local function toggle(key) map.SetOption(key, not settings()[key]) end
local function rowEnter(row)
    if not row.quest then return end
    tooltip(row, row.quest.title, row.quest.location .. "\n"
        .. (row.quest.complete and "Ready to turn in" or "In progress")
        .. "\nClick: show quest and route\nShift-click: track / untrack")
end
local function createRows()
    drawer.rows = {}
    for index = 1, ROWS do
        local row = button(drawer, "", WIDTH - 16, function(self)
            if not self.quest then return end
            if IsShiftKeyDown() then nav.Watch(self.quest) else nav.Select(self.quest) end
            map.RequestTools()
        end)
        row:SetHeight(ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 8, -36 - (index - 1) * ROW_HEIGHT)
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", 8, -5)
        row.label:SetWidth(WIDTH - 34)
        row.label:SetWordWrap(false)
        row.detail = text(row, "")
        row.detail:SetPoint("BOTTOMLEFT", 8, 5)
        row.detail:SetWidth(WIDTH - 34)
        row.detail:SetWordWrap(false)
        row:SetScript("OnEnter", rowEnter)
        drawer.rows[index] = row
    end
end
local function renderRows()
    local id = nav.Call(frame.GetMapID, frame)
    if id ~= lastMap then page, lastMap = 1, id end
    local rows, empty = nav.Quests(id, settings().zoneOnly)
    local pages = math.max(1, math.ceil(#rows / ROWS))
    page = math.min(page, pages)
    drawer.title:SetText(string.format("Quests  %d   |   %d / %d", #rows, page, pages))
    drawer.empty:SetText(empty or "")
    for index, row in ipairs(drawer.rows) do
        local entry = rows[(page - 1) * ROWS + index]
        row.quest = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.label:SetText(entry.title)
            row.label:SetTextColor(entry.complete and 0.4 or 1, entry.complete and 1 or 0.82, 0.4)
            row.detail:SetText((entry.complete and "Turn in" or entry.watched and "Tracked" or "Quest") .. "  |  " .. entry.location)
        end
    end
    drawer.previous:SetEnabled(page > 1)
    drawer.next:SetEnabled(page < pages)
    drawer.filter.label:SetText(settings().zoneOnly and "This map" or "All quests")
end
function map.RefreshTools()
    if not toolbar then return end
    toolbar.fog.label:SetText(settings().fog and "Fog: on" or "Reveal all")
    local supported = map.Terrain.Available(frame)
    toolbar.fog:SetEnabled(supported or not settings().fog)
    local markers = nav.Markers()
    toolbar.markers.label:SetText(markers == nil and "Pins: N/A" or markers and "Pins: on" or "Pins: off")
    toolbar.markers:SetEnabled(type(markers) == "boolean")
    toolbar.quests.label:SetText(settings().quests and "Close list" or "Quest list")
    toolbar.coords:SetText(nav.Coordinates(frame))
    drawer:SetShown(settings().quests)
    if settings().quests then renderRows() end
    map.Terrain.Refresh(frame)
end
function map.RequestTools()
    if pending or not toolbar or not frame:IsShown() then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        if frame:IsShown() then map.RefreshTools() end
    end)
end
local function createDrawer()
    drawer = CreateFrame("Frame", nil, toolbar)
    drawer:SetSize(WIDTH, 330)
    drawer:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -4)
    drawer:EnableMouse(true)
    skin.Fill(drawer, { 0.035, 0.045, 0.06, 0.97 })
    skin.Outline(drawer)
    drawer.title = text(drawer, "", "label")
    drawer.title:SetPoint("TOPLEFT", 10, -11)
    drawer.empty = text(drawer, "")
    drawer.empty:SetPoint("TOPLEFT", 10, -44)
    drawer.empty:SetWidth(WIDTH - 20)
    createRows()
    drawer.previous = button(drawer, "Previous", 74, function() page = math.max(1, page - 1); renderRows() end)
    drawer.previous:SetPoint("BOTTOMLEFT", 8, 8)
    drawer.filter = button(drawer, "This map", 112, function() toggle("zoneOnly") end)
    drawer.filter:SetPoint("LEFT", drawer.previous, "RIGHT", 4, 0)
    drawer.next = button(drawer, "Next", 74, function() page = page + 1; renderRows() end)
    drawer.next:SetPoint("LEFT", drawer.filter, "RIGHT", 4, 0)
end
local function build()
    if toolbar then return end
    local canvas = frame:GetCanvasContainer()
    if not canvas then return end
    toolbar = CreateFrame("Frame", "RikUIMapTools", canvas)
    toolbar:SetSize(420, 48)
    toolbar:SetPoint("TOP", canvas, "TOP", 0, -36)
    toolbar:SetFrameLevel(canvas:GetFrameLevel() + 50)
    skin.Fill(toolbar, { 0.035, 0.045, 0.06, 0.95 })
    skin.Outline(toolbar)
    toolbar.fog = button(toolbar, "Fog: on", 82, function() toggle("fog") end,
        "Toggle normal exploration fog / reveal all terrain. Revealed areas are tinted blue. Exploration progress is unchanged. Unavailable for maps without terrain data.")
    toolbar.fog:SetPoint("TOPLEFT", 4, -4)
    toolbar.markers = button(toolbar, "Pins: on", 76, function() nav.ToggleMarkers(); map.RefreshTools() end,
        "Show or hide native quest objective markers. Quest locations are supplied by the game.")
    toolbar.markers:SetPoint("LEFT", toolbar.fog, "RIGHT", 4, 0)
    toolbar.quests = button(toolbar, "Quest list", 88, function() toggle("quests") end, "Browse quests and objective coordinates.")
    toolbar.quests:SetPoint("LEFT", toolbar.markers, "RIGHT", 4, 0)
    local player = button(toolbar, "Player", 76, function() nav.Player(frame) end, "Return to your current zone.")
    player:SetPoint("LEFT", toolbar.quests, "RIGHT", 4, 0)
    local back = button(toolbar, "Up", 70, function() nav.Parent(frame) end, "Go to the parent map.")
    back:SetPoint("LEFT", player, "RIGHT", 4, 0)
    toolbar.coords = text(toolbar, "")
    toolbar.coords:SetPoint("BOTTOMLEFT", 8, 5)
    local hint = text(toolbar, "Scroll to zoom  |  Right-click to go up")
    hint:SetPoint("BOTTOMRIGHT", -8, 5)
    createDrawer()
    map.Toolbar, map.Drawer = toolbar, drawer
    map.RefreshTools()
end
-- OnShow can run while the native canvas is still being sized. Finish on the
-- next frame, then rebuild native providers once with the settled dimensions.
local opening
local function opened()
    if opening then return end
    opening = true
    C_Timer.After(0, function()
        opening = false
        if not frame:IsShown() then return end
        core.Combat.Queue(function()
            if not frame:IsShown() then return end
            if type(frame.RefreshAll) == "function" then frame:RefreshAll(true) end
            build()
            map.RequestTools()
        end, "worldmap:tools")
    end)
end
local function attach()
    if frame then return end
    local candidate = WorldMapFrame
    if not candidate or type(candidate.GetCanvasContainer) ~= "function" then return end
    frame = candidate
    frame:HookScript("OnShow", opened)
    if type(frame.OnMapChanged) == "function" then hooksecurefunc(frame, "OnMapChanged", map.RequestTools) end
    local elapsed = 0
    frame:HookScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 or not toolbar then return end
        elapsed = 0
        toolbar.coords:SetText(nav.Coordinates(frame))
    end)
    if frame:IsShown() then opened() end
end
function map.EnableTools()
    attach()
    core:RegisterEvent("ADDON_LOADED", attach)
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_LIST_CHANGED",
        "CVAR_UPDATE", "MAP_EXPLORATION_UPDATED", "PLAYER_ENTERING_WORLD" }) do
        core:RegisterEvent(event, map.RequestTools)
    end
    hooksecurefunc(core, "SetProfile", map.RequestTools)
end
map.Options = { title = "World map", settings = {} }
for _, setting in ipairs({ { "fog", "Normal exploration fog (off reveals terrain)" },
    { "quests", "Show quest list on the map" }, { "zoneOnly", "Only list quests with locations on this map" } }) do
    local key, label = unpack(setting)
    table.insert(map.Options.settings, { type = "checkbox", key = "worldmap." .. key, label = label,
        get = function() return settings()[key] end, set = function(value) map.SetOption(key, value) end })
end
