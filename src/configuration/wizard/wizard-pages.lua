-- The wizard's six pages. Each one only reads and writes wizard.State; what Apply does with the
-- state is src/configuration/wizard/wizard.lua's business. Pages build on first show and repaint on every show.
local core, wizard, controls, preview = RikUI, RikUI.Wizard, RikUI.WizardControls, RikUI.WizardPreview
local layouts = core.Layouts
local pages = {}
core.WizardPages = pages

local CONTENT_WIDTH, LINE_GAP = 780, 10
local STEP_LABELS = { macros = "Macros", bars = "Action bars", binds = "Keybinds", cvars = "Settings", layout = "Layout" }
local STEP_ORDER = { "macros", "bars", "binds", "cvars", "layout" }

local function paragraph(parent, role, text, anchor, gap)
    local region = controls.Text(parent, role, text, role == "small" and controls.MUTED or nil)
    region:SetWidth(CONTENT_WIDTH)
    region:SetJustifyH("LEFT")
    if anchor then region:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or LINE_GAP))
    else region:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0) end
    return region
end

local function className(state)
    local name = UnitClass("player")
    return type(name) == "string" and name or tostring(state.class)
end

local function preset(state)
    local source = core.Setup.Source(state.class, state.presetName)
    if source and state.presetName and state.presetName ~= "" and core.Setup.ValidateSharedPreset then
        if #core.Setup.ValidateSharedPreset(source) > 0 then return nil end
    end
    return source
end
local function resolved(state)
    if not preset(state) then return nil end
    return (core.Setup.Resolve(state.class, state.role, state.presetName))
end

-- 1. Character setup: current interface is the default, not a replacement preset.
local function startCard(page, state, path, left, title, detail, icon)
    local card = controls.Card(page, 384, 156, function() wizard.ChoosePath(path) end)
    card:SetPoint("TOPLEFT",  left, -94)
    card.icon = core.Media.Icon(card, icon, 28, "ARTWORK")
    card.icon:SetPoint("TOPLEFT", 16, -16)
    card.label = controls.Text(card, "heading", title)
    card.label:SetPoint("TOPLEFT", 16, -54); card.label:SetWidth(352); card.label:SetJustifyH("LEFT")
    card.detail = controls.Text(card, "label", detail, controls.MUTED)
    card.detail:SetPoint("TOPLEFT", 16, -84); card.detail:SetWidth(352); card.detail:SetJustifyH("LEFT")
    return card
end

wizard.AddPage({ key = "welcome", title = "Set up this character", build = function(page, state)
    page.lead = paragraph(page, "heading", className(state) .. " · level " .. UnitLevel("player"))
    page.body = paragraph(page, "label", "Keep the interface you already use, or choose actions for this character.\nNothing is applied until the last page.", page.lead, 12)
    page.keepCard = startCard(page, state, "keep", 0, "Keep my setup",
        "Keep actions, macros and bindings.\nReview layout, then finish.", "character")
    page.actionsCard = startCard(page, state, "actions", 396, "Set up character actions",
        "Preview a class preset and role.\nChoose bindings separately.", "talents")
    page.advanced = controls.Check(page, 760, "Also review modules and game settings",
        function() return state.advanced end, function(value) state.advanced = value; wizard.Go(1) end)
    page.advanced:SetPoint("TOPLEFT", 0, -276)
    page.scope = paragraph(page, "small", "Your current profile is shared with any characters using it.\nBars and bindings are character-specific; layout and modules belong to the profile.\nGame settings may affect your account. Skip setup leaves everything as it is.")
    page.scope:ClearAllPoints(); page.scope:SetPoint("TOPLEFT", 0, -316)
end, refresh = function(page, state)
    page.keepCard:SetChosen(state.path == "keep")
    page.actionsCard:SetChosen(state.path == "actions")
    page.advanced:Refresh()
end })

-- 2. Role
local function guessedRole(state)
    local known = preset(state)
    if not known then return nil end
    local role = core.Setup.GuessRole and core.Setup.GuessRole(state.class, state.presetName) or nil
    return known.roles[role] and role or known.roleOrder[1]
end

local function paintRole(page, state)
    for _, card in ipairs(page.cards) do card:SetChosen(card.role == state.role) end
    page.bar:SetShown(state.role ~= nil)
    local known = state.role and resolved(state)
    local choices = preview.Pages(known)
    page.previewIndex = math.min(page.previewIndex or 1, math.max(1, #choices))
    local choice = choices[page.previewIndex]
    page.barTitle:SetText(choice and (choice.label .. " · " .. page.previewIndex .. " / " .. #choices) or "")
    page.previous:SetDisabled(not choice or page.previewIndex == 1)    page.following:SetDisabled(not choice or page.previewIndex == #choices)
    page.previous:SetShown(choice ~= nil)
    page.following:SetShown(choice ~= nil)
    page.detail:SetText(choice and "Click or hover an ability to inspect it. Dim slots are not learned yet; key labels preview the optional binding scheme." or "")
    preview.FillBar(page.bar, known, UnitLevel("player"), choice and choice.key, { mouse45 = state.mouse45 })
end

local function roleCard(page, state, role, index)
    local card = controls.Card(page, 240, 56, function(self)
        state.role = self.role
        paintRole(page, state)
    end)
    card.role = role
    card:SetPoint("TOPLEFT", page.intro, "BOTTOMLEFT", ((index - 1) % 3) * 252, -16 - math.floor((index - 1) / 3) * 68)
    card.label = controls.Text(card, "label", preset(state).roles[role].label)
    card.label:SetPoint("CENTER", card, "CENTER", 0, 0)
    return card
end

local function refreshRoles(page, state)
    local known = preset(state)
    if page.source ~= known or page.state ~= state then
        for _, card in ipairs(page.cards) do card:Hide() end
        page.cards, page.source, page.state = {}, known, state
        for index, role in ipairs(known and known.roleOrder or {}) do page.cards[index] = roleCard(page, state, role, index) end
        page.barTitle:ClearAllPoints()
        page.barTitle:SetPoint("TOPLEFT", page.intro, "BOTTOMLEFT", 0, -(32 + math.ceil(#page.cards / 3) * 68))
    end
    local sourceLabel = state.presetName ~= "" and state.presetName or "Bundled"
    for _, entry in ipairs(core.PresetLibrary and core.PresetLibrary.Entries(state.class) or {}) do
        if entry.value == state.presetName then sourceLabel = entry.text end
    end    page.presetButton.label:SetText(sourceLabel .. " (click to change)")
    page.note:SetText(known and "" or (state.presetName ~= "" and "Preset unavailable. Choose another preset."
        or "There is no preset for " .. className(state) .. " yet; bars stay as they are."))
    if state.role == nil then state.role = guessedRole(state) end
    paintRole(page, state)
end

local function cyclePreset()
    local state = wizard.State
    local entries = core.PresetLibrary and core.PresetLibrary.Entries(state.class) or { { value = "" } }
    local selected = 0
    for i, entry in ipairs(entries) do if entry.value == state.presetName then selected = i end end
    local ok, reason = wizard.SelectPreset(entries[selected % #entries + 1].value)
    if not ok then core:Print(reason) end
end

wizard.AddPage({ key = "role", title = "Your role", build = function(page, state)
    local known = preset(state)
    page.intro = paragraph(page, "label", known and "Pick what you play. It decides which abilities go on the bars; you "
        .. "can switch later with /rik role." or "")
    page.note = paragraph(page, "label", known and "" or "There is no preset for " .. className(state) .. " yet, so the "
        .. "bars stay as they are. Keybinds, settings and the layout are still set up.")
    page.presetButton = controls.Button(page, "", cyclePreset)
    page.presetButton:SetWidth(CONTENT_WIDTH); page.presetButton:SetPoint("TOPLEFT", 0, 0)
    page.intro:ClearAllPoints(); page.intro:SetPoint("TOPLEFT", 0, -38)
    page.note:ClearAllPoints(); page.note:SetPoint("TOPLEFT", 0, -76)
    page.cards = {}
    page.barTitle = paragraph(page, "small", "")
    page.barTitle:SetPoint("TOPLEFT", page.intro, "BOTTOMLEFT", 0, -(32 + math.ceil(#page.cards / 3) * 68))
    page.bar = preview.Bar(page)
    page.bar:SetPoint("TOPLEFT", page.barTitle, "BOTTOMLEFT", 0, -12)
    page.previous = controls.Button(page, "Previous bar", function()        page.previewIndex = page.previewIndex - 1; paintRole(page, state)
    end)
    page.previous:SetPoint("TOPLEFT", page.bar, "BOTTOMLEFT", 0, -30)
    page.following = controls.Button(page, "Next bar", function()
        page.previewIndex = page.previewIndex + 1; paintRole(page, state)
    end)
    page.following:SetPoint("LEFT", page.previous, "RIGHT", 8, 0)
    page.detail = paragraph(page, "small", "", page.previous, 12)
    page.detail:SetHeight(38)
    page.bar.onInspect = function(description) page.detail:SetText(description) end
end, refresh = refreshRoles })

-- 3. Keybinds
local CAP_WIDTH, CAP_HEIGHT, CAP_GAP, TIER_GAP = 44, 30, 6, 12
local TIERS = { { "ACTIONBUTTON", 11, "Main bar" }, { "MULTIACTIONBAR1BUTTON", 9, "Shift: cooldowns" },
    { "MULTIACTIONBAR2BUTTON", 12, "Ctrl: utility" } }
local SHORT = { ["SHIFT%-"] = "S-", ["CTRL%-"] = "C-", ["BUTTON"] = "M" }

local function shortKey(key)
    for pattern, short in pairs(SHORT) do key = key:gsub(pattern, short) end
    return key
end

local function capRow(page, texts, top, left)
    local row = {}
    for index, text in ipairs(texts) do
        row[index] = controls.KeyCap(page, CAP_WIDTH, CAP_HEIGHT, text, true)
        row[index]:SetPoint("TOPLEFT", page, "TOPLEFT", left + (index - 1) * (CAP_WIDTH + CAP_GAP), -top)
    end
    return row
end
local function tierRow(page, tier, top)
    local texts = {}
    for index = 1, tier[2] do texts[index] = shortKey(core.Bindings.Scheme[tier[1] .. index]) end
    local title = controls.Text(page, "small", tier[3], controls.MUTED)
    title:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -top - 8)
    return capRow(page, texts, top, 130)
end

local function paintKeys(page, state)
    if page.adopt then page.adopt:Refresh() end
    for _, cap in ipairs(page.mouse) do cap:SetActive(state.mouse45) end
    for _, cap in ipairs(page.strafe) do cap:SetActive(state.strafe) end
    local known = resolved(state)
    local row = known and known.bars.bar2 or {}
    page.mouseCheck.label:SetText("Mouse 4/5: " .. preview.Name(row[10]) .. " / " .. preview.Name(row[11]))
    page.fallback:SetText("Off: Shift-G / Ctrl-G instead. Ctrl-G's utility slot and the first pet key then have no assigned key.")
    page.mouseCheck:Refresh()
    page.strafeCheck:Refresh()
end

wizard.AddPage({ key = "keys", title = "Keybinds", build = function(page, state)
    page.intro = paragraph(page, "label", "Keep your current bindings, or use the scheme below.\nHover a key to inspect its action; Shift and Ctrl select the other bars.")
    page.adopt = controls.Check(page, 760, "Replace this character's bindings with these keys",
        function() return state.steps.binds end, function(value) state.steps.binds = value; paintKeys(page, state) end)
    page.adopt:SetPoint("TOPLEFT", 0, -52)
    page.tiers = {}
    for index, tier in ipairs(TIERS) do
        page.tiers[index] = tierRow(page, tier, 88 + (index - 1) * (CAP_HEIGHT + TIER_GAP))
    end
    local extras = 88 + #TIERS * (CAP_HEIGHT + TIER_GAP) + 16
    page.mouse = capRow(page, { "M4", "M5" }, extras, 130)
    page.strafe = capRow(page, { "A", "D" }, extras, 130 + 3 * (CAP_WIDTH + CAP_GAP))
    page.mouseCheck = controls.Check(page, 760, "",
        function() return state.mouse45 end, function(value) state.mouse45 = value; paintKeys(page, state) end)
    page.mouseCheck:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -extras - CAP_HEIGHT - 24)    page.strafeCheck = controls.Check(page, 520, "Also rebind A/D to strafe instead of turn",
        function() return state.strafe end, function(value) state.strafe = value; paintKeys(page, state) end)
    page.fallback = paragraph(page, "small", "", page.mouseCheck, 6)
    page.strafeCheck:SetPoint("TOPLEFT", page.fallback, "BOTTOMLEFT", 0, -10)
    page.inspect = paragraph(page, "small", "Preview only. Bindings change only when the replacement checkbox is checked.", page.strafeCheck, 14)
    for row, caps in ipairs(page.tiers) do
        for index, cap in ipairs(caps) do
            cap:EnableMouse(true)
            cap:SetScript("OnEnter", function()
                local known = resolved(state)
                local key = ({ "main", "bar2", "bar3" })[row]
                local entry = known and known.bars[key] and known.bars[key][index]
                page.inspect:SetText(cap.label:GetText() .. " · " .. preview.Name(entry) .. " (proposed binding)")
            end)
        end
    end
end, refresh = paintKeys })

-- 4. Layout
local CARD_WIDTH, CARD_GAP, PICTURE_INSET = 186, 12, 8

local function paintLayout(page, state)
    for _, card in ipairs(page.cards) do card:SetChosen(not state.keepPositions and card.name == state.layoutPreset) end
    page.description:SetText(state.keepPositions and "Current positions kept. You can adjust individual frames after finishing." or layouts[state.layoutPreset].description)
    page.keep:Refresh()
end

local function layoutCard(page, state, name, index)
    local width = CARD_WIDTH - 2 * PICTURE_INSET
    local card = controls.Card(page, CARD_WIDTH, width * 768 / 1365 + 2 * PICTURE_INSET + 22, function(self)
        state.layoutPreset, state.keepPositions, state.steps.layout = self.name, false, true
        paintLayout(page, state)
    end)
    card.name = name
    card:SetPoint("TOPLEFT", page.intro, "BOTTOMLEFT", (index - 1) * (CARD_WIDTH + CARD_GAP), -14)
    card.picture = preview.Layout(card, name, width)
    card.picture:SetPoint("TOP", card, "TOP", 0, -PICTURE_INSET)
    card.title = controls.Text(card, "label", layouts[name].label)
    card.title:SetPoint("BOTTOM", card, "BOTTOM", 0, 7)
    return card
end

local function legend(page, anchor)
    local left = 0    for _, entry in ipairs(preview.Legend) do
        local swatch = page:CreateTexture(nil, "ARTWORK")
        swatch:SetTexture(RikUI.Skin.FLAT)
        swatch:SetVertexColor(entry[2][1], entry[2][2], entry[2][3], 1)
        swatch:SetSize(10, 10)
        swatch:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", left, -14)
        local label = controls.Text(page, "small", entry[1], controls.MUTED)
        label:SetPoint("LEFT", swatch, "RIGHT", 5, 0)
        left = left + 24 + #entry[1] * 6
    end
end

wizard.AddPage({ key = "layout", title = "Screen layout", build = function(page, state)
    page.intro = paragraph(page, "label", "Keep your current arrangement, or select a layout map.\nThe maps show frame groups, not live game contents. You can practice moving actual frames after finishing.")
    page.cards = {}
    for index, name in ipairs(layouts.Order) do page.cards[index] = layoutCard(page, state, name, index) end
    page.description = paragraph(page, "label", "", page.cards[1], 14)
    legend(page, page.description)
    page.keep = controls.Check(page, 420, "Keep my current positions (skip the layout)",
        function() return state.keepPositions end, function(value) state.keepPositions, state.steps.layout = value, not value; paintLayout(page, state) end)
    page.keep:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
end, refresh = paintLayout })

-- 5. Modules and settings
local MODULE_COLUMNS, MODULE_WIDTH, SETTING_WIDTH = 3, 156, 290

local function moduleLabel(name)
    local module = core.Modules[name]
    return module and module.title or (name:sub(1, 1):upper() .. name:sub(2))
end
local function moduleEntries(state)
    local entries = {}
    for _, name in ipairs(core.Setup.StateKeys(state.modules)) do
        entries[#entries + 1] = { name = name, text = moduleLabel(name), get = function() return state.modules[name] end,
            set = function(value) state.modules[name] = value end }
    end
    return entries
end

local function settingEntries(state)
    local entries = {}
    for _, entry in ipairs(core.CVars.List) do
        entries[#entries + 1] = { name = entry.name, text = entry.label, get = function() return state.cvars[entry.name] end,
            set = function(value) state.cvars[entry.name] = value end }
    end
    return entries
end

local function column(page, title, entries, columns, width, left)
    local heading = controls.Text(page, "label", title, RikUI.Skin.GOLD)
    heading:SetPoint("TOPLEFT", page, "TOPLEFT", left, 0)
    local holder = CreateFrame("Frame", nil, page)
    holder:SetSize(columns * width, 10)
    holder:SetPoint("TOPLEFT", page, "TOPLEFT", left, -24)
    local checks = controls.CheckGrid(holder, entries, columns, width)
    for index, check in ipairs(checks) do check.name = entries[index].name end
    return checks
end

wizard.AddPage({ key = "modules", title = "Modules and settings", build = function(page, state)
    page.modules = column(page, "Interface pieces RikUI replaces (a change needs a reload)", moduleEntries(state),
        MODULE_COLUMNS, MODULE_WIDTH, 0)    page.settings = column(page, "Game settings (account-wide)", settingEntries(state), 1, SETTING_WIDTH,
        MODULE_COLUMNS * MODULE_WIDTH + 20)
    page.enableSettings = controls.Check(page, 760, "Apply checked game settings (otherwise leave them unchanged)",
        function() return state.steps.cvars end, function(value) state.steps.cvars = value end)
    page.enableSettings:SetPoint("BOTTOMLEFT", 0, 0)
end, refresh = function(page)
    for _, check in ipairs(page.modules) do check:Refresh() end
    for _, check in ipairs(page.settings) do check:Refresh() end
    page.enableSettings:Refresh()
end })

-- 6. Summary
local function countBars(known)
    local abilities, bars = 0, 0
    for _, slots in pairs(known.bars) do
        bars = bars + 1
        for _ in pairs(slots) do abilities = abilities + 1 end
    end
    return abilities, bars
end

local function barsLine(state, known)
    if not known then return "Bars: no preset for " .. className(state) .. " yet, nothing to place" end
    local abilities, bars = countBars(known)
    return string.format("Bars: %d abilities on %d bar pages for %s; known ones now, the rest as you learn them",
        abilities, bars, preset(state).roles[state.role].label)
end

local function macrosLine(known)
    local names = known and core.Setup.StateKeys(known.macros) or {}
    if #names == 0 then return "Macros: none" end
    return "Macros: " .. table.concat(names, ", ")
end

local function bindsLine(state)
    return "Keybinds: the three key tiers, " .. (state.mouse45 and "with Mouse 4/5" or "without Mouse 4/5")        .. (state.strafe and ", A/D strafe" or ", A/D left alone") .. "; saved for this character only"
end

local function settingsLine(state)
    local chosen = 0
    for _, on in pairs(state.cvars) do
        if on then chosen = chosen + 1 end
    end
    return "Settings: " .. chosen .. " of " .. #core.CVars.List .. " game settings"
end

local function modulesLine(state)
    local switched = {}
    for _, name in ipairs(core.Setup.StateKeys(state.modules)) do
        if state.modules[name] ~= (core.Profile.modules[name] ~= false) then
            switched[#switched + 1] = name .. (state.modules[name] and " on" or " off")
        end
    end
    if #switched == 0 then return "Modules: unchanged" end
    return "Modules: " .. table.concat(switched, ", ") .. " (needs a reload)"
end

-- What Apply will change, one line per step; a step switched off says so.
function pages.Summary(state)
    local known = resolved(state)
    if known and not state.role then state.role = known.role end
    local byStep = { macros = macrosLine(known), bars = barsLine(state, known), binds = bindsLine(state),
        cvars = settingsLine(state), layout = state.keepPositions and "Layout: your positions are kept"
            or "Layout: " .. layouts[state.layoutPreset].label }
    local lines = {}
    for _, step in ipairs(STEP_ORDER) do
        lines[#lines + 1] = state.steps[step] and byStep[step] or STEP_LABELS[step] .. ": skipped"
    end    lines[#lines + 1] = modulesLine(state)
    return lines
end

local function paintSummary(page, state)
    page.body:SetText(table.concat(pages.Summary(state), "\n\n"))
    for _, check in ipairs(page.steps) do check:Refresh() end
end

wizard.AddPage({ key = "summary", title = "Review changes", build = function(page, state)
    page.intro = paragraph(page, "label", "Only checked steps will change. Uncheck anything you want to keep.\nLayout and module changes affect characters using this profile.")
    local entries = {}
    for index, step in ipairs(STEP_ORDER) do
        entries[index] = { text = STEP_LABELS[step], get = function() return state.steps[step] end,
            set = function(value) state.steps[step] = value; paintSummary(page, state) end }
    end
    local holder = CreateFrame("Frame", nil, page)
    holder:SetSize(CONTENT_WIDTH, 22)
    holder:SetPoint("TOPLEFT", page.intro, "BOTTOMLEFT", 0, -12)
    page.steps = controls.CheckGrid(holder, entries, #entries, 150)
    page.body = paragraph(page, "label", "", holder, 16)
end, refresh = paintSummary })
-- Completion has real next actions. These open existing settings/movers, never a second editor.
function wizard.ShowCompletion(parent, result, needsReload)
    for _, page in ipairs(wizard.Pages) do if page.frame then page.frame:Hide() end end
    local panel = wizard.Completion
    if not panel then
        panel = CreateFrame("Frame", nil, parent); panel:SetAllPoints()
        wizard.Completion = panel
        panel.heading = paragraph(panel, "heading", "Character setup complete")
        panel.detail = paragraph(panel, "label", "", panel.heading, 12)
        local function action(left, title, body, icon, callback)
            local card = controls.Card(panel, 240, 170, callback)
            card:SetPoint("TOPLEFT", left, -130)
            core.Media.Icon(card, icon, 28, "ARTWORK"):SetPoint("TOPLEFT", 16, -16)
            card.title = controls.Text(card, "label", title)
            card.title:SetPoint("TOPLEFT", 16, -60); card.title:SetWidth(208); card.title:SetJustifyH("LEFT")
            card.note = controls.Text(card, "small", body, controls.MUTED)
            card.note:SetPoint("TOPLEFT", 16, -90); card.note:SetWidth(208); card.note:SetJustifyH("LEFT")
            return card
        end
        action(0, "Practice moving frames", "Drag your player frame,\naction bar and chat.\nFinish when you're ready.", "settings", function() wizard.BeginPractice() end)
        action(264, "Configure features", "Enable or disable modules\nin regular settings.\nChanges show reload status.", "character", function()
            wizard.Close(); core.Options.Open("modules")
        end)
        action(528, "Appearance and text", "Adjust fonts, text size,\ncontrast and density\nin regular settings.", "talents", function()
            wizard.Close(); core.Options.Open("appearance")
        end)
        panel.help = paragraph(panel, "small", "/rik setup reopens character setup. /rik config opens settings.")
        panel.help:ClearAllPoints(); panel.help:SetPoint("TOPLEFT", 0, -332)
    end
    panel.detail:SetText((result.unchanged and "Your current actions, bindings and positions were kept."
        or "Selected setup operations finished. /rik undo restores their previous values.")
        .. (needsReload and "\nModule changes need a reload. You can adjust other settings first." or "\nChoose an optional next step, or close and play."))
    panel:Show()
end

local PRACTICE = {
    { key = "player", title = "Move your player frame", text = "Drag the labeled player frame.\nRelease to save its position.\nShift or Alt bypasses snapping." },
    { key = "main", title = "Position your action bar", text = "Drag the main action bar.\nKeep your actions and bindings.\nBar shape is in Settings > Bars." },
    { key = "chat", title = "Position chat", text = "Drag chat to a comfortable spot.\nGrid, snapping and exact coordinates\nare in Settings > General." },
}
local practice, ownedKey
local function restorePractice()
    if ownedKey then core.Layout.SetUnlocked(ownedKey, false); ownedKey = nil end
end
function wizard.EndPractice()
    restorePractice()
    if practice then practice:Hide() end
end
local function practiceStep(index)
    restorePractice()
    local item = PRACTICE[index]
    if not item then wizard.EndPractice(); return end
    practice.index = index
    practice.title:SetText(index .. " / " .. #PRACTICE .. " · " .. item.title)
    practice.body:SetText(item.text)
    practice.next.label:SetText(index == #PRACTICE and "Finish" or "Next frame")
    if core.Layout.Groups[item.key] and core.Layout.Rect(item.key) then
        if not core.Layout.IsUnlocked(item.key) and core.Layout.SetUnlocked(item.key, true) then ownedKey = item.key end
    else
        practice.body:SetText("This frame is not available with your enabled modules.\nUse Next frame or Finish to continue.")
    end
end
function wizard.BeginPractice()
    if InCombatLockdown() then return false end
    if not practice then
        practice = CreateFrame("Frame", "RikUICharacterPractice", UIParent)
        practice:SetSize(360, 176); practice:SetPoint("TOPRIGHT", -20, -110)
        practice:SetFrameStrata("DIALOG"); practice:SetClampedToScreen(true); practice:EnableMouse(true)
        core.Skin.WindowChrome(practice, 36, 40)
        practice.title = controls.Text(practice, "label", "", core.Skin.GOLD)
        practice.title:SetPoint("TOPLEFT", 16, -12); practice.title:SetWidth(328); practice.title:SetJustifyH("LEFT")
        practice.body = controls.Text(practice, "label", "")
        practice.body:SetPoint("TOPLEFT", 16, -50); practice.body:SetWidth(328); practice.body:SetJustifyH("LEFT")
        practice.next = controls.Button(practice, "Next frame", function()
            if not InCombatLockdown() then practiceStep(practice.index + 1) end
        end)
        practice.next:SetPoint("BOTTOMRIGHT", -16, 12)
        practice.close = controls.Button(practice, "Stop", wizard.EndPractice)
        practice.close:SetPoint("BOTTOMLEFT", 16, 12)
        practice:SetScript("OnHide", restorePractice)
        if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "RikUICharacterPractice" end
        wizard.Practice = practice
    end
    wizard.Close(); practice:Show(); practiceStep(1)
    return true
end
core:RegisterEvent("PLAYER_REGEN_DISABLED", wizard.EndPractice)
