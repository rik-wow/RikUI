local loadfile = dofile("tests/load_addon.lua").Loadfile
-- CVar contracts; run through tests/run_tests.lua.
return function(check)
    local env = require("wow_stub")
    local originalAPI = C_CVar
    local expected = {
        cameraDistanceMaxZoomFactor = 2.6, cameraSmoothStyle = 0,
        nameplateShowEnemies = 1, nameplateShowFriendlyPlayers = 0, nameplateShowFriendlyNpcs = 0,
        nameplateStackingTypes = 1,
        autoLootDefault = 1, SpellQueueWindow = 400,
        floatingCombatTextCombatDamage_v2 = 1, floatingCombatTextCombatHealing_v2 = 1,
        showTimestamps = "%H:%M ", chatBubbles = 1, chatBubblesParty = 0, screenshotQuality = 10,
        damageMeterEnabled = 1,
    }
    local values, reads, writes, behavior, bitWrites
    local function reset()
        values, reads, writes, behavior, bitWrites = {}, {}, {}, {}, {}
        for name in pairs(expected) do values[name] = "old:" .. name end
        values.nameplateStackingTypes = "1D" -- version 1, unrelated bit 3 set
        env.printed = {}
        C_CVar = {
            GetCVarInfo = function(name)
                reads[#reads + 1] = name
                if behavior[name] == "read-error" then error("read failed") end
                return values[name], "default", true, false, false, false, behavior[name] == "readonly"
            end,
            SetCVar = function(name, value)
                writes[#writes + 1] = { name = name, value = value }
                assert(type(value) == "string", "C_CVar requires a string value")
                if name == "nameplateStackingTypes" then
                    assert(value:sub(1, 1) == "1", "stacking needs an encoded bitfield")
                end
                if behavior[name] == "write-error" then error("write failed") end
                if behavior[name] == "false" then return false end
                if behavior[name] == "readonly" then return end
                values[name] = value
                return true
            end,
            SetCVarBitfield = function(name, index, value)
                bitWrites[#bitWrites + 1] = { name = name, index = index, value = value }
                assert(name == "nameplateStackingTypes" and (index == 1 or index == 2))
                assert(type(value) == "boolean", "bitfield writes need booleans")
                if behavior[name] == "write-error" then error("bitfield write failed") end
                if behavior[name] == "false" or behavior[name] == index then return false end
                if behavior[name] == "readonly" then return end
                local bit = require("bit")
                local mask = bit.lshift(1, index - 1)
                local data = values[name]:byte(2)
                data = value and bit.bor(data, mask) or bit.band(data, bit.bnot(mask))
                values[name] = values[name]:sub(1, 1) .. string.char(data)
                return true
            end,
        }
    end
    local function writtenCount()
        local names, n = {}, 0
        for _, write in ipairs(writes) do names[write.name] = true end
        for _, write in ipairs(bitWrites) do names[write.name] = true end
        for _ in pairs(names) do n = n + 1 end
        return n
    end
    local function contains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function count(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    reset()
    env.frames, env.inCombat = {}, false
    RikUI, RikUIDB, RikUICharDB = nil, nil, nil
    assert(loadfile("src/core/core.lua"))("RikUI", {})
    assert(loadfile("data/cvars.lua"))("RikUI", {})
    env.fire("ADDON_LOADED", "RikUI")
    env.fire("PLAYER_LOGIN")
    check("CVar module loads without reading or changing settings", #reads == 0 and #writes == 0)
    local cvars = RikUI.CVars
    check("CVar API is exposed", type(cvars) == "table")
    assert(cvars, "CVar API missing")
    local seen, listMatches = {}, #cvars.List == 15
    for _, entry in ipairs(cvars.List) do
        listMatches = listMatches and not seen[entry.name] and expected[entry.name] == entry.value
            and type(entry.label) == "string" and entry.label:match("%S") ~= nil
        seen[entry.name] = true
    end
    check("labelled CVar catalogue contains exactly the SDD settings and values", listMatches and count(seen) == 15)

    local prior, stats = cvars.Apply(nil, { quiet = true })
    check("69913 apply accepts every setting without unknown-CVar warnings",
        stats.placed == 15 and stats.skipped == 0 and stats.error == nil and #env.printed == 0)
    check("69913 apply hides both friendly player and NPC plates",
        values.nameplateShowFriendlyPlayers == "0" and values.nameplateShowFriendlyNpcs == "0")
    check("69913 apply uses the outgoing damage and healing v2 switches",
        values.floatingCombatTextCombatDamage_v2 == "1" and values.floatingCombatTextCombatHealing_v2 == "1")
    check("stacking writes enemy and friendly bits and preserves other bits",
        #bitWrites == 2 and bitWrites[1].index == 1 and bitWrites[2].index == 2
        and bitWrites[1].value == true and bitWrites[2].value == true and values.nameplateStackingTypes == "1G")
    check("stacking snapshot retains the original encoded string", prior.nameplateStackingTypes == "1D")
    check("stacking undo restores the entire original bitfield",
        cvars.Restore("nameplateStackingTypes", prior.nameplateStackingTypes) and values.nameplateStackingTypes == "1D")

    for _, failure in ipairs({ "false", "readonly", "write-error", 2 }) do
        reset()
        behavior.nameplateStackingTypes = failure
        prior, stats = cvars.Apply({ nameplateStackingTypes = true, autoLootDefault = true })
        check("stacking failure is reported once and remaining settings apply: " .. tostring(failure),
            stats.placed == 1 and stats.skipped == 1 and stats.error ~= nil
            and #env.printed == 2 and contains("Skipped nameplateStackingTypes")
            and not contains("Applied nameplateStackingTypes") and values.autoLootDefault == "1")
        behavior.nameplateStackingTypes = nil
        check("stacking failure keeps a restorable snapshot: " .. tostring(failure),
            cvars.Restore("nameplateStackingTypes", prior.nameplateStackingTypes)
            and values.nameplateStackingTypes == "1D")
    end
    reset()
    C_CVar.SetCVarBitfield = nil
    prior, stats = cvars.Apply({ nameplateStackingTypes = true, autoLootDefault = true })
    check("missing bitfield setter skips stacking without a scalar fallback",
        stats.placed == 1 and stats.skipped == 1 and stats.error ~= nil
        and #writes == 1 and writes[1].name == "autoLootDefault"
        and values.nameplateStackingTypes == "1D")
    reset()
    cvars.Apply({ autoLootDefault = true })
    check("unselected stacking leaves its bitfield untouched", #bitWrites == 0 and values.nameplateStackingTypes == "1D")
    reset()
    values.nameplateStackingTypes = nil
    prior, stats = cvars.Apply({ nameplateStackingTypes = true })
    check("unknown stacking is never written through either setter",
        stats.skipped == 1 and #bitWrites == 0 and #writes == 0)

    reset()
    local selection = { autoLootDefault = true, showTimestamps = true, cameraSmoothStyle = false, unknown = true }
    prior = cvars.Apply(selection)
    check("selection writes only explicitly enabled listed names", #writes == 2
        and values.autoLootDefault == "1" and values.showTimestamps == "%H:%M "
        and values.cameraSmoothStyle == "old:cameraSmoothStyle")
    check("selection does not probe unselected or arbitrary names", #reads == 2
        and count(prior) == 2 and prior.unknown == nil)
    check("apply returns the selected original strings", prior.autoLootDefault == "old:autoLootDefault"
        and prior.showTimestamps == "old:showTimestamps")
    check("apply leaves caller selection untouched", selection.cameraSmoothStyle == false and selection.unknown == true)
    check("each accepted write prints one applied line", #env.printed == 2
        and contains("Applied autoLootDefault") and contains("Applied showTimestamps"))

    reset()
    prior = cvars.Apply({})
    check("empty selection is a silent no-op", next(prior) == nil and #reads == 0 and #writes == 0 and #env.printed == 0)
    local validInput = pcall(cvars.Apply, false)
    check("invalid selection is rejected before any work", not validInput and #reads == 0 and #writes == 0)

    reset()
    values.showTimestamps = ""
    local snapshot = cvars.Snapshot()
    check("snapshot reads every listed CVar without writing", #reads == 15 and #writes == 0 and count(snapshot) == 15)
    check("snapshot preserves empty and nonnumeric strings", snapshot.showTimestamps == ""
        and snapshot.autoLootDefault == "old:autoLootDefault")
    values.autoLootDefault = "changed"
    check("snapshot is detached from later reads", snapshot.autoLootDefault == "old:autoLootDefault"
        and cvars.Snapshot().autoLootDefault == "changed")
    check("successful snapshot does not log apply messages", #env.printed == 0)

    reset()
    values.cameraSmoothStyle = nil
    prior = cvars.Apply()
    check("unknown CVar is never written while remaining settings apply", writtenCount() == 14
        and prior.cameraSmoothStyle == nil and values.screenshotQuality == "10")
    check("full apply reports exactly one line per applied or skipped CVar", #env.printed == 15
        and contains("Skipped cameraSmoothStyle") and not contains("Applied cameraSmoothStyle"))
    check("nil selection applies every known SDD value as a string", values.cameraDistanceMaxZoomFactor == "2.6"
        and values.nameplateShowFriendlyPlayers == "0" and values.SpellQueueWindow == "400" and values.showTimestamps == "%H:%M ")
    env.printed, writes = {}, {}
    snapshot = cvars.Snapshot()
    check("snapshot omits unknown values and reports the omission", count(snapshot) == 14
        and snapshot.cameraSmoothStyle == nil and #writes == 0 and #env.printed == 1
        and contains("Skipped cameraSmoothStyle"))

    reset()
    behavior.cameraDistanceMaxZoomFactor = "read-error"
    behavior.cameraSmoothStyle = "write-error"
    behavior.nameplateShowEnemies = "false"
    behavior.nameplateShowFriendlyPlayers = "readonly"
    local applyOk
    applyOk, prior = pcall(cvars.Apply)
    check("read and write failures do not abort the remaining CVars", applyOk and values.screenshotQuality == "10")
    check("failed reads are omitted from returned prior values", prior.cameraDistanceMaxZoomFactor == nil)
    check("rejected writes retain original values for undo", prior.cameraSmoothStyle == "old:cameraSmoothStyle"
        and prior.nameplateShowEnemies == "old:nameplateShowEnemies"
        and prior.nameplateShowFriendlyPlayers == "old:nameplateShowFriendlyPlayers")
    check("false nil and thrown writes are never reported applied", #env.printed == 15
        and contains("Skipped cameraDistanceMaxZoomFactor") and contains("Skipped cameraSmoothStyle")
        and contains("Skipped nameplateShowEnemies") and contains("Skipped nameplateShowFriendlyPlayers")
        and not contains("Applied cameraSmoothStyle") and not contains("Applied nameplateShowEnemies")
        and not contains("Applied nameplateShowFriendlyPlayers"))

    reset()
    local setter = C_CVar.SetCVar
    C_CVar.SetCVar = function(name, value)
        if name == "cameraDistanceMaxZoomFactor" then values.cameraSmoothStyle = "side effect" end
        return setter(name, value)
    end
    prior = cvars.Apply({ cameraDistanceMaxZoomFactor = true, cameraSmoothStyle = true })
    check("all original selected values are captured before the first write", prior.cameraSmoothStyle == "old:cameraSmoothStyle")

    reset()
    C_CVar = nil
    local missingOk, missingSnapshot = pcall(cvars.Snapshot)
    check("missing CVar API produces skips and an empty snapshot", missingOk and next(missingSnapshot) == nil
        and #env.printed == 15 and contains("Skipped autoLootDefault"))
    reset()
    C_CVar.SetCVar = nil
    local missingSetterOk = pcall(cvars.Apply, { autoLootDefault = true })
    check("missing setter is reported as skipped", missingSetterOk and #writes == 0
        and #env.printed == 1 and contains("Skipped autoLootDefault"))

    reset()
    SlashCmdList.RIKUI("")
    check("slash help advertises cvars", contains("/rik cvars"))
    env.printed = {}
    SlashCmdList.RIKUI("cvars")
    check("slash command applies the complete catalogue", writtenCount() == 15 and #env.printed == 15
        and values.autoLootDefault == "1" and values.screenshotQuality == "10")
    C_CVar = originalAPI
end
