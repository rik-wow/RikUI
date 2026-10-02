local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Native binding contracts; run through tests/run_tests.lua.
return function(check)
    local env = require("wow_stub")
    local names = {
        "RikUI", "RikUIDB", "RikUICharDB", "GetBindingAction",
        "GetCurrentBindingSet", "GetBindingKey", "SetBinding", "SaveBindings",
    }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local oldFrames, oldPrinted, oldCombat = env.frames, env.printed, env.inCombat
    local oldSlash = SlashCmdList and SlashCmdList.RIKUI

    local function run()
        local expected = { STRAFELEFT = "A", STRAFERIGHT = "D" }
        local function group(prefix, keys)
            for i, key in ipairs(keys) do expected[prefix .. i] = key end
        end
        group("ACTIONBUTTON", { "1", "2", "3", "4", "5", "Q", "E", "R", "F", "T", "G" })
        group("MULTIACTIONBAR1BUTTON", {
            "SHIFT-1", "SHIFT-2", "SHIFT-3", "SHIFT-4", "SHIFT-5", "SHIFT-Q",
            "SHIFT-E", "SHIFT-R", "SHIFT-F", "BUTTON4", "BUTTON5", "SHIFT-T",
        })
        group("MULTIACTIONBAR2BUTTON", {
            "CTRL-1", "CTRL-2", "CTRL-3", "CTRL-4", "CTRL-5", "CTRL-F",
            "CTRL-T", "CTRL-G", "CTRL-Z", "CTRL-X", "CTRL-C", "CTRL-V",
        })
        group("SHAPESHIFTBUTTON", { "CTRL-Q", "CTRL-E", "CTRL-R" })
        group("BONUSACTIONBUTTON", { "SHIFT-G", "CTRL-B", "CTRL-N" })
        local touched = { ["CTRL-6"] = true }
        for _, key in pairs(expected) do touched[key] = true end

        local function same(a, b)
            for k, v in pairs(a) do if b[k] ~= v then return false end end
            for k, v in pairs(b) do if a[k] ~= v then return false end end
            return true
        end
        local function touchedState(state)
            local keys = {}
            for key in pairs(touched) do keys[key] = state.keys[key] or "" end
            return keys
        end

        local allWritesQueued = true
        local function fresh()
            env.frames, env.printed, env.inCombat = {}, {}, false
            RikUI, RikUIDB, RikUICharDB = nil, nil, nil
            assert(loadfile("src/core/core.lua"))("RikUI", {})
            local state = {
                keys = { ["1"] = "ORIGINAL_ONE", Q = "ORIGINAL_Q", ["6"] = "ACTIONBUTTON6",
                    ["CTRL-6"] = "LEGACY", ["ALT-1"] = "ALT_ACTION", F12 = "KEEP" },
                log = {}, reads = 0, saves = 0, bindingSet = 1, depth = 0,
                keyOrder = { "1", "Q", "6", "CTRL-6", "ALT-1", "F12" },
            }
            local queue = RikUI.Combat.Queue
            RikUI.Combat.Queue = function(fn)
                return queue(function(...)
                    state.depth = state.depth + 1
                    local ok, err = pcall(fn, ...)
                    state.depth = state.depth - 1
                    if not ok then error(err) end
                end)
            end
            GetCurrentBindingSet = function()
                state.reads = state.reads + 1
                return state.bindingSet
            end
            GetBindingAction = function(key)
                state.reads = state.reads + 1
                return state.keys[key] or ""
            end
            GetBindingKey = function(command)
                if state.labelFixture then return state.primary, state.secondary, state.tertiary end
                if state.wrongPrimary and command == "ACTIONBUTTON6" and state.keys.Q == command then
                    return "6", "Q"
                end
                local keys = {}
                for _, key in ipairs(state.keyOrder) do
                    if state.keys[key] == command then keys[#keys + 1] = key end
                end
                return unpack(keys)
            end
            SetBinding = function(key, command)
                assert(not env.inCombat, "binding write during combat")
                allWritesQueued = allWritesQueued and state.depth > 0
                state.log[#state.log + 1] = { kind = "bind", key = key, command = command }
                local fail = state.reject
                if fail and ((fail == "clear" and command == nil)
                    or (fail ~= "clear" and command ~= nil)) then
                    state.reject = nil
                    if fail == "throw" then error("native SetBinding failed") end
                    return nil
                end
                if state.rejectKey == key and command then state.rejectKey = nil; return nil end
                if state.dropKeyAlways == key and command then return 1 end
                if state.dropKey == key and command then state.dropKey = nil; return 1 end
                if state.keys[key] == command then return 1 end
                for index, existing in ipairs(state.keyOrder) do
                    if existing == key then table.remove(state.keyOrder, index); break end
                end
                state.keys[key] = command
                if command then state.keyOrder[#state.keyOrder + 1] = key end
                return 1
            end
            SaveBindings = function(set)
                assert(not env.inCombat, "binding save during combat")
                allWritesQueued = allWritesQueued and state.depth > 0
                state.log[#state.log + 1] = { kind = "save", set = set }
                state.saves = state.saves + 1
                if state.saveFailure == "throw" then error("native SaveBindings failed") end
                if state.saveFailure == "false" then return false end
                state.bindingSet = set
                -- WoW's successful SaveBindings has no return value.
            end
            assert(loadfile("src/character/bindings.lua"))("RikUI", {})
            assert(RikUI.Bindings, "bindings module exposes RikUI.Bindings")
            return RikUI.Bindings, state
        end

        local service, state = fresh()
        check("bindings scheme matches all SDD commands and keys", same(service.Scheme, expected))
        local before = touchedState(state)
        before["6"] = "ACTIONBUTTON6"
        local snapshot = service.Snapshot()
        check("bindings snapshot captures set and every touched key, including empty keys",
            type(snapshot) == "table" and snapshot.bindingSet == 1 and same(snapshot.keys, before))
        check("bindings snapshot performs no writes", #state.log == 0)

        local result, reason = service.Apply()
        check("bindings apply returns the pre-application snapshot",
            type(result) == "table" and result.bindingSet == 1 and same(result.keys, before), reason)
        check("binding snapshots stay detached after writes",
            same(snapshot.keys, before) and snapshot.keys ~= result.keys)
        local clears, assigns, order = {}, 0, true
        for _, call in ipairs(state.log) do
            if call.kind == "bind" and call.command == nil then
                order = order and assigns == 0
                clears[call.key] = true
            elseif call.kind == "bind" then
                assigns = assigns + 1
                for key in pairs(touched) do order = order and clears[key] == true end
            end
        end
        local applied = assigns == 44 -- 43 scheme keys plus retained 6 alias
        for command, key in pairs(expected) do applied = applied and state.keys[key] == command end
        check("bindings clears scheme keys and old target aliases before assigning", order and clears["6"] == true)
        check("bindings applies exactly the default scheme and clears legacy CTRL-6",
            applied and state.keys["CTRL-6"] == nil)
        local last = state.log[#state.log]
        check("bindings saves and selects the character set once, after all bindings",
            state.saves == 1 and last.kind == "save" and last.set == 2 and state.bindingSet == 2)
        check("bindings preserves Alt, unrelated keys and existing aliases",
            state.keys["ALT-1"] == "ALT_ACTION" and state.keys.F12 == "KEEP" and state.keys["6"] == "ACTIONBUTTON6")

        check("native first key is the scheme primary while old number remains alternate",
            GetBindingKey("ACTIONBUTTON6") == "Q" and select(2, GetBindingKey("ACTIONBUTTON6")) == "6")
        service.Apply()
        check("repeat Apply retains primary ordering without duplicate aliases",
            GetBindingKey("ACTIONBUTTON6") == "Q" and select("#", GetBindingKey("ACTIONBUTTON6")) == 2)

        service, state = fresh()
        state.keys["ALT-Q"], state.keys.F11 = "ACTIONBUTTON6", "ACTIONBUTTON6"
        state.keyOrder[#state.keyOrder + 1], state.keyOrder[#state.keyOrder + 2] = "ALT-Q", "F11"
        service.Apply()
        check("all retained aliases keep relative order after new primary",
            table.concat({ GetBindingKey("ACTIONBUTTON6") }, ",") == "Q,6,ALT-Q,F11")
        service, state = fresh()
        state.keys.F11 = "ORIGINAL_Q"
        state.keyOrder[#state.keyOrder + 1] = "F11"
        state.rejectKey = "6" -- fail while restoring a retained target alias
        result, reason = service.Apply()
        check("alias write failure restores both target and displaced source ordering",
            result == nil and state.saves == 0 and GetBindingKey("ACTIONBUTTON6") == "6"
            and table.concat({ GetBindingKey("ORIGINAL_Q") }, ",") == "Q,F11")
        service, state = fresh()
        state.wrongPrimary = true
        result, reason = service.Apply()
        check("native primary mismatch rejects success and does not save",
            result == nil and state.saves == 0 and state.keys.Q == "ORIGINAL_Q"
            and reason:find("primary", 1, true))
        service, state = fresh()
        state.dropKey = "6"
        result, reason = service.Apply()
        check("silent alias loss is detected and restored",
            result == nil and state.saves == 0 and state.keys["6"] == "ACTIONBUTTON6")

        service, state = fresh()
        state.dropKeyAlways = "6"
        result, reason = service.Apply()
        check("silent rollback failure reports incomplete restoration",
            result == nil and state.saves == 0 and state.keys["6"] == nil
            and reason:find("runtime rollback incomplete", 1, true))

        service, state = fresh()
        GetBindingKey = function() end
        result, reason = service.Apply()
        check("incomplete native key enumeration aborts before mutation",
            result == nil and #state.log == 0 and reason:find("incomplete", 1, true))

        service, state = fresh()
        state.keys.Q = "ACTIONBUTTON1"
        result = service.Apply()
        check("old aliases that belong to the scheme are reassigned without being stolen back",
            result ~= nil and GetBindingKey("ACTIONBUTTON1") == "1" and state.keys.Q == "ACTIONBUTTON6")

        service, state = fresh()
        result = service.Apply({ strafe = false, mouse45 = false })
        check("bindings strafe option switches A and D to turning",
            result ~= nil and state.keys.A == "TURNLEFT" and state.keys.D == "TURNRIGHT")
        check("bindings mouse option uses keyboard alternatives without collisions",
            state.keys["SHIFT-G"] == "MULTIACTIONBAR1BUTTON10" and state.keys["CTRL-G"] == "MULTIACTIONBAR1BUTTON11"
                and state.keys.BUTTON4 == nil and state.keys.BUTTON5 == nil
                and GetBindingKey("MULTIACTIONBAR1BUTTON10") == "SHIFT-G")
        check("bindings options leave the canonical scheme unchanged", same(service.Scheme, expected))
        service.Apply()
        check("bindings later defaults restore the original scheme",
            state.keys.A == "STRAFELEFT" and state.keys.BUTTON4 == "MULTIACTIONBAR1BUTTON10"
                and state.keys["SHIFT-G"] == "BONUSACTIONBUTTON1" and state.keys["CTRL-G"] == "MULTIACTIONBAR2BUTTON8")

        service, state = fresh()
        env.inCombat = true
        local options = { strafe = false }
        result, reason = service.Apply(options)
        check("bindings combat application queues without reading or writing bindings",
            result == nil and reason == "queued" and state.reads == 0 and #state.log == 0)
        options.strafe = true
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("bindings queued application copies its options and runs on combat exit",
            state.keys.A == "TURNLEFT" and state.saves == 1 and GetBindingKey("ACTIONBUTTON6") == "Q")

        service, state = fresh()
        env.inCombat = true
        service.Apply()
        state.keys["1"] = "CHANGED_DURING_COMBAT"
        before = touchedState(state)
        state.reject = "set"
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("bindings queued rollback uses the snapshot from execution time",
            same(touchedState(state), before) and state.saves == 0)

        service, state = fresh()
        state.labelFixture = true
        local labels = { ["1"] = "1", Q = "Q", ["SHIFT-1"] = "s1",
            ["SHIFT-Q"] = "sQ", ["CTRL-1"] = "c1", ["CTRL-Z"] = "cZ", BUTTON4 = "M4", BUTTON5 = "M5" }
        local labelsCorrect = true
        for key, label in pairs(labels) do
            state.primary, state.secondary = key, "F12"
            labelsCorrect = labelsCorrect and service.Label("ACTIONBUTTON1") == label
        end
        state.primary = "R"
        check("bindings labels shorten the live primary key and follow rebindings",
            labelsCorrect and service.Label("ACTIONBUTTON1") == "R")
        state.primary, state.secondary, state.tertiary = "6", "F12", "Q"
        check("bindings label prefers the active scheme key among all aliases", service.Label("ACTIONBUTTON6") == "Q")
        state.primary, state.tertiary = "F12", "SHIFT-G"
        check("bindings label prefers the active no-mouse fallback", service.Label("MULTIACTIONBAR1BUTTON10") == "sG")
        state.primary, state.secondary, state.tertiary = nil, nil, nil
        check("bindings label is empty when unbound", service.Label("ACTIONBUTTON1") == "")
        GetBindingKey = nil
        check("bindings label tolerates unavailable API", service.Label("ACTIONBUTTON1") == "")
        GetBindingKey = function() error("unavailable") end
        local ok, label = pcall(service.Label, "ACTIONBUTTON1")
        check("bindings label tolerates native errors", ok and label == "")

        for _, opts in ipairs({ false, "bad", 3, { strafe = "yes" }, { mouse45 = 1 } }) do
            service, state = fresh()
            local success, value, err = pcall(service.Apply, opts)
            check("bindings invalid option types fail without mutations",
                success and value == nil and type(err) == "string" and #state.log == 0)
        end
        for _, failure in ipairs({ "clear", "set", "throw" }) do
            service, state = fresh()
            before, state.reject = touchedState(state), failure
            local success, value, err = pcall(service.Apply)
            check("bindings rejected " .. failure .. " restores snapshot without saving",
                success and value == nil and type(err) == "string" and state.saves == 0 and same(touchedState(state), before))
        end
        for _, failure in ipairs({ "false", "throw" }) do
            service, state = fresh()
            before, state.saveFailure = touchedState(state), failure
            local success, value, err = pcall(service.Apply)
            check("bindings save " .. failure .. " is reported and runtime keys restored",
                success and value == nil and type(err) == "string" and state.saves == 1 and same(touchedState(state), before))
        end
        for _, api in ipairs({ "GetCurrentBindingSet", "GetBindingAction", "GetBindingKey", "SetBinding", "SaveBindings" }) do
            service, state = fresh()
            _G[api] = nil
            local success, value, err = pcall(service.Apply)
            check("bindings handles missing " .. api,
                success and value == nil and type(err) == "string" and #state.log == 0)
            service, state = fresh()
            _G[api] = function() error("native API unavailable") end
            success, value, err = pcall(service.Apply)
            check("bindings handles throwing " .. api, success and value == nil and type(err) == "string")
        end

        service, state = fresh()
        local printedBefore = #env.printed
        SlashCmdList.RIKUI("binds")
        check("rik binds applies and prints one line per successful binding",
            state.saves == 1 and #env.printed - printedBefore == 43)
        service, state = fresh()
        state.saveFailure = "false"
        printedBefore = #env.printed
        SlashCmdList.RIKUI("binds")
        check("rik binds does not print a successful binding dump after failed save", #env.printed - printedBefore < 43)
        service,state=fresh()
        local selected={["ALT-1"]="ACTIONBUTTON1"}
        local selectedSnapshot=assert(service.CaptureSelected(selected))
        check("selected binding review performs no writes",#state.log==0)
        check("selected bindings apply and retain unrelated keys",service.ApplySelected(selected,selectedSnapshot) and state.keys["ALT-1"]=="ACTIONBUTTON1" and state.keys.F12=="KEEP" and state.keys["1"]=="ORIGINAL_ONE")
        local restoredSelected;RikUI.Combat.Queue(function()restoredSelected=service.Restore(selectedSnapshot)end)
        check("selected bindings restore displaced owners",restoredSelected and state.keys["ALT-1"]=="ALT_ACTION")
        service,state=fresh();selectedSnapshot=assert(service.CaptureSelected(selected));state.keys["ALT-1"]="EDITED"
        local selectedOK=service.ApplySelected(selected,selectedSnapshot)
        check("selected bindings reject stale review before writes",not selectedOK and #state.log==0)
        service,state=fresh();selectedSnapshot=assert(service.CaptureSelected(selected));state.dropKey="ALT-1"
        selectedOK=service.ApplySelected(selected,selectedSnapshot)
        check("selected bindings detect silent writes and recover",not selectedOK and state.keys["ALT-1"]=="ALT_ACTION" and state.saves==0)
        service,state=fresh();env.inCombat=true
        check("selected bindings refuse combat without reads",not service.CaptureSelected(selected) and state.reads==0)
        check("selected binding scope is bounded",not service.CaptureSelected({X="ACTIONBUTTON99"}))
        check("bindings routes every native mutation through the core queue", allWritesQueued)
    end

    local ok, err = pcall(run)
    for _, name in ipairs(names) do _G[name] = saved[name] end
    env.frames, env.printed, env.inCombat = oldFrames, oldPrinted, oldCombat
    if SlashCmdList then SlashCmdList.RIKUI = oldSlash end
    if not ok then error(err) end
end
