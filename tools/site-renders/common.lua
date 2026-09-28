-- Development fixture only; never loaded by RikUI.
assert(A_Admin and RikUI and RikUI.Runtime.loggedIn, "RikUI did not finish startup")
RikUI.Profile.reducedMotion = true
RikUI.Wizard.Close()
if GameMenuFrame then GameMenuFrame:Hide() end

function RikRenderCenter(frame, scale)
    assert(frame, "Missing preview frame")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetScale(scale or 1)
end

-- The headless simulator does not emit OnSizeChanged. Deliver the actual
-- callbacks using calculated sizes, leaving RikUI's layout code untouched.
function RikRenderResize(root)
    local previous = {}
    -- Secure aura frames refuse readouts from this tainted fixture; they lay themselves out.
    local function visit(frame)
        local readable, width, height = pcall(frame.GetSize, frame)
        if not readable then return end
        local old = previous[frame]
        if not old or old[1] ~= width or old[2] ~= height then
            previous[frame] = { width, height }
            local callback = frame:GetScript("OnSizeChanged")
            if callback then callback(frame, width, height) end
        end
        local listed, children = pcall(function() return { frame:GetChildren() } end)
        if not listed then return end
        for _, child in ipairs(children) do visit(child) end
    end
    for pass = 1, 6 do visit(root) end
end

function RikRenderCheck(root)
    assert(root, "Scenario root is missing")
    for _, entry in ipairs(RikUI:GetErrors()) do
        error(entry.context .. ": " .. entry.detail)
    end
    CreateFrame("Frame", "RIK_RENDER_OK", root):Hide()
end
-- The simulator's built-in spellbook and spell metadata belong to another game version. These
-- inputs describe a Forever paladin by level 10 using RikUI's own catalogue (data/spells-paladin.lua,
-- ranks and acquisition levels), so the addon's spellbook scans, icons and action textures read
-- the current client's spells. RikUI still resolves ranks, membership and drawing itself.
local PALADIN_SPELLS_BY_10 = { 635, 639, 20154, 20287, 465, 19740, 20271, 679, 498, 21082, 1152, 853, 633, 1022, 1311649 }
function RikRenderSpellbook()
    local catalog, icons, names, known, items = RikUI.Spells.Catalog("PALADIN"), {}, {}, {}, {}
    for name, entry in pairs(catalog) do
        for _, id in ipairs(entry.ranks) do icons[id], names[id] = entry.icon, name end
    end
    for _, id in ipairs(PALADIN_SPELLS_BY_10) do
        assert(icons[id], "Spell " .. id .. " is not in RikUI's paladin catalogue")
        known[id] = true
        items[#items + 1] = id
    end
    C_SpellBook.GetNumSpellBookSkillLines = function() return 1 end
    C_SpellBook.GetSpellBookSkillLineInfo = function(index)
        if index ~= 1 then return nil end
        return { name = "Paladin", iconID = 626003, itemIndexOffset = 0, numSpellBookItems = #items,
            isGuild = false, shouldHide = false, specID = nil, offSpecID = nil }
    end
    C_SpellBook.GetSpellBookItemInfo = function(slot, bank)
        local id = bank == Enum.SpellBookSpellBank.Player and items[slot]
        if not id then return nil end
        return { itemType = Enum.SpellBookItemType.Spell, spellID = id, actionID = id, name = names[id],
            iconID = icons[id], isOffSpec = false, isPassive = false, skillLineIndex = 1 }
    end
    local function isKnown(id) return known[id] == true end
    C_SpellBook.IsSpellKnown, C_SpellBook.IsSpellInSpellBook, C_SpellBook.IsSpellKnownOrOverridesKnown = isKnown, isKnown, isKnown
    IsSpellKnown, IsPlayerSpell, IsSpellKnownOrOverridesKnown = isKnown, isKnown, isKnown
    local texture, spellName = C_Spell.GetSpellTexture, C_Spell.GetSpellName
    C_Spell.GetSpellTexture = function(id) return icons[id] or texture(id) end
    C_Spell.GetSpellName = function(id) return names[id] or spellName(id) end
    -- The two action texture readers are wrapped separately and never call each other, so the
    -- simulator's own aliasing between them cannot loop.
    local busy = false
    local function catalogueTexture(fallback)
        return function(slot)
            if busy then return fallback(slot) end
            busy = true
            local kind, id = GetActionInfo(slot)
            busy = false
            if kind == "spell" and icons[id] then return icons[id] end
            return fallback(slot)
        end
    end
    GetActionTexture = catalogueTexture(GetActionTexture)
    if C_ActionBar and type(rawget(C_ActionBar, "GetActionTexture")) == "function" then
        C_ActionBar.GetActionTexture = catalogueTexture(rawget(C_ActionBar, "GetActionTexture"))
    end
end

-- Cooldown state for the strip: the simulator's Forever profile returns no cooldown duration
-- objects, so these supply them on the game clock; each entry is { id, duration, elapsed }.
function RikRenderCooldowns(entries)
    local now, durations = GetTime(), {}
    for _, entry in ipairs(entries) do
        local duration = C_DurationUtil.CreateDuration()
        duration:SetTimeFromStart(now - entry.elapsed, entry.duration)
        durations[entry.id] = duration
    end
    C_Spell.GetSpellCooldownDuration = function(id) return durations[id] end
    C_Spell.GetSpellChargeDuration = function() return nil end
    C_Spell.GetSpellDisplayCount = function() return "" end
end

-- A capture root for several top-level frames: the simulator renders one frame's subtree, so the
-- frames are re-parented to a holder covering the crop while keeping their screen anchors.
function RikRenderGroup(name, frames, left, bottom, width, height)
    local holder = CreateFrame("Frame", name, UIParent)
    holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    holder:SetSize(width, height)
    for _, frame in ipairs(frames) do
        assert(frame, "Missing frame for " .. name)
        frame:SetParent(holder)
    end
    return holder
end

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

