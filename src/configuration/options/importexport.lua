-- Shared copy/paste window; imports only store data until a separate Apply.
local core, sharing, controls = RikUI, RikUI.Sharing, RikUI.WizardControls
local window
local WIDTH, HEIGHT, PAD = 660, 440, 20

function sharing.Close()
    if not window then return end
    window.edit:ClearFocus(); window.name:ClearFocus(); window:Hide()
end

local function editBox(parent, width, height, maximum)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, height); box:SetAutoFocus(false); box:SetMaxLetters(maximum)
    box:SetFont(core.Media.font, core.Media.sizes.label, "")
    box:SetScript("OnEscapePressed", sharing.Close)
    core.Skin.Fill(box, core.Skin.BACKING); core.Skin.Outline(box)
    return box
end

local function import()
    local ok, reason = window.importAction(window.name:GetText(), window.edit:GetText())
    window.status:SetText(ok and window.successText or tostring(reason))
    if ok then window.edit:ClearFocus(); window.name:ClearFocus() end
end

local function createTextArea()
    window.scroll = CreateFrame("ScrollFrame", nil, window)
    window.scroll:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -112)
    window.scroll:SetSize(WIDTH - 2 * PAD, 230)
    window.edit = editBox(window.scroll, WIDTH - 2 * PAD - 12, 230, sharing.Limit)
    window.edit:SetMultiLine(true)
    window.scroll:SetScrollChild(window.edit)
    window.edit:SetScript("OnEditFocusGained", function(self) if window.exportText then self:HighlightText() end end)
    window.edit:SetScript("OnTextChanged", function(self)
        if window.exportText and self:GetText() ~= window.exportText then self:SetText(window.exportText) end
    end)
    window.edit:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local offset = math.max(0, -y)
        local top, visible = window.scroll:GetVerticalScroll(), window.scroll:GetHeight()
        if offset < top then window.scroll:SetVerticalScroll(offset)
        elseif offset + height > top + visible then window.scroll:SetVerticalScroll(offset + height - visible) end
    end)
    window.scroll:EnableMouseWheel(true)
    window.scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40)))
    end)
end

local function build()
    window = CreateFrame("Frame", "RikUISharing", UIParent)
    window:SetSize(WIDTH, HEIGHT); window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG"); window:EnableMouse(true)
    core.Skin.Fill(window, core.Skin.BACKING); core.Skin.Outline(window)
    window.title = controls.Text(window, "heading", "")
    window.title:SetPoint("TOPLEFT", PAD, -16)
    window.note = controls.Text(window, "small", "")
    window.note:SetWidth(WIDTH - 2 * PAD); window.note:SetJustifyH("LEFT"); window.note:SetPoint("TOPLEFT", PAD, -48)
    window.name = editBox(window, WIDTH - 2 * PAD, 24, 64)
    window.name:SetPoint("TOPLEFT", PAD, -78)
    window.name:SetScript("OnTabPressed", function() window.edit:SetFocus() end)
    createTextArea()
    window.status = controls.Text(window, "small", "")
    window.status:SetWidth(WIDTH - 2 * PAD); window.status:SetHeight(46); window.status:SetJustifyH("LEFT")
    window.status:SetPoint("BOTTOMLEFT", PAD, 54)
    window.importButton = controls.Button(window, "Save import", import)
    window.importButton:SetPoint("BOTTOMRIGHT", -PAD, 16)
    window.close = controls.Button(window, "Close", sharing.Close)
    window.close:SetPoint("BOTTOMLEFT", PAD, 16)
    window:SetScript("OnHide", function() window.edit:ClearFocus(); window.name:ClearFocus() end)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "RikUISharing" end
    sharing.Window = window
end

function sharing.OpenDialog(title, text, action, note, successText)
    if InCombatLockdown() then core:Print("Sharing is unavailable in combat."); return nil end
    if not core.DB then core:Print("Still loading."); return nil end
    if not window then build() end
    window.exportText, window.importAction, window.successText = text, action, successText
    window.title:SetText(title); window.note:SetText(note); window.status:SetText("")
    window.name:SetText(""); window.name:SetShown(action ~= nil)
    window.importButton:SetShown(action ~= nil)
    window.edit:SetText(text or ""); window.scroll:SetVerticalScroll(0); window:Show()
    if text then window.edit:SetFocus(); window.edit:HighlightText() else window.name:SetFocus() end
    return true
end

function sharing.OpenExport(role)
    local _, class = UnitClass("player")
    local text, reason = sharing.ExportPreset(class, role)
    if not text then core:Print(reason); return nil end
    return sharing.OpenDialog("Export character preset", text, nil,
        "Copy with Ctrl-C. This shares preset bars and macros, not your live action bar changes.")
end

function sharing.OpenImport()
    return sharing.OpenDialog("Import character preset", nil, sharing.ImportPreset,
        "Enter a new name, then paste below. Presets include macros; review their source before Apply.",
        "Saved. Open /rik setup and choose this preset to preview and apply it.")
end

core:RegisterCommand("export", function(args) sharing.OpenExport(args ~= "" and args or nil) end,
    "Copy a preset: /rik export [role]")
core:RegisterCommand("import", function(args)
    if args ~= "" then core:Print("Usage: /rik import"); return end
    sharing.OpenImport()
end, "Import a named preset: /rik import")
core:RegisterEvent("PLAYER_REGEN_DISABLED", sharing.Close)
