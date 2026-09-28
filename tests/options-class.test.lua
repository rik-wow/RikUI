local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The Class area of the settings: its own sidebar group, a class chooser that shows any class,
-- and editable lists for the strip and the effect rows.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local restore = widgets.install()
    local savedClass = UnitClass
    local function loadFor(localized, token)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        require("chat_stub").install(env)
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        UnitClass = function() return localized, token, 1 end
        for line in io.lines("RikUI.toc") do
            line = line:gsub("\r", "")
            if line:match("%.lua$") then assert(loadfile(line))("RikUI", {}) end
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return RikUI.Options.Pages()
    end
    local function area(pages)
        local found, titles = {}, {}
        for _, page in ipairs(pages) do
            if page.group == "Class" then found[page.id] = page; titles[#titles + 1] = page.title end
        end
        return found, table.concat(titles, ", ")
    end
    local function keyed(page)
        local found = {}
        for _, spec in ipairs(page.specs) do if spec.key then found[spec.key] = spec end end
        return found
    end
    local function titled(pages, title)
        for _, page in ipairs(pages) do if page.title == title then return page end end
    end
    local function joined(list) return table.concat(list, ",") end

    local ok, reason = pcall(function()
        local pages = loadFor("Paladin", "PALADIN")
        local options, settings = RikUI.Options, RikUI.ClassSettings
        local class, titles = area(pages)
        check("the Class area follows General with an overview, the cooldown strip and the class effects",
            pages[1].id == "general" and pages[2].group == "Class" and titles == "Overview, Cooldown strip, Class effects")
        check("the area opens on the class being played and names it in the sidebar",
            select(1, options.SelectedClass()) == "PALADIN" and select(3, options.SelectedClass()) == true
            and options.GroupLabel("Class") == "Class: Paladin" and options.GroupLabel("Interface") == nil
            and class["class-cooldowns"].description():find("Paladin (your class)", 1, true))
        local overview, cooldowns, effects = keyed(class["class"]), keyed(class["class-cooldowns"]), keyed(class["class-effects"])
        check("every class page starts with the class chooser listing all shipped classes",
            overview["class.selected"] and cooldowns["class.selected"] and effects["class.selected"]
            and #overview["class.selected"].values() == #settings.Classes()
            and overview["class.selected"].get() == "PALADIN")
        check("module switches on the overview say they are shared and follow the class shown",
            overview["class.cooldowns"] and overview["class.cooldowns"].getDescription():find("Shared by every class", 1, true)
            and overview["class.druidmana"] and overview["class.druidmana"].visible() == false
            and overview["show"] and overview["show"].visible() == false)
        check("the cooldown page lists the class list from the settings layer with add and reset",
            cooldowns["class.cooldowns"].type == "spelllist" and joined(cooldowns["class.cooldowns"].get()) == joined(settings.List("PALADIN", "cooldowns"))
            and cooldowns["class.cooldowns.add"].values()[1].text == "Choose a spell"
            and cooldowns["class.cooldowns.reset"].disabled() == true
            and cooldowns["class.cooldowns.heading"].getDescription():find("RikUI's list", 1, true)
            and cooldowns["class.cells"].getDescription():find("Seal", 1, true)
            and cooldowns["class.trackedSpells"].disabled() == true)
        check("the add dropdown is disabled while the list is full", cooldowns["class.cooldowns.add"].disabled() == true
            and cooldowns["class.cooldowns"].remove("Holy Strike") == true and cooldowns["class.cooldowns.add"].disabled() == false)
        check("adding through the dropdown edits the list and enables reset", cooldowns["class.cooldowns.add"].set("Consecration") == true
            and joined(cooldowns["class.cooldowns"].get()):find("Consecration", 1, true)
            and cooldowns["class.cooldowns.reset"].disabled() == false
            and cooldowns["class.cooldowns.heading"].getDescription():find("Changed in this profile", 1, true)
            and cooldowns["class.cooldowns.reset"].action() == true and cooldowns["class.cooldowns.reset"].disabled() == true)
        check("the list's own move and remove reach the settings layer", cooldowns["class.cooldowns"].move("Judgement", 1) == true
            and settings.List("PALADIN", "cooldowns")[2] == "Judgement"
            and cooldowns["class.cooldowns"].remove("Judgement") == true and not joined(settings.List("PALADIN", "cooldowns")):find("Judgement", 1, true))
        settings.Reset("PALADIN", "cooldowns")
        check("the effects page carries the three groups and flags a reload once one changes",
            effects["class.player"] and effects["class.harmful"] and effects["class.helpful"]
            and effects["class.effects.reload"].pending() == false
            and effects["class.harmful.add"].set("Consecration") == true and effects["class.effects.reload"].pending() == true)
        settings.Reset("PALADIN", "harmful")
        check("choosing another class switches every page and its label without changing the character's class",
            overview["class.selected"].set("DRUID") == true and select(1, options.SelectedClass()) == "DRUID"
            and select(3, options.SelectedClass()) == false and options.GroupLabel("Class") == "Class: Druid"
            and class["class"].description():find("Druid:", 1, true) and not class["class"].description():find("your class", 1, true)
            and overview["class.druidmana"].visible() == true and overview["show"].visible() == true
            and overview["class.combopoints"].visible() == true and overview["class.totems"].visible() == false
            and joined(cooldowns["class.cooldowns"].get()) == joined(settings.List("DRUID", "cooldowns")))
        check("a change made while showing another class lands in that class's list",
            cooldowns["class.cooldowns"].move(settings.List("DRUID", "cooldowns")[1], 1) == true
            and settings.IsCustom("DRUID", "cooldowns") and not settings.IsCustom("PALADIN", "cooldowns"))
        check("Druid mana is no longer a page of its own", titled(pages, "Druid mana") == nil)

        pages = loadFor("Shaman", "SHAMAN")
        local shaman = keyed(area(pages)["class"])
        check("a shaman's overview shows totems and no druid options", shaman["class.totems"].visible() == true
            and shaman["class.druidmana"].visible() == false and RikUI.Options.GroupLabel("Class") == "Class: Shaman")
    end)
    restore()
    UnitClass = savedClass
    env.inCombat = false
    -- Whole-addon loads skin the shared tooltip stubs; give later suites fresh ones.
    require("tooltip_stub").install(env)
    check("Class settings area suite completes", ok, reason)
end
