-- Planner window furniture. The controller and local browsing state live elsewhere.
local core, planner = RikUI, RikUI.QuestPlanner
local view = planner.View
local ui = { WIDTH = 840, HEIGHT = 600, PAGE_SIZE = 8, LEFT = 330, RIGHT = 462, BODY = 386 }
view.WindowUI = ui
local ACCENT, MUTED = { 0.4, 0.8, 1 }, { 0.62, 0.7, 0.76 }

function ui.Text(parent, value, role, width, height)
    local label = parent:CreateFontString(nil, "OVERLAY")
    core.Media.Font(label, role or "small")
    if core.Media.font and core.Media.sizes then label:SetFont(core.Media.font, core.Media.Size(role or "small"), "") end
    label:SetText(value or ""); label:SetJustifyH("LEFT"); label:SetJustifyV("TOP")
    label:SetWordWrap(true); label:SetSize(width, height)
    return label
end

function ui.Button(parent, value, width, action, primary)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 28)
    button.surface = core.Skin.ButtonSurface(button, primary)
    button.label = ui.Text(button, value, "small", width - 16, 16)
    button.label:SetPoint("CENTER"); button.label:SetJustifyH("CENTER"); button.label:SetJustifyV("MIDDLE")
    button.label:SetWordWrap(false)
    button:SetHighlightTexture(core.Media.highlight, "ADD")
    button:SetScript("OnClick", function(self) if self:IsEnabled() then action(self) end end)
    return button
end

function ui.Card(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)
    core.Skin.Fill(frame, { 0.055, 0.075, 0.095, 1 })
    return frame
end

local function summary(parent)
    local card = ui.Card(parent, 808, 124)
    card:SetPoint("TOPLEFT", 16, -54)
    card.expanded = true
    card.eyebrow = ui.Text(card, "CURRENT OBJECTIVE", "small", 430, 14)
    card.eyebrow:SetPoint("TOPLEFT", 16, -10); card.eyebrow:SetTextColor(unpack(ACCENT))
    card.title = ui.Text(card, "", "heading", 470, 24); card.title:SetPoint("TOPLEFT", 16, -30)
    card.detail = ui.Text(card, "", "small", 470, 28); card.detail:SetPoint("TOPLEFT", 16, -56)
    card.status = ui.Text(card, "", "label", 278, 38); card.status:SetPoint("TOPRIGHT", -16, -28)
    card.status:SetTextColor(unpack(ACCENT))
    card.arrowHint = ui.Text(card, "", "small", 278, 18); card.arrowHint:SetPoint("TOPRIGHT", -16, -68)
    card.arrowHint:SetTextColor(unpack(MUTED))
    card.pause = ui.Button(card, "Pause", 72, function() view.Command(planner.Controller.Policy().paused and "resume" or "pause") end)
    card.pause:SetPoint("BOTTOMLEFT", 16, 10)
    card.map = ui.Button(card, "Map", 60, function() view.Command("map") end); card.map:SetPoint("LEFT", card.pause, "RIGHT", 8, 0)
    card.arrowToggle = ui.Button(card, "Arrow", 96, function() view.Command("arrow " .. (planner.Controller.Policy().arrow and "off" or "on")) end)
    card.arrowToggle:SetPoint("LEFT", card.map, "RIGHT", 8, 0)
    view.AddFloorControl(card)
    card:EnableMouse(true); card:SetScript("OnEnter", view.SummaryTooltip)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return card
end

local function questList(parent)
    local panel = ui.Card(parent, ui.LEFT, ui.BODY)
    panel:SetPoint("TOPLEFT", 16, -194)
    local heading = ui.Text(panel, "Quests", "label", 180, 22); heading:SetPoint("TOPLEFT", 12, -12)
    parent.filter = ui.Button(panel, "All quests", 116, view.NextFilter); parent.filter:SetPoint("TOPRIGHT", -12, -8)
    parent.rows = {}
    for index = 1, ui.PAGE_SIZE do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(ui.LEFT - 24, 32); row:SetPoint("TOPLEFT", 12, -46 - (index - 1) * 36)
        row.selected = core.Skin.Fill(row, { 0.1, 0.23, 0.3, 1 }); row.selected:Hide()
        row.label = ui.Text(row, "", "small", ui.LEFT - 44, 16); row.label:SetPoint("TOPLEFT", 8, -2); row.label:SetWordWrap(false)
        row.meta = ui.Text(row, "", "small", ui.LEFT - 44, 12); row.meta:SetPoint("BOTTOMLEFT", 8, 0)
        row.meta:SetTextColor(unpack(MUTED)); row.meta:SetWordWrap(false)
        row:SetHighlightTexture(core.Media.highlight, "ADD"); row:SetScript("OnClick", view.Browse)
        parent.rows[index] = row
    end
    parent.previous = ui.Button(panel, "Previous", 84, function() view.ChangePage(-1) end)
    parent.previous:SetPoint("BOTTOMLEFT", 12, 12)
    parent.following = ui.Button(panel, "Next", 64, function() view.ChangePage(1) end); parent.following:SetPoint("BOTTOMRIGHT", -12, 12)
    parent.page = ui.Text(panel, "", "small", 80, 20); parent.page:SetPoint("BOTTOM", 10, 14); parent.page:SetJustifyH("CENTER")
    parent.empty = ui.Text(panel, "", "small", ui.LEFT - 32, 180); parent.empty:SetPoint("TOPLEFT", 16, -60)
    return panel
end

local function selectedActions(parent)
    local actions = { { "route", "Do now", true }, { "log", "Open quest log" },
        { "pin", "Pin" }, { "defer", "Defer" }, { "skip", "Skip" }, { "area", "Avoid area" } }
    for index, spec in ipairs(actions) do
        local key = spec[1]
        local button = ui.Button(parent, spec[2], 211, function() view.ActOnSelection(key) end, spec[3])
        button:SetPoint("BOTTOMLEFT", 16 + ((index - 1) % 2) * 219, 84 - math.floor((index - 1) / 2) * 36)
        parent[key] = button
    end
end

local function selection(parent)
    local panel = ui.Card(parent, ui.RIGHT, ui.BODY)
    panel:SetPoint("TOPRIGHT", -16, -194)
    panel.caption = ui.Text(panel, "SELECTED QUEST", "small", 430, 14)
    panel.caption:SetPoint("TOPLEFT", 16, -12); panel.caption:SetTextColor(unpack(MUTED))
    panel.title = ui.Text(panel, "", "heading", 430, 48); panel.title:SetPoint("TOPLEFT", 16, -34)
    panel.state = ui.Text(panel, "", "small", 430, 22); panel.state:SetPoint("TOPLEFT", 16, -84)
    panel.state:SetTextColor(unpack(ACCENT))
    panel.scroll = core.Scroll.Create(panel); panel.scroll:SetPoint("TOPLEFT", 16, -114)
    panel.scroll:SetSize(430, 146)
    panel.body = ui.Text(panel.scroll.content, "", "label", 416, 1); panel.body:SetPoint("TOPLEFT")
    selectedActions(panel)
    return panel
end

local function routeDetails(parent)
    local panel = ui.Card(parent, 808, ui.BODY)
    panel:SetPoint("TOPLEFT", 16, -194); panel:Hide()
    local heading = ui.Text(panel, "Route details", "heading", 760, 24); heading:SetPoint("TOPLEFT", 16, -14)
    local hint = ui.Text(panel, "Current objective, route evidence and data coverage.", "small", 760, 20)
    hint:SetPoint("TOPLEFT", 16, -42); hint:SetTextColor(unpack(MUTED))
    panel.scroll = core.Scroll.Create(panel); panel.scroll:SetPoint("TOPLEFT", 16, -76); panel.scroll:SetSize(776, 254)
    parent.instructions = ui.Text(panel.scroll.content, "", "label", 762, 1); parent.instructions:SetPoint("TOPLEFT")
    parent.instructionScroll, parent.instructionBody = panel.scroll.view, panel.scroll.content
    parent.retry = ui.Button(panel, "Retry route", 104, function() view.Command("retry") end)
    parent.retry:SetPoint("BOTTOMLEFT", 16, 16)
    parent.copy = ui.Button(panel, "Copy data", 104, function() view.Command("export") end)
    parent.copy:SetPoint("LEFT", parent.retry, "RIGHT", 8, 0)
    parent.restoreArea = ui.Button(panel, "", 260, function(self) if self.mapID then view.Command("avoid " .. self.mapID) end end)
    parent.restoreArea:SetPoint("BOTTOMRIGHT", -16, 16)
    return panel
end

function ui.Create()
    local window = CreateFrame("Frame", "RikUIQuestPlannerWindow", UIParent)
    window:Hide(); window:SetSize(ui.WIDTH, ui.HEIGHT); window:SetClampedToScreen(true)
    window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG"); window:EnableMouse(true)
    core.Skin.Fill(window, { 0.025, 0.035, 0.05, 0.99 }); core.Skin.Outline(window)
    window.heading = ui.Text(window, "Quest planner", "heading", 480, 30); window.heading:SetPoint("TOPLEFT", 20, -16)
    window.close = ui.Button(window, "Close", 64, function() window:Hide() end); window.close:SetPoint("TOPRIGHT", -16, -12)
    window.preferences = ui.Button(window, "Preferences", 108, function() planner.PlanControls.Open() end)
    window.preferences:SetPoint("RIGHT", window.close, "LEFT", -8, 0)
    window.summary = summary(window); window.arrow = window.summary.arrowToggle
    window.detailToggle = ui.Button(window.summary, "Route details", 112, view.ToggleDetails)
    window.detailToggle:SetPoint("BOTTOMRIGHT", -16, 10)
    window.automatic = ui.Button(window.summary, "Use automatic", 118, function() view.Command("route auto") end)
    window.automatic:SetPoint("RIGHT", window.detailToggle, "LEFT", -8, 0)
    window.questList = questList(window); window.selection = selection(window); window.details = routeDetails(window)
    window:SetScript("OnShow", function()
        local width, height = UIParent:GetWidth() or ui.WIDTH + 32, UIParent:GetHeight() or ui.HEIGHT + 32
        window:SetScale(math.min(1, width / (ui.WIDTH + 32), height / (ui.HEIGHT + 32)))
    end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "RikUIQuestPlannerWindow") end
    return window
end
