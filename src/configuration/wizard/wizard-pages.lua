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

local function preset(state) return core.Presets[state.class] end

local function resolved(state)
    if not preset(state) then return nil end
    return (core.Setup.Resolve(state.class, state.role))
end

-- 1. Welcome
wizard.AddPage({ key = "welcome", title = "Welcome to RikUI", build = function(page, state)
    page.lead = paragraph(page, "heading", className(state) .. " detected.")
    page.body = paragraph(page, "label", "RikUI will set up your action bars, keybinds, macros, game settings and screen "
        .. "layout in one go.\n\nThe next pages ask what you want. Nothing is applied until the last page, and "
        .. "/rik undo reverts all of it afterwards.\n\nSkip setup closes this for good on this character; /rik setup "
        .. "brings it back.", page.lead, 16)
end })

-- 2. Role
local function guessedRole(state)
    local known = preset(state)
    if not known then return nil end
    local role = core.Setup.GuessRole and core.Setup.GuessRole(state.class) or nil
    return known.roles[role] and role or known.roleOrder[1]
end

local function paintRole(page, state)
    for _, card in ipairs(page.cards) do card:SetChosen(card.role == state.role) end
    page.bar:SetShown(state.role ~= nil)
    if state.role then preview.FillBar(page.bar, resolved(state), UnitLevel("player")) end
end

local function roleCard(page, state, role, index)
    local card = controls.Card(page, 240, 56, function(self)
        state.role = self.role
        paintRole(page, state)
    end)
    card.role = role
    card:SetPoint("TOPLEFT", page.intro, "BOTTOMLEFT", (index - 1) * 252, -16)
    card.label = controls.Text(card, "label", preset(state).roles[role].label)
    card.label:SetPoint("CENTER", card, "CENTER", 0, 0)
    return card
end

wizard.AddPage({ key = "role", title = "Your role", build = function(page, state)
    local known = preset(state)
    page.intro = paragraph(page, "label", known and "Pick what you play. It decides which abilities go on the bars; you "
        .. "can switch later with /rik role." or "")
    page.note = paragraph(page, "label", known and "" or "There is no preset for " .. className(state) .. " yet, so the "
        .. "bars stay as they are. Keybinds, settings and the layout are still set up.")
    page.cards = {}
    for index, role in ipairs(known and known.roleOrder or {}) do page.cards[index] = roleCard(page, state, role, index) end
    page.barTitle = paragraph(page, "small", known and "Your main bar. Dim abilities come later as you level; RikUI places "
        .. "them when you learn them." or "")
    page.barTitle:SetPoint("TOPLEFT", page.intro, "BOTTOMLEFT", 0, -100)
    page.bar = preview.Bar(page)
    page.bar:SetPoint("TOPLEFT", page.barTitle, "BOTTOMLEFT", 0, -12)
end, refresh = function(page, state)
    if state.role == nil then state.role = guessedRole(state) end
    paintRole(page, state)
end })

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
    for _, cap in ipairs(page.mouse) do cap:SetActive(state.mouse45) end
    for _, cap in ipairs(page.strafe) do cap:SetActive(state.strafe) end
    page.mouseCheck:Refresh()
    page.strafeCheck:Refresh()
end

wizard.AddPage({ key = "keys", title = "Keybinds", build = function(page, state)
    page.intro = paragraph(page, "label", "Every ability sits on a key you reach without moving your hand: 1-5 and the "
        .. "keys around WASD, then the same keys with Shift and with Ctrl.")
    page.tiers = {}
    for index, tier in ipairs(TIERS) do
        page.tiers[index] = tierRow(page, tier, 50 + (index - 1) * (CAP_HEIGHT + TIER_GAP))
    end
    local extras = 50 + #TIERS * (CAP_HEIGHT + TIER_GAP) + 16
    page.mouse = capRow(page, { "M4", "M5" }, extras, 130)
    page.strafe = capRow(page, { "A", "D" }, extras, 130 + 3 * (CAP_WIDTH + CAP_GAP))
    page.mouseCheck = controls.Check(page, 520, "I have Mouse 4/5 (off moves Charge and the interrupt to Shift-G and Ctrl-G)",
        function() return state.mouse45 end, function(value) state.mouse45 = value; paintKeys(page, state) end)
    page.mouseCheck:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -extras - CAP_HEIGHT - 24)
    page.strafeCheck = controls.Check(page, 520, "Also rebind A/D to strafe instead of turn",
        function() return state.strafe end, function(value) state.strafe = value; paintKeys(page, state) end)
    page.strafeCheck:SetPoint("TOPLEFT", page.mouseCheck, "BOTTOMLEFT", 0, -6)
end, refresh = paintKeys })

-- 4. Layout
local CARD_WIDTH, CARD_GAP, PICTURE_INSET = 186, 12, 8

local function paintLayout(page, state)
    for _, card in ipairs(page.cards) do card:SetChosen(card.name == state.layoutPreset) end
    page.description:SetText(layouts[state.layoutPreset].description)
    page.keep:Refresh()
end

local function layoutCard(page, state, name, index)
    local width = CARD_WIDTH - 2 * PICTURE_INSET
    local card = controls.Card(page, CARD_WIDTH, width * 768 / 1365 + 2 * PICTURE_INSET + 22, function(self)
        state.layoutPreset = self.name
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
    local left = 0
    for _, entry in ipairs(preview.Legend) do
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
    page.intro = paragraph(page, "label", "Where everything sits. Every frame has a place in each layout, with the same "
        .. "margins and gaps. Hold the lock key afterwards to move a single frame.")
    page.cards = {}
    for index, name in ipairs(layouts.Order) do page.cards[index] = layoutCard(page, state, name, index) end
    page.description = paragraph(page, "label", "", page.cards[1], 14)
    legend(page, page.description)
    page.keep = controls.Check(page, 420, "Keep my current positions (skip the layout)",
        function() return state.keepPositions end, function(value) state.keepPositions = value end)
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
        MODULE_COLUMNS, MODULE_WIDTH, 0)
    page.settings = column(page, "Game settings", settingEntries(state), 1, SETTING_WIDTH,
        MODULE_COLUMNS * MODULE_WIDTH + 20)
end, refresh = function(page)
    for _, check in ipairs(page.modules) do check:Refresh() end
    for _, check in ipairs(page.settings) do check:Refresh() end
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
    return "Keybinds: the three key tiers, " .. (state.mouse45 and "with Mouse 4/5" or "without Mouse 4/5")
        .. (state.strafe and ", A/D strafe" or ", A/D left alone") .. "; saved for this character only"
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
    local byStep = { macros = macrosLine(known), bars = barsLine(state, known), binds = bindsLine(state),
        cvars = settingsLine(state), layout = state.keepPositions and "Layout: your positions are kept"
            or "Layout: " .. layouts[state.layoutPreset].label }
    local lines = {}
    for _, step in ipairs(STEP_ORDER) do
        lines[#lines + 1] = state.steps[step] and byStep[step] or STEP_LABELS[step] .. ": skipped"
    end
    lines[#lines + 1] = modulesLine(state)
    return lines
end

local function paintSummary(page, state)
    page.body:SetText(table.concat(pages.Summary(state), "\n\n"))
    for _, check in ipairs(page.steps) do check:Refresh() end
end

wizard.AddPage({ key = "summary", title = "Summary", build = function(page, state)
    page.intro = paragraph(page, "label", "This is what Apply changes. Untick a step to leave that part alone.")
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
