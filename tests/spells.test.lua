-- Spell contracts; run through tests/run_tests.lua.
return function(check)
    local env = require("wow_stub")
    local oldBook, oldSpell, oldEnum, oldGlobal = C_SpellBook, C_Spell, Enum, GetSpellInfo
    local lines, items, reads, textures, failure
    local function reset()
        lines = { { itemIndexOffset = 2, numSpellBookItems = 2 },
            { itemIndexOffset = 8, numSpellBookItems = 6 } }
        items = {
            [3] = { spellID = 900, itemType = 71, name = "Localized ability", subName = "Rang 2" },
            [4] = { spellID = 1000, itemType = 71 },
            [9] = { spellID = 200, itemType = 72 },
            [10] = { spellID = 200, itemType = 71, isOffSpec = true },
            [11] = { spellID = 200, itemType = 74 },
            [12] = { spellID = 200, itemType = 73 },
            [13] = { spellID = 900, itemType = 71 },
            [14] = { itemType = 0 },
        }
        reads, textures, failure, env.printed = {}, {}, nil, {}
        Enum = { SpellBookSpellBank = { Player = 91 }, SpellBookItemType = { Spell = 71 } }
        C_SpellBook = {
            GetNumSpellBookSkillLines = function()
                if failure == "count" then error("count failure") end
                return #lines
            end,
            GetSpellBookSkillLineInfo = function(index)
                if failure == "line" then error("line failure") end
                return lines[index]
            end,
            GetSpellBookItemInfo = function(slot, bank)
                assert(bank == 91, "must use the player bank enum")
                reads[#reads + 1] = slot
                if failure == "item" and slot == 9 then error("item failure") end
                return items[slot]
            end,
        }
        C_Spell = { GetSpellTexture = function(id)
            textures[#textures + 1] = id
            return 777
        end }
        GetSpellInfo = function() error("removed global must never be used") end
    end
    local function contains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end

    reset()
    env.frames, env.inCombat = {}, false
    RikUI, RikUIDB, RikUICharDB = nil, nil, nil
    assert(loadfile("core.lua"))("RikUI", {})
    assert(loadfile("data/spells.lua"))("RikUI", {})
    check("spell module performs no API reads at load", #reads == 0 and #textures == 0)
    local spells, data = RikUI.Spells, RikUI.SpellData
    check("spell APIs and catalogue are exposed", type(spells) == "table" and type(data) == "table")
    assert(spells and data, "spell module missing")

    -- Source-derived beta-cap fixture: every available family and rank through level 30.
    local through30 = {
        { "Battle Stance", 1, { 2457 } },
        { "Heroic Strike", 1, { 78, 284, 285, 1608 } },
        { "Charge", 4, { 100, 6178 } },
        { "Rend", 4, { 772, 6546, 6547, 6548 } },
        { "Thunder Clap", 6, { 6343, 8198, 8204 } },
        { "Hamstring", 8, { 1715 } },
        { "Overpower", 12, { 7384, 7887 } },
        { "Tactical Mastery", 14, { 1310185 } },
        { "Mocking Blow", 16, { 694, 7400 } },
        { "Retaliation", 20, { 20230 } },
        { "Victory Rush", 20, { 402927 } },
        { "Battle Shout", 1, { 6673, 5242, 6192 } },
        { "Demoralizing Shout", 14, { 1160, 6190 } },
        { "Cleave", 20, { 845, 7369 } },
        { "Slam", 20, { 1240193, 1464 } },
        { "Intimidating Shout", 22, { 5246 } },
        { "Execute", 24, { 5308 } },
        { "Challenging Shout", 26, { 1161 } },
        { "Berserker Stance", 30, { 2458 } },
        { "Intercept", 30, { 20252 } },
        { "Bloodrage", 10, { 2687 } },
        { "Defensive Stance", 10, { 71 } },
        { "Sunder Armor", 10, { 7386, 7405 } },
        { "Taunt", 10, { 355 } },
        { "Shield Bash", 12, { 72 } },
        { "Revenge", 14, { 6572, 6574 } },
        { "Shield Block", 16, { 2565 } },
        { "Disarm", 18, { 676 } },
        { "Shield Wall", 28, { 871 } },
    }
    local families, ranks, seenIDs = 0, 0, {}
    local valid = true
    for _, entry in pairs(data) do
        families = families + 1
        valid = valid and type(entry.icon) == "number" and entry.icon > 0
            and type(entry.level) == "number" and entry.level >= 1 and #entry.ranks > 0
        for _, spellID in ipairs(entry.ranks) do
            ranks = ranks + 1
            valid = valid and type(spellID) == "number" and spellID > 0 and not seenIDs[spellID]
            seenIDs[spellID] = true
        end
    end
    check("complete source catalogue contains 36 families and 111 distinct ranks", valid and families == 36 and ranks == 111)
    for _, fixture in ipairs(through30) do
        local entry = data[fixture[1]]
        local matches = entry and entry.level == fixture[2]
        for rank, spellID in ipairs(fixture[3]) do
            matches = matches and entry.ranks[rank] == spellID
        end
        check("verified level-30 ranks and first trainer level: " .. fixture[1], matches)
    end
    local later = { ["Berserker Rage"] = 32, Whirlwind = 36, Pummel = 38,
        ["Mortal Strike"] = 40, Bloodthirst = 40, ["Shield Slam"] = 40, Recklessness = 50 }
    for name, level in pairs(later) do
        check("post-cap family retains its source level: " .. name, data[name] and data[name].level == level)
    end

    -- Deliberately nonmonotonic IDs and localized names: rank is not ID or slot order.
    data["Test Ability"] = { ranks = { 1000, 900, 200 }, icon = 888, level = 1 }
    check("highest learned rank ignores future offspec flyout pet and duplicate entries",
        spells.HighestKnownRank("Test Ability") == 900)
    check("walk respects every skill line offset and count", table.concat(reads, ",") == "3,4,9,10,11,12,13,14")
    items[14] = { spellID = 200, itemType = 71 }
    check("next lookup sees a newly trained rank without reloading", spells.HighestKnownRank("Test Ability") == 200)
    items[14], items[3], items[13] = { itemType = 0 }, { itemType = 0 }, { itemType = 0 }
    check("removing trained ranks is reflected without stale cache", spells.HighestKnownRank("Test Ability") == 1000)
    items[4] = { spellID = 12345, itemType = 71, name = "Test Ability" }
    check("same name with an unrelated spell ID is not a known catalogue rank",
        spells.HighestKnownRank("Test Ability") == nil)
    reset()
    items[3] = { actionID = 900, itemType = 71 }
    items[13] = { itemType = 0 }
    check("base action ID identifies spells whose spellID is absent", spells.HighestKnownRank("Test Ability") == 900)
    items[3] = { spellID = 9999, actionID = 900, itemType = 71 }
    check("known base rank returns its active overriding spell ID", spells.HighestKnownRank("Test Ability") == 9999)
    SlashCmdList.RIKUI("spells Test Ability")
    check("slash diagnostic preserves the resolved override ID", contains("2 (9999)") and contains("highest: 9999"))
    local count = #reads
    check("unlisted names return nil without walking", spells.HighestKnownRank("Not Listed") == nil and #reads == count)
    check("invalid names return nil", spells.HighestKnownRank(nil) == nil and spells.HighestKnownRank({}) == nil)
    lines = {}
    check("empty spellbook returns nil", spells.HighestKnownRank("Test Ability") == nil)

    reset()
    items[14] = nil
    local incompleteID, incompleteReason = spells.HighestKnownRank("Test Ability")
    check("missing item inside declared range rejects a partial lower rank",
        incompleteID == nil and type(incompleteReason) == "string")
    reset()
    lines[2] = { itemIndexOffset = 8, numSpellBookItems = 6, offSpecID = 123 }
    items[9] = { spellID = 200, itemType = 71 }
    check("offspec skill line cannot supply a learned rank", spells.HighestKnownRank("Test Ability") == 900)

    for _, mode in ipairs({ "count", "line", "item" }) do
        reset()
        failure = mode
        local ok, id, reason = pcall(spells.HighestKnownRank, "Test Ability")
        check("failed " .. mode .. " lookup never returns a partial lower rank", ok and id == nil
            and type(reason) == "string")
    end
    reset()
    C_SpellBook = nil
    local ok, id, reason = pcall(spells.HighestKnownRank, "Test Ability")
    check("missing spellbook API returns an explicit diagnostic", ok and id == nil and type(reason) == "string")
    reset()
    C_SpellBook.GetSpellBookItemInfo = nil
    ok, id, reason = pcall(spells.HighestKnownRank, "Test Ability")
    check("incomplete spellbook API is guarded", ok and id == nil and type(reason) == "string")
    reset()
    Enum = nil
    ok, id, reason = pcall(spells.HighestKnownRank, "Test Ability")
    check("missing enums are guarded", ok and id == nil and type(reason) == "string")

    reset()
    lines = {}
    check("unlearned spell texture is requested by first-rank ID",
        spells.Icon("Test Ability") == 777 and textures[1] == 1000 and #reads == 0)
    C_Spell.GetSpellTexture = function() return nil end
    check("unavailable texture data falls back to the catalogue icon", spells.Icon("Test Ability") == 888)
    C_Spell.GetSpellTexture = function() error("texture failure") end
    check("texture API errors fall back safely", spells.Icon("Test Ability") == 888)
    C_Spell = nil
    check("missing texture API falls back safely", spells.Icon("Test Ability") == 888)
    check("unknown spell icon is nil", spells.Icon("Not Listed") == nil and spells.Icon(nil) == nil)

    reset()
    SlashCmdList.RIKUI("")
    check("slash help advertises spells", contains("/rik spells"))
    env.printed = {}
    SlashCmdList.RIKUI("spells Test Ability")
    check("slash command prints each known rank and highest ID",
        contains("1 (1000)") and contains("2 (900)") and contains("highest: 900") and not contains("3 (200)"))
    check("slash diagnostics use one consistent spellbook scan", #reads == 8)
    env.printed = {}
    SlashCmdList.RIKUI("spells")
    check("empty spell command gives usage", contains("/rik spells <name>"))
    env.printed = {}
    SlashCmdList.RIKUI("spells Not Listed")
    check("unlisted spell command reports its name", contains("Unknown spell: Not Listed"))
    lines, env.printed = {}, {}
    SlashCmdList.RIKUI("spells Test Ability")
    check("unlearned spell command reports no known ranks", contains("known ranks: none") and contains("highest: none"))
    reset()
    failure = "item"
    SlashCmdList.RIKUI("spells Test Ability")
    check("failed spellbook scan is reported instead of a false unknown result",
        contains("Spellbook lookup failed") and not contains("highest:"))
    data["Test Ability"] = nil
    C_SpellBook, C_Spell, Enum, GetSpellInfo = oldBook, oldSpell, oldEnum, oldGlobal
end
