-- Control types for the options renderer: create, refresh, activate and adjust per type.
local core, media, options = RikUI, RikUI.Media, RikUI.Options
local types, metrics, setShown = options.Types, options.Metrics, options.SetShown
local THUMB_WIDTH, MAX_LETTERS, SWATCH_INSET, LIST_GAP, LIST_LEVEL = 12, 32, 2, 2, 10
local BACKGROUND, BORDER_TINT, ACTIVE_TINT = { 0.055, 0.065, 0.08, 0.95 }, { 0.35, 0.38, 0.42, 1 }, { 1, 0.78, 0.3, 1 }
local DROPDOWN_ICON, DROPDOWN_ICON_SIZE = "chevron-down", 10

types.heading = { refresh = function() end }

types.checkbox = {
    create = function(row)
        local box = options.WidgetFrame(row)
        box:SetSize(metrics.controlHeight, metrics.controlHeight)
        box.mark = box:CreateTexture(nil, "ARTWORK")
        box.mark:SetAllPoints()
        box.mark:SetTexture(media.checked)
        box.mark:SetVertexColor(ACTIVE_TINT[1], ACTIVE_TINT[2], ACTIVE_TINT[3], ACTIVE_TINT[4])
        box:SetHighlightTexture(media.highlight, "ADD")
        box:SetScript("OnClick", function() options.Commit(row, not row.value) end)
        return box
    end,
    refresh = function(row, value) setShown(row.widget.mark, value == true) end,
    activate = function(row) options.Commit(row, not row.value) end,
}

local function clampStep(spec, value)
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
            if not row.refreshing then options.Commit(row, value) end
        end)
        return slider
    end,
    refresh = function(row, value)
        row.refreshing = true
        row.widget:SetValue(value)
        row.refreshing = false
        row.widget.text:SetFormattedText("%.2f", value)
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

local function closeList(row)
    if row.widget.list then row.widget.list:Hide() end
end

local function listButton(row, list, index)
    local button = CreateFrame("Button", nil, list)
    button:SetSize(metrics.controlWidth, metrics.controlHeight)
    button:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * metrics.controlHeight)
    button:SetHighlightTexture(media.highlight, "ADD")
    button.text = options.Text(button, "label")
    button.text:SetPoint("LEFT", button, "LEFT", metrics.textInset, 0)
    button:SetScript("OnClick", function()
        closeList(row)
        options.Commit(row, button.entry.value)
    end)
    return button
end

local function createList(widget)
    local list = CreateFrame("Frame", nil, widget)
    local level = widget:GetFrameLevel()
    if level then list:SetFrameLevel(level + LIST_LEVEL) end
    list:SetPoint("TOPLEFT", widget, "BOTTOMLEFT", 0, -LIST_GAP)
    list:SetWidth(metrics.controlWidth)
    options.Flat(list, "BACKGROUND", BACKGROUND)
    options.Border(list, BORDER_TINT)
    list.buttons = {}
    list:Hide()
    return list
end

local function openList(row)
    local widget = row.widget
    widget.list = widget.list or createList(widget)
    local list, values = widget.list, dropdownValues(row.spec)
    for index, entry in ipairs(values) do
        local button = list.buttons[index] or listButton(row, list, index)
        list.buttons[index] = button
        button.entry = entry
        button.text:SetText(entry.text)
        button:Show()
    end
    for index = #values + 1, #list.buttons do list.buttons[index]:Hide() end
    list:SetHeight(math.max(1, #values) * metrics.controlHeight)
    list:Show()
end

local function toggleList(row)
    local list = row.widget.list
    if list and list:IsShown() then closeList(row) else openList(row) end
end

types.dropdown = {
    create = function(row)
        local widget = options.WidgetFrame(row)
        widget:SetHighlightTexture(media.highlight, "ADD")
        widget.text = options.Text(widget, "label")
        widget.text:SetPoint("LEFT", widget, "LEFT", metrics.textInset, 0)
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
        widget:SetHighlightTexture(media.highlight, "ADD")
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
        box:SetMaxLetters(MAX_LETTERS)
        box:SetTextInsets(metrics.textInset, metrics.textInset, 0, 0)
        media.Font(box, "label")
        box:SetScript("OnTextChanged", function(self, userInput)
            if userInput and not row.refreshing then options.Commit(row, self:GetText()) end
        end)
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

types.button = {
    create = function(row)
        local widget = options.WidgetFrame(row)
        widget:SetHighlightTexture(media.highlight, "ADD")
        widget.text = options.Text(widget, "label", row.spec.text or row.spec.label)
        widget.text:SetPoint("CENTER", widget, "CENTER", 0, 0)
        widget:SetScript("OnClick", function() options.Activate(row) end)
        return widget
    end,
    refresh = function() end,
    activate = function(row)
        if row.spec.action then row.spec.action() end
        options.RefreshList(row.list)
    end,
}
