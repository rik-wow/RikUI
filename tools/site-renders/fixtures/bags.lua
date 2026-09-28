-- Bags, merchant and loot: item identities the fixture supplies; RikUI still lays out the containers.

-- Inputs for two items whose artwork was extracted from the current client.
-- These supply game API data; RikUI still creates and paints every control.
function RikRenderItems()
    local items = {
        [6948] = { name = "Hearthstone", icon = 134414, count = 1 },
        [118] = { name = "Minor Healing Potion", icon = 134829, count = 5 },
    }
    local slots = { 6948, 118 }
    C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end
    C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 14 or 0, 0 end
    C_Container.GetContainerItemInfo = function(bag, slot)
        local id = bag == 0 and slots[slot]
        local item = items[id]
        if not item then return nil end
        return { itemID = id, iconFileID = item.icon, stackCount = item.count,
            quality = 1, isLocked = false, hasNoValue = false,
            hyperlink = "|cffffffff|Hitem:" .. id .. "::::::::10:::::|h[" .. item.name .. "]|h|r" }
    end
    C_Container.SetItemSearch = function() return false end
    C_Container.GetContainerItemQuestInfo = function() return { isQuestItem = false } end
    local texture, bagSlots = GetInventoryItemTexture, {}
    for bag = 1, 4 do bagSlots[C_Container.ContainerIDToInventoryID(bag)] = true end
    GetInventoryItemTexture = function(unit, slot)
        if unit == "player" and bagSlots[slot] then return nil end
        return texture(unit, slot)
    end
    GetNumLootItems = function() return 2 end
    GetLootSlotInfo = function(slot)
        local item = items[slots[slot]]
        if item then return item.icon, item.name, item.count, nil, 1, false, false end
    end
end

-- Bags: item identities the fixture supplies; the simulator knows none of these ids.
local BAG_ITEMS = {
    [6948] = { name = "Hearthstone", icon = 134414, count = 1, quality = 1, class = 15, subclass = 0 },
    [118] = { name = "Minor Healing Potion", icon = 134829, count = 5, quality = 1, class = 0, subclass = 1 },
    [2589] = { name = "Linen Cloth", icon = 132889, count = 12, quality = 1, class = 7, subclass = 5 },
    [117] = { name = "Tough Jerky", icon = 133971, count = 4, quality = 1, class = 0, subclass = 5 },
    [25] = { name = "Worn Shortsword", icon = 135274, count = 1, quality = 1, class = 2, subclass = 7, level = 2, equipLoc = "INVTYPE_WEAPON" },
    [3300] = { name = "Rabbit's Foot", icon = 133731, count = 3, quality = 0, class = 15, subclass = 0 },
    [3299] = { name = "Fractured Canine", icon = 133724, count = 2, quality = 0, class = 15, subclass = 0 },
    [2070] = { name = "Darnassian Bleu", icon = 133950, count = 6, quality = 1, class = 0, subclass = 5 },
    [4865] = { name = "Torn Note", icon = 134939, count = 1, quality = 1, class = 12, subclass = 0 },
}

local BAG_SLOTS = { 6948, 118, 2589, 117, 25, 3300, 3299, 2070, 4865 }

function RikRenderBagItems()
    local items, slots = BAG_ITEMS, BAG_SLOTS
    -- The backpack holds the items; one six-slot bag is equipped, the other bag slots are empty.
    C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 16 or bag == 1 and 6 or 0 end
    C_Container.GetContainerNumFreeSlots = function(bag)
        if bag == 0 then return 16 - #slots, 0 end
        if bag == 1 then return 6, 0 end
        return 0, 0
    end
    local inventoryTexture = GetInventoryItemTexture
    local bagSlots = {}
    for bag = 1, 4 do bagSlots[C_Container.ContainerIDToInventoryID(bag)] = bag end
    GetInventoryItemTexture = function(unit, inventoryID)
        local bag = bagSlots[inventoryID]
        if bag == 1 then return "Interface/Icons/INV_Misc_Bag_10" end
        if bag then return nil end
        return inventoryTexture(unit, inventoryID)
    end
    C_Container.GetContainerItemInfo = function(bag, slot)
        local id = bag == 0 and slots[slot]
        local item = items[id]
        if not item then return nil end
        return { itemID = id, iconFileID = item.icon, stackCount = item.count, quality = item.quality,
            isLocked = false, isReadable = false, hasLoot = false, hyperlink = "|cffffffff|Hitem:" .. id .. "::::::::10:::::|h[" .. item.name .. "]|h|r",
            isFiltered = false, hasNoValue = item.quality == 0 and false or false, itemName = item.name }
    end
    C_Container.GetContainerItemID = function(bag, slot) return bag == 0 and slots[slot] or nil end
    C_Container.GetContainerItemLink = function(bag, slot)
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.hyperlink
    end
    local itemInfo, instant = GetItemInfo, C_Item.GetItemInfoInstant
    local function known(id)
        if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) or tonumber(id) end
        return items[id], id
    end
    GetItemInfo = function(id)
        local item, numeric = known(id)
        if not item then return itemInfo(id) end
        return item.name, "|cffffffff|Hitem:" .. numeric .. "::::::::10:::::|h[" .. item.name .. "]|h|r", item.quality,
            item.level or 1, 1, nil, nil, item.count > 1 and 20 or 1, item.equipLoc or "", item.icon, item.quality == 0 and 3 or 25,
            item.class, item.subclass
    end
    C_Item.GetItemInfo = GetItemInfo
    C_Item.GetItemInfoInstant = function(id)
        local item, numeric = known(id)
        if not item then return instant(id) end
        return numeric, nil, nil, item.equipLoc or "", item.icon, item.class, item.subclass
    end
    C_Item.GetItemQualityByID = function(id) local item = known(id); return item and item.quality end
    return slots
end

function RikRenderBagFilter(value)
    assert(RikUI.Bags.SetFilter, "no bag filters")
    RikUI.Bags.SetFilter(value)
end

-- One slot holds an item that starts a quest, another a newly looted item.
function RikRenderBagMarkers(questSlot, newSlot)
    C_Container.GetContainerItemQuestInfo = function(bag, slot)
        local starts = bag == 0 and slot == questSlot
        return { isQuestItem = starts, questID = starts and 62 or nil, isActive = false }
    end
    C_NewItems = C_NewItems or {}
    C_NewItems.IsNewItem = function(bag, slot) return bag == 0 and slot == newSlot end
    RikUI.Bags.Refresh()
end

function RikRenderCapacityHUD(lowOnly)
    RikRenderSetOption("bags", "capacityHUD", true)
    RikRenderSetOption("bags", "capacityLowOnly", lowOnly == true)
    RikUI.Bags.UpdateCapacity()
    return RikUI.Bags.CapacityHUD
end

-- A merchant open: junk sale and repair controls appear in the bag window.
function RikRenderMerchant(repairCost)
    GetRepairAllCost = function() return repairCost or 0, (repairCost or 0) > 0 end
    CanMerchantRepair = function() return (repairCost or 0) > 0 end
    A_Admin.FireEvent("MERCHANT_SHOW")
    if RikUI.Bags.RefreshMerchant then RikUI.Bags.RefreshMerchant() end
    if RikUI.Bags.RefreshRepair then RikUI.Bags.RefreshRepair() end
end

-- Loot: coins take a slot of their own; a roll comes from the group loot readers.
function RikRenderLootCoins(copper)
    local count, info, slotType = GetNumLootItems, GetLootSlotInfo, GetLootSlotType
    local base = count()
    local gold, silver, cop = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. " Gold" end
    if silver > 0 then parts[#parts + 1] = silver .. " Silver" end
    if cop > 0 then parts[#parts + 1] = cop .. " Copper" end
    GetNumLootItems = function() return base + 1 end
    GetLootSlotInfo = function(slot)
        if slot == base + 1 then return "Interface\\Icons\\INV_Misc_Coin_02", table.concat(parts, "\n"), 0, nil, 1 end
        return info(slot)
    end
    GetLootSlotType = function(slot)
        if slot == base + 1 then return 2 end
        return slotType and slotType(slot) or 1
    end
end

function RikRenderLootRoll(name, icon, quality, seconds)
    local link = "|cff1eff00|Hitem:2488::::::::10:::::|h[" .. name .. "]|h|r"
    GetLootRollItemInfo = function() return icon, name, 1, quality, true, true, true, false, nil, nil, nil, nil, false end
    GetLootRollItemLink = function() return link end
    GetLootRollTimeLeft = function() return (seconds or 60) * 0.6 end
    GroupLootContainer_AddRoll(1, seconds or 60)
    assert(GroupLootFrame1:IsShown(), "roll frame hidden")
    GroupLootFrame1.Timer:SetValue((seconds or 60) * 0.6)
    if RikUI.Loot.SkinRolls then RikUI.Loot.SkinRolls() end
    return GroupLootFrame1
end

function RikRenderLootConfirm(name)
    local popup = StaticPopup_Show("LOOT_BIND", name)
    assert(popup, "no loot confirmation")
    return popup
end
