-- Shared controls: Blizzard's own control templates on a plain frame, passed through RikUI's controls
-- walk the way every skinned window's controls are. The fixture builds nothing of its own.

-- One row per control kind; the holder is the capture root and each control is named for a tight crop.
function RikRenderControls()
    local holder = CreateFrame("Frame", "RikRenderControls", UIParent)
    holder:SetSize(560, 300)
    holder:SetPoint("CENTER")
    RikUI.Skin.Fill(holder, { 0.055, 0.075, 0.095, 1 })

    local button = CreateFrame("Button", "RikRenderControlButton", holder, "UIPanelButtonTemplate")
    button:SetSize(120, 22); button:SetPoint("TOPLEFT", 24, -24); button:SetText("Accept")

    local disabled = CreateFrame("Button", "RikRenderControlDisabled", holder, "UIPanelButtonTemplate")
    disabled:SetSize(150, 22); disabled:SetPoint("LEFT", button, "RIGHT", 16, 0); disabled:SetText("Locked"); disabled:Disable()

    local check = CreateFrame("CheckButton", "RikRenderControlCheck", holder, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 24, -64); check:SetChecked(true)
    check.text = check.text or _G[check:GetName() .. "Text"]
    if check.text then check.text:SetText("Show helm") end
    local unchecked = CreateFrame("CheckButton", "RikRenderControlUnchecked", holder, "UICheckButtonTemplate")
    unchecked:SetPoint("LEFT", check, "RIGHT", 120, 0); unchecked:SetChecked(false)
    if unchecked.text or _G[unchecked:GetName() .. "Text"] then (unchecked.text or _G[unchecked:GetName() .. "Text"]):SetText("Show cloak") end

    local edit = CreateFrame("EditBox", "RikRenderControlEdit", holder, "InputBoxTemplate")
    edit:SetSize(200, 24); edit:SetPoint("TOPLEFT", 32, -112); edit:SetAutoFocus(false); edit:SetText("Mira")

    local slider = CreateFrame("Slider", "RikRenderControlSlider", holder, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("TOPLEFT", 24, -156); slider:Init(60, 0, 100, 10)

    local dropdown = CreateFrame("DropdownButton", "RikRenderControlDropdown", holder, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", 24, -212); dropdown:SetWidth(160)
    dropdown:SetupMenu(function(_, root)
        root:CreateRadio("Party", function() return true end, function() end)
        root:CreateRadio("Guild", function() return false end, function() end)
    end)

    local swatch = CreateFrame("Button", "RikRenderControlSwatch", holder, "ColorSwatchTemplate")
    swatch:SetPoint("LEFT", dropdown, "RIGHT", 24, 0); swatch:SetSize(20, 20)
    if swatch.Color then swatch.Color:SetVertexColor(0.3, 0.75, 1) end

    local scroll = CreateFrame("EventFrame", "RikRenderControlScroll", holder, "MinimalScrollBar")
    scroll:SetPoint("TOPRIGHT", -24, -24); scroll:SetHeight(180)
    scroll:SetScrollPercentage(0.3, ScrollBoxConstants.NoScrollInterpolation)

    RikUI.Controls.Walk(holder)
    RikRenderResize(holder)
    return holder
end
