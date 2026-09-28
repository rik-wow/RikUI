-- Tooltips through GameTooltip's own setters.

-- Tooltips through GameTooltip's own setters; RikUI's anchor hook places the frame.
function RikRenderTooltip(kind, a, b)
    local tip = GameTooltip
    -- The tooltip's unit health bar polls this client reader, which the simulator lacks.
    UnitPercentHealthFromGUID = UnitPercentHealthFromGUID or function()
        return math.floor(UnitHealth("target") / math.max(1, UnitHealthMax("target")) * 100 + 0.5)
    end
    -- The PTR issue reporter appends a keybind notice to every tooltip on test builds.
    if type(PTR_IssueReporter) == "table" then PTR_IssueReporter.HookIntoTooltip = function() end end
    GameTooltip_SetDefaultAnchor(tip, UIParent)
    if kind == "unit" then tip:SetUnit(a or "target")
    elseif kind == "item" then tip:SetItemByID(a)
    elseif kind == "spell" then tip:SetSpellByID(a)
    elseif kind == "inventory" then tip:SetInventoryItem("player", a)
    elseif kind == "aura" then tip:SetUnitAura("player", a or 1, b or "HELPFUL")
    else error("Unknown tooltip kind " .. tostring(kind)) end
    tip:Show()
    RikRenderRemeasure(tip)
    return tip
end

function RikRenderCompareTooltip(slot)
    local tip = RikRenderTooltip("inventory", slot or 16)
    GameTooltip_ShowCompareItem(tip)
    RikRenderRemeasure(ShoppingTooltip1)
    RikRenderRemeasure(ShoppingTooltip2)
    return tip
end
