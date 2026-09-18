-- CVar contracts; run through tests/run_tests.lua.
return function(check)
    local env = require("wow_stub")
    local originalAPI = C_CVar
    local expected = {
        cameraDistanceMaxZoomFactor = 2.6, cameraSmoothStyle = 0,
        nameplateShowEnemies = 1, nameplateShowFriends = 0, nameplateMotion = 1,
        autoLootDefault = 1, SpellQueueWindow = 400,
        floatingCombatTextCombatDamage = 1, floatingCombatTextCombatHealing = 1,
        showTimestamps = "%H:%M ", chatBubbles = 1, chatBubblesParty = 0, screenshotQuality = 10,
    }
    local values, reads, writes, behavior
    local function reset()
        values, reads, writes, behavior = {}, {}, {}, {}
        for name in pairs(expected) do values[name] = "old:" .. name end
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
                if behavior[name] == "write-error" then error("write failed") end
                if behavior[name] == "false" then return false end
                if behavior[name] == "readonly" then return end
                values[name] = value
                return true
            end,
        }
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
    assert(loadfile("core.lua"))("RikUI", {})
    assert(loadfile("data/cvars.lua"))("RikUI", {})
    env.fire("ADDON_LOADED", "RikUI")
    env.fire("PLAYER_LOGIN")
    check("CVar module loads without reading or changing settings", #reads == 0 and #writes == 0)
    local cvars = RikUI.CVars
    check("CVar API is exposed", type(cvars) == "table")
    assert(cvars, "CVar API missing")
    local seen, listMatches = {}, #cvars.List == 13
    for _, entry in ipairs(cvars.List) do
        listMatches = listMatches and not seen[entry.name] and expected[entry.name] == entry.value
            and type(entry.label) == "string" and entry.label:match("%S") ~= nil
        seen[entry.name] = true
    end
    check("labelled CVar catalogue contains exactly the SDD settings and values", listMatches and count(seen) == 13)

    local selection = { autoLootDefault = true, showTimestamps = true, cameraSmoothStyle = false, unknown = true }
    local prior = cvars.Apply(selection)
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
    check("snapshot reads every listed CVar without writing", #reads == 13 and #writes == 0 and count(snapshot) == 13)
    check("snapshot preserves empty and nonnumeric strings", snapshot.showTimestamps == ""
        and snapshot.autoLootDefault == "old:autoLootDefault")
    values.autoLootDefault = "changed"
    check("snapshot is detached from later reads", snapshot.autoLootDefault == "old:autoLootDefault"
        and cvars.Snapshot().autoLootDefault == "changed")
    check("successful snapshot does not log apply messages", #env.printed == 0)

    reset()
    values.cameraSmoothStyle = nil
    prior = cvars.Apply()
    check("unknown CVar is never written while remaining settings apply", #writes == 12
        and prior.cameraSmoothStyle == nil and values.screenshotQuality == "10")
    check("full apply reports exactly one line per applied or skipped CVar", #env.printed == 13
        and contains("Skipped cameraSmoothStyle") and not contains("Applied cameraSmoothStyle"))
    check("nil selection applies every known SDD value as a string", values.cameraDistanceMaxZoomFactor == "2.6"
        and values.nameplateShowFriends == "0" and values.SpellQueueWindow == "400" and values.showTimestamps == "%H:%M ")
    env.printed, writes = {}, {}
    snapshot = cvars.Snapshot()
    check("snapshot omits unknown values and reports the omission", count(snapshot) == 12
        and snapshot.cameraSmoothStyle == nil and #writes == 0 and #env.printed == 1
        and contains("Skipped cameraSmoothStyle"))

    reset()
    behavior.cameraDistanceMaxZoomFactor = "read-error"
    behavior.cameraSmoothStyle = "write-error"
    behavior.nameplateShowEnemies = "false"
    behavior.nameplateShowFriends = "readonly"
    local applyOk
    applyOk, prior = pcall(cvars.Apply)
    check("read and write failures do not abort the remaining CVars", applyOk and values.screenshotQuality == "10")
    check("failed reads are omitted from returned prior values", prior.cameraDistanceMaxZoomFactor == nil)
    check("rejected writes retain original values for undo", prior.cameraSmoothStyle == "old:cameraSmoothStyle"
        and prior.nameplateShowEnemies == "old:nameplateShowEnemies"
        and prior.nameplateShowFriends == "old:nameplateShowFriends")
    check("false nil and thrown writes are never reported applied", #env.printed == 13
        and contains("Skipped cameraDistanceMaxZoomFactor") and contains("Skipped cameraSmoothStyle")
        and contains("Skipped nameplateShowEnemies") and contains("Skipped nameplateShowFriends")
        and not contains("Applied cameraSmoothStyle") and not contains("Applied nameplateShowEnemies")
        and not contains("Applied nameplateShowFriends"))

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
        and #env.printed == 13 and contains("Skipped autoLootDefault"))
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
    check("slash command applies the complete catalogue", #writes == 13 and #env.printed == 13
        and values.autoLootDefault == "1" and values.screenshotQuality == "10")
    C_CVar = originalAPI
end
