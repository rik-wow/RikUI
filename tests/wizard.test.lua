-- The wizard's shell: when it opens, how it moves between pages, what it hands to setup.Apply and how
-- it behaves around combat. setup.Apply is faked here; the pages have their own suite. How the window
-- looks and whether ReloadUI is allowed from its button need a beta check.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local restore = widgets.install()
    local savedReload, savedSpecial = ReloadUI, UISpecialFrames
    local FILES = { "data/cvars.lua", "data/layouts.lua", "layout-audit.lua", "skin.lua", "layout-unlock.lua", "layout-drag.lua",
        "layout-presets.lua", "wizard-controls.lua", "wizard.lua" }
    local wizard, applied, reloads
    local function load(character, combat, profile)
        applied, reloads = {}, 0
        UISpecialFrames = {}
        ReloadUI = function() reloads = reloads + 1 end
        widgets.loadAddon(env, FILES, profile, combat)
        if character then for key, value in pairs(character) do RikUICharDB[key] = value end end
        wizard = RikUI.Wizard
        RikUI.Setup.Apply = function(class, role, opts)
            applied[#applied + 1] = { class = class, role = role, opts = opts }
            return { status = "running", steps = {} }
        end
        for _, key in ipairs({ "one", "two", "three" }) do
            wizard.AddPage({ key = key, title = "Page " .. key,
                build = function(page) page.built = (page.built or 0) + 1 end,
                refresh = function(page, state) page.refreshed = (page.refreshed or 0) + 1; page.state = state end })
        end
        env.printed = {}
    end
    local function complete(status, reason)
        local call = applied[#applied]
        call.opts.onComplete({ status = status, error = reason, steps = { layout = { placed = 35, skipped = 0, edited = 0 } } })
    end

    local ok, reason = pcall(function()
        load()
        check("nothing is built before the wizard opens", wizard.Window == nil and not wizard.IsOpen())
        env.fire("PLAYER_ENTERING_WORLD")
        local window = wizard.Window
        check("a character that was never set up gets the wizard on entering the world", wizard.IsOpen() and window ~= nil
            and window:IsShown() and window.strata == "DIALOG" and window.fade.plays == 1)
        check("it opens on the first page and says where you are", wizard.Index == 1 and window.title.text == "Page one"
            and window.step.text == "Step 1 of 3" and #window.dots == 3)
        check("Escape closes it", UISpecialFrames[1] == "RikUIWizard")
        check("Back is disabled on the first page and Next reads Next", window.back.disabled == true
            and window.next.label.text == "Next" and window.skip:IsShown())
        local first = wizard.Pages[1].frame
        check("only the shown page is built", first.built == 1 and first.refreshed == 1 and wizard.Pages[2].frame == nil)
        env.fire("PLAYER_ENTERING_WORLD")
        check("a second world entry does not reopen or rebuild it", first.built == 1 and window.fade.plays == 1)

        wizard.State.role = "tank"
        env.click(window.next)
        local second = wizard.Pages[2].frame
        check("Next shows the second page with the same state and fades it in", wizard.Index == 2 and second.built == 1
            and second.state == wizard.State and second.state.role == "tank" and second:IsShown() and not first:IsShown()
            and second.fade.plays == 1 and window.back.disabled == false)
        env.click(window.back)
        check("Back returns without rebuilding and refreshes the page", wizard.Index == 1 and first.built == 1
            and first.refreshed == 2 and first:IsShown())
        env.click(window.back)
        check("Back stops at the first page", wizard.Index == 1)
        wizard.Go(3)
        check("the last page turns Next into Apply", wizard.Index == 3 and window.next.label.text == "Apply"
            and window.step.text == "Step 3 of 3")

        local state = wizard.State
        state.strafe, state.mouse45, state.layoutPreset = true, false, "hud"
        state.cvars.autoLootDefault, state.steps.macros = false, false
        env.click(window.next)
        local call = applied[1]
        check("Apply hands setup the class, the role and every choice", call ~= nil and call.class == "WARRIOR"
            and call.role == "tank" and call.opts.strafe == true and call.opts.mouse45 == false
            and call.opts.layoutPreset == "hud" and call.opts.macros == false and call.opts.bars == true
            and call.opts.cvarSelection.autoLootDefault == nil and call.opts.cvarSelection.SpellQueueWindow == true
            and call.opts.allowEmpty == true and type(call.opts.onComplete) == "function")
        env.click(window.next)
        check("a second click while setup runs does nothing", #applied == 1 and window.next.disabled == true)
        complete("applied")
        check("a finished setup marks the wizard done and offers Close", RikUICharDB.wizardDone == true
            and window.next.label.text == "Close" and window.next.disabled == false and window.back.disabled == true
            and not window.skip:IsShown() and window.status.text:find("/rik undo", 1, true) ~= nil)
        env.click(window.next)
        check("Close closes", not wizard.IsOpen() and not window:IsShown() and reloads == 0)

        load()
        wizard.Open()
        wizard.State.keepPositions = true
        wizard.Go(3)
        env.click(wizard.Window.next)
        check("keeping your positions switches the layout step off", applied[1].opts.layout == false
            and applied[1].opts.layoutPreset == nil)
        complete("failed", "macro limit reached")
        check("a failed setup says why and lets you go back", wizard.Window.status.text:find("macro limit reached", 1, true) ~= nil
            and wizard.Window.back.disabled == false and wizard.Window.next.label.text == "Apply"
            and RikUICharDB.wizardDone == false)

        load()
        wizard.Open()
        local modules = RikUI.Profile.modules
        modules.minimap = true
        wizard.State.modules.minimap = false
        wizard.Go(3)
        env.click(wizard.Window.next)
        check("module choices are written to the profile", modules.minimap == false)
        complete("applied")
        check("a changed module turns Close into Reload UI", wizard.Window.next.label.text == "Reload UI")
        env.click(wizard.Window.next)
        check("which reloads", reloads == 1)

        load()
        wizard.Open()
        env.click(wizard.Window.skip)
        check("Skip closes, marks the wizard done and says how to return", not wizard.IsOpen() and RikUICharDB.wizardDone == true
            and widgets.printedContains(env, "/rik setup") and #applied == 0)
        env.fire("PLAYER_ENTERING_WORLD")
        check("a skipped wizard does not come back by itself", not wizard.IsOpen())
        SlashCmdList.RIKUI("setup")
        check("/rik setup opens it again with a fresh state", wizard.IsOpen() and wizard.Index == 1
            and wizard.State.role == nil and RikUI:HasCommand("setup"))

        load({ applied = { class = "WARRIOR", role = "dps" } })
        env.fire("PLAYER_ENTERING_WORLD")
        check("a character that was set up does not get the wizard", not wizard.IsOpen() and wizard.Window == nil)

        load(nil, true)
        env.fire("PLAYER_ENTERING_WORLD")
        check("in combat the wizard waits", not wizard.IsOpen() and wizard.Window == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("and opens when combat ends", wizard.IsOpen())
        wizard.Go(2)
        env.inCombat = true
        env.fire("PLAYER_REGEN_DISABLED")
        check("combat hides it and says so", not wizard.Window:IsShown() and widgets.printedContains(env, "combat"))
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("it returns on the same page after combat", wizard.Window:IsShown() and wizard.Index == 2)

        load()
        wizard.Open()
        local fresh = wizard.State
        check("a fresh state has every module and setting on, Mouse 4/5 on, strafe off and the current layout",
            fresh.class == "WARRIOR" and fresh.mouse45 == true and fresh.strafe == false and fresh.keepPositions == false
            and fresh.layoutPreset == "centered" and fresh.cvars.autoLootDefault == true and fresh.steps.layout == true)
        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports the wizard", widgets.printedContains(env, "Wizard open=true page=1/3 done=false"))
    end)
    ReloadUI, UISpecialFrames = savedReload, savedSpecial
    restore()
    env.inCombat = false
    check("wizard suite completes", ok, reason)
end
