-- Data-driven option rows with shared media and keyboard focus. Control types live in
-- options-controls.lua; pages live in options.lua.
local core, media = RikUI, RikUI.Media
local options = { Types = {}, Metrics = { controlWidth = 180, controlHeight = 22, textInset = 6 } }
core.Options = options
local ROW_HEIGHT, ROW_GAP, LABEL_WIDTH, DISABLED_ALPHA = 26, 6, 240, 0.4
local RELOAD_TAG = " |cffffd100(needs /reload)|r"
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
    local edge = frame:CreateTexture(nil, "BORDER")
    edge:SetAllPoints()
    edge:SetTexture(media.border)
    edge:SetVertexColor(tint[1], tint[2], tint[3], tint[4])
    return edge
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
    widget:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH, 0)
    widget.background = options.Flat(widget, "BACKGROUND", BACKGROUND)
    widget.border = options.Border(widget, BORDER_TINT)
    return widget
end

function options.Commit(row, value)
    local spec = row.spec
    if not row.enabled then return end
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
    if spec.reload then core:Print(spec.label .. " takes effect after /reload.") end
end

function options.Activate(row)
    local kind = types[row.spec.type]
    if row.enabled and kind.activate then kind.activate(row) end
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
    local role = spec.type == "heading" and "heading" or "label"
    row.label = options.Text(row, role, spec.label .. (spec.reload and RELOAD_TAG or ""))
    row.label:SetPoint("LEFT", row, "LEFT", metrics.textInset, 0)
    if kind.create then row.widget = kind.create(row) end
    return row
end

function options.RefreshRow(row)
    local spec = row.spec
    if spec.get then row.value = spec.get() end
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

function options.Render(parent, specs)
    local list, y = { rows = {}, height = 0 }, 0
    for index, spec in ipairs(specs) do
        local row = options.CreateRow(parent, spec, list)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
        y = y + ROW_HEIGHT + ROW_GAP
        list.rows[index] = row
    end
    list.height = y
    options.RefreshList(list)
    return list
end

function options.SetFocus(panel, row)
    if panel.focused then panel.focused.focus:Hide() end
    panel.focused = row
    if row then row.focus:Show() end
end

local function moveFocus(panel, rows, delta)
    local candidates = {}
    for _, row in ipairs(rows) do
        if row.widget and row.enabled then candidates[#candidates + 1] = row end
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

local function handleKey(panel, key)
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
    panel.GetRows = getRows
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
