-- Runs RikProbe.lua under the stubbed WoW environment. Usage from the repo
-- root: luajit tests/run_tests.lua
package.path = "tests/?.lua;" .. package.path
local env = require("wow_stub")

local ADDON_FILE = "RikProbe/RikProbe.lua"
local failures, passes = {}, 0

local function check(name, ok, detail)
    if ok then
        passes = passes + 1
    else
        table.insert(failures, name .. (detail and (": " .. detail) or ""))
    end
end

local function printedContains(pattern)
    for _, line in ipairs(env.printed) do
        if line:find(pattern, 1, true) then return true end
    end
    return false
end

local function logContains(pattern)
    for _, line in ipairs(RikProbe and RikProbe.log or {}) do
        if line:find(pattern, 1, true) then return true end
    end
    return false
end

local function loadAddon()
    local chunk, err = loadfile(ADDON_FILE)
    if not chunk then return false, err end
    return pcall(chunk, "RikProbe", {})
end

-- 1. the file loads
local ok, err = loadAddon()
check("addon file loads", ok, err)

-- 2. ADDON_LOADED seeds both saved variables on a fresh install
env.fire("ADDON_LOADED", "RikProbe")
check("RikProbeDB seeded", type(RikProbeDB) == "table" and RikProbeDB.seededAt ~= nil)
check("RikProbeDB load counter starts at 1", RikProbeDB and RikProbeDB.loads == 1, tostring(RikProbeDB and RikProbeDB.loads))
check("RikProbeCharDB seeded", type(RikProbeCharDB) == "table" and RikProbeCharDB.seededAt ~= nil)

-- 3. PLAYER_LOGIN survives an unknown event and avoids the broken snippet VM.
local snippetCalls = 0
local originalExecute = SecureHandlerExecute
SecureHandlerExecute = function(...)
    snippetCalls = snippetCalls + 1
    return originalExecute(...)
end
local loginOk, loginErr = pcall(env.fire, "PLAYER_LOGIN")
check("PLAYER_LOGIN handler does not abort", loginOk, loginErr)
check("RikProbe namespace exposed", type(RikProbe) == "table")
check("missing snippet compiler never invokes executor", snippetCalls == 0)
check("missing snippet compiler never creates header", RikProbeSnippetHeader == nil)
check("missing snippet compiler is reported as skipped",
    RikProbe.results.snippets:find("skipped: snippet compiler unavailable", 1, true))

local driver
for _, d in ipairs(env.stateDrivers) do
    if d.state == "visibility" and d.condition == "[bonusbar:1] show; hide" then driver = d end
end
check("visibility driver registered for [bonusbar:1]", driver ~= nil)

local button = RikProbeAction73
check("action 73 button uses SecureActionButtonTemplate", button and button.template == "SecureActionButtonTemplate")
check("action 73 button type attribute", button and button:GetAttribute("type") == "action")
check("action 73 button action attribute", button and button:GetAttribute("action") == 73)

local events = RikProbe and RikProbe.results and RikProbe.results.events or {}
check("LEARNED_SPELL_IN_SKILL_LINE registered", events.LEARNED_SPELL_IN_SKILL_LINE == "ok", tostring(events.LEARNED_SPELL_IN_SKILL_LINE))
check("LEARNED_SPELL_IN_TAB failure recorded", type(events.LEARNED_SPELL_IN_TAB) == "string" and events.LEARNED_SPELL_IN_TAB ~= "ok", tostring(events.LEARNED_SPELL_IN_TAB))
check("SPELLS_CHANGED registered", events.SPELLS_CHANGED == "ok", tostring(events.SPELLS_CHANGED))

-- 4. /probe prints the report
local slashOk, slashErr = pcall(function() SlashCmdList.RIKPROBE("") end)
check("/probe runs without error", slashOk, slashErr)
check("/probe prints loadstring_untainted type", printedContains("loadstring_untainted") and printedContains("nil"))
check("/probe prints UnitHealth(player) secrecy", printedContains("UnitHealth(player)"))
check("/probe prints event registration results", printedContains("LEARNED_SPELL_IN_TAB"))
check("/probe prints bonus bar offset", printedContains("GetBonusBarOffset"))
check("/probe prints saved variable status", printedContains("RikProbeDB"))

-- 5. secret snapshots on entering and leaving combat
env.inCombat = true
env.fire("PLAYER_REGEN_DISABLED")
env.flushTimers()
local secrets = RikProbe and RikProbe.results and RikProbe.results.secrets
check("in-combat secret snapshot recorded", secrets and secrets["in combat"] ~= nil)
check("in-combat snapshot flags UnitHealth(player) secret", secrets and secrets["in combat"] and secrets["in combat"]["UnitHealth(player)"] == true)
check("in-combat snapshot flags UnitHealth(target) readable", secrets and secrets["in combat"] and secrets["in combat"]["UnitHealth(target)"] == false)
env.inCombat = false
env.fire("PLAYER_REGEN_ENABLED")
env.flushTimers()
check("out-of-combat secret snapshot recorded", secrets and secrets["out of combat"] ~= nil)

-- 6. stance events are logged with the bonus bar offset
env.bonusBarOffset = 2
env.fire("UPDATE_BONUS_ACTIONBAR")
check("UPDATE_BONUS_ACTIONBAR logged with offset", logContains("UPDATE_BONUS_ACTIONBAR: GetShapeshiftForm()=1 GetBonusBarOffset()=2"))

-- 7. ActionButton1 click compares resolved slot against the overlay mapping
env.click(ActionButton1)
check("ActionButton1 click logs resolved slot", logContains("resolved slot 1"))
check("ActionButton1 click logs expected overlay slot", logContains("expected 85"))

-- 8. visibility frames log Show/Hide with the combat flag
if driver then
    driver.frame:Hide()
    driver.frame:Show()
end
check("visibility frame logs hide", logContains("[bonusbar:1] show; hide -> hidden"))
check("visibility frame logs show", logContains("[bonusbar:1] show; hide -> shown"))

-- 9. the fixed action button logs its click
if button then env.click(button) end
check("action 73 click logged", logContains("action 73"))

-- 9b. /probe fill copies slot 1 into slot 73 and logs the result
local fillOk, fillErr = pcall(function() SlashCmdList.RIKPROBE("fill") end)
check("/probe fill runs without error", fillOk, fillErr)
check("/probe fill logs the filled slot", logContains("fill: slot 73 now holds spell 78"))
check("/probe prints character line", printedContains("character: WARRIOR level 12"))

-- 10. a relog sees the seeded saved variables
local relogOk, relogErr = loadAddon()
check("addon reloads for relog", relogOk, relogErr)
env.fire("ADDON_LOADED", "RikProbe")
check("load counter increments on relog", RikProbeDB and RikProbeDB.loads == 2, tostring(RikProbeDB and RikProbeDB.loads))
check("relog reports survival", printedContains("survived"))

-- Snippet API availability must not prevent the other probes from running.
local function probeSnippetAvailability(compiler, executor)
    env.frames = {}
    RikProbeSnippetHeader = nil
    loadstring_untainted, SecureHandlerExecute = compiler, executor
    local loaded, loadErr = loadAddon()
    check("probe reloads for snippet API scenario", loaded, loadErr)
    env.fire("PLAYER_LOGIN")
end

probeSnippetAvailability(true, function() error("must not execute") end)
check("non-function compiler skips header creation", RikProbeSnippetHeader == nil
    and RikProbe.results.snippets:find("skipped: snippet compiler unavailable", 1, true))

probeSnippetAvailability(function() end, nil)
check("missing snippet executor skips header creation", RikProbeSnippetHeader == nil
    and RikProbe.results.snippets:find("skipped: API unavailable", 1, true))

local workingCalls = 0
probeSnippetAvailability(function() end, function(header)
    workingCalls = workingCalls + 1
    header:SetAttribute("rikprobe", 1)
end)
check("available snippet machinery still runs the probe", workingCalls == 1
    and RikProbe.results.snippets:find("ran and set the attribute", 1, true))

loadstring_untainted, SecureHandlerExecute = nil, originalExecute

dofile("tests/sharing-codec.test.lua")(check)
dofile("tests/preset-schema.test.lua")(check)
dofile("tests/preset-library.test.lua")(check)
dofile("tests/importexport.test.lua")(check)
dofile("tests/profile-sharing.test.lua")(check)

-- The addon core shares the same runner and reports through check().
local coreOk, coreErr = pcall(function() dofile("tests/core.test.lua")(check) end)
check("core test suite completes", coreOk, coreErr)

local hideOk, hideErr = pcall(function() dofile("tests/hide.test.lua")(check) end)
check("Hide helper test suite completes", hideOk, hideErr)

local cvarsOk, cvarsErr = pcall(function() dofile("tests/cvars.test.lua")(check) end)
check("CVar test suite completes", cvarsOk, cvarsErr)

local spellsOk, spellsErr = pcall(function() dofile("tests/spells.test.lua")(check) end)
check("Spell test suite completes", spellsOk, spellsErr)

local macrosOk, macrosErr = pcall(function() dofile("tests/macros.test.lua")(check) end)
check("Macro test suite completes", macrosOk, macrosErr)

local bindingsOk, bindingsErr = pcall(function() dofile("tests/bindings.test.lua")(check) end)
check("Binding test suite completes", bindingsOk, bindingsErr)

local presetOk, presetErr = pcall(function() dofile("tests/preset-warrior.test.lua")(check) end)
check("Warrior preset test suite completes", presetOk, presetErr)

dofile("tests/presets-classes.test.lua")(check)

local setupOk, setupErr = pcall(function() dofile("tests/setup.test.lua")(check) end)
check("Setup test suite completes", setupOk, setupErr)

local levelupOk, levelupErr = pcall(function() dofile("tests/setup-levelup.test.lua")(check) end)
check("Level-up test suite completes", levelupOk, levelupErr)

local roleOk, roleErr = pcall(function() dofile("tests/setup-role.test.lua")(check) end)
check("Role test suite completes", roleOk, roleErr)

dofile("tests/hooks-policy.test.lua")(check)
dofile("tests/tutorials.test.lua")(check)

local barsOk, barsErr = pcall(function() dofile("tests/bars.test.lua")(check) end)
check("Bar test suite completes", barsOk, barsErr)

local ghostsOk, ghostsErr = pcall(function() dofile("tests/bars-ghosts.test.lua")(check) end)
check("Ghost slot test suite completes", ghostsOk, ghostsErr)

local stockOk, stockErr = pcall(function() dofile("tests/bars-stock.test.lua")(check) end)
check("Stock-bar test suite completes", stockOk, stockErr)

local pagingOk, pagingErr = pcall(function() dofile("tests/bars-paging.test.lua")(check) end)
check("Paging test suite completes", pagingOk, pagingErr)

local controlsOk, controlsErr = pcall(function() dofile("tests/bars-controls.test.lua")(check) end)
check("Control test suite completes", controlsOk, controlsErr)

local stateOk, stateErr = pcall(function() dofile("tests/bars-state.test.lua")(check) end)
check("Button state test suite completes", stateOk, stateErr)

local displayOk, displayErr = pcall(function() dofile("tests/bars-state-display.test.lua")(check) end)
check("Button display test suite completes", displayOk, displayErr)

local layoutOk, layoutErr = pcall(function() dofile("tests/layout.test.lua")(check) end)
check("Layout test suite completes", layoutOk, layoutErr)

local optionsOk, optionsErr = pcall(function() dofile("tests/options.test.lua")(check) end)
check("Options test suite completes", optionsOk, optionsErr)
local unitOk, unitErr = pcall(function() dofile("tests/unitframes.test.lua")(check) end)
check("Unit frame test suite completes", unitOk, unitErr)
local partyOk, partyErr = pcall(function() dofile("tests/unitframes-party.test.lua")(check) end)
check("Party frame test suite completes", partyOk, partyErr)
local raidOk, raidErr = pcall(function() dofile("tests/unitframes-raid.test.lua")(check) end)
check("Raid frame test suite completes", raidOk, raidErr)
local castOk, castErr = pcall(function() dofile("tests/castbars.test.lua")(check) end)
check("Castbar test suite completes", castOk, castErr)
local auraOk, auraErr = pcall(function() dofile("tests/auras.test.lua")(check) end)
check("Aura test suite completes", auraOk, auraErr)
local unitAuraOk, unitAuraErr = pcall(function() dofile("tests/auras-units.test.lua")(check) end)
check("Unit aura test suite completes", unitAuraOk, unitAuraErr)
local tooltipOk, tooltipErr = pcall(function() dofile("tests/tooltip.test.lua")(check) end)
check("Tooltip test suite completes", tooltipOk, tooltipErr)
local minimapOk, minimapErr = pcall(function() dofile("tests/minimap.test.lua")(check) end)
check("Minimap test suite completes", minimapOk, minimapErr)
local chatOk, chatErr = pcall(function() dofile("tests/chat.test.lua")(check) end)
check("Chat test suite completes", chatOk, chatErr)
local chatLinesOk, chatLinesErr = pcall(function() dofile("tests/chat-lines.test.lua")(check) end)
check("Chat lines test suite completes", chatLinesOk, chatLinesErr)
local chatNavOk, chatNavErr = pcall(function() dofile("tests/chat-nav.test.lua")(check) end)
check("Chat navigation test suite completes", chatNavOk, chatNavErr)
local chatControlsOk, chatControlsErr = pcall(function() dofile("tests/chat-controls.test.lua")(check) end)
check("Chat controls test suite completes", chatControlsOk, chatControlsErr)
local bagsOk, bagsErr = pcall(function() dofile("tests/bags.test.lua")(check) end)
check("Bag test suite completes", bagsOk, bagsErr)
local microOk, microErr = pcall(function() dofile("tests/micromenu.test.lua")(check) end)
check("Micro menu test suite completes", microOk, microErr)
local xpOk, xpErr = pcall(function() dofile("tests/xpbar.test.lua")(check) end)
check("XP bar test suite completes", xpOk, xpErr)
local questOk, questErr = pcall(function() dofile("tests/questtracker.test.lua")(check) end)
check("Quest tracker test suite completes", questOk, questErr)
local panelsOk, panelsErr = pcall(function() dofile("tests/panels.test.lua")(check) end)
check("Panels test suite completes", panelsOk, panelsErr)
local lootOk, lootErr = pcall(function() dofile("tests/loot.test.lua")(check) end)
check("Loot test suite completes", lootOk, lootErr)
local plateOk, plateErr = pcall(function() dofile("tests/nameplates.test.lua")(check) end)
check("Nameplate test suite completes", plateOk, plateErr)
local mirrorOk, mirrorErr = pcall(function() dofile("tests/mirrortimers.test.lua")(check) end)
check("Mirror timer test suite completes", mirrorOk, mirrorErr)
local swingOk, swingErr = pcall(function() dofile("tests/swingtimer.test.lua")(check) end)
check("Swing timer test suite completes", swingOk, swingErr)
local comboOk, comboErr = pcall(function() dofile("tests/combopoints.test.lua")(check) end)
check("Combo point test suite completes", comboOk, comboErr)
local durabilityOk, durabilityErr = pcall(function() dofile("tests/durability.test.lua")(check) end)
check("Durability test suite completes", durabilityOk, durabilityErr)
local popupsOk, popupsErr = pcall(function() dofile("tests/popups.test.lua")(check) end)
check("Popup test suite completes", popupsOk, popupsErr)
local screenOk, screenErr = pcall(function() dofile("tests/screentext.test.lua")(check) end)
check("Screen text test suite completes", screenOk, screenErr)
-- Later suites share one loop: a chunk of Lua holds at most 200 locals.
for _, suite in ipairs({ "combattimer", "cooldowns-profiles", "cooldowns", "cooldowns-native", "cooldowns-controls", "class-auras", "druid-mana", "combat-resource", "personalresource", "menus", "menus-rows", "windows-motion", "ui-polish", "chatbubbles", "totems", "alerts", "widgets", "combattext", "questtimers", "hudframes", "worldmap", "worldmap-tools",
    "interiors", "interiors-spells", "interiors-quests", "interiors-commerce", "interiors-services", "interiors-social", "interiors-misc", "controls", "dialogs", "lossofcontrol", "extrabuttons", "proc-overlay", "shell", "toasts", "banners", "damagemeter", "layout-geometry", "layout-rects", "layout-unlock", "editmode", "layouts", "layout-presets", "wizard", "wizard-pages", "layout-resize", "icons", "store", "store-macros", "runtime", "layout-refresh", "quest-plan-state", "quest-plan-search", "quest-plan-travel", "quest-plan-rewards", "quest-plan-xp", "quest-plan-event-chain", "quest-plan-live", "quest-plan-coverage", "quest-plan-acceptance", "quest-evidence", "questplanner", "quest-corpus", "quest-transfer-session", "quest-eligibility", "quest-travel", "quest-journey-graph", "quest-journey", "quest-optimizer", "quest-navmesh", "quest-nav-attach", "quest-path-codec", "quest-builds", "quest-roads", "quest-road-guidance", "quest-road-guidance-trip", "quest-road-travel", "quest-travel-estimate", "quest-regions", "quest-terrain-packs", "quest-den-corner", "quest-route-quality", "quest-steps", "quest-semantic", "quest-recommendations", "quest-enrichment", "quest-hunts", "quest-targets", "quest-terrain", "quest-context", "quest-objectives", "quest-gossip", "quest-live", "architecture", "commands" }) do
    local suiteOk, suiteErr = pcall(function() dofile("tests/" .. suite .. ".test.lua")(check) end)
    check(suite .. " test suite completes", suiteOk, suiteErr)
end

-- report
if #failures == 0 then
    io.write(string.format("OK: %d checks passed\n", passes))
    os.exit(0)
end
io.write(string.format("FAILED: %d of %d checks\n", #failures, passes + #failures))
for _, f in ipairs(failures) do io.write("  - " .. f .. "\n") end
os.exit(1)
