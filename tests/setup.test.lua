-- Setup contracts exercise the real modules and real combat queue.
return function(check)
    local env = require("wow_stub")
    local core, actions, cursor, calls, macroData, settings, keys, known, items
    local failPlace, failBinding, failCVar, combatAfterMacro
    local savedGlobals = {}
    local globals = { "GetActionInfo", "GetCursorInfo", "PickupAction", "PickupMacro", "PlaceAction",
        "ClearCursor", "GetMacroInfo", "CreateMacro", "EditMacro", "GetCurrentBindingSet",
        "GetBindingAction", "SetBinding", "SaveBindings", "C_Spell", "C_Item", "C_CVar", "C_Container", "time" }
    for _, name in ipairs(globals) do savedGlobals[name] = _G[name] end

    local function record(value)
        assert(not InCombatLockdown(), "protected write in combat")
        calls[#calls + 1] = value
    end
    local function fresh()
        env.frames, env.printed, env.inCombat = {}, {}, false
        RikUIDB, RikUICharDB = nil, nil
        for _, file in ipairs({ "core.lua", "data/spells.lua", "data/cvars.lua",
            "presets/warrior.lua", "setup.lua", "setup-actions.lua", "setup-apply.lua", "macros.lua", "bindings.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        core = RikUI
        env.fire("ADDON_LOADED", "RikUI")
        actions, calls, macroData, keys = {}, {}, {}, {}
        cursor, failPlace, failBinding, failCVar, combatAfterMacro = nil, false, false, false, false
        known = { ["Heroic Strike"] = 284, ["Rend"] = 772 }
        items, settings = { Hearthstone = 6948 }, {}
        for _, entry in ipairs(core.CVars.List) do settings[entry.name] = "old" end
        settings.nameplateMotion = nil -- valid unknown-CVar skip
        core.Spells.HighestKnownRank = function(name) return known[name] end
        GetActionInfo = function(slot)
            local action = actions[slot]
            if action then return action.kind, action.id end
        end
        GetCursorInfo = function() if cursor then return cursor.kind, cursor.id end end
        ClearCursor = function() cursor = nil end
        PickupAction = function(slot) record("clear:" .. slot); cursor, actions[slot] = actions[slot], nil end
        C_Spell = { PickupSpell = function(id) record("spell"); cursor = { kind = "spell", id = id } end }
        C_Container = {
            GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
            GetContainerItemID = function(bag, slot) return items.Hearthstone end,
        }
        C_Item = {
            GetItemInfo = function(id) if id == 6948 then return "Hearthstone" end end,
            PickupItem = function(id) record("item"); cursor = { kind = "item", id = id } end,
        }
        PickupMacro = function(id) record("pickupMacro"); cursor = { kind = "macro", id = id } end
        PlaceAction = function(slot)
            record("place:" .. slot)
            if failPlace then return end -- client rejected silently
            actions[slot], cursor = cursor, actions[slot]
        end
        GetMacroInfo = function(index)
            local value = macroData[index]
            if value then return value.name, value.icon, value.body end
        end
        CreateMacro = function(name, icon, body)
            record("macro")
            local index = 121
            while macroData[index] do index = index + 1 end
            macroData[index] = { name = name, icon = icon, body = body }
            if combatAfterMacro then env.inCombat = true; combatAfterMacro = false end
            return index
        end
        EditMacro = function(index, name, icon, body)
            record("macro")
            macroData[index] = { name = name, icon = icon, body = body }
            return index
        end
        GetCurrentBindingSet = function() return 1 end
        GetBindingAction = function(key) return keys[key] or "" end
        SetBinding = function(key, command)
            record("bind")
            if failBinding then return false end
            keys[key] = command
            return true
        end
        SaveBindings = function(set) record("save"); assert(set == 2) end
        C_CVar = {
            GetCVarInfo = function(name) return settings[name] end,
            SetCVar = function(name, value)
                record("cvar")
                if failCVar then return false end
                settings[name] = value
                return true
            end,
        }
        time = function() return 123456 end
        return core.Setup
    end
    local function countLines(fragment)
        local count = 0
        for _, line in ipairs(env.printed) do
            if not fragment or line:find(fragment, 1, true) then count = count + 1 end
        end
        return count
    end
    local function only(step)
        local opts = { macros = false, bars = false, binds = false, cvars = false, layout = false }
        opts[step] = true
        return opts
    end
    local setup = fresh()
    check("Setup exports Resolve, SlotToAction and Apply", type(setup.Resolve) == "function"
        and type(setup.SlotToAction) == "function" and type(setup.Apply) == "function")
    if type(setup.Apply) ~= "function" then
        for _, name in ipairs(globals) do _G[name] = savedGlobals[name] end
        return
    end

    local resolved = assert(setup.Resolve("WARRIOR", "tank"))
    check("role main override replaces full slots", resolved.bars.main[1].spell == "Sunder Armor")
    check("stance overrides follow role main", resolved.bars.battle[6].spell == "Charge"
        and resolved.bars.defensive[6].spell == "Taunt" and resolved.bars.berserker[8].spell == "Pummel")
    check("stance inherits shared entries through sparse holes", resolved.bars.battle[12].item == "Hearthstone")
    resolved.bars.main[1].spell = "changed"
    resolved.macros.Execute.body = "changed"
    check("Resolve does not alias source or sibling pages", core.Presets.WARRIOR.roleOverrides.tank.main[1].spell == "Sunder Armor"
        and resolved.bars.defensive[1].spell == "Sunder Armor" and core.Presets.WARRIOR.macros.Execute.body ~= "changed")
    check("Resolve defaults to dps", setup.Resolve("WARRIOR").role == "dps")
    check("Resolve rejects missing class and role", setup.Resolve("MAGE") == nil and setup.Resolve("WARRIOR", "healer") == nil)
    for page, first in pairs({ main = 1, battle = 73, defensive = 85, berserker = 97,
        bar2 = 61, bar3 = 49, bar4 = 25, bar5 = 37 }) do
        check("native slot mapping " .. page, setup.SlotToAction(page, 1) == first
            and setup.SlotToAction(page, 12) == first + 11)
    end
    check("invalid slot mappings rejected", setup.SlotToAction("main", 0) == nil
        and setup.SlotToAction("main", 13) == nil and setup.SlotToAction("unknown", 1) == nil
        and setup.SlotToAction("main", 1.5) == nil)

    actions[8], actions[25] = { kind = "spell", id = 999 }, { kind = "item", id = 42 }
    cursor = { kind = "item", id = 777 }
    local result = setup.Apply("WARRIOR")
    check("Apply finishes and records versioned character identity", result.status == "applied"
        and RikUICharDB.applied.class == "WARRIOR" and RikUICharDB.applied.role == "dps"
        and RikUICharDB.applied.at == 123456 and RikUICharDB.applied.presetVersion == 1)
    check("highest known spell placed on base and stance pages", actions[1].id == 284 and actions[73].id == 284)
    check("unknown designated spell is cleared and unspecified side slot preserved", actions[8] == nil and actions[25].id == 42)
    check("bag item and existing macro placed", actions[12].id == 6948 and actions[5].kind == "macro")
    check("cursor is empty after Apply", cursor == nil)
    check("layout positions are saved independently", core.Profile.positions.main.point == "BOTTOM"
        and core.Profile.positions.main ~= setup.DefaultPositions.main)
    check("one summary per step without per-binding/cvar chatter", countLines() == 5
        and countLines("Setup macros:") == 1 and countLines("Setup bars:") == 1
        and countLines("Setup binds:") == 1 and countLines("Setup cvars:") == 1
        and countLines("Setup layout:") == 1)
    local stages, previous = { macro = 1, spell = 2, item = 2, pickupMacro = 2, bind = 3, save = 3, cvar = 4 }, 0
    local ordered = true
    for _, call in ipairs(calls) do
        local stage = stages[call] or (call:match("^place:") or call:match("^clear:")) and 2
        if stage then if stage < previous then ordered = false end; previous = stage end
    end
    check("real writers run in macro/bar/bind/cvar order", ordered)
    env.printed = {}
    local second = setup.Apply("WARRIOR", "tank")
    check("repeat Apply edits four macros without duplicates", second.steps.macros.edited == 4
        and macroData[125] == nil and RikUICharDB.applied.role == "tank")

    setup = fresh()
    env.inCombat = true
    local opts = {}
    result = setup.Apply("WARRIOR", nil, opts)
    opts.bars = false
    check("combat Apply queues all writes and defers marker", result.status == "queued" and #calls == 0
        and RikUICharDB.applied == nil and countLines("queued") == 1)
    check("second Apply cannot interleave pending work", setup.Apply("WARRIOR") == nil)
    env.printed = {}
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("nested queue completion drains entire sequence in order", result.status == "applied"
        and actions[73].id == 284 and RikUICharDB.applied ~= nil and countLines() == 5)

    setup = fresh()
    combatAfterMacro = true
    result = setup.Apply("WARRIOR")
    check("combat appearing between writes suspends remaining work", result.status == "queued"
        and #calls == 1 and RikUICharDB.applied == nil)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("suspended sequence resumes after combat", result.status == "applied" and actions[1].id == 284)

    setup = fresh()
    result = setup.Apply("WARRIOR", nil, only("bars"))
    check("disabled steps perform no writes and missing macros stay empty", result.status == "applied"
        and next(macroData) == nil and next(keys) == nil and actions[5] == nil
        and settings.autoLootDefault == "old" and next(core.Profile.positions) == nil)
    setup = fresh()
    items = {}
    result = setup.Apply("WARRIOR", nil, only("bars"))
    check("items absent from bags leave designated slot empty", actions[12] == nil and result.status == "applied")
    setup = fresh()
    failPlace = true
    result = setup.Apply("WARRIOR", nil, only("bars"))
    check("silent placement rejection fails without success marker", result.status == "failed"
        and RikUICharDB.applied == nil and cursor == nil and result.error:find("slot 1", 1, true))
    setup = fresh()
    core.Spells.HighestKnownRank = function() return nil, "Spellbook lookup failed" end
    actions[1] = { kind = "spell", id = 999 }
    result = setup.Apply("WARRIOR", nil, only("bars"))
    check("spellbook errors do not clear existing action", result.status == "failed" and actions[1].id == 999)
    setup = fresh()
    failBinding = true
    result = setup.Apply("WARRIOR")
    check("binding failure stops cvars/layout and success marker", result.status == "failed"
        and settings.autoLootDefault == "old" and next(core.Profile.positions) == nil and RikUICharDB.applied == nil)
    setup = fresh()
    failCVar = true
    result = setup.Apply("WARRIOR", nil, only("cvars"))
    check("CVar failures cannot masquerade as success", result.status == "failed" and RikUICharDB.applied == nil)
    setup = fresh()
    core.Presets.WARRIOR.bars.invalid = {}
    check("unknown page rejects before any mutation", setup.Apply("WARRIOR") == nil and #calls == 0)
    setup = fresh()
    check("invalid option rejected before mutation", setup.Apply("WARRIOR", nil, { bars = "yes" }) == nil and #calls == 0)
    setup = fresh()
    CreateMacro = function() return nil end
    result = setup.Apply("WARRIOR")
    check("macro rejection stops before bars with one failed summary", result.status == "failed"
        and next(actions) == nil and RikUICharDB.applied == nil and countLines() == 1)
    setup = fresh()
    C_Spell.PickupSpell = function() end
    result = setup.Apply("WARRIOR", nil, only("bars"))
    check("empty cursor after pickup never reaches PlaceAction", result.status == "failed"
        and next(actions) == nil and #calls == 0 and cursor == nil)
    setup = fresh()
    actions[8] = { kind = "spell", id = 999 }
    PickupAction = function() end
    result = setup.Apply("WARRIOR", nil, only("bars"))
    check("rejected clearing is reported", result.status == "failed" and actions[8].id == 999
        and result.error:find("clear slot 8", 1, true))
    setup = fresh()
    C_Container.GetContainerNumSlots = function(bag)
        assert(bag >= 0 and bag <= 4, "bank must not be inspected")
        return bag == 4 and 1 or 0
    end
    result = setup.Apply("WARRIOR", nil, only("bars"))
    check("last carried bag is searched", result.status == "applied" and actions[12].id == 6948)
    setup = fresh()
    core.Presets.WARRIOR.positions = { custom = { point = "CENTER", x = 15, y = 20 } }
    core.Profile.positions.untouched = { x = 90 }
    result = setup.Apply("WARRIOR", nil, only("layout"))
    check("preset layout is copied and unrelated positions preserved", result.status == "applied"
        and core.Profile.positions.custom.x == 15 and core.Profile.positions.untouched.x == 90
        and core.Profile.positions.custom ~= core.Presets.WARRIOR.positions.custom)
    setup = fresh()
    local bindOpts = only("binds")
    bindOpts.strafe, bindOpts.mouse45 = false, false
    result = setup.Apply("WARRIOR", nil, bindOpts)
    check("binding preferences forwarded", result.status == "applied" and keys.A == "TURNLEFT"
        and keys["SHIFT-G"] == "MULTIACTIONBAR1BUTTON10" and keys.BUTTON4 == nil)
    setup = fresh()
    local cvarOpts = only("cvars")
    cvarOpts.cvarSelection = { autoLootDefault = true }
    result = setup.Apply("WARRIOR", nil, cvarOpts)
    check("CVar selection forwarded", result.status == "applied" and settings.autoLootDefault == "1"
        and settings.screenshotQuality == "old" and result.steps.cvars.placed == 1)
    setup = fresh()
    env.inCombat = true
    result = setup.Apply("WARRIOR")
    core.Presets.WARRIOR.bars.main[1].spell = "changed while queued"
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("queued preset is isolated from later mutation", result.status == "applied" and actions[1].id == 284)
    setup = fresh()
    C_Item.GetItemInfo = function() return nil end
    actions[12] = { kind = "item", id = 6948 }
    result = setup.Apply("WARRIOR", nil, only("bars"))
    check("uncached bag item metadata preserves the designated action", result.status == "failed"
        and actions[12].id == 6948 and RikUICharDB.applied == nil)
    setup = fresh()
    local oldApplied = { class = "WARRIOR", role = "tank", at = 1, presetVersion = 1 }
    RikUICharDB.applied = oldApplied
    failPlace = true
    result = setup.Apply("WARRIOR", nil, only("bars"))
    check("failed attempt does not replace previous successful marker", result.status == "failed"
        and RikUICharDB.applied == oldApplied)
    failPlace = false
    result = setup.Apply("WARRIOR", nil, only("bars"))
    check("failed run releases pending Apply lock", result.status == "applied")
    setup = fresh()
    env.inCombat = true
    CreateMacro = function() return nil end
    result = setup.Apply("WARRIOR")
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("deferred macro failure terminates and releases Apply", result.status == "failed"
        and RikUICharDB.applied == nil and setup.Apply("WARRIOR", nil, only("layout")).status == "applied")
    setup = fresh()
    env.inCombat, failBinding = true, true
    result = setup.Apply("WARRIOR")
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("deferred binding failure stops later steps and releases Apply", result.status == "failed"
        and settings.autoLootDefault == "old" and RikUICharDB.applied == nil
        and setup.Apply("WARRIOR", nil, only("layout")).status == "applied")
    setup = fresh()
    check("false options rejected instead of enabling every step", setup.Apply("WARRIOR", nil, false) == nil
        and #calls == 0)
    setup = fresh()
    SlashCmdList.RIKUI("apply tank")
    check("slash command applies player class and requested role", RikUICharDB.applied and RikUICharDB.applied.role == "tank")
    for _, name in ipairs(globals) do _G[name] = savedGlobals[name] end
end
