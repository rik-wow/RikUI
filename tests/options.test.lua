local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Options panel: data-driven controls, keyboard focus, pages from implemented modules, profiles.
return function(check)
    local env = require("wow_stub")
    local originalCreate, originalSettings, originalPicker = CreateFrame, Settings, ColorPickerFrame
    local function contains(text)
        for _, line in ipairs(env.printed) do if line:find(text, 1, true) then return true end end
        return false
    end
    local function instrument(frame)
        local methods = getmetatable(frame).__index
        setmetatable(frame, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        frame.alpha, frame.enabled = 1, true
        if frame.kind == "Texture" then frame.shown = true end
        function frame:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        function frame:SetTexture(path) self.texture = path end
        function frame:SetColorTexture(...) self.color = { ... } end
        function frame:SetVertexColor(...) self.tint = { ... } end
        function frame:SetAlpha(value) self.alpha = value end
        function frame:SetValue(value) self.value = value end
        function frame:SetMinMaxValues(low, high) self.low, self.high = low, high end
        function frame:SetValueStep(step) self.step = step end
        function frame:Enable() self.enabled = true end
        function frame:Disable() self.enabled = false end
        function frame:IsEnabled() return self.enabled end
        function frame:SetEnabled(value) self.enabled = value end
        function frame:SetSize(w,h)
            if self.width == w and self.height == h then return end
            self.width,self.height=w,h
            env.runScript(self, "OnSizeChanged", w, h)
        end
        function frame:SetWidth(w) self.width=w end
        function frame:SetHeight(h) self.height=h end
        function frame:GetWidth() return self.width end
        function frame:GetHeight() return self.height end
        function frame:SetClipsChildren(value) self.clips=value end
        function frame:SetScrollChild(child) self.scrollChild=child end
        function frame:SetVerticalScroll(value) self.scrollOffset=value end
        function frame:SetPropagateKeyboardInput(value) self.propagate = value end
        function frame:EnableKeyboard(value) self.keyboard = value end
        function frame:SetParent(parent) self.parent = parent end
        function frame:GetParent() return self.parent end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:SetFocus() self.focused = true end
        function frame:ClearFocus() self.focused = false end
        function frame:HasFocus() return self.focused == true end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return instrument(texture(self, ...)) end
        function frame:CreateFontString(...) return instrument(font(self, ...)) end
        return frame
    end
    CreateFrame = function(...) return instrument(originalCreate(...)) end
    local FILES = { "src/core/core.lua", "src/ui/media.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/setup/setup-snapshot.lua",
        "src/setup/setup-undo.lua", "src/setup/setup-levelup.lua", "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua", "src/ui/motion.lua", "src/ui/skin.lua", "src/ui/scroll.lua", "src/layout/layout-unlock.lua", "src/layout/layout-drag.lua", "src/configuration/options/options-widgets.lua",
        "src/configuration/options/options-controls.lua", "src/configuration/options/options.lua", "src/configuration/options/options-view.lua" }
    local function boot(db, character, prepare)
        env.frames, env.printed, env.inCombat, env.shiftDown = {}, {}, false, false
        env.settings = { registered = {}, opened = {} }
        RikUI, RikUIDB, RikUICharDB = nil, db, character
        for _, file in ipairs(FILES) do assert(loadfile(file))("RikUI", {}) end
        if prepare then prepare(RikUI) end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return RikUI.Options
    end
    local function rowByKey(list, key)
        for _, row in ipairs(list.rows) do if row.spec.key == key then return row end end
    end
    local function pageByTitle(options, title)
        for _, page in ipairs(options.Panel().pages) do if page.title == title then return page end end
    end
    local function press(panel, key) env.runScript(panel, "OnKeyDown", key) end

    local ok, reason = pcall(function()
        -- Renderer with synthetic specs.
        local options = boot()
        check("configuration confines page content to a scrolling viewport", options.Panel().pages[1].scroll ~= nil)
        local state = { flag = false, amount = 1, choice = "b", colour = { 0.1, 0.2, 0.3 }, name = "", pressed = 0, locked = true }
        local sets = {}
        local function setter(key) return function(value) state[key] = value; sets[key] = (sets[key] or 0) + 1 end end
        local specs = {
            { type = "heading", label = "Synthetic" },
            { type = "checkbox", key = "flag", label = "Flag", reload = true, get = function() return state.flag end, set = setter("flag") },
            { type = "slider", key = "amount", label = "Amount", min = 0, max = 2, step = 0.5, protected = true,
                get = function() return state.amount end, set = setter("amount") },
            { type = "dropdown", key = "choice", label = "Choice", values = function()
                return { { value = "a", text = "Alpha" }, { value = "b", text = "Beta" }, { value = "c", text = "Gamma" } }
            end, get = function() return state.choice end, set = setter("choice") },
            { type = "colour", key = "colour", label = "Colour", get = function() return state.colour end, set = setter("colour") },
            { type = "text", key = "name", label = "Name", get = function() return state.name end, set = setter("name") },
            { type = "button", key = "press", label = "Action", text = "Press", action = function() state.pressed = state.pressed + 1 end },
            { type = "checkbox", key = "locked", label = "Locked", disabled = function() return state.locked end,
                get = function() return true end, set = setter("locked") },
        }
        local parent = CreateFrame("Frame", nil, UIParent)
        local list = options.Render(parent, specs)
        check("renderer creates one row per spec in order", #list.rows == #specs and list.rows[2].spec.key == "flag")
        check("heading rows have no control and rows use the shared font", list.rows[1].widget == nil
            and list.rows[1].label.fontPath == RikUI.Media.font and list.rows[2].label.fontPath == RikUI.Media.font)
        check("reload text does not clutter every row", list.rows[2].label:GetText() == "Flag" and not list.rows[2].pending)
        check("rows stack with coherent spacing", list.rows[2].point[5] < list.rows[1].point[5]
            and list.rows[3].point[5] - list.rows[2].point[5] == list.rows[2].point[5] - list.rows[1].point[5])
        local flag, amount, choice, colour, name, pressRow = rowByKey(list, "flag"), rowByKey(list, "amount"),
            rowByKey(list, "choice"), rowByKey(list, "colour"), rowByKey(list, "name"), rowByKey(list, "press")
        check("checkbox reflects false before any click", flag.widget.mark.shown == false)
        env.click(flag.widget)
        check("checkbox click sets true and shows the mark", state.flag == true and flag.widget.mark.shown == true
            and flag.pending)
        env.click(flag.widget)
        check("checkbox toggles back", state.flag == false and flag.widget.mark.shown == false)
        check("slider carries bounds, step and shared media", amount.widget.low == 0 and amount.widget.high == 2
            and amount.widget.step == 0.5 and amount.widget.value == 1 and amount.widget.text.fontPath == RikUI.Media.font)
        env.runScript(amount.widget, "OnValueChanged", 1.5)
        check("slider value change commits once", state.amount == 1.5 and sets.amount == 1 and amount.widget.value == 1.5)
        check("dropdown shows the current text", choice.widget.text:GetText() == "Beta")
        env.click(choice.widget)
        check("dropdown opens a list of readable entries", choice.widget.list.shown and #choice.widget.list.buttons == 3
            and choice.widget.list.buttons[3].text:GetText() == "Gamma")
        env.click(choice.widget.list.buttons[3])
        check("dropdown selection commits and closes", state.choice == "c" and not choice.widget.list.shown
            and choice.widget.text:GetText() == "Gamma")
        check("colour swatch shows the current value", colour.widget.swatch.color[1] == 0.1 and colour.widget.swatch.color[3] == 0.3)
        env.click(colour.widget)
        local info = ColorPickerFrame.info
        check("colour click opens the picker with the current colour", info and info.r == 0.1 and info.b == 0.3 and info.hasOpacity == false)
        ColorPickerFrame.rgb = { 0.5, 0.6, 0.7 }
        info.swatchFunc()
        check("picker swatch commits the picked colour", state.colour[1] == 0.5 and state.colour[3] == 0.7
            and colour.widget.swatch.color[2] == 0.6)
        info.cancelFunc({ r = 0.1, g = 0.2, b = 0.3 })
        check("picker cancel restores the previous colour", state.colour[1] == 0.1 and state.colour[3] == 0.3)
        name.widget:SetText("Alt")
        env.runScript(name.widget, "OnTextChanged", true)
        check("text input commits typed text", state.name == "Alt")
        env.click(pressRow.widget)
        check("button click runs its action", state.pressed == 1 and pressRow.widget.text:GetText() == "Press")
        local locked = rowByKey(list, "locked")
        check("disabled rows are dimmed and inert", locked.alpha < 1 and locked.widget.enabled == false)
        env.click(locked.widget)
        check("disabled control ignores clicks", sets.locked == nil)
        state.locked = false
        options.RefreshList(list)
        check("refresh re-enables rows when predicates change", locked.alpha == 1 and locked.widget.enabled == true)

        env.inCombat = true
        env.runScript(amount.widget, "OnValueChanged", 0.5)
        check("protected setting is queued in combat", state.amount == 1.5 and contains("queued until combat ends"))
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("queued protected setting applies after combat", state.amount == 0.5 and amount.widget.value == 0.5)

        -- Keyboard focus over the same list.
        local panel = CreateFrame("Frame", nil, UIParent)
        options.EnableKeyboard(panel, function() return list.rows end)
        check("panel captures keys and propagates by default", panel.keyboard == true and panel.propagate == true)
        press(panel, "TAB")
        check("tab focuses the first control, skipping headings", panel.focused == flag and flag.focus.shown and panel.propagate == false)
        press(panel, "DOWN")
        press(panel, "DOWN")
        check("arrows move focus down", panel.focused == choice and not flag.focus.shown)
        press(panel, "RIGHT")
        check("right cycles a dropdown forward without opening it", state.choice == "c" and not choice.widget.list.shown)
        press(panel, "LEFT")
        check("left cycles a dropdown backward", state.choice == "b")
        press(panel, "UP")
        press(panel, "RIGHT")
        press(panel, "RIGHT")
        press(panel, "RIGHT")
        press(panel, "RIGHT")
        check("right adjusts a slider by step and clamps at max", panel.focused == amount and state.amount == 2)
        press(panel, "LEFT")
        check("left adjusts a slider down", state.amount == 1.5)
        press(panel, "UP")
        press(panel, "SPACE")
        check("space toggles the focused checkbox", panel.focused == flag and state.flag == true)
        env.shiftDown = true
        press(panel, "TAB")
        env.shiftDown = false
        check("shift-tab wraps focus to the last enabled control", panel.focused == locked)
        state.locked = true
        options.RefreshList(list)
        press(panel, "TAB")
        check("focus skips disabled controls", panel.focused == flag)
        press(panel, "ESCAPE")
        check("unhandled keys propagate to the client", panel.propagate == true)
        press(panel, "TAB")
        env.inCombat = true
        press(panel, "ESCAPE")
        check("combat leaves keyboard propagation untouched", panel.propagate == false and panel.focused == amount)
        env.inCombat = false
        env.runScript(panel, "OnHide")
        check("hiding clears focus and restores propagation", panel.focused == nil and panel.propagate == true)

        -- Pages from implemented modules and registration.
        local settingsHit = 0
        options = boot(nil, nil, function(core)
            core:RegisterModule("zeta", { OnEnable = function() end })
            core:RegisterModule("alpha", { title = "Alpha", Options = { title = "Alpha things", settings = {
                { type = "checkbox", key = "shiny", label = "Shiny", get = function() return settingsHit > 0 end,
                    set = function() settingsHit = settingsHit + 1 end },
            } } })
        end)
        local registered = env.settings.registered[1]
        check("panel registers as an AddOns Settings category at login", registered and registered.name == "RikUI"
            and registered.addon == true and registered.frame:GetName() == "RikUIOptionsPanel"
            and type(registered.frame.OnRefresh) == "function")
        SlashCmdList.RIKUI("config")
        check("/rik config opens the Settings category", env.settings.opened[1] == registered:GetID())
        local panelFrame = options.Panel()
        local titles = {}
        for index, page in ipairs(panelFrame.pages) do titles[index] = page.title end
        check("nested pages separate modules and maintenance", table.concat(titles, ",") == "General,Alpha things,Modules,Profiles,Setup and support")
        local general = pageByTitle(options, "General").list
        local modules = pageByTitle(options, "Modules").list
        local setup = pageByTitle(options, "Setup and support").list
        check("Modules lists registered modules without filling General", rowByKey(modules, "module.alpha")
            and rowByKey(modules, "module.zeta") and not rowByKey(modules, "module.bars")
            and not rowByKey(general, "module.alpha") and rowByKey(modules, "module.alpha").spec.reload == true)
        check("General has the scale slider and layout actions", rowByKey(general, "scale") and rowByKey(general, "move")
            and rowByKey(general, "reset") and not rowByKey(general, "resync") and not rowByKey(general, "wizard"))
        env.click(rowByKey(modules, "module.zeta").widget)
        check("module toggle persists with one actionable reload notice", RikUI.Profile.modules.zeta == false and panelFrame.reload.shown)
        env.click(rowByKey(modules, "module.zeta").widget)
        check("reverting module change clears reload notice", not panelFrame.reload.shown)
        env.runScript(rowByKey(general, "scale").widget, "OnValueChanged", 0.8)
        check("scale slider persists through Layout", RikUI.Profile.scale == 0.8)
        env.click(rowByKey(general, "move").widget)
        check("Move frames uses the existing layout editor", RikUI.Layout.IsMoving())
        env.click(rowByKey(general, "reset").widget)
        check("Reset positions clears stored positions", next(RikUI.Profile.positions) == nil)
        env.click(rowByKey(setup, "resync").widget)
        check("Re-sync uses the existing command", contains("Resync: no applied preset"))
        local alpha = pageByTitle(options, "Alpha things").list
        env.click(rowByKey(alpha, "shiny").widget)
        check("module page renders and commits module-declared settings", settingsHit == 1
            and rowByKey(alpha, "shiny").widget.mark.shown == true)
        check("sidebar entries are readable and the first page starts selected", panelFrame.pages[1].tab.text:GetText() == "General"
            and panelFrame.pages[1].frame.shown and not panelFrame.pages[2].frame.shown)
        env.click(panelFrame.pages[2].tab)
        check("sidebar click switches the visible page", panelFrame.pages[2].frame.shown and not panelFrame.pages[1].frame.shown
            and panelFrame.current == 2)

        options = boot({ profiles = { Default = { modules = { alpha = false } } } }, nil, function(core)
            core:RegisterModule("alpha", { Options = { title = "Alpha things", settings = {
                { type = "checkbox", key = "shiny", label = "Shiny", get = function() return false end, set = function() end },
            } } })
            core:RegisterCommand("setup", function() settingsHit = settingsHit + 10 end, "Wizard")
        end)
        local disabledPage = pageByTitle(options, "Alpha things").list
        check("settings of a disabled module are shown disabled", rowByKey(disabledPage, "shiny").enabled == false)
        setup = pageByTitle(options, "Setup and support").list
        env.click(rowByKey(setup, "wizard").widget)
        check("Re-run wizard appears only when its command exists", settingsHit == 11)

        Settings = nil
        options = boot()
        SlashCmdList.RIKUI("config")
        local standalone = options.Panel()
        check("without the Settings API the panel opens standalone", standalone.shown and standalone.parent == UIParent
            and standalone.close.shown)
        env.click(standalone.close)
        check("standalone close hides the panel", not standalone.shown)
        Settings = originalSettings

        -- Long pages and narrow native Settings canvases remain fully reachable.
        local picked = 1
        options = boot(nil, nil, function(core)
            for index = 1, 40 do core:RegisterModule("extra" .. index, { OnEnable = function() end }) end
            local specs = {}
            for index = 1, 30 do
                specs[#specs + 1] = { type = "checkbox", label = "A longer option label " .. index,
                    get = function() return true end, set = function() end }
            end
            local values = {}
            for index = 1, 20 do values[index] = { value = index, text = "Choice " .. index } end
            specs[#specs + 1] = { type = "dropdown", key = "last", label = "Last choice", values = values,
                get = function() return picked end, set = function(value) picked = value end }
            core:RegisterModule("long", { Options = { title = "Long page", settings = specs } })
        end)
        local config, long = options.Panel(), pageByTitle(options, "Long page")
        options.Resize(540, 400)
        options.Open("long")
        check("sidebar groups contain indented page entries", config.groups.Interface and config.groups.System
            and long.tab.parent == config.nav.content and long.tab.point[2] == 10)
        check("long module page clips content and exposes a scroll range", long.scroll.view.clips
            and long.scroll.view.scrollChild == long.scroll.content and long.scroll.range > 0)
        local last = rowByKey(long.list, "last")
        check("narrow canvas stacks bounded labels and controls", last.height > 40 and last.label.width <= last.width
            and last.widget.point[1] == "BOTTOMRIGHT" and last.widget.width <= last.width)
        options.SetFocus(config, last)
        check("keyboard focus reveals last row", long.scroll.offset > 0
            and last.top + last.height <= long.scroll.offset + long.scroll.height)
        env.click(last.widget)
        local popup = last.widget.list
        check("dropdown uses unclipped canvas host with bounded scrolling", popup.parent.parent == config
            and popup.height == 6 * options.Metrics.controlHeight and popup.scroll.range > 0)
        env.runScript(popup.scroll.view, "OnMouseWheel", -100)
        env.click(popup.buttons[20])
        check("last dropdown entry remains selectable", picked == 20 and not popup.shown)
        env.click(last.widget)
        env.runScript(long.scroll.view, "OnMouseWheel", 1)
        check("scrolling content dismisses detached dropdown", not popup.shown)
        env.click(config.groups.Interface)
        check("collapsing a navigation group hides its children", not long.tab.shown)
        options.Open("long")
        check("direct page entry expands its parent group", long.tab.shown and not config.groups.Interface.collapsed)
        options.Resize(1000, 3000)
        check("resizing to a wide canvas clears scroll and restores aligned rows", long.scroll.offset == 0
            and last.height < 40 and last.widget.point[1] == "RIGHT")
        options.Resize(540, 400)
        local modulePage = pageByTitle(options, "Modules")
        local firstModule = rowByKey(modulePage.list, "module.extra1")
        env.click(firstModule.widget)
        check("module changes show reload once outside scrolling content", config.reload.shown
            and config.reload.parent == config and firstModule.label:GetText() == "Extra1")
        env.click(firstModule.widget)
        check("reverting long-page module setting clears reload", not config.reload.shown)
        RikUI.DB.profiles.Off = { modules = { extra1 = false } }
        RikUI:SetProfile("Off"); options.Refresh()
        check("profile switch recomputes reload against loaded modules", config.reload.shown)
        RikUI:SetProfile("Default"); options.Refresh()
        check("switching back clears reload state", not config.reload.shown)
        env.inCombat = true; env.fire("PLAYER_REGEN_DISABLED")
        local generalPage = pageByTitle(options, "General")
        check("layout actions are disabled in combat", not rowByKey(generalPage.list, "move").enabled
            and not rowByKey(generalPage.list, "reset").enabled)
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")

        -- Profiles.
        options = boot({ profiles = { Default = { scale = 0.9, positions = { main = { x = 5 } } } } })
        local profiles = pageByTitle(options, "Profiles").list
        local active, nameRow = rowByKey(profiles, "profile"), rowByKey(profiles, "newName")
        check("create and copy are disabled without a name", rowByKey(profiles, "create").enabled == false
            and rowByKey(profiles, "copy").enabled == false)
        nameRow.widget:SetText("  Alt  ")
        env.runScript(nameRow.widget, "OnTextChanged", true)
        env.click(rowByKey(profiles, "copy").widget)
        check("copy creates an independent copy and selects it", RikUI.CharDB.profile == "Alt" and RikUI.Profile == RikUIDB.profiles.Alt
            and RikUIDB.profiles.Alt.scale == 0.9 and RikUIDB.profiles.Alt.positions ~= RikUIDB.profiles.Default.positions
            and RikUIDB.profiles.Alt.positions.main.x == 5 and RikUIDB.profiles.Default.scale == 0.9)
        check("name clears after creation", nameRow.widget:GetText() == "" and rowByKey(profiles, "create").enabled == false)
        nameRow.widget:SetText("Alt")
        env.runScript(nameRow.widget, "OnTextChanged", true)
        check("duplicate names cannot be created", rowByKey(profiles, "create").enabled == false)
        nameRow.widget:SetText("Fresh")
        env.runScript(nameRow.widget, "OnTextChanged", true)
        env.click(rowByKey(profiles, "create").widget)
        check("create starts from defaults and selects", RikUI.CharDB.profile == "Fresh" and RikUI.Profile.scale == 1
            and RikUIDB.profiles.Alt.scale == 0.9)
        check("active dropdown lists every profile sorted", active.widget.text:GetText() == "Fresh"
            and active.spec.values()[1].value == "Alt" and active.spec.values()[3].value == "Fresh")
        env.click(active.widget)
        env.click(active.widget.list.buttons[2])
        check("selecting a profile switches it", RikUI.CharDB.profile == "Default" and RikUI.Profile.scale == 0.9)
        local remove, deleteRow = rowByKey(profiles, "delete"), rowByKey(profiles, "deleteName")
        check("delete is disabled until a profile is chosen", remove.enabled == false)
        local candidates = deleteRow.spec.values()
        check("delete list excludes the active profile", #candidates == 2 and candidates[1].value == "Alt" and candidates[2].value == "Fresh")
        check("deleting the active profile is refused", select(2, options.DeleteProfile("Default")):find("active", 1, true) ~= nil
            and RikUIDB.profiles.Default)
        check("deleting an unknown profile is refused", options.DeleteProfile("Nope") == nil)
        env.click(deleteRow.widget)
        env.click(deleteRow.widget.list.buttons[2])
        env.click(remove.widget)
        check("delete removes only the chosen profile", RikUIDB.profiles.Fresh == nil and RikUIDB.profiles.Alt and RikUIDB.profiles.Default
            and remove.enabled == false)
        check("empty and blank names are refused", options.CreateProfile("") == nil and options.CreateProfile("   ") == nil)
        env.inCombat = true
        nameRow.widget:SetText("Combat")
        env.runScript(nameRow.widget, "OnTextChanged", true)
        env.click(rowByKey(profiles, "create").widget)
        check("combat creates the profile but defers selection", RikUIDB.profiles.Combat and RikUI.CharDB.profile == "Default"
            and contains("combat"))
        env.click(active.widget)
        env.click(active.widget.list.buttons[1])
        check("combat defers the dropdown switch", RikUI.CharDB.profile == "Default")
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("deferred profile selection applies after combat", RikUI.CharDB.profile == "Alt")

        -- Real bars module declares appearance options.
        env.frames, env.printed, env.inCombat = {}, {}, false
        env.settings = { registered = {}, opened = {} }
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = { modules = { bars = false } } } }, nil
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/setup/setup-snapshot.lua", "src/setup/setup-undo.lua",
            "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua", "src/ui/motion.lua", "src/ui/skin.lua", "src/ui/scroll.lua", "src/layout/layout-unlock.lua", "src/layout/layout-drag.lua", "src/modules/bars/bars.lua", "src/modules/bars/bars-skin.lua", "src/modules/bars/bars-stock.lua", "src/configuration/options/options-widgets.lua",
            "src/configuration/options/options-controls.lua", "src/configuration/options/options.lua", "src/configuration/options/options-view.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        options = RikUI.Options
        local barsPage = pageByTitle(options, "Bars and layout")
        check("bars module declares its page", barsPage and rowByKey(barsPage.list, "gryphons") and rowByKey(barsPage.list, "showStockBars")
            and rowByKey(barsPage.list, "borderColor"))
        check("bars settings are disabled while the module is off", rowByKey(barsPage.list, "gryphons").enabled == false)
        RikUI.Modules.bars.enabled = true
        options.Refresh()
        env.click(rowByKey(barsPage.list, "gryphons").widget)
        env.click(rowByKey(barsPage.list, "showStockBars").widget)
        check("bars appearance choices persist to the profile", RikUI.Profile.gryphons == true and RikUI.Profile.showStockBars == true)
        local button = CreateFrame("Button", nil, UIParent)
        RikUI.Bars.DecorateButton(button)
        env.click(rowByKey(barsPage.list, "borderColor").widget)
        ColorPickerFrame.rgb = { 0.9, 0.1, 0.1 }
        ColorPickerFrame.info.swatchFunc()
        check("border colour persists and retints decorated buttons", RikUI.Profile.borderColor[1] == 0.9
            and button.border[1].tint[1] == 0.9 and button.border[4].tint[2] == 0.1)
    end)
    CreateFrame, Settings, ColorPickerFrame = originalCreate, originalSettings, originalPicker
    env.inCombat, env.shiftDown = false, false
    check("options suite completes", ok, reason)
end
