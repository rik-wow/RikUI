-- Nested navigation and independently bounded content inside the native Settings canvas.
local core, options, scroll = RikUI, RikUI.Options, RikUI.Scroll
local PAD, HEADER, FOOTER, NAV_WIDTH, GAP, NAV_ROW = 16, 94, 42, 140, 20, 28
local WIDTH, HEIGHT = 760, 560
-- The fixed sidebar groups; a class area (options-class.lua) declares its own group, named after
-- the class, and takes the place after Interface.
local BASE_GROUPS = { "Interface", "Gameplay", "System" }
local CLASS_GROUP_POSITION = 2
local panel, category
local applySearch
local function shown(frame, value) options.SetShown(frame, value) end

function options.Panel() return panel end

-- A page's hint may follow state (the class area names the class it shows).
local function pageDescription(page)
    local description = page.description
    if type(description) == "function" then description = description() end
    return description or "Customize this part of your interface."
end

local function groupLabel(group)
    local label = options.GroupLabel and options.GroupLabel(group)
    return label or group
end

local function pendingReload()
    local total, seen = 0, {}
    for _, page in ipairs(panel.pages) do
        local count = 0
        for _, row in ipairs(page.list.rows) do
            if row.pending then
                count=count+1
                local key=row.spec.key or row
                if type(key)=="string" then key=key:gsub("^page%.module%.","module.") end
                if not seen[key] then seen[key]=true;total=total+1 end
            end
        end
        page.tab.badge:SetText(tostring(count))
        shown(page.tab.badge, count > 0)
        page.tab.text:ClearAllPoints()
        page.tab.text:SetPoint("LEFT", 10, 0)
        page.tab.text:SetPoint("RIGHT", count > 0 and -24 or -4, 0)
    end
    return total
end

function options.Refresh()
    if not panel then return end
    for _, page in ipairs(panel.pages) do options.RefreshList(page.list) end
    local pending = pendingReload()
    local profile = core.CharDB and core.CharDB.profile or "Default"
    local message = pending > 0 and (pending .. (pending == 1 and " change needs reload" or " changes need reload"))
        or "Changes save automatically"
    local issue = core.Store and core.Store.BackupIssue and core.Store.BackupIssue()
    if issue then message = issue .. (pending > 0 and " | Reload needed" or "") end
    panel.status:SetText(profile .. " | " .. message)
    if panel.current and panel.pages[panel.current] then panel.hint:SetText(pageDescription(panel.pages[panel.current])) end
    shown(panel.reload, pending > 0)
    local combat = InCombatLockdown()
    panel.reload:SetEnabled(not combat)
    panel.reload:SetAlpha(combat and 0.4 or 1)
    panel.reload.text:SetText(combat and "After combat" or "Reload UI")
    if applySearch then applySearch() end
end

-- Sidebar groups in order: the fixed three, with any group a page adds (the class area) after Interface.
local function groupOrder(pages)
    local order, known = {}, {}
    for index, group in ipairs(BASE_GROUPS) do order[index], known[group] = group, true end
    local extra = 0
    for _, page in ipairs(pages) do
        if not known[page.group] then
            known[page.group] = true
            table.insert(order, CLASS_GROUP_POSITION + extra, page.group)
            extra = extra + 1
        end
    end
    return order
end

local function navigationLayout()
    local y = 0
    for _, group in ipairs(panel.groupOrder) do
        local header = panel.groups[group]
        header:ClearAllPoints(); header:SetPoint("TOPLEFT", 0, -y)
        header.label:SetText(groupLabel(group))
        core.Media.SetIcon(header.disclosure, header.collapsed and "chevron-right" or "chevron-down")
        y = y + NAV_ROW
        for _, page in ipairs(panel.pages) do
            if page.group == group then
                shown(page.tab, not header.collapsed and not page.filtered)
                page.tab.top = y
                page.tab:ClearAllPoints(); page.tab:SetPoint("TOPLEFT", 10, -y)
                if not header.collapsed and not page.filtered then y = y + NAV_ROW end
            end
        end
        y = y + 12
    end
    scroll.SetContentHeight(panel.nav, y)
end

function options.ShowPage(index, skipRefresh)
    local selected = panel and panel.pages[index]
    if not selected or selected.filtered then return end
    if options.CloseDropdown then options.CloseDropdown() end
    for position, page in ipairs(panel.pages) do
        shown(page.frame, position == index); shown(page.tab.selected, position == index)
        shown(page.tab.rail, position == index)
        page.tab.text:SetTextColor(position == index and 0.4 or 0.8, position == index and 0.8 or 0.83, 1)
    end
    panel.current = index
    panel.groups[selected.group].collapsed = false
    navigationLayout()
    scroll.Reveal(panel.nav, selected.tab.top, NAV_ROW)
    panel.title:SetText(selected.title)
    panel.hint:SetText(pageDescription(selected))
    options.SetFocus(panel, nil)
    if not skipRefresh then options.Refresh() end
end

local function matches(text, query)
    local haystack = tostring(text or ""):lower()
    for word in query:gmatch("%S+") do
        if not haystack:find(word, 1, true) then return false end
    end
    return true
end

local function filterPage(page, query)
    local whole = query == "" or matches(page.title, query)
    local count = 0
    for _, row in ipairs(page.list.rows) do
        local description = row.spec.getDescription and row.spec.getDescription() or row.spec.description
        local searchable = table.concat({ page.title or "", page.group or "",
            row.spec.label or "", description or "" }, " ")
        local hidden = row.spec.visible ~= nil and not row.spec.visible()
        row.filtered = hidden or (panel.onlyPending and not row.pending) or not (whole or matches(searchable, query))
        if not row.filtered then count = count + 1 end
    end
    page.filtered = count == 0 and (panel.onlyPending or not whole)
    options.ResizeList(page.list, page.list.width)
    return not page.filtered
end

applySearch = function()
    local query, first = panel.query or "", nil
    for index, page in ipairs(panel.pages) do
        if filterPage(page, query) then first = first or index end
    end
    if panel.focused and panel.focused.filtered then options.SetFocus(panel, nil) end
    panel.empty:SetText(panel.onlyPending and (query == "" and "No changes need reload."
        or "No pending changes match this search.") or "No settings match. Try a shorter search.")
    shown(panel.empty, not first)
    if first then
        local current = panel.pages[panel.current or first]
        local target = current.filtered and first or (panel.current or first)
        if panel.current ~= target or not panel.pages[target].frame:IsShown() then
            options.ShowPage(target, true)
        end
    else
        for _, page in ipairs(panel.pages) do page.frame:Hide(); page.tab.selected:Hide(); page.tab.rail:Hide() end
    end
    navigationLayout()
    shown(panel.clearSearch, query ~= "")
    panel.pendingOnly.text:SetText(panel.onlyPending and "All settings" or "Needs reload")
end

function options.Search(text)
    if not panel then return end
    panel.query = (text or ""):lower():match("^%s*(.-)%s*$")
    options.CloseDropdown(); options.SetFocus(panel, nil)
    options.Refresh()
end

local function navigationButton(index, page)
    local button = CreateFrame("Button", nil, panel.nav.content)
    button:SetSize(NAV_WIDTH - 24, NAV_ROW)
    button.selected = options.Flat(button, "BACKGROUND", { 0.1, 0.23, 0.3, 0.8 })
    button.rail = button:CreateTexture(nil, "OVERLAY")
    button.rail:SetTexture(core.Skin.FLAT)
    button.rail:SetVertexColor(0.4, 0.8, 1, 1)
    button.rail:SetPoint("TOPLEFT", 0, -4); button.rail:SetPoint("BOTTOMLEFT", 0, 4)
    button.rail:SetWidth(3)
    core.Motion.BindHover(button)
    button.badge = options.Text(button, "small")
    button.badge:SetPoint("RIGHT", -4, 0); button.badge:SetTextColor(1, 0.78, 0.3); button.badge:Hide()
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
    list.scroll, list.popupHost, list.keyboardPanel = pane, panel, panel
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
    panel.navBacking:SetWidth(navWidth + PAD)
    if panel.empty then
        panel.empty:ClearAllPoints()
        panel.empty:SetPoint("TOPLEFT", navWidth + GAP + PAD + 12, -HEADER - 48)
        panel.empty:SetWidth(math.max(1, width - navWidth - GAP - PAD * 2 - 24))
    end
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
    for _, group in ipairs(panel.groupOrder) do
        local button = CreateFrame("Button", nil, panel.nav.content)
        button:SetSize(NAV_WIDTH - 14, NAV_ROW)
        core.Motion.BindHover(button)
        button.label = options.Text(button, "small")
        button.label:SetPoint("LEFT", 20, 0); button.label:SetTextColor(0.4, 0.75, 0.9)
        button.disclosure = core.Media.Icon(button, "chevron-down", 10, "OVERLAY")
        button.disclosure:SetPoint("LEFT", 3, 0)
        button.disclosure:SetVertexColor(0.4, 0.75, 0.9, 1)
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
    panel.chrome = core.Skin.WindowChrome(panel, HEADER - 6, FOOTER)
    panel.navBacking = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
    panel.navBacking:SetTexture(core.Skin.FLAT)
    panel.navBacking:SetVertexColor(0.04, 0.05, 0.07, 1)
    panel.navBacking:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -HEADER)
    panel.navBacking:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 1, FOOTER)
    panel.navRule = panel:CreateTexture(nil, "BORDER")
    panel.navRule:SetTexture(core.Skin.FLAT)
    panel.navRule:SetVertexColor(unpack(core.Skin.LINE))
    panel.navRule:SetPoint("TOPRIGHT", panel.navBacking, "TOPRIGHT")
    panel.navRule:SetPoint("BOTTOMRIGHT", panel.navBacking, "BOTTOMRIGHT")
    panel.navRule:SetWidth(1)
    panel.title = options.Text(panel, "heading", "RikUI")
    panel.title:SetTextColor(1, 0.82, 0)
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

local function movePage(delta)
    for distance = 1, #panel.pages do
        local index = ((panel.current - 1 + delta * distance) % #panel.pages) + 1
        if not panel.pages[index].filtered then options.ShowPage(index); return true end
    end
    return false
end

local function searchFocus(box)
    box.focusBorder = core.Skin.Outline(box, { 0.5, 0.85, 1, 1 }, 0, nil, "OVERLAY")
    local function paint(active)
        for _, edge in ipairs(box.focusBorder) do shown(edge, active) end
    end
    box:HookScript("OnEditFocusGained", function() paint(true) end)
    box:HookScript("OnEditFocusLost", function() paint(false) end)
    box:HookScript("OnHide", function() paint(false) end)
    paint(false)
end

local function createSearch()
    local box = CreateFrame("EditBox", nil, panel)
    box:SetAutoFocus(false); box:SetMaxLetters(100); box:SetText("")
    box:SetPoint("TOPLEFT", PAD, -60); box:SetPoint("TOPRIGHT", -184, -60); box:SetHeight(24)
    box:SetTextInsets(8, 8, 0, 0); core.Media.Font(box, "label")
    options.Flat(box, "BACKGROUND", { 0.07, 0.09, 0.12, 1 })
    options.Border(box, { 0.25, 0.4, 0.5, 1 })
    searchFocus(box)
    box.placeholder = options.Text(box, "small", "Search settings")
    box.placeholder:SetPoint("LEFT", 8, 0)
    box:SetScript("OnTextChanged", function(self)
        shown(self.placeholder, self:GetText() == "")
        options.Search(self:GetText())
    end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus(); options.Search("") end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:HookScript("OnHide", function(self) self:ClearFocus() end)
    panel.search = box
    panel.clearSearch = footerButton("X", 24, function() box:SetText(""); options.Search("") end)
    panel.clearSearch:SetPoint("TOPRIGHT", -146, -60); panel.clearSearch:Hide()
    panel.pendingOnly = footerButton("Needs reload", 122, function()
        panel.onlyPending = not panel.onlyPending
        options.Search(panel.query)
    end)
    panel.pendingOnly:SetPoint("TOPRIGHT", -PAD, -60)
    panel.empty = options.Text(panel, "label", "No settings match. Try a shorter search.")
    panel.empty:SetHeight(72); panel.empty:SetJustifyH("CENTER"); panel.empty:SetWordWrap(true)
    panel.empty:SetTextColor(0.72, 0.8, 0.88); panel.empty:Hide()
end

local function register()
    if panel then return end
    panel = CreateFrame("Frame", "RikUIOptionsPanel", UIParent)
    panel:Hide(); panel:SetSize(WIDTH, HEIGHT)
    core.Motion.BindEntrance(panel, true)
    local declared = options.Pages()
    panel.groupOrder = groupOrder(declared)
    createFurniture(); createNavigation()
    panel.pages = {}
    for index, page in ipairs(declared) do panel.pages[index] = createPage(index, page) end
    createSearch()
    panel.MovePage = movePage
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
        panel.onlyPending = false
        panel.search:SetText(""); options.Search("")
        for index, page in ipairs(panel.pages) do if page.id == id then options.ShowPage(index); break end end
    end
    options.Refresh()
end

core:RegisterEvent("PLAYER_LOGIN", register)
core:RegisterEvent("PLAYER_REGEN_ENABLED", options.Refresh)
core:RegisterEvent("PLAYER_REGEN_DISABLED", options.Refresh)
core:RegisterCommand("config", function() options.Open() end, "Open RikUI settings")
