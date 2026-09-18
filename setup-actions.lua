-- Synchronous action-slot writer, called only through Apply's combat queue.
local core, setup = RikUI, RikUI.Setup
local FIRST_BAG, DEFAULT_LAST_BAG = 0, 4

local function carriedItem(name)
    if not C_Container or type(C_Container.GetContainerNumSlots) ~= "function"
        or type(C_Container.GetContainerItemID) ~= "function" then
        return nil, "bag lookup unavailable"
    end
    if not C_Item or type(C_Item.GetItemInfo) ~= "function" then return nil, "item lookup unavailable" end
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or DEFAULT_LAST_BAG
    local uncached = false
    for bag = FIRST_BAG, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                local itemName = C_Item.GetItemInfo(id)
                if itemName == name then return id end
                if not itemName then uncached = true end
            end
        end
    end
    if uncached then return nil, "bag item data not loaded; retry Apply after items load" end
end

local function resolveAction(entry)
    if entry.spell then
        local id, reason = core.Spells.HighestKnownRank(entry.spell)
        return "spell", id, reason
    end
    if entry.macro then
        local id, reason = core.Macros.Find(entry.macro)
        return "macro", id, reason
    end
    local id, reason = carriedItem(entry.item)
    return "item", id, reason
end

local function pickup(kind, id)
    if kind == "spell" then return C_Spell.PickupSpell(id) end
    if kind == "item" then return C_Item.PickupItem(id) end
    return PickupMacro(id)
end

local function writeAction(slot, kind, id)
    local oldKind = GetActionInfo(slot)
    ClearCursor()
    if not id then
        if oldKind then PickupAction(slot); ClearCursor() end
        if GetActionInfo(slot) ~= nil then return nil, "could not clear slot " .. slot end
        return { placed = 0, skipped = 1, edited = oldKind and 1 or 0 }
    end
    pickup(kind, id)
    if GetCursorInfo() ~= kind then return nil, "pickup failed for slot " .. slot end
    PlaceAction(slot)
    ClearCursor()
    local placedKind, placedID = GetActionInfo(slot)
    if placedKind ~= kind or placedID ~= id then return nil, "placement rejected at slot " .. slot end
    return { placed = oldKind and 0 or 1, skipped = 0, edited = oldKind and 1 or 0 }
end

function setup.WriteSlot(slot, entry)
    if InCombatLockdown() then return nil, "slot write requires leaving combat" end
    local readOK, kind, id, reason = pcall(resolveAction, entry)
    if not readOK then return nil, "action lookup failed for slot " .. slot .. ": " .. tostring(kind) end
    if reason then return nil, "slot " .. slot .. ": " .. reason end
    local ok, stats
    ok, stats, reason = pcall(writeAction, slot, kind, id)
    -- Cleanup even when a pickup/placement API throws.
    local cleared = pcall(ClearCursor)
    if not ok then return nil, "slot " .. slot .. ": " .. tostring(stats) end
    if not cleared then return nil, "cursor cleanup failed at slot " .. slot end
    return stats, reason
end
