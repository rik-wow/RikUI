-- Control types for the options renderer: create, refresh, activate and adjust per type.
local core, media, options = RikUI, RikUI.Media, RikUI.Options
local types, metrics, setShown = options.Types, options.Metrics, options.SetShown
local THUMB_WIDTH, MAX_LETTERS, SWATCH_INSET, LIST_GAP, LIST_LEVEL = 12, 32, 2, 2, 10
local BACKGROUND, BORDER_TINT, ACTIVE_TINT = { 0.055, 0.065, 0.08, 0.95 }, { 0.35, 0.38, 0.42, 1 }, { 1, 0.78, 0.3, 1 }
local DROPDOWN_ICON, DROPDOWN_ICON_SIZE, MAX_VISIBLE = "chevron-down", 10, 6
local activeDropdown

types.heading = { refresh = function() end }

types.checkbox = {
    create = function(row)
        local box = options.WidgetFrame(row)
        box:SetSize(metrics.controlHeight, metrics.controlHeight)
        box.mark = box:CreateTexture(nil, "ARTWORK")
        box.mark:SetAllPoints()
        box.mark:SetTexture(media.checked)
        box.mark:SetVertexColor(ACTIVE_TINT[1], ACTIVE_TINT[2], ACTIVE_TINT[3], ACTIVE_TINT[4])
        -- Hover wash is provided by WidgetFrame.
        box:SetScript("OnClick", function() options.Commit(row, not row.value) end)
        return box
    end,
    refresh = function(row, value) setShown(row.widget.mark, value == true) end,
    activate = function(row) options.Commit(row, not row.value) end,
}

local function clampStep(spec, value)
    local step = spec.step or 1
    if step > 0 then value = spec.min + math.floor((value - spec.min) / step + 0.5) * step end
    return math.min(spec.max, math.max(spec.min, value))
end

types.slider = {
    create = function(row)
        local slider = options.WidgetFrame(row, "Slider")
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(row.spec.min, row.spec.max)
        slider:SetValueStep(row.spec.step)
        slider:SetObeyStepOnDrag(true)
        slider:SetThumbTexture(media.checked)
        local thumb = slider:GetThumbTexture()
        if thumb then thumb:SetSize(THUMB_WIDTH, metrics.controlHeight) end
        slider.text = options.Text(slider, "small")
        slider.text:SetPoint("LEFT", slider, "RIGHT", metrics.textInset, 0)
        slider:SetScript("OnValueChanged", function(_, value)
            if not row.refreshing then options.Commit(row, clampStep(row.spec, value)) end
        end)
        return slider
    end,
    refresh = function(row, value)
        row.refreshing = true
        row.widget:SetValue(value)
        row.refreshing = false
        local text = row.spec.format and row.spec.format(value)
            or string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", "")
        row.widget.text:SetText(text)
    end,
    adjust = function(row, delta)
        options.Commit(row, clampStep(row.spec, row.value + delta * row.spec.step))
    end,
}

local function dropdownValues(spec)
    local values = spec.values
    if type(values) == "function" then values = values() end
    return values or {}
end

local function valueText(spec, value)
    for _, entry in ipairs(dropdownValues(spec)) do
        if entry.value == value then return entry.text end
    end
    return value == nil and "" or tostring(value)
end

function options.CloseDropdown()
    if activeDropdown then activeDropdown:Hide(); activeDropdown.dismiss:Hide(); activeDropdown = nil end
end

local function closeList(row)
    if row.widget.list and activeDropdown == row.widget.list then options.CloseDropdown() end
end

local function listButton(row, list, index)
    local button = CreateFrame("Button", nil, list.scroll.content)
    button:SetSize(metrics.controlWidth - 14, metrics.controlHeight)
    button:SetPoint("TOPLEFT", 0, -(index - 1) * metrics.controlHeight)
    core.Motion.BindHover(button)
    button.selected = options.Flat(button, "BACKGROUND", { 0.12, 0.27, 0.34, 0.9 })
    button.mark = options.Text(button, "small", ">")
    button.mark:SetPoint("RIGHT", -4, 0)
    button.text = options.Text(button, "label")
    button.text:SetPoint("LEFT", metrics.textInset, 0); button.text:SetPoint("RIGHT", -18, 0)
    button.text:SetJustifyH("LEFT"); button.text:SetWordWrap(false)
    button:SetScript("OnClick", function()
        closeList(row)
        options.Commit(row, button.entry.value)
    end)
    return button
end

local function createList(row)
    local host = row.list.popupHost or UIParent
    local dismiss = CreateFrame("Button", nil, host)
    dismiss:SetAllPoints(host); dismiss:SetFrameLevel((host:GetFrameLevel() or 1) + LIST_LEVEL)
    dismiss:SetScript("OnClick", options.CloseDropdown); dismiss:Hide()
    local list = CreateFrame("Frame", nil, dismiss)
    list.dismiss = dismiss
    list:SetWidth(metrics.controlWidth)
    list:SetClampedToScreen(true)
    options.Flat(list, "BACKGROUND", BACKGROUND); options.Border(list, BORDER_TINT)
    list.scroll = core.Scroll.Create(list)
    list.scroll:SetAllPoints()
    list.buttons = {}
    list.empty = options.Text(list, "small", "No choices available")
    list.empty:SetPoint("CENTER"); list.empty:Hide()
    core.Motion.BindEntrance(list, false)
    list:Hide()
    return list
end

local function placeList(row, list, height)
    local widget, host = row.widget, row.list.popupHost or UIParent
    list:ClearAllPoints()
    local bottom, hostBottom = widget:GetBottom(), host:GetBottom()
    local above = type(bottom) == "number" and type(hostBottom) == "number" and bottom - height < hostBottom + 12
    list:SetPoint(above and "BOTTOMRIGHT" or "TOPRIGHT", widget, above and "TOPRIGHT" or "BOTTOMRIGHT", 0, above and LIST_GAP or -LIST_GAP)
    list:SetHeight(height)
    list.scroll:SetSize(metrics.controlWidth, height)
end

local function openList(row)
    if not row.enabled then return end
    options.CloseDropdown()
    local widget = row.widget
    widget.list = widget.list or createList(row)
    local list, values = widget.list, dropdownValues(row.spec)
    local selected = 1
    for index, entry in ipairs(values) do
        local button = list.buttons[index] or listButton(row, list, index)
        list.buttons[index] = button
        button.entry = entry
        button.text:SetText(entry.text)
        local current = entry.value == row.value
        setShown(button.selected, current); setShown(button.mark, current)
        if current then selected = index end
        button:Show()
    end
    for index = #values + 1, #list.buttons do list.buttons[index]:Hide() end
    placeList(row, list, math.max(1, math.min(MAX_VISIBLE, #values)) * metrics.controlHeight)
    core.Scroll.SetContentHeight(list.scroll, math.max(1, #values) * metrics.controlHeight)
    setShown(list.empty, #values == 0)
    core.Scroll.SetOffset(list.scroll, 0)
    core.Scroll.Reveal(list.scroll, (selected - 1) * metrics.controlHeight, metrics.controlHeight)
    list.row, list.count, list.cursor = row, #values, selected
    activeDropdown = list
    list.dismiss:Show(); list:Show()
end

local function previewChoice(list, index)
    list.cursor = math.max(1, math.min(list.count, index))
    for position, button in ipairs(list.buttons) do
        setShown(button.selected, position == list.cursor)
    end
    core.Scroll.Reveal(list.scroll, (list.cursor - 1) * metrics.controlHeight, metrics.controlHeight)
end

function options.DropdownKey(key)
    local list = activeDropdown
    if not list then return false end
    if key == "ESCAPE" or key == "TAB" then options.CloseDropdown(); return key == "ESCAPE" end
    if key == "ENTER" or key == "SPACE" then
        local button = list.count > 0 and list.buttons[list.cursor]
        options.CloseDropdown()
        if button then options.Commit(list.row, button.entry.value) end
        return true
    end
    local delta = key == "UP" and -1 or key == "DOWN" and 1
    if delta or key == "HOME" or key == "END" then
        if list.count > 0 then
            previewChoice(list, delta and list.cursor + delta or (key == "HOME" and 1 or list.count))
        end
        return true
    end
    return false
end

local function toggleList(row)
    local list = row.widget.list
    if list and list:IsShown() then closeList(row) else openList(row) end
end

types.dropdown = {
    create = function(row)
        local widget = options.WidgetFrame(row)
        -- Hover wash is provided by WidgetFrame.
        widget.text = options.Text(widget, "label")
        widget.text:SetPoint("LEFT", widget, "LEFT", metrics.textInset, 0)
        widget.text:SetPoint("RIGHT", widget, "RIGHT", -24, 0)
        widget.text:SetJustifyH("LEFT"); widget.text:SetWordWrap(false)
        widget.arrow = media.Icon(widget, DROPDOWN_ICON, DROPDOWN_ICON_SIZE, "OVERLAY")
        widget.arrow:SetPoint("RIGHT", widget, "RIGHT", -metrics.textInset, 0)
        widget:SetScript("OnClick", function() toggleList(row) end)
        widget:SetScript("OnHide", function() closeList(row) end)
        return widget
    end,
    refresh = function(row, value) row.widget.text:SetText(valueText(row.spec, value)) end,
    activate = toggleList,
    adjust = function(row, delta)
        local values = dropdownValues(row.spec)
        for index, entry in ipairs(values) do
            if entry.value == row.value then
                local target = values[index + delta]
                if target then options.Commit(row, target.value) end
                return
            end
        end
        if values[1] then options.Commit(row, values[1].value) end
    end,
}

local function colourParts(value)
    if type(value) ~= "table" then value = {} end
    return value[1] or 1, value[2] or 1, value[3] or 1
end

local function openPicker(row)
    local picker = ColorPickerFrame
    if not picker or type(picker.SetupColorPickerAndShow) ~= "function" then
        core:Print("Colour picker unavailable on this client.")
        return
    end
    local r, g, b = colourParts(row.value)
    picker:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
        swatchFunc = function() options.Commit(row, { picker:GetColorRGB() }) end,
        cancelFunc = function(previous) options.Commit(row, { previous.r, previous.g, previous.b }) end })
end

types.colour = {
    create = function(row)
        local widget = options.WidgetFrame(row)
        widget:SetSize(metrics.controlHeight * 2, metrics.controlHeight)
        -- Hover wash is provided by WidgetFrame.
        widget.swatch = widget:CreateTexture(nil, "ARTWORK")
        widget.swatch:SetPoint("TOPLEFT", widget, "TOPLEFT", SWATCH_INSET, -SWATCH_INSET)
        widget.swatch:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -SWATCH_INSET, SWATCH_INSET)
        widget:SetScript("OnClick", function() openPicker(row) end)
        return widget
    end,
    refresh = function(row, value)
        local r, g, b = colourParts(value)
        row.widget.swatch:SetColorTexture(r, g, b, 1)
    end,
    activate = openPicker,
}

types.text = {
    create = function(row)
        local box = options.WidgetFrame(row, "EditBox")
        box:SetAutoFocus(false)
        box:HookScript("OnEditFocusGained", function() options.EditFocus(row, true) end)
        box:HookScript("OnEditFocusLost", function() options.EditFocus(row, false) end)
        box:SetMaxLetters(MAX_LETTERS)
        box:SetTextInsets(metrics.textInset, metrics.textInset, 0, 0)
        media.Font(box, "label")
        box:SetScript("OnTextChanged", function(self, userInput)
            if userInput and not row.refreshing then options.Commit(row, self:GetText()) end
        end)
        box:SetScript("OnTabPressed", function() options.TabFromText(row) end)
        box:HookScript("OnHide", function(self) self:ClearFocus() end)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return box
    end,
    refresh = function(row, value)
        if row.widget:HasFocus() then return end
        row.refreshing = true
        row.widget:SetText(value or "")
        row.refreshing = false
    end,
    activate = function(row) row.widget:SetFocus() end,
}

local function cancelConfirmation(row)
    row.confirming = nil
    if row.cancel then row.cancel:Hide(); row.confirmText:Hide() end
    row.widget.text:SetText(row.spec.text or row.spec.label)
    options.ResizeList(row.list, row.list.width)
end

local function createConfirmation(row)
    local cancel = CreateFrame("Button", nil, row)
    cancel:SetSize(64, 22); cancel:SetPoint("BOTTOMRIGHT", 0, 4)
    options.Flat(cancel, "BACKGROUND", BACKGROUND); options.Border(cancel, BORDER_TINT)
    cancel.text = options.Text(cancel, "small", "Cancel"); cancel.text:SetPoint("CENTER")
    core.Motion.BindHover(cancel)
    cancel:SetScript("OnClick", function() cancelConfirmation(row) end)
    row.cancel = cancel; cancel:Hide()
    row.confirmText = options.Text(row, "small")
    row.confirmText:SetPoint("BOTTOMLEFT", 6, 6)
    row.confirmText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -72, 6)
    row.confirmText:SetJustifyH("LEFT"); row.confirmText:SetWordWrap(false)
    row.confirmText:SetTextColor(1, 0.78, 0.3); row.confirmText:Hide()
    row:HookScript("OnHide", function() if row.confirming then cancelConfirmation(row) end end)
end

types.button = {
    create = function(row)
        local widget = options.WidgetFrame(row)
        -- Hover wash is provided by WidgetFrame.
        widget.text = options.Text(widget, "label", row.spec.text or row.spec.label)
        widget.text:SetPoint("LEFT", 6, 0); widget.text:SetPoint("RIGHT", -6, 0)
        widget.text:SetJustifyH("CENTER"); widget.text:SetWordWrap(false)
        widget:SetScript("OnClick", function() options.Activate(row) end)
        if row.spec.confirm then createConfirmation(row) end
        return widget
    end,
    refresh = function(row)
        if row.confirming and (not row.enabled or row.spec.confirm() ~= row.confirming) then cancelConfirmation(row) end
    end,
    activate = function(row)
        if row.spec.confirm then
            local target = row.spec.confirm()
            if not target then return end
            if row.confirming ~= target then
                row.confirming = target
                row.widget.text:SetText("Confirm")
                row.confirmText:SetText(target); row.confirmText:Show(); row.cancel:Show()
                options.ResizeList(row.list, row.list.width)
                return
            end
            cancelConfirmation(row)
        end
        if row.spec.action then row.spec.action() end
        options.RefreshList(row.list)
    end,
}
