-- Flat cosmetic regions only; secure actions and visibility belong to bars.lua.
local core, bars, media = RikUI, RikUI.Bars, RikUI.Media
local ICON_MIN, ICON_MAX, EDGE = 0.07, 0.93, 1
local GRYPHON = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf"
local GRYPHON_SIZE, GRYPHON_OVERLAP = 96, 8

local function borderEdge(button, first, second, horizontal)
    local edge = button:CreateTexture(nil, "OVERLAY")
    edge:SetTexture(media.border)
    edge:SetVertexColor(0.25, 0.28, 0.32, 1)
    edge:SetPoint(first, button, first, 0, 0)
    edge:SetPoint(second, button, second, 0, 0)
    if horizontal then edge:SetHeight(EDGE) else edge:SetWidth(EDGE) end
    return edge
end

function bars.DecorateButton(button)
    button:ClearNormalTexture()
    button.empty = button:CreateTexture(nil, "BACKGROUND")
    button.empty:SetAllPoints()
    button.empty:SetColorTexture(0.055, 0.065, 0.08, 0.95)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", EDGE, -EDGE)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -EDGE, EDGE)
    button.icon:SetTexCoord(ICON_MIN, ICON_MAX, ICON_MIN, ICON_MAX)
    button.border = {
        borderEdge(button, "TOPLEFT", "TOPRIGHT", true),
        borderEdge(button, "BOTTOMLEFT", "BOTTOMRIGHT", true),
        borderEdge(button, "TOPLEFT", "BOTTOMLEFT", false),
        borderEdge(button, "TOPRIGHT", "BOTTOMRIGHT", false),
    }
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    media.Font(button.count, "count")
    button:SetHighlightTexture(media.highlight, "ADD")
    button:SetPushedTexture(media.highlight, "ADD")
end

function bars.CreateActiveTexture(parent)
    local texture = parent:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetTexture(media.checked)
    texture:SetVertexColor(1, 0.78, 0.3, 1)
    texture:SetAlphaFromBoolean(false, 1, 0)
    return texture
end

function bars.SkinButtonState(button)
    media.Font(button.hotkey, "hotkey")
    media.Font(button.cooldown:GetCountdownFontString(), "cooldown")
    media.Font(button.chargeCooldown:GetCountdownFontString(), "charge")
    for _, edge in ipairs(button.border) do edge:SetParent(button.stateOverlay) end
    button.current = bars.CreateActiveTexture(button.stateOverlay)
    button.repeating = bars.CreateActiveTexture(button.stateOverlay)
end

local function gryphon(bar, right)
    local art = bar:CreateTexture(nil, "BACKGROUND")
    art:SetTexture(GRYPHON)
    art:SetSize(GRYPHON_SIZE, GRYPHON_SIZE)
    art:SetPoint(right and "BOTTOMLEFT" or "BOTTOMRIGHT", bar,
        right and "BOTTOMRIGHT" or "BOTTOMLEFT", right and -GRYPHON_OVERLAP or GRYPHON_OVERLAP, -12)
    if right then art:SetTexCoord(1, 0, 0, 1) end
    return art
end

function bars.UpdateGryphons(bar)
    if (bar.positionKey or bar.key) ~= "main" then return end
    if not bar.gryphons then bar.gryphons = { gryphon(bar, false), gryphon(bar, true) } end
    for _, art in ipairs(bar.gryphons) do art:SetShown(core.Profile.gryphons == true) end
end

core:RegisterCommand("gryphons", function(args)
    if not core.Profile then core:Print("Still loading."); return end
    if args ~= "on" and args ~= "off" then core:Print("Usage: /rik gryphons on|off"); return end
    core.Profile.gryphons = args == "on"
    bars.ApplyLayout()
end, "Show or hide main-bar gryphon end caps")
