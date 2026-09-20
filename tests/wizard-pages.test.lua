-- The wizard's six pages against the real preset, bindings scheme, settings catalogue and layouts.
-- setup.Apply is faked; what the pages write into the state is what is checked. How the pages look
-- needs a beta check.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local restore = widgets.install()
    local savedClass, savedLevel = UnitClass, UnitLevel
    local FILES = { "data/spells.lua", "data/cvars.lua", "presets/warrior.lua", "bindings.lua", "setup-talents.lua",
        "data/layouts.lua", "layout-audit.lua", "skin.lua", "layout-unlock.lua", "layout-drag.lua", "layout-presets.lua",
        "wizard-controls.lua", "wizard.lua", "wizard-preview.lua", "wizard-pages.lua" }
    local wizard, applied
    local function load(class, level)
        UnitClass = function() return class or "Warrior", (class or "Warrior"):upper(), 1 end
        UnitLevel = function() return level or 12 end
        applied = {}
        widgets.loadAddon(env, FILES)
        wizard = RikUI.Wizard
        RikUI.Setup.Apply = function(_, role, opts) applied[#applied + 1] = { role = role, opts = opts }; return { status = "running", steps = {} } end
        wizard.Open()
        env.printed = {}
    end
    local function page(key)
        for index, entry in ipairs(wizard.Pages) do
            if entry.key == key then wizard.Go(index); return entry.frame end
        end
    end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end
    local function count(values)
        local total = 0
        for _ in pairs(values) do total = total + 1 end
        return total
    end

    local ok, reason = pcall(function()
        load()
        local keys = {}
        for index, entry in ipairs(wizard.Pages) do keys[index] = entry.key end
        check("six pages in the order of the decisions", table.concat(keys, " ") == "welcome role keys layout modules summary")
        local welcome = wizard.Pages[1].frame
        check("the welcome page names the class and says nothing is applied yet", welcome.lead.text:find("Warrior", 1, true) ~= nil
            and welcome.body.text:find("Nothing is applied until the last page", 1, true) ~= nil)

        local role = page("role")
        check("the role page offers the preset's roles in order and preselects one", #role.cards == 2
            and role.cards[1].label.text == "Arms / Fury" and role.cards[2].label.text == "Protection"
            and wizard.State.role == "dps" and role.cards[1].isChosen == true and role.cards[2].isChosen == false)
        local heroic = RikUI.SpellData["Heroic Strike"].icon
        check("it previews the main bar that role gets, with its keys", role.bar.slots[1].icon.texture == heroic
            and role.bar.slots[1].key.text == "1" and role.bar.slots[6].key.text == "Q" and role.bar.slots[12].key.text == "")
        local dimmed, bright = 0, 0
        for _, slot in ipairs(role.bar.slots) do
            if slot.icon.alpha == 1 and slot.icon.texture then bright = bright + 1 elseif slot.icon.texture then dimmed = dimmed + 1 end
        end
        check("spells above the character's level are drawn dim", bright > 0 and dimmed > 0)
        -- A macro slot has no level of its own; it waits for the spells it casts (Execute is level 24).
        local execute
        for _, slot in ipairs(role.bar.slots) do
            if slot.entry and slot.entry.macro == "Execute" then execute = slot end
        end
        check("a macro is dim until the character can learn a spell it casts", execute ~= nil
            and execute.icon.texture ~= nil and execute.icon.alpha ~= 1)
        env.click(role.cards[2])
        check("choosing Protection changes the state and the preview", wizard.State.role == "tank" and role.cards[2].isChosen == true
            and role.cards[1].isChosen == false and role.bar.slots[1].icon.texture == RikUI.SpellData["Sunder Armor"].icon)

        local keysPage = page("keys")
        check("the key page draws the three tiers and the mouse and strafe keys", #keysPage.tiers == 3
            and #keysPage.tiers[1] == 11 and keysPage.tiers[1][1].label.text == "1" and keysPage.tiers[2][1].label.text == "S-1"
            and keysPage.mouse[1].label.text == "M4" and keysPage.strafe[1].label.text == "A")
        check("Mouse 4/5 start on and strafe starts off, on the caps too", keysPage.mouse[1].active == true
            and keysPage.strafe[1].active == false)
        env.click(keysPage.mouseCheck)
        env.click(keysPage.strafeCheck)
        check("the two check boxes write the state and repaint the caps", wizard.State.mouse45 == false
            and wizard.State.strafe == true and keysPage.mouse[1].active == false and keysPage.strafe[1].active == true)

        local layoutPage = page("layout")
        check("the layout page has one card per layout with the current one chosen", #layoutPage.cards == 4
            and layoutPage.cards[1].isChosen == true and layoutPage.cards[2].title.text == "Classic"
            and layoutPage.description.text == RikUI.Layouts.centered.description)
        local picture = layoutPage.cards[2].picture
        local scale = picture.width / 1365
        check("a card's picture is the layout's own rectangles, scaled", count(picture.blocks) >= 28
            and picture.blocks.tooltip == nil and near(picture.blocks.player.point[4], 16 * scale)
            and near(picture.blocks.player.width, 220 * scale) and near(picture.height, 768 * scale))
        env.click(layoutPage.cards[2])
        check("choosing a card sets the layout and its description", wizard.State.layoutPreset == "classic"
            and layoutPage.cards[2].isChosen == true and layoutPage.cards[1].isChosen == false
            and layoutPage.description.text == RikUI.Layouts.classic.description)
        env.click(layoutPage.keep)
        check("keeping your positions is a separate choice", wizard.State.keepPositions == true)
        env.click(layoutPage.keep)

        local modulesPage = page("modules")
        check("every module but the wizard and every catalogue setting gets a check box",
            #modulesPage.modules == count(RikUI.Modules) - 1 and #modulesPage.settings == #RikUI.CVars.List
            and modulesPage.settings[1].label.text == RikUI.CVars.List[1].label)
        -- The stub profile has the unit frame module off, so the first module starts unticked.
        local firstModule = modulesPage.modules[1]
        local before = wizard.State.modules[firstModule.name]
        env.click(firstModule)
        check("a module's check box starts from the profile and writes the state", before == (RikUI.Profile.modules[firstModule.name] ~= false)
            and wizard.State.modules[firstModule.name] == not before)
        env.click(modulesPage.settings[1])
        check("and a setting", wizard.State.cvars[RikUI.CVars.List[1].name] == false)

        local summary = page("summary")
        local text = summary.body.text
        check("the summary names the role, the keys, the layout, the settings and the switched module",
            text:find("Protection", 1, true) and text:find("without Mouse 4/5", 1, true) and text:find("A/D strafe", 1, true)
            and text:find("Layout: Classic", 1, true) and text:find((#RikUI.CVars.List - 1) .. " of " .. #RikUI.CVars.List, 1, true)
            and text:find(firstModule.name, 1, true), text)
        check("it counts what goes on the bars and names the macros", text:find("%d+ abilities") ~= nil
            and text:find("Interrupt", 1, true) ~= nil, text)
        check("the five steps can be switched off one by one", #summary.steps == 5 and summary.steps[1].label.text == "Macros")
        env.click(summary.steps[1])
        check("a step switched off leaves the summary and the options", wizard.State.steps.macros == false
            and summary.body.text:find("Macros: skipped", 1, true) ~= nil)
        env.click(wizard.Window.next)
        check("Apply carries all of it to setup", applied[1].role == "tank" and applied[1].opts.macros == false
            and applied[1].opts.layoutPreset == "classic" and applied[1].opts.strafe == true and applied[1].opts.mouse45 == false)

        load("Priest")
        local none = page("role")
        check("a class without a preset gets an explanation instead of roles", #none.cards == 0 and wizard.State.role == nil
            and none.note.text:find("no preset for Priest yet", 1, true) ~= nil and not none.bar:IsShown())
        local priest = page("summary").body.text
        check("and its summary says bars and macros have nothing to do", priest:find("Bars: no preset", 1, true) ~= nil, priest)
        check("no page printed anything", #env.printed == 0, env.printed[1])
    end)
    UnitClass, UnitLevel = savedClass, savedLevel
    restore()
    env.inCombat = false
    check("wizard pages suite completes", ok, reason)
end
