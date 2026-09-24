local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Conservative level-up placement through the real spellbook, core queue and writer.
return function(check)
    local env = require("wow_stub")
    local names = { "GetActionInfo", "GetCursorInfo", "ClearCursor", "PlaceAction",
        "C_Spell", "C_SpellBook", "Enum", "UnitClass", "GetMacroInfo", "PickupMacro" }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local actions, cursor, known, writes, reads, failBook, failPlace, combatAfterPlace, setup
    local macroData
    local function countLines(fragment)
        local count = 0
        for _, line in ipairs(env.printed) do
            if line:find(fragment, 1, true) then count = count + 1 end
        end
        return count
    end
    local function fresh(rejectLearned)
        env.frames, env.printed, env.inCombat = {}, {}, false
        RikUIDB, RikUICharDB = nil, nil
        actions, known, writes, reads = {}, {}, {}, 0
        cursor, failBook, failPlace, combatAfterPlace = nil, false, false, false
        macroData = { [121] = { name = "Gated", icon = 1, body = "/cast Slam" } }
        GetMacroInfo = function(index)
            local macro = macroData[index]
            if macro then return macro.name, macro.icon, macro.body end
        end
        PickupMacro = function(id)
            assert(not env.inCombat, "pickup in combat")
            cursor = { kind = "macro", id = id }
        end
        UnitClass = function() return "Warrior", "WARRIOR" end
        Enum = { SpellBookSpellBank = { Player = 1 }, SpellBookItemType = { Spell = 1 } }
        C_SpellBook = {
            GetNumSpellBookSkillLines = function()
                reads = reads + 1
                if failBook then error("book unavailable") end
                return 1
            end,
            GetSpellBookSkillLineInfo = function()
                return { itemIndexOffset = 0, numSpellBookItems = #known }
            end,
            GetSpellBookItemInfo = function(index)
                local value = known[index]
                return { itemType = 1, spellID = type(value) == "table" and value.id or value,
                    actionID = type(value) == "table" and value.base or nil }
            end,
        }
        GetActionInfo = function(slot)
            local action = actions[slot]
            if action then return action.kind, action.id end
        end
        GetCursorInfo = function() if cursor then return cursor.kind, cursor.id end end
        ClearCursor = function() cursor = nil end
        C_Spell = { PickupSpell = function(id)
            assert(not env.inCombat, "pickup in combat")
            cursor = { kind = "spell", id = id }
        end }
        PlaceAction = function(slot)
            assert(not env.inCombat, "placement in combat")
            writes[#writes + 1] = slot
            if failPlace then return end
            actions[slot], cursor = cursor, actions[slot]
            if combatAfterPlace then env.inCombat, combatAfterPlace = true, false end
        end
        if rejectLearned then env.KNOWN_EVENTS.LEARNED_SPELL_IN_SKILL_LINE = nil end
        for _, file in ipairs({ "src/core/core.lua", "data/spells.lua", "presets/warrior.lua",
            "src/setup/setup.lua", "src/setup/setup-actions.lua", "src/setup/setup-apply.lua", "src/character/macros.lua", "src/setup/setup-undo.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        -- Loading the TOC entry is tested separately; a missing implementation is a red assertion.
        local levelup = loadfile("src/setup/setup-levelup.lua")
        if levelup then levelup("RikUI", {}) end
        env.KNOWN_EVENTS.LEARNED_SPELL_IN_SKILL_LINE = true
        setup = RikUI.Setup
        env.fire("ADDON_LOADED", "RikUI")
        RikUI.Presets.WARRIOR = {
            version = 1, roles = { dps = {}, tank = {} },
            macros = { Keep = {}, Gated = { spells = { "Slam" } } },
            bars = { main = { [1] = { spell = "Heroic Strike", level = 1 },
                [2] = { spell = "Rend", level = 4 }, [3] = { macro = "Keep" },
                [4] = { item = "Hearthstone" }, [5] = { macro = "Gated" } }, battle = {},
                bar2 = { [1] = { spell = "Slam", level = 20 } } },
            roleOverrides = { tank = { main = { [1] = { spell = "Sunder Armor", level = 10 } } } },
        }
        RikUICharDB.applied = { class = "WARRIOR", role = "dps", at = 1, presetVersion = 1 }
        env.fire("PLAYER_LOGIN")
    end
    local function learned(id) env.fire("LEARNED_SPELL_IN_SKILL_LINE", id, 1, false) end

    fresh()
    local hasResync = type(setup.Resync) == "function"
    check("level-up exposes Resync", hasResync)
    local frame = env.frames[1]
    check("learned spell and broad fallback events registered", frame.events.LEARNED_SPELL_IN_SKILL_LINE
        and frame.events.SPELLS_CHANGED)
    known = { 78, 284, 772 }
    learned(78)
    check("learned event fills all designated family slots at highest rank", actions[1] and actions[1].id == 284
        and actions[73] and actions[73].id == 284)
    check("learned event only processes its family", actions[2] == nil and actions[74] == nil)
    if not hasResync then
        for _, name in ipairs(names) do _G[name] = saved[name] end
        return
    end

    fresh()
    known = { 78, 284 }
    actions[1], actions[73] = { kind = "spell", id = 78 }, { kind = "spell", id = 285 }
    learned(284)
    check("older rank upgrades", actions[1].id == 284)
    check("higher rank is never downgraded by incomplete book", actions[73].id == 285)
    local before = #writes
    learned(284)
    check("duplicate learned event is idempotent", #writes == before)

    for _, kind in ipairs({ "spell", "macro", "item", "flyout" }) do
        fresh()
        known = { 284 }
        actions[1] = { kind = kind, id = kind == "spell" and 772 or 78 }
        learned(284)
        check("preserves occupied " .. kind, actions[1].kind == kind and #writes == 1)
        check("reports skipped spell and occupied slot for " .. kind,
            countLines("Heroic Strike") == 1 and countLines("slot 1") == 1)
        env.fire("SPELLS_CHANGED")
        check("fallback does not repeat unchanged conflict for " .. kind, countLines("slot 1") == 1)
    end

    fresh()
    known = { 284, 772, 1464 }
    actions[1] = { kind = "spell", id = 78 }
    actions[61] = { kind = "spell", id = 1240193 }
    local undo, applied = { sentinel = true }, RikUICharDB.applied
    RikUICharDB.undo = undo
    SlashCmdList.RIKUI("resync")
    check("resync fills every resolved spell slot including stance inheritance",
        actions[1].id == 284 and actions[2].id == 772 and actions[73].id == 284 and actions[74].id == 772)
    check("rank order follows catalogue not numeric spell IDs", actions[61].id == 1464)
    check("resync ignores ungated macro and item slots", actions[3] == nil and actions[4] == nil)
    check("resync places a macro whose attack is known on base and stance pages",
        actions[5] and actions[5].kind == "macro" and actions[5].id == 121
        and actions[77] and actions[77].kind == "macro" and actions[77].id == 121)
    check("resync preserves applied marker and undo snapshot", RikUICharDB.applied == applied and RikUICharDB.undo == undo)
    check("resync reports completion", countLines("Resync complete") == 1)
    before = #writes
    SlashCmdList.RIKUI("resync extra")
    check("resync rejects arguments without writes", #writes == before and countLines("Usage: /rik resync") == 1)

    fresh()
    known = { 284 }
    RikUICharDB.autoPlacement = false
    RikUI.Runtime.BindProfile()
    check("character default normalization preserves opted-out preference", RikUICharDB.autoPlacement == false)
    learned(284)
    env.fire("SPELLS_CHANGED")
    check("automatic placement opt-out avoids writes and spellbook reads", #writes == 0 and reads == 0)
    setup.Resync()
    check("manual resync remains available with automatic placement disabled", actions[1] and actions[1].id == 284)

    fresh()
    known = { 284 }
    env.inCombat = true
    learned(284)
    RikUICharDB.autoPlacement = false
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("disabling automatic placement cancels already queued automatic work", #writes == 0)
    RikUICharDB.autoPlacement = true
    env.fire("SPELLS_CHANGED")
    check("reenabling automatic placement permits later learned updates", actions[1] and actions[1].id == 284)

    fresh(true)
    known = { 284 }
    env.fire("SPELLS_CHANGED")
    check("unknown learned event falls back without aborting module", actions[1] and actions[1].id == 284)
    check("registration failure uses core diagnostic", countLines("Could not register event: LEARNED_SPELL_IN_SKILL_LINE") == 1)

    for _, marker in ipairs({ false, "bad", { class = "MAGE", role = "dps" } }) do
        fresh()
        RikUICharDB.applied = marker or nil
        known = { 284 }
        learned(284)
        env.fire("SPELLS_CHANGED")
        check("inactive or wrong-class marker leaves handler inert", #writes == 0 and reads == 0 and #env.printed == 0)
    end

    fresh()
    RikUICharDB.applied.role = "tank"
    known = { 284, 7386 }
    SlashCmdList.RIKUI("resync")
    check("resync honors applied role overrides", actions[1].id == 7386 and actions[73].id == 7386)

    fresh()
    known = { 78 }
    env.inCombat = true
    learned(78)
    known = { 78, 284 }
    learned(284)
    env.fire("SPELLS_CHANGED")
    check("combat defers all book reads and slot writes", #writes == 0 and reads == 0)
    check("combat event burst reports one queued batch", countLines("queued until combat ends") == 1)
    actions[1] = { kind = "item", id = 6948 }
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("deferred placement rereads latest rank and player action", actions[1].kind == "item"
        and actions[73].id == 284 and #writes == 1)

    fresh()
    known = { 284 }
    env.inCombat = true
    learned(284)
    RikUICharDB.applied = nil
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("queued event is inert after applied marker removal", #writes == 0)

    fresh()
    known = { 284 }
    combatAfterPlace = true
    learned(284)
    check("combat beginning mid-pass stops subsequent writes", #writes == 1 and actions[73] == nil)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("mid-pass combat resumes remaining slots", actions[73] and actions[73].id == 284)

    fresh()
    known = { 284 }
    cursor = { kind = "item", id = 6948 }
    learned(284)
    check("automatic placement preserves a player's held cursor", #writes == 0 and cursor and cursor.id == 6948)
    cursor = nil
    env.fire("SPELLS_CHANGED")
    check("a later fallback retries after cursor clears", actions[1] and actions[1].id == 284)

    fresh()
    known, failBook = { 284 }, true
    actions[1] = { kind = "spell", id = 78 }
    learned(284)
    check("lookup failure preserves original slot and reports failure", actions[1].id == 78
        and #writes == 0 and countLines("Spellbook lookup failed") > 0)
    failBook = false
    env.fire("SPELLS_CHANGED")
    check("lookup failure is retryable on later event", actions[1].id == 284)

    fresh()
    known, failPlace = { 284 }, true
    learned(284)
    check("failed placement is reported and cursor cleared", actions[1] == nil and cursor == nil
        and countLines("placement rejected") > 0)
    failPlace = false
    SlashCmdList.RIKUI("resync")
    check("manual resync retries rejected placement", actions[1] and actions[1].id == 284)

    fresh()
    known = { { id = 900001, base = 284 } }
    actions[1] = { kind = "spell", id = 78 }
    env.fire("SPELLS_CHANGED")
    check("runtime spellbook aliases preserve catalogue rank ordering", actions[1].id == 900001
        and actions[73] and actions[73].id == 900001)

    fresh()
    known = { 284 }
    setup.IsUndoing = function() return true end
    learned(284)
    env.fire("SPELLS_CHANGED")
    check("automatic sync never interleaves with Undo", #writes == 0)
    setup.IsUndoing = function() return false end
    setup.IsApplying = function() return true end
    SlashCmdList.RIKUI("resync")
    check("manual sync refuses pending Apply", #writes == 0 and countLines("pending") > 0)

    fresh()
    known = { 284 }
    env.inCombat = true
    local cancelled = setup.Resync()
    RikUICharDB.applied.role = "tank"
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("queued resync cancels on in-place role changes", #writes == 0 and cancelled.status == "cancelled"
        and countLines("Resync complete") == 0)

    fresh()
    known = { 284 }
    env.fire("LEARNED_SPELL_IN_SKILL_LINE")
    check("missing learned payload safely uses broad reconciliation", actions[1] and actions[1].id == 284)

    fresh()
    actions[2] = { kind = "item", id = 6948 }
    SlashCmdList.RIKUI("resync")
    check("unlearned spells do not clear occupied or empty slots", #writes == 0
        and actions[2].kind == "item" and actions[1] == nil)
    check("a macro whose attacks are unlearned stays off the bar", actions[5] == nil and #env.printed == 1)

    fresh()
    known = { 284, 1464 }
    learned(284)
    check("a learned event outside the macro's attacks leaves the slot alone", actions[5] == nil and #writes == 2)
    learned(1464)
    check("learning a macro's attack places the macro on base and stance pages",
        actions[5] and actions[5].id == 121 and actions[77] and actions[77].id == 121)
    local before = #writes
    learned(1464)
    check("a placed macro is idempotent", #writes == before and countLines("Gated") == 0)

    fresh()
    known = { 1464 }
    actions[5] = { kind = "spell", id = 78 }
    learned(1464)
    check("an occupied macro slot is preserved and reported once", actions[5].kind == "spell"
        and actions[77] and actions[77].kind == "macro" and countLines("Gated skipped at slot 5") == 1)
    env.fire("SPELLS_CHANGED")
    check("fallback does not repeat the macro conflict", countLines("Gated skipped at slot 5") == 1)

    fresh()
    known = { 1464 }
    macroData = {}
    learned(1464)
    check("a missing preset macro is reported instead of placed", actions[5] == nil and actions[77] == nil
        and countLines("Gated skipped at slot 5") == 1 and countLines("/rik apply") == 2)

    fresh()
    known = { 284 }
    local placeBeforeEvent = PlaceAction
    local eventOnce = true
    PlaceAction = function(slot)
        placeBeforeEvent(slot)
        if slot == 73 and eventOnce then
            eventOnce = false
            known = { 285 }
            learned(285)
        end
    end
    learned(284)
    check("reentrant learned events revisit the first job", actions[1].id == 285 and actions[73].id == 285)

    for _, name in ipairs(names) do _G[name] = saved[name] end
    env.inCombat = false
end
