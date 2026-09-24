local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Options panel: data-driven controls, keyboard focus, pages from implemented modules, profiles.
return function(check)
    local env = require("wow_stub")
    local originalCreate, originalSettings, originalPicker = CreateFrame, Settings, ColorPickerFrame
    local deferPaneSizeEvents = false
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
        function frame:CreateAnimationGroup() return require("widget_stub").animationGroup() end
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
        function frame:SetShown(value) if value then self:Show() else self:Hide() end end
        function frame:SetSize(w,h)
            if self.view and deferPaneSizeEvents then
                self.nativeWidth, self.nativeHeight = w, h
                return
            end
            self.nativeWidth, self.nativeHeight = nil, nil
            if self.width == w and self.height == h then return end
            self.width,self.height=w,h
            env.runScript(self, "OnSizeChanged", w, h)
        end
        function frame:SetWidth(w) self.width=w end
        function frame:SetHeight(h) self.height=h end
        function frame:GetWidth() return self.nativeWidth or self.width end
        function frame:GetHeight() return self.nativeHeight or self.height end
        function frame:SetClipsChildren(value) self.clips=value end
        function frame:SetScrollChild(child) self.scrollChild=child end
        function frame:SetVerticalScroll(value) self.scrollOffset=value end
        function frame:SetPropagateKeyboardInput(value) self.propagate = value end
        function frame:EnableKeyboard(value) self.keyboard = value end
        function frame:SetParent(parent) self.parent = parent end
        function frame:GetParent() return self.parent end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:SetText(value)
            self.text = value
            if self.kind == "EditBox" then env.runScript(self, "OnTextChanged", false) end
        end
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
        -- Hidden panes can have dimensions before their size callback runs.
        deferPaneSizeEvents = true
        local options = boot()
        check("login completes before hidden pane size events", not contains("Event PLAYER_LOGIN:")
            and #env.settings.registered > 0)
        check("login navigation uses its real viewport", options.Panel().nav.height == 424
            and options.Panel().nav.offset == 0)
        local earlyPane = RikUI.Scroll.Create(UIParent)
        local unsized = pcall(RikUI.Scroll.Reveal, earlyPane, 44, 22)
        check("reveal tolerates a pane without dimensions", unsized)
        earlyPane:SetSize(200, 88)
        RikUI.Scroll.SetContentHeight(earlyPane, 88)
        RikUI.Scroll.Reveal(earlyPane, 44, 22)
        check("reveal before size event keeps a fitting row visible", earlyPane.offset == 0 and earlyPane.range == 0)
        earlyPane:SetSize(200, 44)
        RikUI.Scroll.Reveal(earlyPane, 44, 22)
        check("reveal uses a resized viewport before its event", earlyPane.offset == 22 and earlyPane.range == 44)
        deferPaneSizeEvents = false
        local saves = 0
        RikUI.Store = { Touch = function() saves = saves + 1 end }
        check("profile creation schedules a save", options.CreateProfile("Saved") and saves == 1)
        check("profile deletion schedules a save", options.DeleteProfile("Saved") and saves == 2)
        check("profile names reject markup", not options.CreateProfile("|Hbad"))
        check("profile names reject excessive length", not options.CreateProfile(string.rep("x", 65)))
        check("profile copy rejects missing source", not options.CreateProfile("Missing", "Absent")
            and RikUI.DB.profiles.Missing == nil)
        RikUI.DB.profiles.Cyclic = {}; RikUI.DB.profiles.Cyclic.self = RikUI.DB.profiles.Cyclic
        local copied, copyResult = pcall(options.CreateProfile, "Broken", "Cyclic")
        check("cyclic copy fails safely without mutation", copied and not copyResult and RikUI.DB.profiles.Broken == nil)
        RikUI.DB.profiles.Cyclic = nil
        local huge = {}; for i = 1, 8200 do huge[i] = i end
        RikUI.DB.profiles.Huge = huge
        check("oversized copy fails without mutation", not options.CreateProfile("TooBig", "Huge")
            and RikUI.DB.profiles.TooBig == nil)
        RikUI.DB.profiles.Huge = nil
        RikUI.Store = nil
        options = boot(nil, nil, function(core)
            core:RegisterModule("broken", { OnEnable = function() error("fixture failure") end,
                Options = { title = "Broken", settings = {
                    { type = "checkbox", key = "setting", label = "Setting", get = function() return true end, set = function() end }
                } } })
            core:RegisterModule("dependent", {}, { dependencies = { "broken" } })
        end)
        local brokenPage = pageByTitle(options, "Broken")
        check("failed module controls cannot be used", rowByKey(brokenPage.list, "setting").enabled == false)
        check("module status names unavailable dependency", options.ModuleStatus("dependent"):find("Needs Broken", 1, true) ~= nil)
        local brokenRow = rowByKey(pageByTitle(options, "Modules").list, "module.broken")
        check("failed status is visible beside usable module toggle", brokenRow.enabled
            and brokenRow.description:GetText():find("Could not start", 1, true) ~= nil)

        -- Renderer with synthetic specs.

        check("configuration confines page content to a scrolling viewport", options.Panel().pages[1].scroll ~= nil)
        local emptyPane=RikUI.Scroll.Create(UIParent)
        local emptyList=options.Render(emptyPane.content,{})
        emptyList.scroll=emptyPane
        local resizeCalls=0
        emptyPane.OnResize=function(width) resizeCalls=resizeCalls+1;assert(resizeCalls<5,"recursive scroll layout");options.ResizeList(emptyList,width) end
        emptyPane:SetSize(200,100)
        check("empty options page does not recurse during layout",resizeCalls==1 and emptyPane.range==0)
        RikUI.Scroll.SetContentHeight(emptyPane,500);RikUI.Scroll.SetOffset(emptyPane,999)
        check("shared scroller clamps long content",emptyPane.offset==400 and emptyPane.bar:IsShown())
        check("scroll thumb reflects viewport fraction", emptyPane.thumbHeight == 28
            and emptyPane.moreAbove:IsShown() and not emptyPane.moreBelow:IsShown())
        RikUI.Scroll.SetContentHeight(emptyPane,200)
        check("scroll thumb grows as content shortens", emptyPane.thumbHeight == 50)
        RikUI.Scroll.SetOffset(emptyPane,0)
        check("scroll cues identify content below", not emptyPane.moreAbove:IsShown() and emptyPane.moreBelow:IsShown())
        RikUI.Scroll.SetContentHeight(emptyPane,0)
        check("content shrink clears stale scroll and thumb",emptyPane.offset==0 and not emptyPane.bar:IsShown() and resizeCalls==1
            and not emptyPane.moreAbove:IsShown() and not emptyPane.moreBelow:IsShown())
        RikUI.Scroll.SetContentHeight(emptyPane,500)
        RikUI.Scroll.Reveal(emptyPane,40,200)
        check("oversized rows reveal their beginning",emptyPane.offset==40)
        RikUI.Scroll.SetContentHeight(emptyPane,0)
        local selectedSize = 0
        local sizeList = options.Render(CreateFrame("Frame", nil, UIParent), {
            { type = "dropdown", key = "prose", label = "Quest body text size",
                choices = { { value = 0, label = "Native size" }, { value = 18, label = "18" } },
                get = function() return selectedSize end, set = function(value) selectedSize = value end }
        })
        local sizeRow = sizeList.rows[1]
        check("declared choices render readable labels including zero", sizeRow.widget.text:GetText() == "Native size")
        env.click(sizeRow.widget)
        check("declared choices populate the actual menu", #sizeRow.widget.list.buttons == 2)
        env.click(sizeRow.widget.list.buttons[2])
        check("declared choice selection saves its value", selectedSize == 18 and sizeRow.widget.text:GetText() == "18")
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
            { type = "text", key = "name", label = "Name", description = "Choose a memorable name.", get = function() return state.name end, set = setter("name") },
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
        check("described settings have readable secondary text", name.description and name.description:GetText() == "Choose a memorable name."
            and name.height > flag.height)
        options.ResizeList(list, 260)
        check("descriptions fit below stacked controls", name.description.width == 248
            and name.widget.point[5] > 4 and name.height > 62)
        options.ResizeList(list, 500)
        env.runScript(flag.widget, "OnEnter")
        check("controls use a cancellable hover wash", flag.widget.rikHover.enter:IsPlaying())
        env.runScript(flag.widget, "OnHide")
        check("hidden controls cancel hover", not flag.widget.rikHover.enter:IsPlaying()
            and flag.widget.rikHover.region.alpha == 0)
        env.runScript(name.widget, "OnEditFocusGained")
        check("text entry focus animates the row", name.focusEnter:IsPlaying() and name.focusActive)
        env.runScript(name.widget, "OnEditFocusLost")
        name.focusLeave:Finish()
        check("text blur clears focus after its fade", not name.focus.shown)
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
        env.runScript(amount.widget, "OnValueChanged", 1.26)
        check("slider rounds drag values to its step", state.amount == 1.5)
        check("slider trims redundant trailing zeroes", amount.widget.text:GetText() == "1.5")
        env.runScript(amount.widget, "OnValueChanged", 99)
        check("slider clamps input at bounds", state.amount == 2)
        env.runScript(amount.widget, "OnValueChanged", 1.5)
        check("dropdown shows the current text", choice.widget.text:GetText() == "Beta")
        deferPaneSizeEvents = true
        env.click(choice.widget)
        check("dropdown lays out before its size event", choice.widget.list.scroll.height == 66
            and choice.widget.list.scroll.range == 0 and choice.widget.list.scroll.offset == 0)
        deferPaneSizeEvents = false
        check("dropdown opens a list of readable entries", choice.widget.list.shown and #choice.widget.list.buttons == 3
            and choice.widget.list.buttons[3].text:GetText() == "Gamma")
        env.click(choice.widget.list.buttons[3])
        local savedValues = choice.spec.values
        choice.spec.values = {}
        env.click(choice.widget)
        check("empty dropdown explains missing choices", choice.widget.list.empty:IsShown()
            and not choice.widget.list.buttons[1]:IsShown())
        options.CloseDropdown()
        choice.spec.values = savedValues
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
        options.Activate(colour)
        local stalePicker = ColorPickerFrame.info
        RikUI.DB.profiles.PickerTarget = {}
        RikUI:SetProfile("PickerTarget")
        ColorPickerFrame.rgb = { 0.8, 0.8, 0.8 }
        stalePicker.swatchFunc()
        stalePicker.cancelFunc({ r = 1, g = 1, b = 1 })
        check("old profile picker cannot write through callbacks", state.colour[1] == 0.1 and state.colour[3] == 0.3)
        RikUI:SetProfile("Default")
        stalePicker.cancelFunc({ r = 1, g = 1, b = 1 })
        check("returning to profile does not revive an old picker", state.colour[1] == 0.1)
        options.Activate(colour)
        local olderPicker = ColorPickerFrame.info
        options.Activate(colour)
        olderPicker.cancelFunc({ r = 1, g = 1, b = 1 })
        check("superseded picker cannot restore stale color", state.colour[1] == 0.1)
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

        env.inCombat = true
        local beforeSets = sets.amount or 0
        options.Commit(amount, 1)
        options.Commit(amount, 2)
        check("combat setting changes coalesce", RikUI.Combat.Pending() == 1)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("combat setting applies final value once", state.amount == 2 and sets.amount == beforeSets + 1)
        env.inCombat = true
        options.Commit(amount, 1)
        RikUI.DB.profiles.Other = {}
        env.inCombat = false
        RikUI:SetProfile("Other")
        env.fire("PLAYER_REGEN_ENABLED")
        check("stale profile setting is discarded", state.amount == 2)
        RikUI:SetProfile("Default")
        env.inCombat = true
        options.Commit(amount, 1)
        amount.spec.disabled = function() return true end
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("queued setting rechecks availability", state.amount == 2)
        amount.spec.disabled = nil
        options.RefreshList(list)
        options.Commit(amount, 0.5)

        local oldSetter, oldChanged = amount.spec.set, RikUI.Changed
        local saved = 0
        RikUI.Changed = function() saved = saved + 1 end
        amount.spec.set = function() error("preference unavailable") end
        check("setter exception stays inside settings", pcall(options.Commit, amount, 1))
        check("failed setter is reported without saving", saved == 0 and contains("preference unavailable"))
        amount.spec.set = function() return false, "preference refused" end
        options.Commit(amount, 1)
        check("rejected setting is reported without saving", saved == 0 and contains("preference refused"))
        amount.spec.set, RikUI.Changed = oldSetter, oldChanged
        local oldAction = pressRow.spec.action
        pressRow.spec.action = function() error("action unavailable") end
        check("action exception stays inside settings", pcall(options.Activate, pressRow))
        check("failed action has context", contains("action unavailable"))
        pressRow.spec.action = oldAction
        options.Activate(pressRow)
        check("settings action recovers after failure", state.pressed == 2)

        -- Keyboard focus over the same list.
        local panel = CreateFrame("Frame", nil, UIParent)
        options.EnableKeyboard(panel, function() return list.rows end)
        check("panel captures keys and propagates by default", panel.keyboard == true and panel.propagate == true)
        press(panel, "TAB")
        check("tab focuses the first control, skipping headings", panel.focused == flag and flag.focus.shown and panel.propagate == false)
        press(panel, "DOWN")
        press(panel, "DOWN")
        check("arrows move focus down", panel.focused == choice and flag.focus.alpha == 0)
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

        options.SetFocus(panel, name)
        name.widget:SetFocus()
        press(panel, "LEFT")
        check("text caret keys propagate while editing", panel.propagate and panel.focused == name)
        options.SetFocus(panel, flag)
        check("moving keyboard focus releases the old text editor", not name.widget:HasFocus())
        name.widget:SetFocus()
        options.SetFocus(panel, name)
        env.runScript(name.widget, "OnTabPressed")
        check("text tab moves to the next enabled control", panel.focused == pressRow and not name.widget:HasFocus())

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
        RikUI.Store = { BackupIssue = function() return "Reload backup needs attention" end }
        options.Refresh()
        check("settings footer surfaces backup problems", panelFrame.status:GetText():find("Reload backup needs attention", 1, true) ~= nil)
        RikUI.Store = nil
        options.Refresh()
        local titles = {}
        for index, page in ipairs(panelFrame.pages) do titles[index] = page.title end
        check("nested pages separate modules and maintenance", table.concat(titles, ",") == "General,Alpha things,Modules,Profiles,Setup and support")
        local general = pageByTitle(options, "General").list
        local modules = pageByTitle(options, "Modules").list
        local setup = pageByTitle(options, "Setup and support").list
        local automatic = rowByKey(setup, "autoPlacement")
        check("setup exposes default-on per-character automatic placement", automatic and automatic.spec.get() == true)
        env.click(automatic.widget)
        check("setup checkbox persists automatic placement opt-out", RikUI.CharDB.autoPlacement == false)
        RikUI.Runtime.BindProfile()
        check("profile binding keeps automatic placement opt-out", RikUI.CharDB.autoPlacement == false)
        check("Modules lists registered modules without filling General", rowByKey(modules, "module.alpha")
            and rowByKey(modules, "module.zeta") and not rowByKey(modules, "module.bars")
            and not rowByKey(general, "module.alpha") and rowByKey(modules, "module.alpha").spec.reload == true)
        check("General has the scale slider and layout actions", rowByKey(general, "scale") and rowByKey(general, "move")
            and rowByKey(general, "reset") and not rowByKey(general, "resync") and not rowByKey(general, "wizard"))
        env.click(rowByKey(modules, "module.zeta").widget)
        check("reload footer counts changes and names active profile", panelFrame.status:GetText():find("1 change", 1, true)
            and panelFrame.status:GetText():find("Default", 1, true)
            and pageByTitle(options, "Modules").tab.badge:GetText() == "1")
        check("module toggle persists with one actionable reload notice", RikUI.Profile.modules.zeta == false and panelFrame.reload.shown)
        env.click(rowByKey(modules, "module.zeta").widget)
        check("reverting module change clears reload notice", not panelFrame.reload.shown
            and not pageByTitle(options, "Modules").tab.badge:IsShown())
        env.inCombat = true; options.Refresh()
        check("reload button explains combat restriction", panelFrame.reload.text:GetText() == "After combat"
            and not panelFrame.reload.enabled)
        env.inCombat = false; options.Refresh()
        env.runScript(rowByKey(general, "scale").widget, "OnValueChanged", 0.8)
        check("scale slider persists through Layout", RikUI.Profile.scale == 0.8)
        check("scale is displayed as a readable percentage", rowByKey(general, "scale").widget.text:GetText() == "80%")
        env.click(rowByKey(general, "move").widget)
        check("Move frames uses the existing layout editor", RikUI.Layout.IsMoving())
        RikUI.Layout.Register(CreateFrame("Frame", nil, UIParent), "test", { point = "CENTER", x = 0, y = 0 })
        RikUI.Profile.positions.test = { x = 10 }
        env.click(rowByKey(general, "reset").widget)
        check("reset requires confirmation", RikUI.Profile.positions.test ~= nil
            and rowByKey(general, "reset").confirming ~= nil)
        env.click(rowByKey(general, "reset").cancel)
        check("reset cancellation preserves positions", RikUI.Profile.positions.test ~= nil
            and rowByKey(general, "reset").confirming == nil)
        env.click(rowByKey(general, "reset").widget)
        env.click(rowByKey(general, "reset").widget)
        check("Reset positions restores registered defaults", RikUI.Profile.positions.test.x == 0)
        env.click(rowByKey(setup, "resync").widget)
        check("Re-sync uses the existing command", contains("Resync: no applied preset"))
        local alpha = pageByTitle(options, "Alpha things").list
        env.click(rowByKey(alpha, "shiny").widget)
        check("module page renders and commits module-declared settings", settingsHit == 1
            and rowByKey(alpha, "shiny").widget.mark.shown == true)
        check("sidebar entries are readable and the first page starts selected", panelFrame.pages[1].tab.text:GetText() == "General"
            and panelFrame.pages[1].frame.shown and not panelFrame.pages[2].frame.shown)
        env.click(panelFrame.pages[2].tab)
        check("page transition starts its own entrance", panelFrame.pages[2].frame.rikEntry:IsPlaying())
        check("settings title has a flat gold rule", panelFrame.titleRule.height == 1)
        check("sidebar click switches the visible page", panelFrame.pages[2].frame.shown and not panelFrame.pages[1].frame.shown
            and panelFrame.current == 2)

        options = boot({ profiles = { Default = { modules = { alpha = false } } } }, nil, function(core)
            core:RegisterModule("alpha", { Options = { title = "Alpha things", settings = {
                { type = "checkbox", key = "shiny", label = "Shiny", get = function() return false end, set = function() end },
            } } })
            core:RegisterCommand("setup", function() settingsHit = settingsHit + 10 end, "Wizard")
        end)
        check("disabled module explanation uses runtime state", options.ModuleStatus("alpha"):find("Disabled", 1, true) ~= nil)
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
        check("standalone close has a short exit fade", standalone.rikExit:IsPlaying() and standalone.shown)
        standalone.rikExit:Finish()
        check("standalone close hides the panel", not standalone.shown)
        options.Open()
        env.click(standalone.close)
        options.Open()
        standalone.rikExit:Finish()
        check("reopening settings cancels stale close", standalone.shown and not standalone.rikClosing)
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
        check("dropdown reveals and marks the selected choice", popup.scroll.offset > 0
            and popup.buttons[20].selected:IsShown() and not popup.buttons[1].selected:IsShown())
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

        config.search:SetText("last choice")
        check("typing search applies filter and exposes clear action", config.query == "last choice" and config.clearSearch:IsShown())
        options.Search("last choice")
        check("search finds settings across pages", config.current == 2 and last:IsShown()
            and not long.list.rows[1]:IsShown())
        options.Search("choice long")
        check("search combines words across title and label", not last.filtered and long.list.rows[1].filtered)
        options.Search("  CHOICE    LAST ")
        check("search ignores word order and repeated spaces", not last.filtered)
        options.Search("choice [")
        check("search punctuation stays literal", config.empty:IsShown())
        options.Search("no such preference")
        check("search explains empty results", config.empty:IsShown() and not long.frame:IsShown())
        options.Search("  LONG PAGE  ")
        check("search matches page titles without case sensitivity", long.frame:IsShown() and long.list.rows[1]:IsShown())
        options.Search("")
        check("clearing search restores navigation and rows", long.tab:IsShown() and long.list.rows[1]:IsShown()
            and not config.empty:IsShown())
        options.Open("long")
        press(config, "END")
        check("end focuses last visible enabled control", config.focused == last and long.scroll.offset > 0)
        press(config, "HOME")
        check("home focuses first control", config.focused == long.list.rows[1] and long.scroll.offset == 0)
        press(config, "PAGEDOWN")
        check("page down selects the next settings page", config.pages[config.current].id == "modules")
        press(config, "PAGEUP")
        check("page up returns to the previous page", config.pages[config.current].id == "long")
        -- Open dropdown keyboard navigation does not commit until confirmed.
        options.Open("long")
        env.click(last.widget)
        press(config, "HOME")
        check("dropdown home previews first choice without saving", popup.cursor == 1 and picked == 20)
        press(config, "DOWN"); press(config, "ENTER")
        check("dropdown enter commits highlighted choice", picked == 2 and not popup.shown)
        env.click(last.widget); press(config, "END"); press(config, "ESCAPE")
        check("dropdown escape cancels preview", picked == 2 and not popup.shown)
        do
            local copied
            local copyOptions = boot({profiles={Default={},Source={}}}, nil, function(core)
                core.Layout.CopyProfile = function(name) copied = name; return true end
            end)
            local rows = pageByTitle(copyOptions, "Profiles").list
            local source, copyRow = rowByKey(rows,"layoutSource"), rowByKey(rows,"copyLayout")
            copyOptions.Commit(source, "Source")
            check("layout copy exposes selected source", copyRow.enabled and source.spec.get() == "Source")
            env.click(copyRow.widget)
            check("layout copy waits for named confirmation", copied == nil and copyRow.confirmText:GetText():find("Source",1,true))
            env.click(copyRow.widget)
            check("layout copy routes confirmed action", copied == "Source")
        end
        do
            local safeOptions = boot({profiles={Default={},[5]={},[" bad"]={},["Good"]={}}})
            local safeRows = pageByTitle(safeOptions,"Profiles").list
            local choices = rowByKey(safeRows,"profile").spec.values()
            check("malformed restored profile keys do not break pickers", #choices == 2 and choices[2].value == "Good")
        end
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
        check("copied profile requests reload even with matching module flags", RikUI:ProfileNeedsReload()
            and active.pending and options.Panel().reload:IsShown())
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
        check("returning to loaded profile clears profile reload request", not RikUI:ProfileNeedsReload() and not active.pending)
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
        deleteRow.spec.set("Alt"); options.RefreshList(profiles)
        check("changing deletion target cancels confirmation", remove.confirming == nil and RikUIDB.profiles.Fresh)
        deleteRow.spec.set("Fresh"); options.RefreshList(profiles)
        env.click(remove.widget)
        check("delete first click retains chosen profile", RikUIDB.profiles.Fresh and remove.confirming ~= nil)
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
        check("combat profile choices coalesce", RikUI.Combat.Pending() == 1)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("deferred profile selection applies after combat", RikUI.CharDB.profile == "Alt")

        options = boot({ profiles = { Default = { modules = { base = false, middle = false, feature = false } } } }, nil, function(core)
            core:RegisterModule("base", {})
            core:RegisterModule("middle", {}, { dependencies = { "base" } })
            core:RegisterModule("feature", {}, { dependencies = { "middle" } })
            core:RegisterModule("broken", {}, { dependencies = { "absent" } })
            core:RegisterModule("cycleA", {}, { dependencies = { "cycleB" } })
            core:RegisterModule("cycleB", {}, { dependencies = { "cycleA" } })
        end)
        local dependencyRows = pageByTitle(options, "Modules").list
        env.click(rowByKey(dependencyRows, "module.feature").widget)
        check("enable selects transitive module requirements", RikUI.Profile.modules.feature
            and RikUI.Profile.modules.middle and RikUI.Profile.modules.base)
        check("dependency selection does not activate live modules", RikUI:GetModuleState("base") == "disabled")
        RikUI:SetModuleEnabled("feature", false)
        check("disabling feature preserves dependency choices", not RikUI.Profile.modules.feature and RikUI.Profile.modules.base)
        RikUI:SetModuleEnabled("base", false)
        RikUI:SetModuleEnabled("feature", true)
        RikUI:SetModuleEnabled("base", false)
        check("saved dependency conflict is explained before reload", options.ModuleStatus("feature"):find("After reload", 1, true)
            and options.ModuleStatus("feature"):find("Base", 1, true))
        RikUI:SetModuleEnabled("base", true)
        check("restoring saved provider clears dependency warning", not options.ModuleStatus("feature"):find("After reload", 1, true))
        RikUI:SetModuleEnabled("feature", false)
        local requirements = RikUI:GetModuleRequirements("feature")
        requirements[1] = "changed"
        check("module requirements are detached and transitive", RikUI:GetModuleRequirements("feature")[1] == "base"
            and #RikUI:GetModuleRequirements("feature") == 2)
        check("missing and cyclic graphs are reported", not RikUI:GetModuleRequirements("broken")
            and not RikUI:GetModuleRequirements("cycleA"))
        RikUI.Profile.modules.broken = false
        check("missing dependency rejects atomically", not RikUI:SetModuleEnabled("broken", true)
            and RikUI.Profile.modules.broken == false and RikUI.Profile.modules.absent == nil)
        RikUI.Profile.modules.cycleA, RikUI.Profile.modules.cycleB = false, false
        check("cyclic dependencies reject atomically", not RikUI:SetModuleEnabled("cycleA", true)
            and not RikUI.Profile.modules.cycleA and not RikUI.Profile.modules.cycleB)

        options = boot({ profiles = { Default = { scale = 0.75, tooltip = { scale = 1.4 } }, ["Recovery 1"] = {} } })
        local recoveryRows = pageByTitle(options, "Profiles").list
        local resetProfile = rowByKey(recoveryRows, "resetProfile")
        check("profile reset is exposed", resetProfile ~= nil)
        env.click(resetProfile.widget)
        check("profile reset requires confirmation", RikUI.Profile.scale == 0.75)
        env.click(resetProfile.cancel)
        check("cancel profile reset preserves settings", RikUI.Profile.scale == 0.75)
        env.click(resetProfile.widget); env.click(resetProfile.widget)
        check("profile reset keeps active name and defaults", RikUI.CharDB.profile == "Default"
            and RikUI.Profile.scale == 1 and RikUI:ProfileNeedsReload())
        local recovery = RikUI.DB.profiles["Recovery 2"]
        check("profile reset makes independent recovery copy", recovery and recovery.scale == 0.75
            and recovery.tooltip.scale == 1.4 and recovery.tooltip ~= RikUI.Profile.tooltip)
        RikUI:SetProfile("Recovery 2")
        check("recovery profile restores old preferences", RikUI.Profile.scale == 0.75)
        env.inCombat = true
        check("combat reset is refused", not options.ResetProfile() and RikUI.Profile == recovery)
        env.inCombat = false
        local isApplying = RikUI.Setup.IsApplying
        RikUI.Setup.IsApplying = function() return true end
        check("setup conflict leaves reset data untouched", not options.ResetProfile()
            and RikUI.Profile == recovery and RikUI.DB.profiles["Recovery 3"] == nil)
        RikUI.Setup.IsApplying = isApplying

        do
            options = boot()
            local oldWidth, oldHeight = UIParent.GetWidth, UIParent.GetHeight
            UIParent.GetWidth, UIParent.GetHeight = function() return 1365 end, function() return 768 end
            local frame = CreateFrame("Frame", nil, UIParent)
            frame:SetSize(100, 30)
            RikUI.Layout.Register(frame, "precision", { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }, { label = "Precision frame" })
            options.Refresh()
            local controls = pageByTitle(options, "General").list
            local picker = rowByKey(controls, "layoutFrame")
            check("precision frame picker is available", picker ~= nil)
            if picker then
                options.Commit(picker, "precision")
                local before = RikUI.Layout.Rect("precision")
                env.click(rowByKey(controls, "nudgeRight").widget)
                check("settings move selected frame by one screen unit", RikUI.Layout.Rect("precision").left == before.left + 1)
                env.inCombat = true
                local saved = RikUI.Profile.positions.precision
                check("precision edits refuse combat", not RikUI.Layout.Nudge("precision", 1, 0) and RikUI.Profile.positions.precision == saved)
                env.inCombat = false
                check("precision edits reject invalid deltas and groups", not RikUI.Layout.Nudge("missing", 1, 0)
                    and not RikUI.Layout.Nudge("precision", 0/0, 0))
                RikUI.Layout.SetScale(0.5)
                before = RikUI.Layout.Rect("precision")
                RikUI.Layout.Nudge("precision", 1, 0)
                check("nudge distance does not shrink with frame scale", RikUI.Layout.Rect("precision").left == before.left + 1)
                RikUI.Layout.Nudge("precision", 10000, 0)
                check("nudge stops at the screen edge", RikUI.Layout.Rect("precision").right <= 1365)
                local obstacle = CreateFrame("Frame", nil, UIParent)
                obstacle:SetSize(100, 30)
                RikUI.Layout.Register(obstacle, "obstacle", { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 })
                RikUI.Layout.Nudge("precision", -10000, 0)
                check("nudge does not cross another frame", not RikUI.Geometry.Overlaps(RikUI.Layout.Rect("precision"), RikUI.Layout.Rect("obstacle")))
                RikUI.Layout.Groups.precision.floating = function() return true end
                check("self-positioned frames refuse nudges", not RikUI.Layout.Nudge("precision", 1, 0))
            end
            UIParent.GetWidth, UIParent.GetHeight = oldWidth, oldHeight
        end

        do
            options = boot()
            assert(loadfile("data/layouts.lua"))("RikUI", {})
            assert(loadfile("src/layout/layout-presets.lua"))("RikUI", {})
            local layout = RikUI.Layout
            local frame = CreateFrame("Frame", nil, UIParent); frame:SetSize(100, 30)
            layout.Register(frame, "resetOne", { point = "CENTER", relativePoint = "CENTER", x = 5, y = 6 })
            RikUI.Profile.positions.resetOne = { point = "CENTER", relativePoint = "CENTER", x = 50, y = 60 }
            RikUI.Profile.positions.unrelated = { point = "TOP", relativePoint = "TOP", x = 7, y = 8 }
            RikUI.Profile.chat.size = { width = 333, height = 222 }
            check("selected frame reset succeeds", layout.Reset("resetOne"))
            check("reset keeps previous positions for undo", RikUI.Profile.layoutUndo and RikUI.Profile.layoutUndo.positions.resetOne.x == 50)
            check("selected reset preserves unrelated state", RikUI.Profile.positions.unrelated.x == 7 and RikUI.Profile.positions.resetOne.x == 5)
            if RikUI.Profile.layoutUndo then
                layout.UndoPreset()
                check("undo restores reset and chat size", RikUI.Profile.positions.resetOne.x == 50 and RikUI.Profile.chat.size.width == 333)
            end
            check("unknown reset target is refused", not layout.Reset("absent"))
            env.inCombat = true
            check("reset refuses combat without recovery overwrite", not layout.Reset("resetOne") and not RikUI.Profile.layoutUndo)
            env.inCombat = false
        end

        do
            options = boot({ profiles = { Default = {}, Alt = {} } })
            local scale = rowByKey(pageByTitle(options, "General").list, "scale")
            env.inCombat = true
            options.Commit(scale, 2)
            env.inCombat = false
            RikUI:SetProfile("Alt"); RikUI:SetProfile("Default")
            env.fire("PLAYER_REGEN_ENABLED")
            check("queued setting cancels after switching away and back", RikUI.Profile.scale == 1)
            local active = rowByKey(pageByTitle(options, "Profiles").list, "profile")
            env.inCombat = true
            options.Commit(active, "Alt")
            options.DeleteProfile("Alt"); options.CreateProfile("Alt")
            env.inCombat = false
            env.fire("PLAYER_REGEN_ENABLED")
            check("queued profile selection cannot target recreated name", RikUI.CharDB.profile == "Default")
            local reset = rowByKey(pageByTitle(options, "Profiles").list, "resetProfile")
            env.click(reset.widget)
            RikUI:SetProfile("Alt"); RikUI:SetProfile("Default")
            env.click(reset.widget)
            check("profile transition invalidates destructive confirmation", RikUI.DB.profiles["Recovery 1"] == nil)
        end

        do
            local review = boot(nil, nil, function(core)
                core:RegisterModule("review", { Options = { title = "Review feature", settings = {} } })
            end)
            local canvas = review.Panel()
            local mod = pageByTitle(review, "Modules")
            local toggle = rowByKey(mod.list, "module.review")
            check("settings offers pending review toggle", canvas.pendingOnly ~= nil)
            env.click(toggle.widget)
            env.click(canvas.pendingOnly)
            check("pending review hides unchanged rows and pages", canvas.onlyPending
                and not toggle.filtered and pageByTitle(review, "General").filtered
                and canvas.pages[canvas.current] == mod)
            review.Search("no such setting")
            check("pending search has an empty state", canvas.empty:IsShown())
            review.Search("review")
            check("pending search intersects row labels", not toggle.filtered and not canvas.empty:IsShown())
            review.SetFocus(canvas, toggle)
            env.click(toggle.widget)
            check("reverted pending row disappears and drops keyboard focus", toggle.filtered
                and canvas.empty:IsShown() and canvas.focused == nil and not canvas.reload:IsShown())
            press(canvas, "SPACE")
            check("hidden pending control cannot be activated by stale focus", RikUI.Profile.modules.review ~= false)
            env.click(canvas.pendingOnly)
            review.Search("")
            check("all settings restores normal navigation", not canvas.onlyPending
                and not pageByTitle(review, "General").filtered and not canvas.empty:IsShown())
            env.click(toggle.widget)
            env.click(canvas.pendingOnly)
            review.Open("general")
            check("direct page links clear both filters", not canvas.onlyPending and canvas.query == ""
                and canvas.pages[canvas.current].id == "general")
            env.click(canvas.pendingOnly)
            RikUI.Profile.modules.review = true
            review.Refresh()
            check("external preference refresh removes resolved pending rows", toggle.filtered and canvas.empty:IsShown())
            check("pending review explains an empty result", canvas.empty:GetText() == "No changes need reload.")
            RikUI.DB.profiles.ReviewAlt = {}
            RikUI:SetProfile("ReviewAlt"); review.Refresh()
            local profilesPage = pageByTitle(review, "Profiles")
            check("profile switch surfaces pending profile selector", not profilesPage.filtered
                and not rowByKey(profilesPage.list, "profile").filtered and toggle.filtered)
            env.inCombat = true; review.Refresh()
            check("pending review retains combat reload restriction", not canvas.reload.enabled
                and canvas.reload.text:GetText() == "After combat")
            env.inCombat = false
            RikUI:SetProfile("Default"); review.Refresh()
            check("returning to loaded profile empties pending review", canvas.empty:IsShown() and not canvas.reload:IsShown())

        end

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
