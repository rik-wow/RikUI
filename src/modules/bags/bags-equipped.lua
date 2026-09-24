-- Equipped bag targets use the same hardware-action APIs as BaseBagSlotButtonMixin.
-- Plain buttons keep the movable bag window unprotected and leave native inventory fields alone.
local core, bags, media = RikUI, RikUI.Bags, RikUI.Media
local SIZE, GAP, COUNT = 30, 4, 4
local slots = {}

local function plainNumber(value)
    return not core.Secret.IsSecret(value) and type(value) == "number"
end

local function inventoryID(bag)
    if type(C_Container.ContainerIDToInventoryID) == "function" then
        local ok, id = pcall(C_Container.ContainerIDToInventoryID, bag)
        if ok and plainNumber(id) then return id end
    end
    if type(GetInventorySlotInfo) == "function" then
        local ok, id = pcall(GetInventorySlotInfo, "Bag" .. (bag - 1) .. "Slot")
        if ok and plainNumber(id) then return id end
    end
end

local function act(button, pickup)
    if InCombatLockdown() then
        core:Print("Replace bags after combat.")
        return
    end
    local id = inventoryID(button:GetID())
    local action = PutItemInBag
    if pickup then action = PickupBagFromSlot end
    if not id or type(action) ~= "function" then
        bags.Warn("equipped", "bag replacement unavailable on this client")
        return
    end
    if not pickup and (type(CursorHasItem) ~= "function" or not CursorHasItem()) then return end
    local ok, reason = pcall(action, id)
    if not ok then bags.Warn("equipped", reason) end
    -- Never clear the cursor: the old bag or a refused replacement stays in the player's hand.
end

local function tooltip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    local id = inventoryID(button:GetID())
    if not id or not GameTooltip:SetInventoryItem("player", id) then
        GameTooltip:SetText("Empty bag slot " .. button:GetID())
    end
    GameTooltip:AddLine("Drop a bag here to equip or replace it.", 0.9, 0.92, 0.96, true)
    GameTooltip:AddLine("Drag this bag to move it. Replacements must fit its contents.", 0.65, 0.7, 0.78, true)
    GameTooltip:Show()
end

function bags.CreateEquipped(holder)
    -- The TOC loads Skin after this file; all services exist by module activation.
    local skin = core.Skin
    for bag = 1, COUNT do
        local button = CreateFrame("Button", nil, holder)
        button:SetID(bag)
        button:SetSize(SIZE, SIZE)
        button:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 8 + (bag - 1) * (SIZE + GAP), 26)
        button.fill = skin.Fill(button, skin.CONTROL)
        button.border = skin.Outline(button, nil, 0, nil, "OVERLAY")
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        skin.CropIcon(button.icon)
        button.count = button:CreateFontString(nil, "OVERLAY")
        media.Font(button.count, "small")
        button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        button:SetHighlightTexture(media.highlight, "ADD")
        button:RegisterForClicks("LeftButtonUp")
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnClick", function(self) act(self, false) end)
        button:SetScript("OnReceiveDrag", function(self) act(self, false) end)
        button:SetScript("OnDragStart", function(self) act(self, true) end)
        button:SetScript("OnEnter", tooltip)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        slots[bag] = button
    end
    holder.equipped = slots
    holder.bagHint = holder:CreateFontString(nil, "OVERLAY")
    media.Font(holder.bagHint, "small")
    holder.bagHint:SetPoint("LEFT", slots[COUNT], "RIGHT", 10, 0)
    holder.bagHint:SetText("Equipped bags\nDrop a bag to replace")
    holder.bagHint:SetTextColor(0.7, 0.75, 0.82)
end

function bags.RefreshEquipped()
    for bag, button in ipairs(slots) do
        local id, icon = inventoryID(bag)
        if id and type(GetInventoryItemTexture) == "function" then
            local ok, value = pcall(GetInventoryItemTexture, "player", id)
            if ok and not core.Secret.IsSecret(value) then icon = value end
        end
        button.icon:SetTexture(icon)
        local ok, size = pcall(C_Container.GetContainerNumSlots, bag)
        button.count:SetText(ok and plainNumber(size) and size > 0 and tostring(size) or "+")
    end
end

