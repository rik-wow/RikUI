-- Cooldown tools in the shared utility flyout: move the strip and the effect rows, and open
-- Blizzard's Tracked spells window, which still edits the native part of the list.
local core, panel, skin, media, layout = RikUI, RikUI.Cooldowns, RikUI.Skin, RikUI.Media, RikUI.Layout
local controls = {}
panel.Controls = controls
local HEIGHT, ACCENT = 28, { 0.3, 0.75, 1, 1 }
local MOVE_KEYS = { "cooldowns", "classbuffs", "classeffects" }
local notice = ""

local function editing() return core.EditMode ~= nil and core.EditMode.IsActive() end
local function available() return not InCombatLockdown() and not editing() end

local function moving()
    if type(layout.IsUnlocked) ~= "function" then return false end
    for _, key in ipairs(MOVE_KEYS) do
        if layout.IsUnlocked(key) then return true end
    end
    return false
end

local function setMoving(open)
    if type(layout.SetUnlocked) ~= "function" or (open and not available()) then return end
    if not open and layout.EndDrag then layout.EndDrag() end
    for _, key in ipairs(MOVE_KEYS) do
        if layout.Groups[key] then layout.SetUnlocked(key, open) end
    end
end

local function button(dock, width, x, label, tip, click)
    local control = CreateFrame("Button", nil, dock)
    control:SetSize(width, HEIGHT)
    control:SetPoint("TOPLEFT", dock, "TOPLEFT", x, 0)
    skin.Fill(control, skin.CONTROL)
    control.edge = skin.Outline(control, skin.LINE)
    control.label = control:CreateFontString(nil, "OVERLAY")
    media.Font(control.label, "small")
    control.label:SetPoint("CENTER", control, "CENTER", 0, 0)
    control.label:SetText(label)
    control:SetScript("OnEnter", function()
        for _, line in ipairs(control.edge) do line:SetVertexColor(unpack(ACCENT)) end
        if type(GameTooltip) ~= "table" then return end
        GameTooltip:SetOwner(control, "ANCHOR_TOP")
        GameTooltip:SetText(tip)
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function()
        for _, line in ipairs(control.edge) do line:SetVertexColor(unpack(skin.LINE)) end
        if type(GameTooltip) == "table" then GameTooltip:Hide() end
    end)
    control:SetScript("OnMouseDown", function() if available() then control.label:SetAlpha(0.65) end end)
    control:SetScript("OnMouseUp", function() control.label:SetAlpha(1) end)
    control:SetScript("OnClick", function()
        if not available() then return end
        notice = ""
        click()
        controls.Refresh()
    end)
    return control
end

function controls.Refresh()
    local dock = controls.Dock
    if not dock then return end
    local usable = available()
    dock.move.label:SetText(moving() and "Done" or "Move")
    dock.move:SetEnabled(usable)
    dock.settings:SetEnabled(usable and type(ShowUIPanel) == "function" and CooldownViewerSettings ~= nil)
    dock.message:SetText(InCombatLockdown() and "Controls locked in combat"
        or (editing() and "Finish Edit Mode to use these controls" or notice))
    for _, control in ipairs({ dock.move, dock.settings }) do
        control:SetAlpha(control:IsEnabled() and 1 or 0.45)
    end
end

local function openSettings()
    local ok, reason = panel.Native.OpenSettings()
    if not ok then notice = reason end
end

local function build(parent)
    local dock = CreateFrame("Frame", nil, parent)
    controls.Dock = dock
    dock:SetSize(280, HEIGHT)
    dock.move = button(dock, 134, 0, "Move", "Move the cooldown strip and effect rows; click Done to save", function()
        setMoving(not moving())
        core.Shell.Refresh()
    end)
    dock.settings = button(dock, 140, 138, "Tracked spells", "Choose the client's tracked spells and buffs", openSettings)
    dock.message = dock:CreateFontString(nil, "OVERLAY")
    media.Font(dock.message, "small")
    dock.message:SetTextColor(1, 0.82, 0)
    dock.message:SetPoint("TOPLEFT", 0, -34); dock.message:SetWidth(278); dock.message:SetHeight(28)
    controls.Refresh()
    return dock
end

function controls.Create()
    if core.Shell.Entries.cooldowns then return end
    core.Shell.Register("cooldowns", { group = "Tools", order = 10, height = 62, build = build, refresh = controls.Refresh })
    core:RegisterEvent("PLAYER_REGEN_DISABLED", function() setMoving(false) end, panel)
end
