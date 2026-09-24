-- New-item state belongs to the client; this badge only presents and acknowledges it.
local core, bags = RikUI, RikUI.Bags

function bags.UpdateNewItem(button)
    local fresh = false
    if button.rikFilled and C_NewItems and type(C_NewItems.IsNewItem) == "function" then
        local ok, value = pcall(C_NewItems.IsNewItem, button:GetParent():GetID(), button:GetID())
        fresh = ok and not core.Secret.IsSecret(value) and value == true
    end
    button.rikFresh = fresh
    button.rikNew:SetShown(fresh)
end

local function acknowledge(button)
    if not button.rikFilled or not C_NewItems or type(C_NewItems.RemoveNewItem) ~= "function" then return end
    local ok, reason = pcall(C_NewItems.RemoveNewItem, button:GetParent():GetID(), button:GetID())
    if not ok then bags.Warn("new item", reason) end
    bags.UpdateButton(button)
    bags.UpdateTitle()
end

function bags.CreateNewItem(button)
    button.rikNew = button:CreateFontString(nil, "OVERLAY")
    core.Media.Font(button.rikNew, "small")
    button.rikNew:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button.rikNew:SetText("N")
    button.rikNew:SetTextColor(1, 0.82, 0)
    button.rikNew:SetShown(false)
    button:HookScript("OnEnter", acknowledge)
end

