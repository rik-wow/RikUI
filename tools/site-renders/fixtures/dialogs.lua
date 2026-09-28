-- Confirmation popups, the small dialogs and context menus, opened through Blizzard's own entry points
-- so RikUI's popup, dialog and menu modules skin them the way they do in the client.

-- which: a StaticPopup key. "QUIT" is a plain confirmation, "ADD_FRIEND" carries a text field,
-- "EQUIP_BIND" an item. The dialog is centred for the capture.
function RikRenderPopup(which, ...)
    local dialog = StaticPopup_Show(which, ...)
    assert(dialog, "StaticPopup did not open: " .. tostring(which))
    RikRenderCenter(dialog)
    RikRenderResize(dialog)
    return dialog
end

-- A context menu the way a unit frame opens one: title, plain rows, a checked row, a submenu and a
-- disabled row. The menu opens at the cursor; the fixture reads the open menu back for the capture.
function RikRenderContextMenu(withSubmenu)
    local menu = MenuUtil.CreateContextMenu(UIParent, function(_, root)
        root:CreateTitle("Mira")
        root:CreateButton("Whisper", function() end)
        root:CreateButton("Invite", function() end)
        root:CreateCheckbox("Show helm", function() return true end, function() end)
        local interact = root:CreateButton("Interact")
        interact:CreateButton("Inspect", function() end)
        interact:CreateButton("Trade", function() end)
        interact:CreateButton("Follow", function() end)
        local duel = root:CreateButton("Duel", function() end)
        duel:SetEnabled(false)
        root:CreateButton("Cancel", function() end)
    end)
    local open = Menu.GetManager():GetOpenMenu()
    assert(open, "context menu did not open")
    open:ClearAllPoints()
    open:SetPoint("CENTER", UIParent, "CENTER", withSubmenu and -80 or 0, 0)
    if withSubmenu then
        -- Hovering "Interact" opens its submenu beside the row.
        for _, frame in ipairs({ open:GetChildren() }) do
            for _, region in ipairs({ frame:GetRegions() }) do
                if region:GetObjectType() == "FontString" and region:GetText() == "Interact" then
                    local enter = frame:GetScript("OnEnter")
                    if enter then enter(frame) end
                end
            end
        end
    end
    -- The capture renders one frame's subtree: the open menus and RikUI's backings under them move
    -- into a holder, keeping their levels.
    local holder = CreateFrame("Frame", "RikRenderMenu", UIParent)
    holder:SetFrameStrata("FULLSCREEN_DIALOG")
    holder:SetPoint("TOPLEFT", open, "TOPLEFT", -12, 12)
    holder:SetPoint("BOTTOMRIGHT", open, "BOTTOMRIGHT", withSubmenu and 180 or 12, -12)
    for menu, backing in pairs(RikUI.Menus.Active) do
        local level = menu:GetFrameLevel()
        menu:SetParent(holder)
        backing:SetParent(holder)
        menu:SetFrameLevel(math.max(level, 2))
        backing:SetFrameLevel(math.max(level, 2) - 1)
    end
    return holder
end

-- The ready check as the client shows it to a group member.
function RikRenderReadyCheck()
    RikRenderClientStubs()
    ShowReadyCheck("Mira", 30)
    -- The listener takes its size from its anchors to ReadyCheckFrame; centring keeps the size explicit.
    local width, height = ReadyCheckListenerFrame:GetSize()
    RikRenderCenter(ReadyCheckListenerFrame)
    ReadyCheckListenerFrame:SetSize(width > 0 and width or 323, height > 0 and height or 112)
    return ReadyCheckListenerFrame
end

-- The role poll a leader starts; the sim ignores the event, so the dialog is shown directly.
function RikRenderRolePoll()
    RolePollPopup:Show()
    RikRenderCenter(RolePollPopup)
    return RolePollPopup
end

function RikRenderStackSplit(total)
    StackSplitFrame:OpenStackSplitFrame(total or 20, UIParent, "CENTER", "CENTER", 1, total or 20)
    RikRenderCenter(StackSplitFrame)
    return StackSplitFrame
end

function RikRenderColorPicker()
    ColorPickerFrame:SetupColorPickerAndShow({ r = 0.3, g = 0.75, b = 1, hasOpacity = true, opacity = 0.85,
        swatchFunc = function() end, opacityFunc = function() end, cancelFunc = function() end })
    RikRenderCenter(ColorPickerFrame)
    return ColorPickerFrame
end

-- The Battle.net add-friend dialog with its entry page; the client opens it from the friends list.
function RikRenderAddFriend()
    StaticPopupSpecial_Show(AddFriendFrame)
    if AddFriendFrame.ShowEntry then AddFriendFrame:ShowEntry() end
    AddFriendNameEditBox:SetText("Mira")
    RikRenderCenter(AddFriendFrame)
    return AddFriendFrame
end

-- The queue-ready prompt for a battleground.
function RikRenderQueueReady()
    PVPReadyDialog:Show()
    if PVPReadyDialog.label then PVPReadyDialog.label:SetText("Warsong Gulch") end
    RikRenderCenter(PVPReadyDialog)
    return PVPReadyDialog
end

function RikRenderReportDialog()
    ReportFrame:Show()
    -- Without a report in progress the frame shows its title format and its thank-you line at once;
    -- the capture shows the form for one player.
    local function visit(frame)
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:GetObjectType() == "FontString" then
                local text = region:GetText() or ""
                if text:find("%s", 1, true) then region:SetText((text:gsub("%%s", "Toddrick"))) end
                if text:find("Thank you", 1, true) then region:Hide() end
            end
        end
        for _, child in ipairs({ frame:GetChildren() }) do visit(child) end
    end
    visit(ReportFrame)
    RikRenderCenter(ReportFrame)
    return ReportFrame
end

-- Name autocompletion under a chat-style edit box, with two matching names.
function RikRenderAutoComplete()
    GetAutoCompleteResults = function() return { { name = "Mira", priority = 1 }, { name = "Mirabelle", priority = 2 }, { name = "Mirko", priority = 3 } } end
    local holder = CreateFrame("Frame", "RikRenderAutoComplete", UIParent)
    holder:SetSize(240, 130)
    holder:SetPoint("CENTER")
    local edit = CreateFrame("EditBox", "RikRenderAutoCompleteEdit", holder, "AutoCompleteEditBoxTemplate")
    edit:SetSize(200, 24)
    edit:SetPoint("TOP", 0, -8)
    edit:SetAutoFocus(false)
    AutoCompleteEditBox_SetAutoCompleteSource(edit, GetAutoCompleteResults, AUTOCOMPLETE_FLAG_ALL, AUTOCOMPLETE_FLAG_NONE)
    edit:SetText("Mi")
    AutoComplete_Update(edit, "Mi", 2)
    AutoCompleteBox:ClearAllPoints()
    AutoCompleteBox:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -4)
    return holder
end

-- A legacy UIDropDownMenu list with a checked entry.
function RikRenderLegacyDropdown()
    local dropdown = CreateFrame("Frame", "RikRenderLegacyDropDown", UIParent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("CENTER")
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        for _, name in ipairs({ "Say", "Party", "Guild", "Officer" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.checked = name, name == "Party"
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    ToggleDropDownMenu(1, nil, dropdown, "cursor", 0, 0)
    DropDownList1:ClearAllPoints()
    DropDownList1:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    return DropDownList1
end
