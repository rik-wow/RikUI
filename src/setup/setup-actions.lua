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

-- A macro earns its slot once the character knows one of the attacks it
-- casts; a macro without a spells list is always placeable.
function setup.MacroKnown(macro)
    local spells = type(macro) == "table" and macro.spells
    if type(spells) ~= "table" or #spells == 0 then return true end
    local failure
    for _, name in ipairs(spells) do
        local id, reason = core.Spells.HighestKnownRank(name)
        if id then return true end
        failure = failure or reason
    end
    if failure then return nil, failure end
    return false
end

local function resolveMacro(entry, preset)
    local macros = type(preset) == "table" and preset.macros or {}
    local usable, reason = setup.MacroKnown(macros[entry.macro])
    if reason then return "macro", nil, reason end
    if not usable then return "macro", nil end
    local id
    id, reason = core.Macros.Find(entry.macro)
    return "macro", id, reason
end

local function resolveAction(entry, preset)
    if entry.spell then
        local id, reason = core.Spells.HighestKnownRank(entry.spell)
        return "spell", id, reason
    end
    if entry.macro then return resolveMacro(entry, preset) end
    local id, reason = carriedItem(entry.item)
    return "item", id, reason
end

-- A spell the preset expects at this level that the spellbook lookup did not find. An empty slot
-- says nothing about why, so Apply names these after the bars step. Stance pages repeat the main
-- bar, hence the set.
setup.Missing = {}

local function noteMissing(entry, kind, id)
    if kind ~= "spell" or id or type(entry.level) ~= "number" then return end
    local level = type(UnitLevel) == "function" and UnitLevel("player") or nil
    if type(level) == "number" and entry.level <= level then setup.Missing[entry.spell] = true end
end

local function pickup(kind, id)
    if kind == "spell" then return C_Spell.PickupSpell(id) end
    if kind == "item" then return C_Item.PickupItem(id) end
    return PickupMacro(id)
end

-- On 69913 a macro slot answers ("macro", <ID of the spell the macro casts>, "spell"), not the
-- macro's index, so a macro in a slot is identified by its name, which GetActionText returns.
function setup.MacroNameInSlot(slot)
    if type(GetActionText) ~= "function" then return nil end
    local ok, name = pcall(GetActionText, slot)
    if ok and type(name) == "string" and name ~= "" then return name end
end

function setup.SlotHolds(slot, kind, id)
    local placedKind, placedID = GetActionInfo(slot)
    if placedKind ~= kind then return false end
    if kind ~= "macro" then return placedID == id end
    local name = setup.MacroNameInSlot(slot)
    if not name then return placedID == id end
    return name == GetMacroInfo(id)
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
    if not setup.SlotHolds(slot, kind, id) then return nil, "placement rejected at slot " .. slot end
    return { placed = oldKind and 0 or 1, skipped = 0, edited = oldKind and 1 or 0 }
end

function setup.WriteSlot(slot, entry, preset)
    if InCombatLockdown() then return nil, "slot write requires leaving combat" end
    local readOK, kind, id, reason = pcall(resolveAction, entry, preset)
    if not readOK then return nil, "action lookup failed for slot " .. slot .. ": " .. tostring(kind) end
    if reason then return nil, "slot " .. slot .. ": " .. reason end
    noteMissing(entry, kind, id)
    return setup.RestoreSlot(slot, { kind = kind, id = id })
end

function setup.RestoreSlot(slot, action)
    if InCombatLockdown() then return nil, "slot restore requires leaving combat" end
    local ok, stats, reason = pcall(writeAction, slot, action.kind, action.id)
    -- Cleanup even when a pickup/placement API throws.
    local cleared = pcall(ClearCursor)
    if not ok then return nil, "slot " .. slot .. ": " .. tostring(stats) end
    if not cleared then return nil, "cursor cleanup failed at slot " .. slot end
    return stats, reason
end
