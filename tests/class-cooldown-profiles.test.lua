-- Source-ID fixtures exercise the shipped profiles through the real spellbook resolver.
return function(check)
    local env = require("wow_stub")
    local loader = dofile("tests/load_addon.lua").Loadfile
    local restoreWidgets = require("widget_stub").install()
    local oldClass, oldBook, oldSpell, oldEnum = UnitClass, C_SpellBook, C_Spell, Enum
    local baseCreate = CreateFrame
    CreateFrame = function(...)
        local frame = baseCreate(...)
        function frame:SetCooldownFromDurationObject(value) self.duration = value end
        function frame:Clear() self.duration = nil end
        return frame
    end
    for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USES",
        "SPELL_UPDATE_ICON" }) do env.KNOWN_EVENTS[event] = true end
    local items, failScan = {}, false
    local cases = {
        { class = "WARRIOR", ids = { 72, 1671, 1672, 871, 6552, 6554 }, excluded = 78 },
        { class = "ROGUE", ids = { 1766, 1769, 2983, 11305, 14185 }, excluded = 1752 },
        { class = "HUNTER", ids = { 5384, 3045, 1293241, 1293527 }, excluded = 75 },
        { class = "PALADIN", ids = { 853, 10308, 633, 10310, 1044 }, excluded = 21084 },
        { class = "SHAMAN", ids = { 8042, 10414, 17364, 408521, 1239243, 408490 }, excluded = 403 },
        { class = "DRUID", ids = { 5211, 8983, 1238122, 29166, 20484, 20748 }, excluded = 5176 },
        -- Add independently sourced class fixtures here.
    }
    local function item(id) return { spellID = id, itemType = 71 } end
    local function load(sample)
        env.frames, env.printed, env.timers, env.inCombat = {}, {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        UnitClass = function() return sample.class, sample.class end
        Enum = { SpellBookSpellBank = { Player = 91 }, SpellBookItemType = { Spell = 71 } }
        C_SpellBook = {
            GetNumSpellBookSkillLines = function() return 1 end,
            GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #items } end,
            GetSpellBookItemInfo = function(index, bank)
                assert(bank == 91, "only player spells belong here")
                if failScan then error("spellbook changing") end
                return items[index]
            end,
        }
        C_Spell = { GetSpellCooldownDuration = function(id, ignoreGCD)
                assert(ignoreGCD == true); return env.SECRET
            end,
            GetSpellChargeDuration = function() return env.SECRET end,
            GetSpellDisplayCount = function() return env.SECRET end,
            GetSpellTexture = function(id) return id end }
        for _, path in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/ui/media.lua",
            "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout.lua",
            "src/modules/classcooldowns/classcooldowns.lua" }) do assert(loader(path))("RikUI", {}) end
        for _, path in ipairs(dofile("tests/load_addon.lua").Manifest()) do
            if path == "data/spells.lua" or path:match("^data/spells%-")
                or path:match("^data/class%-cooldowns%-") then assert(loader(path))("RikUI", {}) end
        end
        env.fire("ADDON_LOADED", "RikUI"); env.fire("PLAYER_LOGIN")
        return RikUI.ClassCooldowns
    end
    local function verify(sample)
        items, failScan = {}, false
        for _, id in ipairs(sample.ids) do items[#items + 1] = item(id) end
        items[#items + 1] = item(sample.excluded)
        local panel = load(sample)
        local profile = RikUI.ClassCooldownProfiles[sample.class]
        check(sample.class .. " profile is shipped", type(profile) == "table")
        assert(type(profile) == "table", sample.class .. " profile missing")
        local byID = {}
        for _, button in ipairs(panel.Buttons) do byID[button.spellID] = button end
        check(sample.class .. " excludes filler abilities", byID[sample.excluded] == nil)
        for _, id in ipairs(sample.ids) do
            local highest, covered = false, false
            for _, name in ipairs(profile) do
                local entry = RikUI.Spells.Entry(name, sample.class)
                for _, rank in ipairs(entry.ranks) do
                    if rank == id then covered = true; highest = RikUI.Spells.HighestKnownRank(name, sample.class) == id end
                end
            end
            -- Lower ranks disappear when a higher learned rank of the same family exists.
            check(sample.class .. " fixture rank " .. id, covered and highest == (byID[id] ~= nil))
        end
        check(sample.class .. " independent fixture produces icons", #panel.Buttons > 0)
        items = {}
        for _, name in ipairs(profile) do
            local entry = assert(RikUI.Spells.Entry(name, sample.class), name)
            for _, id in ipairs(entry.ranks) do items[#items + 1] = item(id) end
        end
        env.fire("SPELLS_CHANGED")
        check(sample.class .. " fits complete learned profile", #profile <= 12 and #panel.Buttons == #profile)
        for index, name in ipairs(profile) do
            local entry, button = RikUI.Spells.Entry(name, sample.class), panel.Buttons[index]
            check(sample.class .. " highest rank for " .. name, button.spellID == entry.ranks[#entry.ranks]
                and button.cooldown.duration == env.SECRET and button.count.text == env.SECRET)
        end
        local firstID = panel.Buttons[1].spellID
        failScan = true; env.fire("SPELLS_CHANGED")
        check(sample.class .. " keeps complete profile during failed scan", panel.Buttons[1].spellID == firstID
            and #panel.Buttons == #profile)
        failScan = false
        items = { { spellID = 9000001, actionID = firstID, itemType = 71 } }
        env.fire("SPELLS_CHANGED")
        check(sample.class .. " uses live override and removes unlearned talents", #panel.Buttons == 1
            and panel.Buttons[1].spellID == 9000001)
        items = {}; env.fire("SPELLS_CHANGED")
        check(sample.class .. " empty learned book leaves no visible panel", #panel.Buttons == 0 and not panel.Frame:IsShown())
    end
    local ok, reason = pcall(function() for _, sample in ipairs(cases) do verify(sample) end end)
    UnitClass, C_SpellBook, C_Spell, Enum = oldClass, oldBook, oldSpell, oldEnum
    CreateFrame = baseCreate
    restoreWidgets()
    env.inCombat = false
    check("class cooldown profile integration suite completes", ok, reason)
end

