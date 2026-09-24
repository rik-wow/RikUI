-- The wizard's six pages against the real preset, bindings scheme, settings catalogue and layouts.
-- setup.Apply is faked; what the pages write into the state is what is checked. How the pages look
-- is exercised with widget geometry; native acceptance is supplied by the user.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local restore = widgets.install()
    local savedClass, savedLevel = UnitClass, UnitLevel
    local FILES = { "data/spells.lua", "data/spells-hunter.lua", "data/spells-mage.lua", "data/spells-rogue.lua", "data/spells-priest.lua", "data/spells-warlock.lua", "data/spells-shaman.lua", "data/spells-paladin.lua", "data/spells-druid.lua", "data/cvars.lua", "presets/warrior.lua", "presets/hunter.lua", "presets/mage.lua", "presets/rogue.lua", "presets/priest.lua", "presets/warlock.lua", "presets/shaman.lua", "presets/paladin.lua", "presets/druid.lua", "src/character/bindings.lua", "src/setup/setup-talents.lua",
        "data/layouts.lua", "src/layout/layout-audit.lua", "src/ui/skin.lua", "src/layout/layout-unlock.lua", "src/layout/layout-drag.lua", "src/layout/layout-presets.lua",
        "src/configuration/wizard/wizard-controls.lua", "src/configuration/wizard/wizard.lua", "src/configuration/wizard/wizard-preview.lua", "src/configuration/wizard/wizard-pages.lua" }
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
        check("the role page offers the preset's roles in order and preselects one", #role.cards == 3
            and role.cards[1].label.text == "Arms" and role.cards[2].label.text == "Fury" and role.cards[3].label.text == "Protection"
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
        env.click(role.cards[3])
        check("choosing Protection changes the state and the preview", wizard.State.role == "tank" and role.cards[3].isChosen == true
            and role.cards[1].isChosen == false and role.bar.slots[1].icon.texture == RikUI.SpellData["Sunder Armor"].icon)

        dofile("src/persistence/codec.lua"); dofile("src/setup/preset-schema.lua"); dofile("src/setup/preset-library.lua")
        local shared = RikUI.Setup.CopyState(RikUI.Presets.WARRIOR)
        shared.roles, shared.roleOrder = { tank = shared.roles.tank }, { "tank" }
        shared.roleOverrides = { tank = shared.roleOverrides.tank }
        RikUI.PresetLibrary.Add("Shared tank", shared)
        local marker = RikUI.CharDB.applied
        local selected = wizard.SelectPreset("Shared tank")
        role = page("role")
        check("wizard shows imported source roles", selected and #role.cards == 1 and role.cards[1].role == "tank")
        check("draft source selection does not change applied state", RikUI.CharDB.applied == marker
            and wizard.Options().presetName == "Shared tank")
        env.click(role.presetButton)
        check("picker cycles back to bundled source", wizard.State.presetName == "" and #role.cards == 3)
        wizard.State.role = "tank"

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

        load("Evoker")
        local none = page("role")
        check("a class without a preset gets an explanation instead of roles", #none.cards == 0 and wizard.State.role == nil
            and none.note.text:find("no preset for Evoker yet", 1, true) ~= nil and not none.bar:IsShown())
        local priest = page("summary").body.text
        check("and its summary says bars and macros have nothing to do", priest:find("Bars: no preset", 1, true) ~= nil, priest)
        check("no page printed anything", #env.printed == 0, env.printed[1])
        for _, class in ipairs({ "Hunter", "Mage", "Rogue", "Priest", "Warlock", "Shaman", "Paladin", "Druid" }) do
            load(class, 60)
            local classRole = page("role")
            local expected = RikUI.WizardPreview.Pages(RikUI.Setup.Resolve(class:upper(), wizard.State.role))
            for index, choice in ipairs(expected) do
                check(class .. " preview visits " .. choice.key, classRole.barTitle.text:find(choice.label, 1, true) ~= nil)
                if index < #expected then env.click(classRole.following) end
            end
            check(class .. " preview stops at last page", classRole.following.disabled == true)
            for index = #expected, 2, -1 do env.click(classRole.previous) end
            check(class .. " preview returns to main", classRole.previous.disabled == true
                and classRole.barTitle.text:find("Main bar", 1, true) ~= nil)
        end
        load("Druid", 60)
        local druid = page("role")
        check("four Druid roles wrap to a second row", #druid.cards == 4 and druid.cards[4].point[4] == 0
            and druid.cards[4].point[5] < druid.cards[1].point[5] and druid.barTitle.point[5] < druid.cards[4].point[5] - 56)
        env.click(druid.following)
        check("Druid preview exposes Cat actions and base keys", druid.barTitle.text:find("Cat form", 1, true)
            and druid.bar.slots[1].key.text == "1")
        env.runScript(druid.bar.slots[1], "OnEnter")
        check("hover gives action name and learning status", druid.detail.text:find(druid.bar.slots[1].entry.spell, 1, true)
            and druid.detail.text:find("Spellbook unavailable", 1, true))
        load("Mage", 60)
        local mage = page("role")
        local mageKeys = page("keys")
        check("mouse help names Mage actions", mageKeys.mouseCheck.label.text:find("Blink", 1, true)
            and mageKeys.mouseCheck.label.text:find("Counterspell", 1, true)
            and not mageKeys.mouseCheck.label.text:find("Charge", 1, true))
        env.click(mageKeys.mouseCheck)
        mage = page("role")
        env.click(mage.following)
        check("preview uses proposed keyboard fallback", mage.bar.slots[10].key.text == "SHIFT-G"
            and mage.bar.slots[11].key.text == "CTRL-G")
        env.click(mage.following)
        check("displaced Ctrl-G utility is visibly unbound", mage.bar.slots[8].key.text == "")
        local preview, savedKnown = RikUI.WizardPreview, RikUI.Spells.HighestKnownRank
        local current = RikUI.Setup.Resolve("MAGE", "frost")
        RikUI.Spells.HighestKnownRank = function() return nil end
        local _, description, ready = preview.Details({ spell = "Ice Block" }, current, 60)
        check("unlearned talent at max level stays dim with unknown acquisition", not ready
            and description:find("acquisition level unknown", 1, true))
        RikUI.Spells.HighestKnownRank = function(name, class) if name == "Ice Block" and class == "MAGE" then return 11958 end end
        _, description, ready = preview.Details({ spell = "Ice Block" }, current, 60)
        check("learned status checks the selected class catalogue", ready and description:find("Learned", 1, true))
        RikUI.Spells.HighestKnownRank = savedKnown
        UnitClass = nil
        check("unavailable class never falls back to Warrior spells", next(RikUI.Spells.Catalog()) == nil)

    end)
    UnitClass, UnitLevel = savedClass, savedLevel
    restore()
    env.inCombat = false
    check("wizard pages suite completes", ok, reason)
end
