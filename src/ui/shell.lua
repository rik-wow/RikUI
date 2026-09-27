-- One expandable utility surface. Modules register actions or bounded custom sections.
local core, skin, media = RikUI, RikUI.Skin, RikUI.Media
local shell = { Entries = {}, Groups = { "Interface", "Tools", "Support" } }
core.Shell = shell
local WIDTH, PAD, ROW_HEIGHT, HEADER_HEIGHT = 320, 14, 30, 44
local ACCENT = { 0.3, 0.75, 1, 1 }
local GROUP_ICONS = { Interface = "settings", Tools = "menu", Support = "help" }

function shell.Text(parent, text, role)
    local label = parent:CreateFontString(nil, "OVERLAY")
    media.Font(label, role or "label")
    label:SetText(text)
    label:SetJustifyH("LEFT")
    return label
end

function shell.Button(parent, label, click)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(ROW_HEIGHT)
    skin.Fill(button, skin.CONTROL)
    button.label = shell.Text(button, label)
    button.label:SetPoint("LEFT", button, "LEFT", 10, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -10, 0)
    button.label:SetWordWrap(false)
    core.Motion.BindHover(button)
    core.Motion.BindPress(button)
    button:SetScript("OnClick", click)
    return button
end

local function invoke(entry, key, ...)
    local ok, value = pcall(entry[key], ...)
    if ok then return value end
    if not entry.warned then
        entry.warned = true
        core:Print("Utility " .. entry.id .. " unavailable: " .. tostring(value))
    end
end

local function allowed(entry, key)
    return not entry[key] or invoke(entry, key)
end

function shell.Close()
    core.Motion.CloseOwned(shell.Panel)
end

function shell.Register(id, entry)
    entry.id = id
    local previous = shell.Entries[id]
    if previous and previous.frame then previous.frame:Hide() end
    shell.Entries[id] = entry
    if shell.Panel then shell.Rebuild() end
end

local function sortedEntries(group)
    local entries = {}
    for _, entry in pairs(shell.Entries) do
        if entry.group == group and allowed(entry, "visible") then entries[#entries + 1] = entry end
    end
    table.sort(entries, function(a, b) return (a.order or 100) < (b.order or 100)
        or ((a.order or 100) == (b.order or 100) and a.id < b.id) end)
    return entries
end

local function actionFrame(entry, parent)
    local button = shell.Button(parent, "", function()
        if entry.warned or not allowed(entry, "enabled") or not allowed(entry, "visible") then return end
        if not entry.keepOpen then shell.Close() end
        invoke(entry, "action")
        shell.Refresh()
    end)
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", 12, 0); button.label:SetPoint("RIGHT", -30, 0)
    button.chevron = media.Icon(button, "chevron-right", 10, "OVERLAY")
    button.chevron:SetPoint("RIGHT", -10, 0)
    button.chevron:SetVertexColor(0.55, 0.66, 0.76, 1)
    return button
end

local function placeEntry(entry, parent, y)
    entry.frame = entry.frame or (entry.build and invoke(entry, "build", parent) or (entry.action and actionFrame(entry, parent)))
    local frame = entry.frame
    if not frame then return y end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    frame:SetWidth(WIDTH - PAD * 2 - 14)
    frame:SetHeight(entry.height or ROW_HEIGHT)
    frame:Show()
    return y + (entry.height or ROW_HEIGHT) + 4
end

function shell.Rebuild()
    local panel, y = shell.Panel, 0
    if not panel then return end
    for _, entry in pairs(shell.Entries) do if entry.frame then entry.frame:Hide() end end
    for _, title in pairs(panel.headings) do title:Hide() end
    for _, icon in pairs(panel.groupIcons) do icon:Hide() end
    for _, group in ipairs(shell.Groups) do
        local entries = sortedEntries(group)
        if #entries > 0 then
            local title = panel.headings[group] or shell.Text(panel.scroll.content, group, "small")
            panel.headings[group] = title
            title:ClearAllPoints(); title:SetPoint("TOPLEFT", 24, -y - 2); title:SetTextColor(unpack(ACCENT)); title:Show()
            local icon = panel.groupIcons[group] or media.Icon(panel.scroll.content, GROUP_ICONS[group], 16)
            panel.groupIcons[group] = icon
            icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", 2, -y); icon:SetVertexColor(unpack(ACCENT)); icon:Show()
            y = y + 24
            for _, entry in ipairs(entries) do y = placeEntry(entry, panel.scroll.content, y) end
            y = y + 10
        end
    end
    local height = math.min(y, math.max(160, (UIParent:GetHeight() or 800) * 0.65))
    panel:SetSize(WIDTH, height + HEADER_HEIGHT + PAD)
    panel.scroll:SetSize(WIDTH - PAD * 2, height)
    core.Scroll.SetContentHeight(panel.scroll, y)
    shell.Refresh()
end

local function entryLabel(entry)
    local label = entry.label
    if type(label) == "function" then label = invoke(entry, "label") end
    return type(label) == "string" and label or (entry.id .. " (unavailable)")
end

function shell.Refresh()
    for _, entry in pairs(shell.Entries) do
        local frame = entry.frame
        if frame then
            if entry.refresh then invoke(entry, "refresh", frame) end
            if entry.action then
                frame.label:SetText(entryLabel(entry))
                local enabled = not entry.warned and allowed(entry, "enabled")
                frame:SetEnabled(enabled)
                frame:SetAlpha(enabled and 1 or 0.4)
            end
        end
    end
    if shell.Launcher then
        local moving = core.Layout and core.Layout.IsMoving()
        shell.Launcher.label:SetText(moving and "Done" or "RikUI")
    end
end

function shell.Anchor()
    local launcher = shell.Launcher
    if not launcher or InCombatLockdown() then return end
    local minimap = core.Minimap and core.Minimap.Holder
    launcher:ClearAllPoints()
    if minimap then
        launcher:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", -4, 4)
        launcher:SetScale(minimap:GetEffectiveScale() / UIParent:GetEffectiveScale())
    else
        launcher:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -32)
    end
end

local function createPanel()
    local panel = CreateFrame("Frame", "RikUIUtilityPanel", UIParent)
    shell.Panel = panel
    panel:Hide()
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel.chrome = skin.WindowChrome(panel, HEADER_HEIGHT)
    panel.title = shell.Text(panel, "RikUI", "heading")
    panel.title:SetPoint("TOPLEFT", PAD, -PAD)
    panel.close = shell.Button(panel, "", shell.Close)
    panel.close.icon = media.Icon(panel.close, "close", 10, "OVERLAY")
    panel.close.icon:SetPoint("CENTER")
    panel.close:SetSize(28, 24); panel.close:SetPoint("TOPRIGHT", -PAD, -10)
    panel.scroll = core.Scroll.Create(panel)
    panel.scroll:SetPoint("TOPLEFT", PAD, -HEADER_HEIGHT)
    panel.headings, panel.groupIcons = {}, {}
    core.Motion.BindEntrance(panel, true)
    panel:SetScript("OnShow", shell.Rebuild)
    panel:SetScript("OnHide", function() if shell.Dismiss then shell.Dismiss:Hide() end end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "RikUIUtilityPanel") end
    return panel
end

function shell.Open()
    shell.Initialize()
    shell.Rebuild()
    shell.Dismiss:Show()
    core.Motion.CancelClose(shell.Panel)
    shell.Panel:Show()
end

function shell.Initialize()
    if shell.Launcher then return end
    local panel = createPanel()
    local dismiss = CreateFrame("Button", nil, UIParent)
    shell.Dismiss = dismiss
    dismiss:SetAllPoints(UIParent); dismiss:SetFrameStrata("DIALOG")
    dismiss:SetFrameLevel(math.max(0, (panel:GetFrameLevel() or 1) - 1))
    dismiss:SetScript("OnClick", shell.Close); dismiss:Hide()
    local launcher = shell.Button(UIParent, "RikUI", function()
        if core.Layout and core.Layout.IsMoving() then core.Layout.LockAll(); shell.Refresh(); return end
        if panel:IsShown() then shell.Close() else shell.Open() end
    end)
    shell.Launcher = launcher
    launcher:SetSize(64, 24); launcher:SetFrameStrata("DIALOG")
    launcher:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -32)
    skin.Outline(launcher, ACCENT)
    panel:SetPoint("TOPRIGHT", launcher, "BOTTOMRIGHT", 0, -6)
    shell.Anchor()
    shell.Rebuild()
    local elapsed = 0
    launcher:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.25 then return end
        elapsed = 0
        local moving = core.Layout and core.Layout.IsMoving()
        if moving ~= launcher.moving or panel:IsShown() then shell.Refresh() end
        launcher.moving = moving
    end)
end

core:RegisterEvent("PLAYER_LOGIN", function() shell.Initialize(); shell.Anchor() end)
core:RegisterEvent("PLAYER_ENTERING_WORLD", function() shell.Anchor(); shell.Refresh() end)
core:RegisterEvent("PLAYER_REGEN_ENABLED", function() shell.Anchor(); shell.Refresh() end)
core:RegisterEvent("PLAYER_REGEN_DISABLED", function() shell.Close(); shell.Refresh() end)
core:RegisterEvent("UI_SCALE_CHANGED", function() shell.Anchor() end)
