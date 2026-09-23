-- Cooldown tools live inside the shared utility flyout; native viewers stay on the HUD.
local core, viewer, skin, media = RikUI, RikUI.CooldownViewer, RikUI.Skin, RikUI.Media
local CVAR, HEIGHT = "cooldownViewerEnabled", 28
local ACCENT = { 0.3, 0.75, 1, 1 }
local notice = ""

local function enabled()
    if type(C_CVar) ~= "table" or type(C_CVar.GetCVarBool) ~= "function" then return nil end
    local ok, value = pcall(C_CVar.GetCVarBool, CVAR)
    if not ok or (type(issecretvalue) == "function" and issecretvalue(value)) then return nil end
    if type(value) == "boolean" then return value end
end

local function available()
    return not InCombatLockdown() and not viewer.Editing()
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
        viewer.RefreshControls()
    end)
    return control
end

function viewer.RefreshControls()
    local dock = viewer.Controls
    if not dock then return end
    local state, usable = enabled(), available()
    local setter = type(C_CVar) == "table" and type(C_CVar.SetCVar) == "function"
    dock.toggle.label:SetText(state == nil and "Cooldowns: N/A" or (state and "Cooldowns: On" or "Cooldowns: Off"))
    dock.toggle.label:SetTextColor(unpack(state and ACCENT or { 0.8, 0.83, 0.88 }))
    dock.move.label:SetText(viewer.Moving() and "Done" or "Move groups")
    dock.toggle:SetEnabled(usable and state ~= nil and setter)
    dock.move:SetEnabled(usable)
    dock.settings:SetEnabled(usable and type(ShowUIPanel) == "function" and CooldownViewerSettings ~= nil)
    dock.message:SetText(InCombatLockdown() and "Controls locked in combat"
        or (viewer.Editing() and "Finish Edit Mode to use these controls" or notice))
    for _, control in ipairs({ dock.toggle, dock.move, dock.settings }) do
        control:SetAlpha(control:IsEnabled() and 1 or 0.45)
    end
end

local function toggle()
    local state = enabled()
    if state == nil or type(C_CVar.SetCVar) ~= "function" then return end
    local wanted = not state
    local ok = pcall(C_CVar.SetCVar, CVAR, wanted and "1" or "0")
    if not ok or enabled() ~= wanted then notice = "Cooldown setting unavailable on this character" end
end

local function settings()
    if type(ShowUIPanel) ~= "function" or not CooldownViewerSettings then return end
    core.Shell.Close()
    local ok = pcall(ShowUIPanel, CooldownViewerSettings)
    if not ok then notice = "Cooldown settings are unavailable" end
end

local function buildControls(parent)
    local dock = CreateFrame("Frame", nil, parent)
    viewer.Controls = dock
    dock:SetSize(280, HEIGHT)
    dock.toggle = button(dock, 278, 0, "Cooldowns", "Show or hide cooldowns", toggle)
    dock.move = button(dock, 134, 0, "Move groups", "Move cooldown groups; click Done to save", function()
        viewer.SetMoving(not viewer.Moving())
        core.Shell.Refresh()
    end)
    dock.settings = button(dock, 140, 138, "Tracked spells", "Choose tracked spells and buffs", settings)
    dock.message = dock:CreateFontString(nil, "OVERLAY")
    media.Font(dock.message, "small")
    dock.message:SetTextColor(1, 0.82, 0)
    dock.move:ClearAllPoints(); dock.move:SetPoint("TOPLEFT", 0, -34)
    dock.settings:ClearAllPoints(); dock.settings:SetPoint("TOPLEFT", 138, -34)
    dock.message:SetPoint("TOPLEFT", 0, -66); dock.message:SetWidth(278); dock.message:SetHeight(28)
    viewer.RefreshControls()
    return dock
end

function viewer.CreateControls()
    if core.Shell.Entries.cooldowns then return end
    core.Shell.Register("cooldowns", { group = "Tools", order = 10, height = 96,
        build = buildControls, refresh = viewer.RefreshControls })
    core:RegisterEvent("CVAR_UPDATE", function(_, name)
        if type(issecretvalue) == "function" and issecretvalue(name) then return end
        if type(name) == "string" and name:lower() == CVAR:lower() then notice = ""; viewer.RefreshControls() end
    end, viewer)
    viewer.RefreshControls()
end
