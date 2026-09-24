-- Warrior spellbook: foreverchanges.pro/spellbook/warrior and
-- wowforevertalents.com/abilities/warrior, checked 2026-09-18.
-- Source build and rank/level verification are documented in docs/spells.md.
local core = RikUI
local spells = {}
core.Spells = spells

core.SpellData = {
    ["Battle Shout"] = { ranks = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, icon = 132333, level = 1 },
    ["Battle Stance"] = { ranks = { 2457 }, icon = 132349, level = 1 },
    ["Berserker Rage"] = { ranks = { 18499 }, icon = 136009, level = 32 },
    ["Berserker Stance"] = { ranks = { 2458 }, icon = 132275, level = 30 },
    ["Bloodrage"] = { ranks = { 2687 }, icon = 132277, level = 10 },
    ["Bloodthirst"] = { ranks = { 23881, 23892, 23893, 23894 }, icon = 136012, level = 40 },
    ["Challenging Shout"] = { ranks = { 1161 }, icon = 132091, level = 26 },
    ["Charge"] = { ranks = { 100, 6178, 11578 }, icon = 132337, level = 4 },
    ["Cleave"] = { ranks = { 845, 7369, 11608, 11609, 20569 }, icon = 132338, level = 20 },
    ["Defensive Stance"] = { ranks = { 71 }, icon = 132341, level = 10 },
    ["Demoralizing Shout"] = { ranks = { 1160, 6190, 11554, 11555, 11556 }, icon = 132366, level = 14 },
    ["Disarm"] = { ranks = { 676 }, icon = 132343, level = 18 },
    ["Execute"] = { ranks = { 5308, 20658, 20660, 20661, 20662 }, icon = 135358, level = 24 },
    ["Hamstring"] = { ranks = { 1715, 7372, 7373 }, icon = 132316, level = 8 },
    ["Heroic Strike"] = { ranks = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 }, icon = 132282, level = 1 },
    ["Intercept"] = { ranks = { 20252, 20616, 20617 }, icon = 132307, level = 30 },
    ["Intimidating Shout"] = { ranks = { 5246 }, icon = 132154, level = 22 },
    ["Mocking Blow"] = { ranks = { 694, 7400, 7402, 20559, 20560 }, icon = 132350, level = 16 },
    ["Mortal Strike"] = { ranks = { 12294, 21551, 21552, 21553 }, icon = 132355, level = 40 },
    ["Overpower"] = { ranks = { 7384, 7887, 11584, 11585 }, icon = 132223, level = 12 },
    ["Pummel"] = { ranks = { 6552, 6554 }, icon = 132938, level = 38 },
    ["Recklessness"] = { ranks = { 1719 }, icon = 132109, level = 50 },
    ["Rend"] = { ranks = { 772, 6546, 6547, 6548, 11572, 11573, 11574 }, icon = 132155, level = 4 },
    ["Retaliation"] = { ranks = { 20230 }, icon = 132336, level = 20 },
    ["Revenge"] = { ranks = { 6572, 6574, 7379, 11600, 11601, 25288 }, icon = 132353, level = 14 },
    ["Shield Bash"] = { ranks = { 72, 1671, 1672 }, icon = 132357, level = 12 },
    ["Shield Block"] = { ranks = { 2565 }, icon = 132110, level = 16 },
    ["Shield Slam"] = { ranks = { 23922, 23923, 23924, 23925 }, icon = 134951, level = 40 },
    ["Shield Wall"] = { ranks = { 871 }, icon = 132362, level = 28 },
    ["Slam"] = { ranks = { 1240193, 1464, 8820, 11604, 11605 }, icon = 132340, level = 20 },
    ["Sunder Armor"] = { ranks = { 7386, 7405, 8380, 11596, 11597 }, icon = 132363, level = 10 },
    ["Tactical Mastery"] = { ranks = { 1310185 }, icon = 136031, level = 14 },
    ["Taunt"] = { ranks = { 355 }, icon = 136080, level = 10 },
    ["Thunder Clap"] = { ranks = { 6343, 8198, 8204, 8205, 11580, 11581 }, icon = 136105, level = 6 },
    ["Victory Rush"] = { ranks = { 402927 }, icon = 132342, level = 20 },
    ["Whirlwind"] = { ranks = { 1680 }, icon = 132369, level = 36 },
}


core.SpellCatalogs = { WARRIOR = core.SpellData }

function spells.RegisterClass(class, data)
    core.SpellCatalogs[class] = data
end

function spells.Catalog(class)
    if class == nil and type(UnitClass) == "function" then
        local _, token = UnitClass("player")
        class = token
    end
    return core.SpellCatalogs[class or "WARRIOR"] or {}
end

function spells.Entry(name, class)
    if type(name) == "string" then return spells.Catalog(class)[name] end
end

local function entryFor(name) return spells.Entry(name) end

local function scanLine(line, ranksByID, known)
    if line.offSpecID then return end
    local bank = Enum.SpellBookSpellBank.Player
    local spellType = Enum.SpellBookItemType.Spell
    for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
        local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
        assert(item, "Missing spellbook item")
        if item.itemType == spellType and not item.isOffSpec then
            local rank = ranksByID[item.spellID] or ranksByID[item.actionID]
            if rank then known[rank] = item.spellID or item.actionID end
        end
    end
end

local function scanKnown(entry)
    local ranksByID, known = {}, {}
    for rank, id in ipairs(entry.ranks) do ranksByID[id] = rank end
    for lineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        assert(line, "Missing spellbook skill line")
        scanLine(line, ranksByID, known)
    end
    return known
end

local function knownRanks(entry)
    if not C_SpellBook or type(C_SpellBook.GetNumSpellBookSkillLines) ~= "function"
        or type(C_SpellBook.GetSpellBookSkillLineInfo) ~= "function"
        or type(C_SpellBook.GetSpellBookItemInfo) ~= "function"
        or not Enum or not Enum.SpellBookSpellBank or Enum.SpellBookSpellBank.Player == nil
        or not Enum.SpellBookItemType or Enum.SpellBookItemType.Spell == nil then
        return nil, "Spellbook lookup unavailable"
    end
    -- Discard the whole scan on failure; a partial result could downgrade a bar.
    local ok, known = pcall(scanKnown, entry)
    if not ok then return nil, "Spellbook lookup failed" end
    return known
end

local function highestRank(entry, known)
    for rank = #entry.ranks, 1, -1 do
        if known[rank] then return known[rank], rank end
    end
end

function spells.HighestKnownRank(name)
    local entry = entryFor(name)
    if not entry then return nil end
    local known, reason = knownRanks(entry)
    if not known then return nil, reason end
    local id, rank = highestRank(entry, known)
    return id, nil, rank
end

function spells.Icon(name)
    local entry = entryFor(name)
    if not entry then return nil end
    if not C_Spell or type(C_Spell.GetSpellTexture) ~= "function" then
        return entry.icon, "Spell texture lookup unavailable"
    end
    local ok, texture = pcall(C_Spell.GetSpellTexture, entry.ranks[1])
    if not ok then return entry.icon, "Spell texture lookup failed" end
    return texture or entry.icon
end

-- A spell the character has but the catalogue misses: same name, other ID. Forever reissued some
-- spells under new IDs, and the lookup above is strict on IDs on purpose.
local function namedIDs(name)
    local ids = {}
    for lineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
            if item and item.name == name then ids[#ids + 1] = tostring(item.spellID or item.actionID) end
        end
    end
    return ids
end

local function reportUncatalogued(name)
    local ok, ids = pcall(namedIDs, name)
    if not ok or #ids == 0 then
        core:Print("The spellbook has no entry named " .. name .. "; it is not trained on this character.")
        return
    end
    core:Print("The spellbook has " .. name .. " as ID " .. table.concat(ids, ", ")
        .. ", which the RikUI catalogue does not list. Report these IDs.")
end

local function showSpell(name)
    if name == "" then core:Print("Usage: /rik spells <name>") return end
    local entry = entryFor(name)
    if not entry then core:Print("Unknown spell: " .. name) return end
    local known, reason = knownRanks(entry)
    if not known then core:Print(reason .. ": " .. name) return end
    local labels = {}
    for rank in ipairs(entry.ranks) do
        if known[rank] then labels[#labels + 1] = rank .. " (" .. known[rank] .. ")" end
    end
    core:Print(name .. " known ranks: " .. (#labels > 0 and table.concat(labels, ", ") or "none")
        .. "; highest: " .. tostring(highestRank(entry, known) or "none"))
    if #labels == 0 then reportUncatalogued(name) end
end

core:RegisterCommand("spells", showSpell, "Show known ranks: /rik spells <name>")
