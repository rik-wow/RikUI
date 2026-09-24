-- Data-driven option rows with shared media and keyboard focus. Control types live in
-- src/configuration/options/options-controls.lua; pages live in src/configuration/options/options.lua.
local core, media = RikUI, RikUI.Media
local options = { Types = {}, Metrics = { controlWidth = 180, controlHeight = 22, textInset = 6 } }
core.Options = options
local ROW_HEIGHT, ROW_GAP, LABEL_WIDTH, DISABLED_ALPHA = 38, 4, 240, 0.4
local STACK_WIDTH, STACK_HEIGHT, CONTROL_GAP = 390, 62, 18
local BACKGROUND, BORDER_TINT, FOCUS_TINT = { 0.055, 0.065, 0.08, 0.95 }, { 0.35, 0.38, 0.42, 1 }, { 0.5, 0.8, 1, 0.6 }
local MOVE_KEYS, ADJUST_KEYS = { TAB = 1, DOWN = 1, UP = -1 }, { LEFT = -1, RIGHT = 1 }
local ACTIVATE_KEYS = { SPACE = true, ENTER = true }
local types, metrics = options.Types, options.Metrics

function options.SetShown(region, shown)
    if shown then region:Show() else region:Hide() end
end

function options.Flat(frame, layer, color)
    local texture = frame:CreateTexture(nil, layer)
    texture:SetAllPoints()
    texture:SetColorTexture(color[1], color[2], color[3], color[4])
    return texture
end

function options.Border(frame, tint)
    return core.Skin.Outline(frame, tint)
end

function options.Text(parent, role, text)
    local region = parent:CreateFontString(nil, "OVERLAY")
    media.Font(region, role or "label")
    region:SetText(text or "")
    return region
end

function options.WidgetFrame(row, kind)
    local widget = CreateFrame(kind or "Button", nil, row)
    widget:SetSize(metrics.controlWidth, metrics.controlHeight)
    widget:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    widget.background = options.Flat(widget, "BACKGROUND", BACKGROUND)
    widget.border = options.Border(widget, BORDER_TINT)
    core.Motion.BindHover(widget)
    return widget
end

function options.Commit(row, value)
    local spec = row.spec
    if not row.enabled or (spec.disabled and spec.disabled()) then return end
    local function apply()
        local ok, reason = spec.set(value)
        if ok == nil and reason then core:Print(reason) end
        if core.Changed then core:Changed() end
        options.RefreshList(row.list)
    end
    if spec.protected and InCombatLockdown() then
        core.Combat.Queue(apply)
        core:Print(spec.label .. ": queued until combat ends.")
        return
    end
    apply()
    if options.Refresh then options.Refresh() end
end

function options.Activate(row)
    local kind = types[row.spec.type]
    if row.enabled and not (row.spec.disabled and row.spec.disabled()) and kind.activate then kind.activate(row) end
end

function options.CreateRow(parent, spec, list)
    local kind = types[spec.type]
    assert(kind, "Unknown option control type: " .. tostring(spec.type))
    local row = CreateFrame("Frame", nil, parent)
    row.spec, row.list, row.enabled = spec, list, true
    row:SetSize(LABEL_WIDTH + metrics.controlWidth, ROW_HEIGHT)
    row.focus = row:CreateTexture(nil, "BACKGROUND")
    row.focus:SetAllPoints()
    row.focus:SetTexture(media.highlight)
    row.focus:SetVertexColor(FOCUS_TINT[1], FOCUS_TINT[2], FOCUS_TINT[3], FOCUS_TINT[4])
    row.focus:Hide()
    row.focusEnter = core.Motion.Tween(row.focus, 0, 0.6, 0.1)
    row.focusLeave = core.Motion.Tween(row.focus, 0.6, 0, 0.1)
    if row.focusLeave then row.focusLeave:SetScript("OnFinished", function()
        if not row.focusActive then row.focus:Hide() end
    end) end
    row:HookScript("OnHide", function()
        core.Motion.Stop(row.focusEnter); core.Motion.Stop(row.focusLeave)
        row.focusActive, row.keyboardFocused, row.editFocused = false, false, false
        row.focus:Hide()
    end)
    local role = spec.type == "heading" and "heading" or "label"
    row.label = options.Text(row, role, spec.label)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(true)
    if spec.get then row.initial = spec.get() end
    row.label:SetPoint("LEFT", row, "LEFT", metrics.textInset, 0)
    if spec.type == "heading" then
        row.label:SetTextColor(1, 0.82, 0)
        row.rule = row:CreateTexture(nil, "BORDER")
        row.rule:SetTexture(core.Skin.FLAT)
        row.rule:SetVertexColor(0.3, 0.28, 0.2, 0.7)
        row.rule:SetPoint("BOTTOMLEFT", 6, 0); row.rule:SetPoint("BOTTOMRIGHT", -6, 0)
        row.rule:SetHeight(1)
    end
    if spec.description then
        row.description = options.Text(row, "small", spec.description)
        row.description:SetJustifyH("LEFT"); row.description:SetWordWrap(true)
        row.description:SetTextColor(0.62, 0.7, 0.77)
    end
    if kind.create then row.widget = kind.create(row) end
    return row
end

function options.RefreshRow(row)
    local spec = row.spec
    if spec.get then row.value = spec.get() end
    row.pending = spec.reload and (spec.pending and spec.pending() or (not spec.pending and row.value ~= row.initial)) or false
    local enabled = not (spec.disabled and spec.disabled())
    row.enabled = enabled
    row:SetAlpha(enabled and 1 or DISABLED_ALPHA)
    if row.widget then
        if enabled then row.widget:Enable() else row.widget:Disable() end
    end
    types[spec.type].refresh(row, row.value)
end

function options.RefreshList(list)
    for _, row in ipairs(list.rows) do options.RefreshRow(row) end
end

local function placeRow(row, width, y)
    local kind = row.spec.type
    local narrow = kind == "checkbox" and metrics.controlHeight or (kind == "colour" and metrics.controlHeight * 2)
    local stacked = width < STACK_WIDTH and row.widget ~= nil and not narrow
    local baseHeight = stacked and STACK_HEIGHT or ROW_HEIGHT
    local descriptionHeight = 0
    if row.description then
        row.description:SetWidth(math.max(1, width - 12))
        descriptionHeight = math.max(24, row.description:GetStringHeight() or 0) + 8
        row.description:ClearAllPoints()
        row.description:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -baseHeight)
        row.description:SetHeight(descriptionHeight - 8)
    end
    local height = baseHeight + descriptionHeight
    row.top, row.height = y, height
    row:SetSize(width, height)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", row.list.parent, "TOPLEFT", 0, -y)
    row.label:ClearAllPoints()
    row.label:SetPoint(stacked and "TOPLEFT" or "LEFT", row, stacked and "TOPLEFT" or "LEFT", 6, stacked and -4 or descriptionHeight / 2)
    local controlWidth = math.min(narrow or metrics.controlWidth, width - 12)
    row.label:SetWidth(math.max(1, row.widget and not stacked and width - controlWidth - CONTROL_GAP or width - 12))
    row.label:SetHeight(stacked and 24 or 32)
    if row.widget then
        local widget = row.widget
        local reserved = kind == "slider" and 44 or 0
        widget:ClearAllPoints()
        widget:SetWidth(narrow or math.max(1, controlWidth - reserved))
        widget:SetPoint(stacked and "BOTTOMRIGHT" or "RIGHT", row, stacked and "BOTTOMRIGHT" or "RIGHT", -reserved, stacked and 4 + descriptionHeight or descriptionHeight / 2)
    end
    return y + height + ROW_GAP
end

function options.ResizeList(list, width)
    local y = 0
    list.width = math.max(1, width)
    for _, row in ipairs(list.rows) do
        options.SetShown(row, not row.filtered)
        if not row.filtered then y = placeRow(row, list.width, y) end
    end
    list.height = y
    if list.scroll and list.scroll.contentHeight ~= y then core.Scroll.SetContentHeight(list.scroll, y) end
end

function options.Render(parent, specs)
    local list = { rows = {}, height = 0, parent = parent }
    for index, spec in ipairs(specs) do list.rows[index] = options.CreateRow(parent, spec, list) end
    options.ResizeList(list, parent:GetWidth() or LABEL_WIDTH + metrics.controlWidth)
    options.RefreshList(list)
    return list
end

local function focusEffect(row, active)
    if row.focusActive == active then return end
    row.focusActive = active
    core.Motion.Stop(row.focusEnter); core.Motion.Stop(row.focusLeave)
    row.focus:Show()
    row.focus:SetAlpha(active and 0.6 or 0)
    local animation = active and row.focusEnter or row.focusLeave
    core.Motion.Play(animation)
    if not active and not animation then row.focus:Hide() end
end

function options.EditFocus(row, active)
    row.editFocused = active
    focusEffect(row, active or row.keyboardFocused == true)
end

function options.SetFocus(panel, row)
    if panel.focused and panel.focused ~= row and panel.focused.spec.type == "text" then
        panel.focused.widget:ClearFocus()
        panel.focused.editFocused = false
    end
    if panel.focused then
        panel.focused.keyboardFocused = false
        focusEffect(panel.focused, panel.focused.editFocused == true)
    end
    panel.focused = row
    if row then
        row.list.keyboardPanel = panel
        row.keyboardFocused = true
        focusEffect(row, true)
        if row.list.scroll then core.Scroll.Reveal(row.list.scroll, row.top, row.height) end
    end
end

local function moveFocus(panel, rows, delta)
    local candidates = {}
    for _, row in ipairs(rows) do
        if row.widget and row.enabled and not row.filtered then candidates[#candidates + 1] = row end
    end
    if #candidates == 0 then return end
    local index = 0
    for position, row in ipairs(candidates) do
        if row == panel.focused then index = position end
    end
    index = index + delta
    if index < 1 then index = #candidates elseif index > #candidates then index = 1 end
    options.SetFocus(panel, candidates[index])
end

function options.TabFromText(row)
    local panel = row.list.keyboardPanel
    row.widget:ClearFocus()
    options.EditFocus(row, false)
    if panel then
        options.SetFocus(panel, row)
        moveFocus(panel, panel.GetRows(), IsShiftKeyDown() and -1 or 1)
    end
end

local function focusEdge(panel, last)
    local target
    for _, row in ipairs(panel.GetRows()) do
        if row.widget and row.enabled and not row.filtered then
            target = row
            if not last then break end
        end
    end
    options.SetFocus(panel, target)
    return target ~= nil
end

local function handleKey(panel, key)
    if panel.search and panel.search:HasFocus() then return false end
    for _, candidate in ipairs(panel.GetRows()) do
        if candidate.spec.type == "text" and candidate.widget:HasFocus() then return false end
    end
    if options.DropdownKey and options.DropdownKey(key) then return true end
    if key == "HOME" or key == "END" then return focusEdge(panel, key == "END") end
    if (key == "PAGEUP" or key == "PAGEDOWN") and panel.MovePage then
        return panel.MovePage(key == "PAGEUP" and -1 or 1)
    end
    if MOVE_KEYS[key] then
        local delta = MOVE_KEYS[key]
        if key == "TAB" and IsShiftKeyDown() then delta = -1 end
        moveFocus(panel, panel.GetRows(), delta)
        return true
    end
    local row = panel.focused
    if not row or not row.enabled then return false end
    if ACTIVATE_KEYS[key] then options.Activate(row); return true end
    local kind = types[row.spec.type]
    if ADJUST_KEYS[key] and kind.adjust then kind.adjust(row, ADJUST_KEYS[key]); return true end
    return false
end

local function releaseKeyboard(panel)
    if not InCombatLockdown() then panel:SetPropagateKeyboardInput(true) end
end

-- Propagation writes are protected in combat, so combat keystrokes pass through untouched.
function options.EnableKeyboard(panel, getRows)
    panel.GetRows = function()
        local rows = getRows()
        for _, row in ipairs(rows) do row.list.keyboardPanel = panel end
        return rows
    end
    panel:EnableKeyboard(true)
    panel:SetPropagateKeyboardInput(true)
    panel:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(not handleKey(self, key))
    end)
    panel:HookScript("OnHide", function(self)
        options.SetFocus(self, nil)
        releaseKeyboard(self)
    end)
    core:RegisterEvent("PLAYER_REGEN_DISABLED", function() releaseKeyboard(panel) end)
end
