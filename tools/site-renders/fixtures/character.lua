-- The Forever character: class, level and a level-10 spellbook from RikUI's own catalogue.

-- The simulator's built-in spellbook and spell metadata belong to another game version. These
-- inputs describe a Forever character by level 10 using RikUI's own catalogue (data/spells-<class>.lua,
-- ranks and acquisition levels: rank 1 of every spell learned by 10, rank 2 of those learned by 4),
-- so the addon's spellbook scans, icons and action textures read the current client's spells.
-- RikUI still resolves ranks, membership and drawing itself.
local SPELLS_BY_10 = {
    DRUID = { 5176, 5177, 8921, 8924, 467, 339, 16689, 18960, 5487, 99, 6795, 6807, 5185, 5186, 1126, 5232, 774, 1058 },
    HUNTER = { 13163, 13165, 883, 2641, 6991, 982, 75, 1978, 13549, 3044, 1130, 5116, 2973, 14260, 1494, 19883, 5149 },
    MAGE = { 1459, 1460, 5504, 5505, 587, 5143, 118, 133, 143, 2136, 168, 7300, 116, 205, 122, 1296017, 1302508 },
    PALADIN = { 635, 639, 20154, 20287, 465, 19740, 20271, 679, 498, 21082, 1152, 853, 633, 1022, 1311649 },
    PRIEST = { 1243, 1244, 17, 1277455, 10797, 2050, 2052, 585, 591, 139, 13908, 1277370, 2006, 589, 594, 586, 9035, 8092, 2652 },
    ROGUE = { 2098, 6760, 5171, 1752, 1757, 53, 2589, 1776, 5277, 2983, 1784, 1785, 921, 6770, 1804 },
    SHAMAN = { 403, 529, 8042, 8044, 2484, 5730, 8050, 3599, 8017, 8018, 8071, 8154, 324, 8024, 8075, 331, 332 },
    WARLOCK = { 172, 6222, 702, 1108, 1454, 980, 5782, 1120, 687, 696, 688, 6201, 697, 348, 707, 686, 695 },
}

local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }

local CLASS_ICONS = { WARRIOR = 626008, PALADIN = 626003, HUNTER = 626000, ROGUE = 626005, PRIEST = 626004, SHAMAN = 626006, MAGE = 626001, WARLOCK = 626007, DRUID = 625999 }

function RikRenderSpellbook(class)
    class = class or "PALADIN"
    local list = assert(SPELLS_BY_10[class], "No level-10 spell list for " .. class)
    local catalog, icons, names, known, items = RikUI.Spells.Catalog(class), {}, {}, {}, {}
    for name, entry in pairs(catalog) do
        for _, id in ipairs(entry.ranks) do icons[id], names[id] = entry.icon, name end
    end
    for _, id in ipairs(list) do
        assert(icons[id], "Spell " .. id .. " is not in RikUI's " .. class .. " catalogue")
        known[id] = true
        items[#items + 1] = id
    end
    local title = class:sub(1, 1) .. class:sub(2):lower()
    C_SpellBook.GetNumSpellBookSkillLines = function() return 1 end
    C_SpellBook.GetSpellBookSkillLineInfo = function(index)
        if index ~= 1 then return nil end
        return { name = title, iconID = CLASS_ICONS[class], itemIndexOffset = 0, numSpellBookItems = #items,
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

-- A character of another class at level 10: the seed's paladin becomes this class, with that class's
-- spellbook. RikUI's class-driven modules read the class through the normal unit APIs; the ones that
-- decided at login that the paladin has no use for them (combo points, totems, form mana) are
-- enabled again now, exactly as they would be for a character of this class. The frames registered
-- while the character was a paladin stand at a paladin's default places; a character of this class
-- starts at its own, which is what applying the Centered layout gives them before the rows register.
function RikRenderPlayer(class, level)
    class = class or "PALADIN"
    A_Admin.SetPlayerClass(assert(CLASS_IDS[class], "Unknown class " .. class))
    if level then A_Admin.SetPlayerLevel(level) end
    RikRenderSpellbook(class)
    if class ~= "PALADIN" then assert(RikUI.Layout.ApplyPreset("centered")) end
    for _, name in ipairs({ "combopoints", "totems", "druidmana" }) do
        local module = RikUI.Modules and RikUI.Modules[name]
        if module and type(module.OnEnable) == "function" and not module.Holder then
            local ok, reason = pcall(module.OnEnable, module)
            assert(ok, name .. ": " .. tostring(reason))
        end
    end
    A_Admin.FireEvent("PLAYER_TARGET_CHANGED")
end
