-- Nested navigation and independently bounded content inside the native Settings canvas.
local core, options, scroll = RikUI, RikUI.Options, RikUI.Scroll
local PAD, HEADER, FOOTER, NAV_WIDTH, GAP, NAV_ROW = 16, 58, 42, 140, 20, 28
local WIDTH, HEIGHT = 760, 560
local GROUPS = { "Interface", "Gameplay", "System" }
local panel, category
local function shown(frame, value) options.SetShown(frame, value) end

function options.Panel() return panel end

local function pendingReload()
    for _, page in ipairs(panel.pages) do
        for _, row in ipairs(page.list.rows) do if row.pending then return true end end
    end
    return false
end

function options.Refresh()
    if not panel then return end
    for _, page in ipairs(panel.pages) do options.RefreshList(page.list) end
    local pending = pendingReload()
    panel.status:SetText(pending and "Changes are ready to apply." or "Changes save automatically.")
    shown(panel.reload, pending)
    panel.reload:SetEnabled(not InCombatLockdown())
end

local function navigationLayout()
    local y = 0
    for _, group in ipairs(GROUPS) do
        local header = panel.groups[group]
        header:ClearAllPoints(); header:SetPoint("TOPLEFT", 0, -y)
        header.label:SetText((header.collapsed and "+  " or "-  ") .. group)
        y = y + NAV_ROW
        for _, page in ipairs(panel.pages) do
            if page.group == group then
                shown(page.tab, not header.collapsed)
                page.tab:ClearAllPoints(); page.tab:SetPoint("TOPLEFT", 10, -y)
                if not header.collapsed then y = y + NAV_ROW end
            end
        end
        y = y + 12
    end
    scroll.SetContentHeight(panel.nav, y)
end

function options.ShowPage(index)
    local selected = panel and panel.pages[index]
    if not selected then return end
    if options.CloseDropdown then options.CloseDropdown() end
    for position, page in ipairs(panel.pages) do
        shown(page.frame, position == index); shown(page.tab.selected, position == index)
        page.tab.text:SetTextColor(position == index and 0.4 or 0.8, position == index and 0.8 or 0.83, 1)
    end
    panel.current = index
    panel.groups[selected.group].collapsed = false
    navigationLayout()
    panel.title:SetText(selected.title)
    panel.hint:SetText(selected.description or "Customize this part of your interface.")
    options.SetFocus(panel, nil)
    options.Refresh()
end

local function navigationButton(index, page)
    local button = CreateFrame("Button", nil, panel.nav.content)
    button:SetSize(NAV_WIDTH - 24, NAV_ROW)
    button.selected = options.Flat(button, "BACKGROUND", { 0.1, 0.23, 0.3, 0.8 })
    core.Motion.BindHover(button)
    button.text = options.Text(button, "small", page.title)
    button.text:SetPoint("LEFT", 10, 0); button.text:SetPoint("RIGHT", -4, 0)
    button.text:SetJustifyH("LEFT"); button.text:SetWordWrap(false)
    button:SetScript("OnClick", function() options.ShowPage(index) end)
    return button
end

local function createPage(index, spec)
    local frame = CreateFrame("Frame", nil, panel)
    local pane = scroll.Create(frame)
    pane:SetAllPoints()
    local list = options.Render(pane.content, spec.specs)
    list.scroll, list.popupHost = pane, panel
    pane.OnResize = function(width) options.ResizeList(list, width) end
    pane.OnScroll = function() if options.CloseDropdown then options.CloseDropdown() end end
    local page = { id = spec.id, title = spec.title, group = spec.group, description = spec.description,
        frame = frame, scroll = pane, list = list, tab = navigationButton(index, spec) }
    core.Motion.BindEntrance(frame, false)
    frame:Hide()
    return page
end

function options.Resize(width, height)
    if not panel or not panel.pages then return end
    width, height = math.max(1, width or WIDTH), math.max(1, height or HEIGHT)
    local navWidth = math.min(NAV_WIDTH, width * 0.28)
    panel.nav:SetSize(navWidth, math.max(1, height - HEADER - FOOTER))
    for _, page in ipairs(panel.pages) do
        page.tab:SetWidth(math.max(1, navWidth - 24))
        page.frame:ClearAllPoints()
        page.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", navWidth + GAP + PAD, -HEADER)
        page.frame:SetSize(math.max(1, width - navWidth - GAP - PAD * 2), math.max(1, height - HEADER - FOOTER))
        page.scroll:SetSize(page.frame:GetWidth(), page.frame:GetHeight())
    end
end

local function createNavigation()
    panel.nav = scroll.Create(panel)
    panel.nav:SetPoint("TOPLEFT", PAD, -HEADER)
    panel.groups = {}
    for _, group in ipairs(GROUPS) do
        local button = CreateFrame("Button", nil, panel.nav.content)
        button:SetSize(NAV_WIDTH - 14, NAV_ROW)
        core.Motion.BindHover(button)
        button.label = options.Text(button, "small")
        button.label:SetPoint("LEFT"); button.label:SetTextColor(0.4, 0.75, 0.9)
        button:SetScript("OnClick", function() button.collapsed = not button.collapsed; navigationLayout() end)
        panel.groups[group] = button
    end
end

local function footerButton(label, width, callback)
    local button = CreateFrame("Button", nil, panel)
    button:SetSize(width, 24)
    options.Flat(button, "BACKGROUND", { 0.1, 0.2, 0.25, 1 })
    options.Border(button, { 0.25, 0.45, 0.55, 1 })
    button.text = options.Text(button, "small", label); button.text:SetPoint("CENTER")
    core.Motion.BindHover(button); button:SetScript("OnClick", callback)
    return button
end

local function createFurniture()
    options.Flat(panel, "BACKGROUND", { 0.035, 0.045, 0.06, 0.98 })
    panel.title = options.Text(panel, "heading", "RikUI")
    panel.title:SetTextColor(1, 0.82, 0)
    options.Border(panel, { 0.25, 0.28, 0.32, 1 })
    panel.titleRule = panel:CreateTexture(nil, "BORDER")
    panel.titleRule:SetTexture(core.Skin.FLAT)
    panel.titleRule:SetVertexColor(0.75, 0.57, 0.18, 0.65)
    panel.titleRule:SetPoint("TOPLEFT", PAD, -50); panel.titleRule:SetPoint("TOPRIGHT", -PAD, -50)
    panel.titleRule:SetHeight(1)
    panel.title:SetPoint("TOPLEFT", PAD, -PAD)
    panel.title:SetPoint("TOPRIGHT", -50, -PAD); panel.title:SetJustifyH("LEFT"); panel.title:SetWordWrap(false)
    panel.hint = options.Text(panel, "small", "")
    panel.hint:SetPoint("TOPLEFT", PAD, -36); panel.hint:SetPoint("TOPRIGHT", -PAD, -36)
    panel.hint:SetJustifyH("LEFT"); panel.hint:SetWordWrap(false); panel.hint:SetTextColor(0.6, 0.68, 0.75)
    panel.status = options.Text(panel, "small", "")
    panel.status:SetPoint("BOTTOMLEFT", PAD, 16)
    panel.status:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -140, 16)
    panel.status:SetJustifyH("LEFT"); panel.status:SetWordWrap(false)
    panel.reload = footerButton("Reload UI", 100, function() if not InCombatLockdown() then ReloadUI() end end)
    panel.reload:SetPoint("BOTTOMRIGHT", -PAD, 10); panel.reload:Hide()
    panel.close = footerButton("X", 24, function() core.Motion.CloseOwned(panel) end)
    panel.close:SetPoint("TOPRIGHT", -PAD, -12); panel.close:Hide()
end

local function register()
    if panel then return end
    panel = CreateFrame("Frame", "RikUIOptionsPanel", UIParent)
    panel:Hide(); panel:SetSize(WIDTH, HEIGHT)
    core.Motion.BindEntrance(panel, true)
    createFurniture(); createNavigation()
    panel.pages = {}
    for index, page in ipairs(options.Pages()) do panel.pages[index] = createPage(index, page) end
    options.EnableKeyboard(panel, function() return panel.pages[panel.current].list.rows end)
    panel.OnRefresh = options.Refresh
    panel:SetScript("OnSizeChanged", function(_, width, height) options.Resize(width, height) end)
    panel:HookScript("OnHide", function() if options.CloseDropdown then options.CloseDropdown() end end)
    panel:HookScript("OnShow", function() options.Resize(panel:GetWidth(), panel:GetHeight()); options.Refresh() end)
    options.Resize(WIDTH, HEIGHT); options.ShowPage(1)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "RikUI")
        Settings.RegisterAddOnCategory(category)
    end
end

function options.Open(id)
    if not core.Profile then core:Print("Still loading."); return end
    register()
    core.Motion.CancelClose(panel)
    if core.Shell then core.Shell.Close() end
    if category and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID())
    else
        panel:SetParent(UIParent); panel:SetSize(WIDTH, HEIGHT); panel:ClearAllPoints()
        panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG"); panel:SetClampedToScreen(true)
        panel.close:Show(); panel:Show()
    end
    if id then
        for index, page in ipairs(panel.pages) do if page.id == id then options.ShowPage(index); break end end
    end
    options.Refresh()
end

core:RegisterEvent("PLAYER_LOGIN", register)
core:RegisterEvent("PLAYER_REGEN_ENABLED", options.Refresh)
core:RegisterEvent("PLAYER_REGEN_DISABLED", options.Refresh)
core:RegisterCommand("config", function() options.Open() end, "Open RikUI settings")
