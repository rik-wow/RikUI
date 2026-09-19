-- Warrior preset contracts; run through tests/run_tests.lua.
return function(check)
    local env = require("wow_stub")
    env.frames, env.printed, env.inCombat = {}, {}, false
    assert(loadfile("core.lua"))("RikUI", {})
    assert(loadfile("data/spells.lua"))("RikUI", {})

    -- The class file must load with only its data namespace, without any WoW APIs.
    local isolated = { Presets = {} }
    local chunk = assert(loadfile("presets/warrior.lua"))
    setfenv(chunk, setmetatable({ RikUI = isolated }, {
        __index = function(_, key) error("preset accessed global " .. key) end,
    }))
    chunk()
    local preset = isolated.Presets.WARRIOR
    check("Warrior preset loads without runtime services", type(preset) == "table")
    if not preset then return end
    RikUI.Presets.WARRIOR = preset

    local function isData(value)
        if type(value) ~= "table" then
            return type(value) == "string" or type(value) == "number" or type(value) == "boolean"
        end
        if getmetatable(value) then return false end
        for key, entry in pairs(value) do
            if not isData(key) or not isData(entry) then return false end
        end
        return true
    end
    check("Warrior preset contains only serializable values", isData(preset))
    check("DPS and Protection roles identify the correct talent trees",
        preset.roles.dps.label == "Arms / Fury" and table.concat(preset.roles.dps.trees, ",") == "1,2"
        and preset.roles.tank.label == "Protection" and table.concat(preset.roles.tank.trees, ",") == "3")
    local main = preset.bars.main
    local expected = { "Heroic Strike", "Rend", "Thunder Clap", "Hamstring", "Execute",
        "Charge", "Overpower", "Pummel", "Bloodrage", "Shield Block", "Demoralizing Shout", "Hearthstone" }
    for index, name in ipairs(expected) do
        local slot = main[index]
        check("main key tier slot " .. index .. " is " .. name,
            slot and (slot.spell or slot.macro or slot.item) == name)
    end
    for _, name in ipairs({ "main", "battle", "defensive", "berserker", "bar2", "bar3", "bar4", "bar5" }) do
        check("page exists: " .. name, type(preset.bars[name]) == "table")
    end

    -- Independent first-acquisition fixture from the Forever spellbook, not runtime data.
    local levels = {
        ["Heroic Strike"] = 1, Rend = 4, ["Thunder Clap"] = 6, Hamstring = 8, Execute = 24,
        Charge = 4, Overpower = 12, Pummel = 38, Bloodrage = 10, ["Shield Block"] = 16,
        ["Demoralizing Shout"] = 14, ["Shield Bash"] = 12, Disarm = 18, Taunt = 10,
        Revenge = 14, Slam = 20, Whirlwind = 36, Intercept = 30, ["Victory Rush"] = 20,
        Retaliation = 20, ["Shield Wall"] = 28, Recklessness = 50, ["Berserker Rage"] = 32,
        ["Challenging Shout"] = 26, ["Mocking Blow"] = 16, ["Intimidating Shout"] = 22,
        Cleave = 20, ["Battle Shout"] = 1, ["Sunder Armor"] = 10, ["Battle Stance"] = 1,
        ["Defensive Stance"] = 10, ["Berserker Stance"] = 30, ["Mortal Strike"] = 40,
        Bloodthirst = 40, ["Shield Slam"] = 40,
    }
    local function checkPages(pages, prefix)
        for page, slots in pairs(pages) do
            for index, slot in pairs(slots) do
                local path = prefix .. "." .. page .. "[" .. index .. "]"
                local selectors = (slot.spell and 1 or 0) + (slot.macro and 1 or 0) + (slot.item and 1 or 0)
                check(path .. " has one action and a valid slot", selectors == 1
                    and type(index) == "number" and index % 1 == 0 and index >= 1 and index <= 12)
                if slot.spell then
                    check(path .. " resolves at its source level", RikUI.SpellData[slot.spell] ~= nil
                        and levels[slot.spell] == slot.level)
                elseif slot.macro then
                    check(path .. " resolves a local macro", preset.macros[slot.macro] ~= nil)
                end
            end
        end
    end
    checkPages(preset.bars, "bars")
    for role, pages in pairs(preset.roleOverrides) do checkPages(pages, "roleOverrides." .. role) end

    local allowedOverrides = {
        battle = { [8] = true, [10] = true },
        defensive = { [4] = true, [6] = true, [7] = true, [8] = true },
        berserker = { [2] = true, [3] = true, [6] = true, [7] = true, [10] = true },
    }
    -- This fixture is the documented consumer contract, not a runtime composer.
    local function compose(role, stance)
        local result, overrides = {}, preset.roleOverrides[role] or {}
        for _, page in ipairs({ main, overrides.main or {}, preset.bars[stance], overrides[stance] or {} }) do
            for index, slot in pairs(page) do result[index] = slot end
        end
        return result
    end
    local restrictions = {
        Charge = { battle = true }, Overpower = { battle = true }, Pummel = { berserker = true },
        ["Shield Block"] = { defensive = true }, Taunt = { defensive = true }, Revenge = { defensive = true },
        ["Shield Bash"] = { battle = true, defensive = true }, Disarm = { defensive = true },
        Rend = { battle = true, defensive = true }, ["Thunder Clap"] = { battle = true, defensive = true },
        Hamstring = { battle = true, berserker = true }, Intercept = { berserker = true },
        Whirlwind = { berserker = true },
    }
    for stance, allowed in pairs(allowedOverrides) do
        for index in pairs(preset.bars[stance]) do
            check(stance .. " overrides only stance-locked slot " .. index, allowed[index] == true)
        end
        for _, role in ipairs({ "dps", "tank" }) do
            local page = compose(role, stance)
            for index = 1, 12 do
                local slot = page[index]
                local forms = slot.spell and restrictions[slot.spell]
                check(role .. " " .. stance .. " slot " .. index .. " is populated and stance-compatible",
                    slot ~= nil and (not forms or forms[stance] == true))
            end
            check(role .. " " .. stance .. " inherits common resource, defensive and hearth slots",
                page[9] == main[9] and page[11] == main[11] and page[12] == main[12])
        end
    end
    local tank = compose("tank", "defensive")
    check("Protection places threat, taunt, revenge and interrupt on their tiers",
        tank[1].spell == "Sunder Armor" and tank[6].spell == "Taunt"
        and tank[7].spell == "Revenge" and tank[8].spell == "Shield Bash")
    check("role composition leaves base rotation intact", main[1].spell == "Heroic Strike" and main[6].spell == "Charge")
    check("side bars leave character-specific item choices empty", next(preset.bars.bar4) == nil and next(preset.bars.bar5) == nil)
    check("Execute can leave Defensive before learning Berserker at 30",
        preset.macros.Execute.body == "#showtooltip Execute\n/cast [stance:1/3] Execute; [stance:2] Battle Stance")
    for name, macro in pairs(preset.macros) do
        check("macro fits native limits: " .. name, #name > 0 and #name <= 16 and #macro.body < 255)
        check("macro has a texture fileID: " .. name, type(macro.icon) == "number" and macro.icon > 0
            and macro.icon == (RikUI.SpellData[name] or RikUI.SpellData.Pummel).icon)
        -- The bundled macros use simple cast alternatives. Check every spell operand.
        local operands, listed = {}, {}
        for line in macro.body:gmatch("[^\n]+") do
            if line:match("^/cast ") then
                for alternative in line:sub(7):gmatch("[^;]+") do
                    local spell = alternative:gsub("%b[]", ""):match("^%s*(.-)%s*$")
                    check(name .. " casts catalogue spell " .. spell, RikUI.SpellData[spell] ~= nil)
                    operands[spell] = true
                end
            end
        end
        -- Bar placement waits for one of these attacks; stances never gate a macro.
        check("macro lists the attacks that gate its slot: " .. name, type(macro.spells) == "table" and #macro.spells > 0)
        for _, spell in ipairs(type(macro.spells) == "table" and macro.spells or {}) do
            listed[spell] = true
            check(name .. " gating spell is a cast operand: " .. spell, operands[spell] and not spell:find("Stance", 1, true))
        end
        for spell in pairs(operands) do
            check(name .. " non-stance operand gates the slot: " .. spell, listed[spell] or spell:find("Stance", 1, true))
        end
    end

    assert(loadfile("setup.lua"))("RikUI", {})
    check("setup exposes a read-only preset validator", RikUI.Setup and type(RikUI.Setup.ValidatePreset) == "function")
    if not RikUI.Setup then return end
    local validate = RikUI.Setup.ValidatePreset
    check("bundled Warrior validates against catalogue", #validate(preset) == 0)
    local fixture = {
        bars = { main = { [12] = { spell = "Missing Base", level = 1 } },
            berserker = { [11] = { spell = "Missing Stance", level = 1 } } },
        macros = {},
        roleOverrides = { tank = { defensive = { [10] = { spell = "Missing Role", level = 1 } } } },
    }
    local issues = table.concat(validate(fixture), "\n")
    check("validator finds sparse names across base stance and role pages",
        issues:find("Missing Base", 1, true) and issues:find("Missing Stance", 1, true)
        and issues:find("Missing Role", 1, true) and issues:find("roleOverrides.tank.defensive[10]", 1, true))
    fixture.bars.main[12] = { spell = "Charge", level = 30 }
    check("wrong ghost level is diagnosed", table.concat(validate(fixture), "\n"):find("level", 1, true))
    fixture.bars.main[12] = { macro = "Missing Macro" }
    check("missing macro references are diagnosed", table.concat(validate(fixture), "\n"):find("Missing Macro", 1, true))
    fixture.bars.main[12] = { spell = "Charge", macro = "Execute", level = 4 }
    check("ambiguous slot actions are rejected", table.concat(validate(fixture), "\n"):find("one action", 1, true))
    fixture.bars.main[12] = { macro = "Gated" }
    fixture.macros.Gated = { icon = 1, body = "/cast Nope", spells = { "Nope" } }
    check("unknown macro gating spell is diagnosed", table.concat(validate(fixture), "\n"):find("Nope", 1, true))
    fixture.macros.Gated.spells = "Execute"
    check("macro spells must be a list", table.concat(validate(fixture), "\n"):find("spells must be a list", 1, true))
    fixture.macros.Gated.spells = { "Execute" }
    check("catalogue gating spells validate", not table.concat(validate(fixture), "\n"):find("macros.Gated", 1, true))
    fixture.macros.Gated = nil
    fixture.bars.main[12] = "invalid"
    check("malformed slot returns a diagnostic", #validate(fixture) > 0)
    check("invalid preset returns a diagnostic", #validate(nil) > 0)

    local function contains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    env.printed = {}
    SlashCmdList.RIKUI("preset validate")
    check("chat validates the loaded preset", contains("WARRIOR") and contains("valid") and not contains("Unknown command"))
    RikUI.Presets.BROKEN = fixture
    env.printed = {}
    SlashCmdList.RIKUI("preset validate")
    check("chat prints unresolved names and their preset", contains("BROKEN") and contains("Missing Stance") and contains("Missing Role"))
    RikUI.Presets.BROKEN = nil
    env.printed = {}
    SlashCmdList.RIKUI("preset")
    check("missing preset subcommand prints usage", contains("/rik preset validate"))
    env.printed = {}
    SlashCmdList.RIKUI("preset apply")
    check("unsupported subcommand does not apply anything", contains("/rik preset validate"))
    RikUI.Presets = {}
    env.printed = {}
    SlashCmdList.RIKUI("preset validate")
    check("empty registry is reported", contains("No presets"))
end
