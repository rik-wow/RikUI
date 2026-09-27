-- The strip itself: RikUI icons with the client's cooldown swipe, charge edge and count from
-- duration objects. Rows fill from the bottom and each row is centred, as the native row was.
local core, panel = RikUI, RikUI.Cooldowns
local strip = {}
panel.Strip = strip
local SIZE, GAP, COLUMNS, WIDTH, MIN_ROWS, MAX_ROWS = 36, 4, 7, 280, 2, 3
local PITCH = SIZE + GAP
local TIMER_FONT, CHARGE_FONT, COUNT_FONT = 18, 12, 13
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local CELL_EDGE = { 0.3, 0.36, 0.43, 1 }
local DIM_ALPHA = 0.55  -- a pure aura cell whose aura is not up
local KEY, LABEL = "cooldowns", "Cooldowns"
strip.MAX_ENTRIES, strip.WIDTH, strip.SIZE = COLUMNS * MAX_ROWS, WIDTH, SIZE
local pool = {}

function strip.Height(rows) return math.max(MIN_ROWS, rows) * PITCH - GAP end
local function rowsFor(count) return math.ceil(count / COLUMNS) end

local function duration(widget, api, id, ignoreGCD)
    local ok, reason = core.Secret.Apply(function(value)
        if not core.Secret.IsSecret(value) and value == nil then widget:Clear()
        else widget:SetCooldownFromDurationObject(value, true) end
    end, C_Spell and C_Spell[api], id, ignoreGCD)
    if not ok then widget:Clear(); panel.Warn(api, reason) end
    return ok
end

local function setCount(button, value)
    button.count:SetText(value)
    if core.Secret.IsSecret(value) then button.countPlate:Show()
    else button.countPlate:SetShown(value ~= nil and value ~= "") end
end

local function refreshButton(button)
    local cooldownOK = duration(button.cooldown, "GetSpellCooldownDuration", button.spellID, true)
    local chargeOK = duration(button.recharge, "GetSpellChargeDuration", button.spellID)
    local countOK, reason = core.Secret.Apply(function(value) setCount(button, value) end,
        C_Spell and C_Spell.GetSpellDisplayCount, button.spellID)
    if not countOK then setCount(button, ""); panel.Warn("count", reason) end
    local unavailable = not cooldownOK or not chargeOK or not countOK
    button.unknown:SetShown(unavailable)
    button.unknownPlate:SetShown(unavailable)
end

function strip.Refresh()
    for _, button in ipairs(panel.Buttons) do
        local ok, reason = pcall(refreshButton, button)
        if not ok then panel.Warn("render", reason) end
    end
end
panel.Refresh = strip.Refresh

local function cooldown(button, charge)
    local widget = CreateFrame("Cooldown", nil, button)
    widget:SetAllPoints(button.icon)
    widget:EnableMouse(false)
    widget:SetDrawSwipe(not charge)
    widget:SetDrawEdge(charge)
    widget:SetDrawBling(false)
    widget:SetHideCountdownNumbers(false)
    widget:SetMinimumCountdownDuration(0)
    widget:SetCountdownFont(charge and "NumberFontNormalSmall" or "NumberFontNormal")
    widget:SetSwipeColor(0, 0, 0, 0.8)
    local font = widget:GetCountdownFontString()
    if font then
        font:SetFont(core.Media.font, charge and CHARGE_FONT or TIMER_FONT, "OUTLINE")
        if charge then font:ClearAllPoints(); font:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2) end
    end
    return widget
end

local function tooltip(button)
    if not button.spellID then return end
    local ok, reason = pcall(function()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(button.spellID)
        GameTooltip:Show()
    end)
    if not ok then panel.Warn("tooltip", reason) end
end

local function textPlate(parent, label, color)
    local plate = parent:CreateTexture(nil, "ARTWORK")
    plate:SetTexture(FLAT); plate:SetVertexColor(unpack(color))
    plate:SetPoint("TOPLEFT", label, "TOPLEFT", -2, 1)
    plate:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 2, -1)
    plate:Hide()
    return plate
end

local function decorateCounts(button)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:EnableMouse(false)
    overlay:SetFrameLevel(math.max(button.cooldown:GetFrameLevel(), button.recharge:GetFrameLevel()) + 1)
    button.border = core.UI.Edges(overlay, 1, "OVERLAY")
    for _, edge in ipairs(button.border) do edge:SetVertexColor(unpack(CELL_EDGE)) end
    button.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    button.count:SetFont(core.Media.font, COUNT_FONT, "OUTLINE")
    button.count:SetTextColor(0.95, 0.97, 1)
    button.countPlate = textPlate(overlay, button.count, { 0.015, 0.025, 0.04, 0.92 })
    button.unknown = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.unknown:SetPoint("TOPLEFT", 2, -2)
    button.unknown:SetText("?")
    button.unknown:SetFont(core.Media.font, CHARGE_FONT, "OUTLINE")
    button.unknown:SetTextColor(1, 0.83, 0.38)
    button.unknownPlate = textPlate(overlay, button.unknown, { 0.16, 0.09, 0.015, 0.96 })
end

local function createButton()
    local button = CreateFrame("Frame", nil, strip.Frame)
    button:SetSize(SIZE, SIZE)
    button:EnableMouse(true)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.backing = button:CreateTexture(nil, "BACKGROUND")
    button.backing:SetAllPoints(button); button.backing:SetTexture(FLAT)
    button.backing:SetVertexColor(0.015, 0.02, 0.03, 1)
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.cooldown, button.recharge = cooldown(button, false), cooldown(button, true)
    decorateCounts(button)
    button:SetScript("OnEnter", tooltip)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return button
end

local function create()
    strip.Frame = CreateFrame("Frame", "RikUICooldowns", UIParent)
    strip.Frame:SetSize(WIDTH, strip.Height(0))
    strip.Frame:EnableMouse(false)
    panel.Frame = strip.Frame
    core.Layout.Register(strip.Frame, KEY,
        { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 376 }, { label = LABEL, grow = "UP" })
end

local function icon(button, entry)
    button.icon:SetTexture(entry.icon)
    local ok, reason = core.Secret.Apply(function(value)
        if core.Secret.IsSecret(value) or value ~= nil then button.icon:SetTexture(value) end
    end, C_Spell and C_Spell.GetSpellTexture, entry.id)
    if not ok then panel.Warn("texture", reason) end
    button.icon:SetDesaturated(entry.dim == true)
    button.icon:SetAlpha(entry.dim and DIM_ALPHA or 1)
end

-- The first entries take the bottom row, nearest the resource strip; every row is centred.
local function arrange(count)
    for index, button in ipairs(panel.Buttons) do
        local row, column = math.floor((index - 1) / COLUMNS), (index - 1) % COLUMNS
        local inRow = math.min(COLUMNS, count - row * COLUMNS)
        local lead = (WIDTH - (inRow * PITCH - GAP)) / 2
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", strip.Frame, "BOTTOMLEFT", lead + column * PITCH, row * PITCH)
    end
end

function strip.Apply(entries)
    if not strip.Frame then create() end
    panel.Buttons = {}
    for index, entry in ipairs(entries) do
        local button = pool[index] or createButton()
        pool[index], panel.Buttons[index] = button, button
        button.spellID, button.spellName = entry.id, entry.name
        icon(button, entry)
        button:Show()
    end
    for index = #entries + 1, #pool do
        pool[index].spellID = nil
        pool[index].cooldown:Clear()
        pool[index].recharge:Clear()
        pool[index]:Hide()
    end
    strip.Frame:SetSize(WIDTH, strip.Height(rowsFor(#entries)))
    arrange(#entries)
    if panel.Cells then
        for index, entry in ipairs(entries) do panel.Cells.Attach(index, panel.Buttons[index], entry.aura) end
        panel.Cells.Trim(#entries)
    end
    strip.Frame:SetShown(#entries > 0)
    strip.Refresh()
end
