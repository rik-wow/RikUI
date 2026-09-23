local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Setup contracts exercise the real modules and real combat queue.
return function(check)
    local env = require("wow_stub")
    local core, actions, cursor, calls, macroData, settings, keys, keyOrder, known, items
    local failPlace, failBinding, failCVar, combatAfterMacro, firstWriteSnapshot
    local savedGlobals = {}
    local globals = { "GetActionInfo", "GetCursorInfo", "PickupAction", "PickupMacro", "PlaceAction",
        "ClearCursor", "GetMacroInfo", "CreateMacro", "EditMacro", "DeleteMacro", "C_Macro", "GetCurrentBindingSet",
        "GetBindingAction", "GetBindingKey", "SetBinding", "SaveBindings", "C_Spell", "C_Item", "C_CVar",
        "C_Container", "time", "StaticPopupDialogs", "StaticPopup_Show" }
    for _, name in ipairs(globals) do savedGlobals[name] = _G[name] end

    local function record(value)
        assert(not InCombatLockdown(), "protected write in combat")
        if #calls == 0 then firstWriteSnapshot = RikUICharDB.undo end
        calls[#calls + 1] = value
    end
    local function fresh()
        env.frames, env.printed, env.inCombat = {}, {}, false
        RikUIDB, RikUICharDB = nil, nil
        for _, file in ipairs({ "src/core/core.lua", "data/spells.lua", "data/cvars.lua",
            "presets/warrior.lua", "src/setup/setup.lua", "src/setup/setup-actions.lua", "src/setup/setup-apply.lua",
            "src/character/macros.lua", "src/character/bindings.lua", "src/character/macros-undo.lua", "src/setup/setup-snapshot.lua", "src/setup/setup-undo.lua",
            "src/setup/setup-levelup.lua", "src/setup/setup-talents.lua", "src/setup/setup-role.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        core = RikUI
        env.fire("ADDON_LOADED", "RikUI")
        actions, calls, macroData, keys, keyOrder = {}, {}, {}, {}, {}
        cursor, failPlace, failBinding, failCVar, combatAfterMacro = nil, false, false, false, false
        firstWriteSnapshot = nil
        known = { ["Heroic Strike"] = 284, ["Rend"] = 772, ["Charge"] = 100 }
        items, settings = { Hearthstone = 6948 }, {}
        for _, entry in ipairs(core.CVars.List) do settings[entry.name] = "old" end
        settings.nameplateStackingTypes = nil -- valid unknown-CVar skip
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
        DeleteMacro = function(index)
            record("deleteMacro")
            macroData[index] = nil
        end
        C_Macro = { GetSelectedMacroIcon = function(index)
            local value = macroData[index]
            return value and (value.selectedIcon or value.icon)
        end }
        GetCurrentBindingSet = function() return 1 end
        GetBindingAction = function(key) return keys[key] or "" end
        GetBindingKey = function(command)
            local matches = {}
            for _, key in ipairs(keyOrder) do
                if keys[key] == command then matches[#matches + 1] = key end
            end
            return unpack(matches)
        end
        SetBinding = function(key, command)
            record("bind")
            if failBinding then return false end
            if keys[key] == command then return true end
            for index, existing in ipairs(keyOrder) do
                if existing == key then table.remove(keyOrder, index); break end
            end
            keys[key] = command
            if command then keyOrder[#keyOrder + 1] = key end
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
    actions[71] = { kind = "spell", id = 555 }
    cursor = { kind = "item", id = 777 }
    keys["6"], keyOrder[1] = "ACTIONBUTTON6", "6"
    local result = setup.Apply("WARRIOR")
    local primary, secondary = GetBindingKey("ACTIONBUTTON6")
    check("Setup promotes preset key and retains the old main-bar alias", primary == "Q" and secondary == "6")
    check("Apply finishes and records versioned character identity", result.status == "applied"
        and RikUICharDB.applied.class == "WARRIOR" and RikUICharDB.applied.role == "dps"
        and RikUICharDB.applied.at == 123456 and RikUICharDB.applied.presetVersion == 1)
    check("highest known spell placed on base and stance pages", actions[1].id == 284 and actions[73].id == 284)
    check("unknown designated spell is cleared and unspecified side slot preserved", actions[8] == nil and actions[25].id == 42)
    check("bag item and usable macro placed", actions[12].id == 6948 and actions[70] and actions[70].kind == "macro")
    check("macros whose attacks are all unlearned leave their slots empty", actions[5] == nil and actions[82] == nil)
    check("an old action in an unusable macro slot is cleared like an unlearned spell", actions[71] == nil)
    check("cursor is empty after Apply", cursor == nil)
    check("layout positions are saved independently", core.Profile.positions.main.point == "BOTTOM"
        and core.Profile.positions.main ~= setup.DefaultPositions.main)
    check("Apply names, once, the spells it expected at this level and did not find, and none above the level",
        countLines("not in your spellbook") == 1 and countLines("Pummel") == 0)
    check("a setting this client does not know is counted as skipped and named once",
        result.steps.cvars.placed == 14 and result.steps.cvars.skipped == 1
        and countLines("nameplateStackingTypes") == 1)
    check("one summary per step without per-binding/cvar chatter", countLines() == 8
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
        and actions[73].id == 284 and RikUICharDB.applied ~= nil and countLines() == 8)

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
        and next(macroData) == nil and next(keys) == nil and actions[70] == nil
        and settings.autoLootDefault == "old" and next(core.Profile.positions) == nil)
    setup = fresh()
    core.Presets.WARRIOR.macros.Execute.spells = nil
    result = setup.Apply("WARRIOR")
    check("a macro without a spells list keeps unconditional placement", result.status == "applied"
        and actions[5] and actions[5].kind == "macro")
    setup = fresh()
    core.Spells.HighestKnownRank = function(name)
        if name == "Execute" then return nil, "Spellbook lookup failed" end
        return known[name]
    end
    actions[5] = { kind = "spell", id = 999 }
    result = setup.Apply("WARRIOR", nil, only("bars"))
    check("spellbook errors on a macro's attacks fail Apply without clearing the slot", result.status == "failed"
        and actions[5].id == 999 and result.error:find("slot 5", 1, true))
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

    setup = fresh()
    check("Setup exports persistent snapshot and undo", type(setup.Snapshot) == "function" and type(setup.Undo) == "function")
    if type(setup.Undo) == "function" and type(setup.Snapshot) == "function" then
        actions[1], actions[8], actions[25] = { kind = "spell", id = 999 }, { kind = "item", id = 42 }, { kind = "spell", id = 555 }
        macroData[121] = { name = "Execute", icon = 999, selectedIcon = 134400, body = "/say original" }
        macroData[1] = { name = "Execute", icon = 77, body = "/say account" }
        actions[5] = { kind = "macro", id = 1 }
        keys["6"], keys["7"], keys.Q = "ACTIONBUTTON6", "ACTIONBUTTON6", "TOGGLEBAG1"
        keyOrder[1], keyOrder[2], keyOrder[3] = "6", "7", "Q"
        core.Profile.positions.main = { x = 12, y = 34 }
        core.Profile.positions.custom = { x = 99 }
        local oldMarker = { class = "WARRIOR", role = "tank", at = 1 }
        RikUICharDB.applied = oldMarker
        result = setup.Apply("WARRIOR")
        local snapshot = RikUICharDB.undo
        check("full snapshot is persisted before first protected write", firstWriteSnapshot == snapshot
            and snapshot.bars[1].id == 999 and snapshot.bars[8].id == 42
            and snapshot.binds.keys.Q == "TOGGLEBAG1" and snapshot.cvars.autoLootDefault == "old")
        check("snapshot excludes undesignated slots and unknown CVars", snapshot.bars[25] == nil
            and snapshot.cvars.nameplateStackingTypes == nil)
        check("Apply advertises undo once", countLines("type /rik undo to revert") == 1)
        macroData[130] = { name = "Unrelated", icon = 55, body = "/say keep" }
        env.printed, calls = {}, {}
        local undone = setup.Undo()
        check("Undo restores spell item empty and scoped macro slots", undone.status == "undone"
            and actions[1].id == 999 and actions[8].id == 42 and actions[2] == nil
            and actions[5].kind == "macro" and actions[5].id == 1 and actions[25].id == 555)
        check("Undo restores edited macro body and selected icon", macroData[121].body == "/say original"
            and macroData[121].icon == 134400 and macroData[1].body == "/say account")
        check("Undo deletes created macros and preserves unrelated macros", core.Macros.Find("Charge") == nil
            and core.Macros.Find("Revenge") == nil and macroData[130].body == "/say keep")
        local a, b = GetBindingKey("ACTIONBUTTON6")
        check("Undo restores binding primary order and displaced commands", a == "6" and b == "7"
            and keys.Q == "TOGGLEBAG1" and keys["SHIFT-1"] == nil)
        check("Undo restores CVars layout and applied marker", settings.autoLootDefault == "old"
            and core.Profile.positions.main.x == 12 and core.Profile.positions.bar2 == nil
            and core.Profile.positions.custom.x == 99 and RikUICharDB.applied.role == "tank"
            and RikUICharDB.applied.at == 1)
        check("Undo consumes snapshot and summarizes each step", RikUICharDB.undo == nil and countLines() == 6
            and countLines("Undo bars:") == 1 and countLines("Undo macros:") == 1)
        calls, env.printed = {}, {}
        SlashCmdList.RIKUI("undo")
        check("second slash undo is a no-op", #calls == 0 and countLines("nothing to undo") == 1)

        setup = fresh()
        local opts = only("cvars")
        opts.cvarSelection = { autoLootDefault = true }
        result = setup.Apply("WARRIOR", nil, opts)
        snapshot = RikUICharDB.undo
        check("snapshot respects step flags and CVar selection", snapshot.bars == nil and snapshot.binds == nil
            and snapshot.macros == nil and snapshot.layout == nil and snapshot.cvars.autoLootDefault == "old"
            and snapshot.cvars.screenshotQuality == nil)
        settings.screenshotQuality = "new unrelated"
        setup.Undo()
        check("selected undo preserves settings outside selection", settings.autoLootDefault == "old"
            and settings.screenshotQuality == "new unrelated")

        setup = fresh()
        env.inCombat = true
        result = setup.Apply("WARRIOR", nil, only("bars"))
        check("queued Apply has no premature snapshot", RikUICharDB.undo == nil and #calls == 0)
        actions[1] = { kind = "spell", id = 333 }
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("snapshot captures state at actual Apply execution", RikUICharDB.undo.bars[1].id == 333)
        env.inCombat, calls, env.printed = true, {}, {}
        undone = setup.Undo()
        check("Undo queues without writes during combat", undone.status == "queued" and #calls == 0 and countLines("combat") == 1)
        check("pending Undo excludes Apply and another Undo", setup.Apply("WARRIOR") == nil and setup.Undo() == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("queued Undo completes out of combat", undone.status == "undone" and actions[1].id == 333)

        setup = fresh()
        local previousUndo = { sentinel = true }
        RikUICharDB.undo = previousUndo
        actions[1] = { kind = "equipmentset", id = 3 }
        result = setup.Apply("WARRIOR")
        check("unsupported prior action rejects before writes and preserves old undo", result.status == "failed"
            and #calls == 0 and RikUICharDB.undo == previousUndo)
        setup = fresh()
        local originalLookup = C_CVar.GetCVarInfo
        C_CVar.GetCVarInfo = function() error("unreadable") end
        result = setup.Apply("WARRIOR")
        check("snapshot failure prevents every Apply write", result.status == "failed" and #calls == 0 and RikUICharDB.undo == nil)
        C_CVar.GetCVarInfo = originalLookup

        setup = fresh()
        actions[1] = { kind = "spell", id = 444 }
        result = setup.Apply("WARRIOR", nil, only("bars"))
        failPlace = true
        undone = setup.Undo()
        check("Undo readback failure retains snapshot", undone.status == "failed" and RikUICharDB.undo ~= nil)
        failPlace = false
        undone = setup.Undo()
        check("failed Undo can retry and consume snapshot", undone.status == "undone"
            and actions[1].id == 444 and RikUICharDB.undo == nil)

        setup = fresh()
        failPlace = true
        result = setup.Apply("WARRIOR")
        failPlace = false
        undone = setup.Undo()
        check("partially failed Apply remains undoable", result.status == "failed" and undone.status == "undone"
            and next(actions) == nil and next(macroData) == nil and RikUICharDB.applied == nil)

        setup = fresh()
        local preview = setup.Snapshot()
        check("Snapshot previews a detached write set without saving or writing", preview and preview.version == 1
            and RikUICharDB.undo == nil and #calls == 0)
        check("Snapshot rejects invalid option values", setup.Snapshot("WARRIOR", nil, false) == nil)
        env.inCombat = true
        check("Snapshot refuses unreadable combat state", setup.Snapshot() == nil)
        env.inCombat = false

        setup = fresh()
        keys["6"], keyOrder[1] = "ACTIONBUTTON6", "6"
        setup.Apply("WARRIOR", nil, only("binds"))
        SetBinding("Z", "ACTIONBUTTON6")
        undone = setup.Undo()
        local primaryKey, addedAlias = GetBindingKey("ACTIONBUTTON6")
        check("Undo preserves a later alias after restoring original primary", undone.status == "undone"
            and primaryKey == "6" and addedAlias == "Z")

        setup = fresh()
        setup.Apply("WARRIOR", nil, only("macros"))
        local charge = assert(core.Macros.Find("Charge"))
        macroData[charge].selectedIcon = 987
        undone = setup.Undo()
        check("Undo preserves a newly edited created macro and reports conflict", undone.status == "failed"
            and macroData[charge] ~= nil and RikUICharDB.undo ~= nil)

        setup = fresh()
        local nativeDelete = DeleteMacro
        setup.Apply("WARRIOR", nil, only("macros"))
        DeleteMacro = function() end
        undone = setup.Undo()
        check("silent macro deletion rejection keeps snapshot", undone.status == "failed"
            and RikUICharDB.undo ~= nil)
        DeleteMacro = nativeDelete
        check("macro deletion failure is retryable", setup.Undo().status == "undone" and next(macroData) == nil)

        setup = fresh()
        macroData[121] = { name = "Execute", body = "one", icon = 1 }
        macroData[122] = { name = "Execute", body = "two", icon = 2 }
        result = setup.Apply("WARRIOR")
        check("ambiguous original macros stop Apply before writes", result.status == "failed" and #calls == 0)

        setup = fresh()
        -- Simulate native sorting and index changes, including action references.
        local function sortMacroPools()
            local remap, sorted = {}, {}
            for _, first in ipairs({ 1, 121 }) do
                local pool = {}
                for index, macro in pairs(macroData) do
                    if (index >= 121) == (first == 121) then
                        pool[#pool + 1] = { old = index, macro = macro }
                    end
                end
                table.sort(pool, function(a, b) return a.macro.name < b.macro.name end)
                for offset, value in ipairs(pool) do
                    local index = first + offset - 1
                    remap[value.old], sorted[index] = index, value.macro
                end
            end
            for _, action in pairs(actions) do
                if action.kind == "macro" then action.id = remap[action.id] end
            end
            macroData = sorted
            return remap
        end
        local createUnsorted, editUnsorted, deleteUnsorted = CreateMacro, EditMacro, DeleteMacro
        CreateMacro = function(...)
            local index = createUnsorted(...)
            return sortMacroPools()[index]
        end
        EditMacro = function(...)
            local index = editUnsorted(...)
            return sortMacroPools()[index]
        end
        DeleteMacro = function(index) deleteUnsorted(index); sortMacroPools() end
        macroData[121] = { name = "Zebra", body = "/say keep", icon = 55 }
        macroData[1] = { name = "Zebra", body = "/say account", icon = 56 }
        actions[1] = { kind = "macro", id = 121 }
        result = setup.Apply("WARRIOR")
        CreateMacro("Alpha", 11, "/say new")
        undone = setup.Undo()
        check("Undo resolves macro actions after sorted creations and deletions", result.status == "applied"
            and undone.status == "undone" and actions[1].id == core.Macros.Find("Zebra")
            and macroData[actions[1].id].body == "/say keep" and core.Macros.Find("Alpha") ~= nil)

        setup = fresh()
        actions[1] = { kind = "spell", id = 345 }
        setup.Apply("WARRIOR")
        local restoreCVar = C_CVar.SetCVar
        local stopOnce = true
        C_CVar.SetCVar = function(name, value)
            local accepted = restoreCVar(name, value)
            if stopOnce then stopOnce = false; env.inCombat = true end
            return accepted
        end
        undone = setup.Undo()
        check("combat appearing during Undo suspends later native writes", undone.status == "queued"
            and RikUICharDB.undo ~= nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("mid-Undo combat suspension resumes and finishes", undone.status == "undone" and actions[1].id == 345)

        setup = fresh()
        actions[1] = { kind = "spell", id = 345 }
        setup.Apply("WARRIOR", nil, only("bars"))
        known["Heroic Strike"] = 1608
        setup.Apply("WARRIOR", nil, only("bars"))
        undone = setup.Undo()
        check("repeat Apply replaces undo with the immediately previous state", undone.status == "undone"
            and actions[1].id == 284 and RikUICharDB.applied.role == "dps")

        setup = fresh()
        core.Profile.positions.main = { x = 9 }
        setup.Apply("WARRIOR")
        RikUICharDB.undo.bars[1] = { kind = "spell" }
        calls = {}
        local invalidUndo = RikUICharDB.undo
        check("malformed action snapshot refuses before restoration writes", setup.Undo() == nil
            and #calls == 0 and RikUICharDB.undo == invalidUndo and core.Profile.positions.main.x == 0)

        setup = fresh()
        setup.Apply("WARRIOR")
        RikUICharDB.undo.binds.commands.ACTIONBUTTON1 = "invalid"
        calls = {}
        check("malformed binding snapshot refuses before restoration writes", setup.Undo() == nil and #calls == 0)

        setup = fresh()
        local createBeforeCVar = CreateMacro
        CreateMacro = function(...)
            settings.nameplateStackingTypes = "new"
            return createBeforeCVar(...)
        end
        result = setup.Apply("WARRIOR")
        check("Apply never writes a CVar absent from initial snapshot", result.status == "applied"
            and settings.nameplateStackingTypes == "new" and RikUICharDB.undo.cvars.nameplateStackingTypes == nil)

        setup = fresh()
        local originalProfile = core.Profile
        originalProfile.positions.main = { x = 19 }
        env.inCombat = true
        result = setup.Apply("WARRIOR", nil, only("layout"))
        core.DB.profiles.Other = { positions = { main = { x = 88 } } }
        core.Profile, core.CharDB.profile = core.DB.profiles.Other, "Other"
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        undone = setup.Undo()
        check("queued Apply undo restores the captured profile after a profile switch", undone.status == "undone"
            and originalProfile.positions.main.x == 19 and core.Profile.positions.main.x == 88)

        setup = fresh()
        actions[1] = { kind = "spell", id = 222 }
        setup.Apply("WARRIOR", nil, only("bars"))
        local savedAccount, savedCharacter = RikUIDB, RikUICharDB
        env.frames = {}
        for _, file in ipairs({ "src/core/core.lua", "data/spells.lua", "data/cvars.lua", "presets/warrior.lua",
            "src/setup/setup.lua", "src/setup/setup-actions.lua", "src/setup/setup-apply.lua", "src/character/macros.lua", "src/character/bindings.lua", "src/character/macros-undo.lua",
            "src/setup/setup-snapshot.lua", "src/setup/setup-undo.lua", "src/setup/setup-levelup.lua", "src/setup/setup-talents.lua", "src/setup/setup-role.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        RikUIDB, RikUICharDB = savedAccount, savedCharacter
        env.fire("ADDON_LOADED", "RikUI")
        core, setup = RikUI, RikUI.Setup
        undone = setup.Undo()
        check("saved snapshot survives addon reload and restores", undone.status == "undone"
            and actions[1].id == 222 and RikUICharDB.undo == nil)
    end

    setup = fresh()
    actions[1] = { kind = "item", id = 6948 }
    setup.Apply("WARRIOR", nil, only("bars"))
    env.inCombat = true
    env.fire("LEARNED_SPELL_IN_SKILL_LINE", 284)
    local pendingUndo = setup.Undo()
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    env.fire("SPELLS_CHANGED")
    check("queued learned event cannot refill slots during or after first Apply Undo",
        pendingUndo.status == "undone" and actions[1].kind == "item" and actions[1].id == 6948
        and RikUICharDB.applied == nil)

    setup = fresh()
    setup.Apply("WARRIOR", nil, only("bars"))
    local restoreSlot = setup.RestoreSlot
    local rejectOnce = true
    setup.RestoreSlot = function(slot, action)
        if slot == 1 and rejectOnce then rejectOnce = false; return nil, "retry me" end
        return restoreSlot(slot, action)
    end
    local failedUndo = setup.Undo()
    env.fire("SPELLS_CHANGED")
    check("resync preserves completed entries after partial Undo failure",
        failedUndo.status == "failed" and actions[73] == nil)
    local retriedUndo = setup.Undo()
    check("retry Undo retains originally empty slots after learned events",
        retriedUndo.status == "undone" and actions[73] == nil)

    setup = fresh()
    known["Sunder Armor"] = 7386
    setup.Apply("WARRIOR", "dps")
    local oldApplied = RikUICharDB.applied
    local originalID = actions[1].id
    core.Profile.positions.main = { x = 777 }
    settings.autoLootDefault = "custom"
    keys.F12 = "JUMP"
    macroData[121].body = "/say original macro"
    local popup
    StaticPopupDialogs = {}
    StaticPopup_Show = function(which, _, _, data)
        popup = { which = which, data = data }
        return popup
    end
    setup.GuessRole = function() return "tank", {} end
    env.fire("PLAYER_TALENT_UPDATE")
    calls = {}
    env.inCombat = true
    StaticPopupDialogs[popup.which].OnAccept(popup, popup.data)
    check("real role Apply waits in combat", #calls == 0 and RikUICharDB.applied == oldApplied)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("confirmed role executes actual bar and macro writers", RikUICharDB.applied.role == "tank"
        and actions[1].id == 7386 and macroData[121].body ~= "/say original macro")
    local wroteOther = false
    for _, call in ipairs(calls) do
        if call == "bind" or call == "save" or call == "cvar" then wroteOther = true end
    end
    check("role switch preserves keys CVars and layout", not wroteOther and keys.F12 == "JUMP"
        and settings.autoLootDefault == "custom" and core.Profile.positions.main.x == 777)
    local roleUndo = setup.Undo()
    check("role switch snapshot restores previous bars macros and role", roleUndo.status == "undone"
        and actions[1].id == originalID and macroData[121].body == "/say original macro"
        and RikUICharDB.applied.role == "dps")

    -- Seen on 69913: a macro slot answers ("macro", <ID of the spell the macro casts>, "spell"), not
    -- the macro's index. The macro's name is only available from GetActionText.
    setup = fresh()
    local savedText = GetActionText
    GetActionInfo = function(slot)
        local action = actions[slot]
        if not action then return end
        if action.kind == "macro" then return "macro", 100, "spell" end
        return action.kind, action.id
    end
    GetActionText = function(slot)
        local action = actions[slot]
        if action and action.kind == "macro" then return macroData[action.id].name end
    end
    local first = setup.Apply("WARRIOR")
    check("a macro is placed although the client reports the spell it casts instead of its index",
        first.status == "applied" and actions[70] and actions[70].kind == "macro")
    env.printed = {}
    local second = setup.Apply("WARRIOR")
    check("a second Apply snapshots the placed macro by its name instead of failing on the spell ID",
        second.status == "applied" and RikUICharDB.undo.bars[70].macro.name == "Charge"
        and countLines("macro missing") == 0)
    local undone = setup.Undo()
    check("and Undo puts that macro back", undone.status == "undone" and actions[70] and actions[70].kind == "macro")
    GetActionText = savedText

    setup = fresh()
    settings.nameplateStackingTypes = "1D"
    C_CVar.SetCVarBitfield = function(name, index, value)
        record("cvar")
        assert(name == "nameplateStackingTypes" and value == true)
        local data, mask = settings[name]:byte(2), 2 ^ (index - 1)
        if math.floor(data / mask) % 2 == 0 then data = data + mask end
        settings[name] = settings[name]:sub(1, 1) .. string.char(data)
        return true
    end
    result = setup.Apply("WARRIOR", nil, only("cvars"))
    check("setup applies all 15 supported 69913 settings without an unknown warning",
        result.status == "applied" and result.steps.cvars.placed == 15
        and result.steps.cvars.skipped == 0 and countLines("unknown on this client") == 0)
    check("setup preserves the stacking snapshot before enabling both bits",
        RikUICharDB.undo.cvars.nameplateStackingTypes == "1D" and settings.nameplateStackingTypes == "1G")
    check("setup applies the replacement friendly and outgoing text settings",
        settings.nameplateShowFriendlyPlayers == "0" and settings.nameplateShowFriendlyNpcs == "0"
        and settings.floatingCombatTextCombatDamage_v2 == "1" and settings.floatingCombatTextCombatHealing_v2 == "1")
    undone = setup.Undo()
    check("setup undo restores encoded stacking and the renamed scalar settings",
        undone.status == "undone" and settings.nameplateStackingTypes == "1D"
        and settings.nameplateShowFriendlyPlayers == "old" and settings.nameplateShowFriendlyNpcs == "old"
        and settings.floatingCombatTextCombatDamage_v2 == "old" and settings.floatingCombatTextCombatHealing_v2 == "old")

    -- Every displayed stance page must expose the actions placed by the real preset writer.
    for _, role in ipairs({ "dps", "tank" }) do
        setup = fresh()
        assert(loadfile("data/bonus-pages.lua"))("RikUI", {})
        for name, spell in pairs(core.SpellData) do known[name] = spell.ranks[1] end
        keys.F12, core.Profile.positions.main = "JUMP", { x = 777 }
        local applied = setup.Apply("WARRIOR", role,
            { macros = true, bars = true, binds = false, cvars = false, layout = false })
        local preset = assert(setup.Resolve("WARRIOR", role))
        check(role .. " stance preset applies successfully", applied.status == "applied")
        check(role .. " has all three display mappings", #core.Data.BonusPages.WARRIOR == 3)
        for _, page in ipairs(core.Data.BonusPages.WARRIOR) do
            for index = 1, 12 do
                local entry, slot = preset.bars[page.name][index], page.firstAction + index - 1
                local action = actions[slot]
                local matches = action and ((entry.spell and action.kind == "spell" and action.id == known[entry.spell])
                    or (entry.item and action.kind == "item" and action.id == items[entry.item])
                    or (entry.macro and action.kind == "macro" and macroData[action.id]
                        and macroData[action.id].name == entry.macro
                        and macroData[action.id].body == preset.macros[entry.macro].body))
                check(role .. " " .. page.name .. " displayed slot " .. index .. " matches Apply",
                    setup.SlotToAction(page.name, index) == slot and matches)
            end
        end
        check(role .. " Battle offers Charge and Overpower", actions[78].id == known.Charge
            and actions[79].id == known.Overpower)
        check(role .. " Defensive offers Taunt and Revenge", actions[90].id == known.Taunt
            and actions[91].id == known.Revenge)
        check(role .. " Berserker offers Intercept and Pummel", actions[102].id == known.Intercept
            and actions[104].id == known.Pummel)
        -- Learning/resync fills empty stance actions without replacing a player's custom slot.
        local custom = { kind = "item", id = 99999 }
        actions[92] = custom
        for _, slot in ipairs({ 78, 90, 102, 77, 89, 101 }) do actions[slot] = nil end
        local synced = setup.Resync()
        check(role .. " Resync fills each stance's spell and macro slots", synced.status == "complete"
            and actions[78].id == known.Charge and actions[90].id == known.Taunt
            and actions[102].id == known.Intercept
            and actions[77].kind == "macro" and actions[89].kind == "macro" and actions[101].kind == "macro")
        check(role .. " Resync preserves custom actions and setup preserves keys/layout",
            actions[92] == custom and keys.F12 == "JUMP" and core.Profile.positions.main.x == 777)
    end

    for _, name in ipairs(globals) do _G[name] = savedGlobals[name] end
end
