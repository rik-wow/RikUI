-- /rik config pages built from implemented modules; controls come from src/configuration/options/options-widgets.lua.
local core, options = RikUI, RikUI.Options
local PANEL_NAME, PANEL_TITLE = "RikUIOptionsPanel", "RikUI"
local PAD, TITLE_HEIGHT, TAB_WIDTH, TAB_HEIGHT, TAB_GAP, CLOSE_SIZE = 16, 30, 140, 24, 4, 22
local STANDALONE_WIDTH, STANDALONE_HEIGHT = 680, 520
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.25, 3, 0.05
local BACKGROUND, TAB_TINT, SELECTED_TINT = { 0.03, 0.035, 0.045, 0.97 }, { 0.35, 0.38, 0.42, 1 }, { 1, 0.78, 0.3, 1 }
local KEY_HINT = "Tab or arrows move, Space toggles, Left/Right adjust"
local panel, category = nil, nil
local state = { newName = "", deleteName = nil }

local function copyTable(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copyTable(entry) end
    return result
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function trim(text)
    return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

local function run(command) SlashCmdList.RIKUI(command) end

local function selectProfile(name)
    if not InCombatLockdown() then return core:SetProfile(name) end
    core.Combat.Queue(function()
        local ok, reason = core:SetProfile(name)
        if not ok then core:Print(reason) end
    end)
    return nil, "Profile " .. name .. " will be selected when combat ends."
end

function options.CreateProfile(name, copyFrom)
    if not core.DB then return nil, "Still loading." end
    name = trim(name)
    if name == "" then return nil, "Enter a profile name." end
    if core.DB.profiles[name] then return nil, "Profile already exists: " .. name end
    local source = copyFrom and core.DB.profiles[copyFrom]
    core.DB.profiles[name] = source and copyTable(source) or {}
    return true
end

function options.DeleteProfile(name)
    if not core.DB then return nil, "Still loading." end
    if name == core.CharDB.profile then return nil, "Switch away from the active profile before deleting it." end
    if type(name) ~= "string" or not core.DB.profiles[name] then return nil, "Unknown profile." end
    core.DB.profiles[name] = nil
    if state.deleteName == name then state.deleteName = nil end
    return true
end

local function moduleTitle(name, module)
    return module.title or (name:sub(1, 1):upper() .. name:sub(2))
end

local function moduleToggle(name, module)
    return { type = "checkbox", key = "module." .. name, label = moduleTitle(name, module), reload = true,
        get = function() return core.Profile.modules[name] ~= false end,
        set = function(value) core.Profile.modules[name] = value == true end }
end

local function action(key, label, text, callback)
    return { type = "button", key = key, label = label, text = text, action = callback }
end

local function moveFrames()
    run("move")
    local moving = core.Layout.IsMoving and core.Layout.IsMoving()
    if moving and SettingsPanel and type(HideUIPanel) == "function" then HideUIPanel(SettingsPanel) end
end

local function layoutSpecs(specs)
    if not core.Layout then return end
    specs[#specs + 1] = { type = "heading", label = "Layout" }
    specs[#specs + 1] = { type = "slider", key = "scale", label = "Frame scale", protected = true,
        min = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP,
        get = function() return core.Layout.GetScale() end,
        set = function(value) return core.Layout.SetScale(value) end }
    if core.Layout.PresetOption then specs[#specs + 1] = core.Layout.PresetOption() end
    specs[#specs + 1] = action("move", "Frame positions", "Move frames", moveFrames)
    specs[#specs + 1] = action("reset", "Default positions", "Reset positions", function() run("move reset") end)
end

local function generalSpecs()
    local specs = { { type = "heading", label = "Modules" } }
    for _, name in ipairs(sortedKeys(core.Modules)) do specs[#specs + 1] = moduleToggle(name, core.Modules[name]) end
    layoutSpecs(specs)
    specs[#specs + 1] = { type = "heading", label = "Setup" }
    if core:HasCommand("resync") then
        specs[#specs + 1] = action("resync", "Preset spell slots", "Re-sync", function() run("resync") end)
    end
    if core:HasCommand("setup") then
        specs[#specs + 1] = action("wizard", "First-login wizard", "Re-run wizard", function() run("setup") end)
    end
    return specs
end

local function moduleSpec(module, spec)
    local wrapped = {}
    for key, value in pairs(spec) do wrapped[key] = value end
    wrapped.disabled = function()
        return module.enabled == false or (spec.disabled and spec.disabled()) or false
    end
    return wrapped
end

local function modulePages(pages)
    for _, name in ipairs(sortedKeys(core.Modules)) do
        local module = core.Modules[name]
        local declared = module.Options
        if type(declared) == "table" and type(declared.settings) == "table" then
            local specs = {}
            for index, spec in ipairs(declared.settings) do specs[index] = moduleSpec(module, spec) end
            pages[#pages + 1] = { title = declared.title or moduleTitle(name, module), specs = specs }
        end
    end
end

local function profileEntries(excludeActive)
    local entries = {}
    for _, name in ipairs(sortedKeys(core.DB.profiles)) do
        if not excludeActive or name ~= core.CharDB.profile then
            entries[#entries + 1] = { value = name, text = name }
        end
    end
    return entries
end

local function cannotCreate()
    return state.newName == "" or core.DB.profiles[state.newName] ~= nil
end

local function createProfile(copy)
    local name = state.newName
    local ok, reason = options.CreateProfile(name, copy and core.CharDB.profile or nil)
    if not ok then core:Print(reason); return end
    state.newName = ""
    local selected, pending = selectProfile(name)
    core:Print(selected and ("Profile created and selected: " .. name) or pending)
end

local function deleteProfile()
    local ok, reason = options.DeleteProfile(state.deleteName)
    core:Print(ok and "Profile deleted." or reason)
end

local function profileSpecs()
    return {
        { type = "heading", label = "Profiles" },
        { type = "dropdown", key = "profile", label = "Active profile", values = function() return profileEntries(false) end,
            get = function() return core.CharDB.profile end, set = selectProfile },
        { type = "heading", label = "New profile" },
        { type = "text", key = "newName", label = "Name",
            get = function() return state.newName end, set = function(value) state.newName = trim(value) end },
        { type = "button", key = "create", label = "Start from defaults", text = "Create", disabled = cannotCreate,
            action = function() createProfile(false) end },
        { type = "button", key = "copy", label = "Copy the active profile", text = "Copy", disabled = cannotCreate,
            action = function() createProfile(true) end },
        { type = "heading", label = "Delete" },
        { type = "dropdown", key = "deleteName", label = "Profile to delete", values = function() return profileEntries(true) end,
            get = function() return state.deleteName end, set = function(value) state.deleteName = value end },
        { type = "button", key = "delete", label = "Remove the chosen profile", text = "Delete", action = deleteProfile,
            disabled = function()
                return state.deleteName == nil or state.deleteName == core.CharDB.profile or not core.DB.profiles[state.deleteName]
            end },
    }
end

function options.Pages()
    local pages = { { title = "General", specs = generalSpecs() } }
    modulePages(pages)
    pages[#pages + 1] = { title = "Profiles", specs = profileSpecs() }
    return pages
end

function options.Refresh()
    if not panel then return end
    for _, page in ipairs(panel.pages) do options.RefreshList(page.list) end
end

function options.ShowPage(index)
    for position, page in ipairs(panel.pages) do
        if position == index then page.frame:Show() else page.frame:Hide() end
        if position == index then page.tab.selected:Show() else page.tab.selected:Hide() end
    end
    panel.current = index
    options.SetFocus(panel, nil)
    options.RefreshList(panel.pages[index].list)
end

local function createTab(index, title)
    local tab = CreateFrame("Button", nil, panel)
    tab:SetSize(TAB_WIDTH, TAB_HEIGHT)
    tab:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + (index - 1) * (TAB_WIDTH + TAB_GAP), -(PAD + TITLE_HEIGHT))
    options.Border(tab, TAB_TINT)
    tab.selected = options.Flat(tab, "ARTWORK", SELECTED_TINT)
    tab.selected:SetAlpha(0.25)
    tab:SetHighlightTexture(core.Media.highlight, "ADD")
    tab.text = options.Text(tab, "label", title)
    tab.text:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab:SetScript("OnClick", function() options.ShowPage(index) end)
    return tab
end

local function createPage(index, page)
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(PAD + TITLE_HEIGHT + TAB_HEIGHT + PAD))
    frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD)
    frame:Hide()
    return { title = page.title, frame = frame, list = options.Render(frame, page.specs), tab = createTab(index, page.title) }
end

local function createClose()
    local close = CreateFrame("Button", nil, panel)
    close:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD)
    options.Border(close, TAB_TINT)
    close:SetHighlightTexture(core.Media.highlight, "ADD")
    close.text = options.Text(close, "label", "X")
    close.text:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnClick", function() panel:Hide() end)
    close:Hide()
    return close
end

local function createPanel()
    panel = CreateFrame("Frame", PANEL_NAME, UIParent)
    panel:Hide()
    options.Flat(panel, "BACKGROUND", BACKGROUND)
    panel.title = options.Text(panel, "heading", PANEL_TITLE)
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
    panel.hint = options.Text(panel, "small", KEY_HINT)
    panel.hint:SetPoint("LEFT", panel.title, "RIGHT", PAD, 0)
    panel.close = createClose()
    panel.pages = {}
    for index, page in ipairs(options.Pages()) do panel.pages[index] = createPage(index, page) end
    options.EnableKeyboard(panel, function()
        local page = panel.pages[panel.current]
        return page and page.list.rows or {}
    end)
    panel.OnRefresh = function() options.Refresh() end
    options.ShowPage(1)
    return panel
end

function options.Panel() return panel end

local function register()
    if panel then return end
    createPanel()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    category = Settings.RegisterCanvasLayoutCategory(panel, PANEL_TITLE)
    Settings.RegisterAddOnCategory(category)
end

local function openStandalone()
    panel:SetParent(UIParent)
    panel:SetSize(STANDALONE_WIDTH, STANDALONE_HEIGHT)
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel.close:Show()
    options.Refresh()
    panel:Show()
end

function options.Open()
    if not core.Profile then core:Print("Still loading."); return end
    register()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
        return
    end
    openStandalone()
end

core:RegisterEvent("PLAYER_LOGIN", register)
core:RegisterCommand("config", function() options.Open() end, "Open the options panel: /rik config")
