return function(check)
    local env = require("wow_stub")
    local originalCreate, originalDriver = CreateFrame, RegisterStateDriver
    local saved = {}
    for _, name in ipairs({ "GetNumShapeshiftForms", "GetShapeshiftFormInfo", "GetPetActionInfo", "GetBindingKey" }) do
        saved[name] = _G[name]
    end
    local forms, pets, writes, drivers = {}, {}, 0, {}
    local keys = { SHAPESHIFTBUTTON1 = "CTRL-Q", BONUSACTIONBUTTON1 = "SHIFT-G" }
    GetBindingKey = function(command) return keys[command] end
    local secureClick = function() end
    local function protected()
        assert(not InCombatLockdown(), "protected control write in combat")
        writes = writes + 1
    end
    local function region(value)
        local methods = getmetatable(value).__index
        setmetatable(value, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function value:SetTexture(texture) self.texture = texture end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        function value:SetTexCoord(...) self.coords = { ... } end
        function value:SetShown(shown) self.shown = shown end
        function value:SetAlphaFromBoolean(active, yes, no) self.active, self.yes, self.no = active, yes, no end
        function value:SetVertexColor(...) self.color = { ... } end
        return value
    end
    CreateFrame = function(kind, name, parent, template)
        protected()
        local frame = originalCreate(kind, name, parent, template)
        local methods = getmetatable(frame).__index
        setmetatable(frame, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        if template then frame.scripts.OnClick = secureClick end
        function frame:SetAttribute(key, value) protected(); self.attributes[key] = value end
        function frame:SetSize(w, h) protected(); self.width, self.height = w, h end
        function frame:SetPoint(...) protected(); self.point = { ... } end
        function frame:ClearAllPoints() protected() end
        function frame:SetScale(value) protected(); self.scale = value end
        function frame:RegisterForClicks(...) self.clicks = { ... } end
        function frame:GetAlpha() return 0 end
        local show, hide = frame.Show, frame.Hide
        function frame:Show() protected(); show(self) end
        function frame:Hide() protected(); hide(self) end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        function frame:CreateAnimationGroup()
            local group = {}
            function group:CreateAnimation() return setmetatable({}, { __index = function() return function() end end }) end
            function group:SetScript() end
            function group:Stop() end
            return group
        end
        return frame
    end
    RegisterStateDriver = function(frame, state, condition)
        protected()
        assert(state == "visibility")
        drivers[frame] = condition
    end
    GetNumShapeshiftForms = function() return #forms end
    GetShapeshiftFormInfo = function(index)
        local form = forms[index]
        if not form then return end
        if form.error then error("form unavailable") end
        return form.texture, form.active, true, form.spell
    end
    GetPetActionInfo = function(index)
        local pet = pets[index]
        if not pet then return end
        if pet.error then error("pet action unavailable") end
        return pet.name, pet.texture, pet.token, pet.active, pet.allowed, pet.enabled, pet.spell
    end
    for _, event in ipairs({ "UPDATE_BINDINGS", "PET_BAR_UPDATE", "PET_UI_UPDATE", "UNIT_PET",
        "PET_BAR_UPDATE_USABLE", "PLAYER_CONTROL_GAINED", "PLAYER_CONTROL_LOST", "UPDATE_SHAPESHIFT_USABLE" }) do
        env.KNOWN_EVENTS[event] = true
    end
    local function loadBars(combat)
        env.frames, env.printed, env.inCombat = {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        for _, file in ipairs({ "core.lua", "media.lua", "setup.lua", "setup-apply.lua", "bindings.lua",
            "bars.lua", "bars-skin.lua", "bars-controls.lua", "bars-stock.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Bars
    end
    local ok, reason = pcall(function()
        forms = { { texture = 10, spell = 2457, active = true } }
        pets = { { name = "Attack", texture = "PET_TEST_TEXTURE", token = true, active = true },
            { name = "Bite", texture = 40, allowed = true, enabled = true } }
        PET_TEST_TEXTURE = 20
        local bars = loadBars()
        local stance, pet = bars.ControlFrames.stance, bars.ControlFrames.pet
        check("known stance creates one visible secure control", stance and stance.buttons[1]:IsShown()
            and not stance.buttons[2]:IsShown())
        check("stance casts exact reported spell ID", stance.buttons[1]:GetAttribute("type1") == "spell"
            and stance.buttons[1]:GetAttribute("spell") == 2457)
        check("stance active highlight is rendered", stance.buttons[1].active.active == true)
        check("companion indicators use shared flat media", RikUI.Media ~= nil
            and stance.buttons[1].active.texture == RikUI.Media.checked
            and pet.buttons[2].autoCastAllowed.texture == RikUI.Media.checked)
        check("native stance and pet binding scheme is preserved",
            RikUI.Bindings.Scheme.SHAPESHIFTBUTTON1 == "CTRL-Q"
            and RikUI.Bindings.Scheme.BONUSACTIONBUTTON1 == "SHIFT-G"
            and RikUI.Bindings.Scheme.SHAPESHIFTBUTTON4 == nil)
        check("pet row has ten secure fixed pet slots", #pet.buttons == 10
            and pet.buttons[10]:GetAttribute("type1") == "pet"
            and pet.buttons[10]:GetAttribute("action") == 10)
        check("pet tuple uses current texture return and resolves tokens", pet.buttons[1].icon.texture == 20
            and pet.buttons[2].icon.texture == 40)
        check("pet autocast availability and enabled state are separate", pet.buttons[2].autoCastAllowed.active
            and pet.buttons[2].autoCastEnabled.active and not pet.buttons[1].autoCastEnabled.active)
        check("companion buttons preserve native secure click and edges",
            pet.buttons[1]:GetScript("OnClick") == secureClick
            and table.concat(pet.buttons[1].clicks, ",") == "AnyDown,AnyUp"
            and pet.buttons[1]:GetAttribute("type2") == nil)
        check("pet visibility requires a living pet and no override", drivers[pet] == "[@pet,exists,nodead,nopossessbar,nooverridebar] show; hide")
        check("stance visibility is driven independently of current form", drivers[stance] == "[possessbar][overridebar] hide; show")
        check("companion rows sit above utility row without overlap", stance.point[5] == 166 and pet.point[5] == 202)
        for _, row in ipairs({ stance, pet }) do
            for _, button in ipairs(row.buttons) do
                check("companion shares flat font and icon crop", #button.border == 4
                    and button.icon.coords[1] == 0.07 and button.count.fontPath == RikUI.Media.font
                    and button.hotkey.fontPath == RikUI.Media.font and button.hotkey.fontSize == 12)
            end
        end
        check("companion labels use real native bindings", stance.buttons[1].hotkey.text == "cQ"
            and pet.buttons[1].hotkey.text == "sG")
        keys.SHAPESHIFTBUTTON1, keys.BONUSACTIONBUTTON1 = "BUTTON4", nil
        env.fire("UPDATE_BINDINGS")
        check("companion rebind and unbind refresh labels", stance.buttons[1].hotkey.text == "M4"
            and pet.buttons[1].hotkey.text == "")
        local before = writes
        env.inCombat = true
        forms[1].active, pets[2].enabled = false, false
        env.fire("UPDATE_SHAPESHIFT_FORM")
        env.fire("PET_BAR_UPDATE")
        check("combat events update stance and autocast art", stance.buttons[1].active.active == false
            and pet.buttons[2].autoCastEnabled.active == false)
        check("combat visual events make no protected writes", before == writes)
        forms[2] = { texture = 50, spell = 71, active = true }
        env.fire("UPDATE_SHAPESHIFT_FORMS")
        check("new forms wait for combat queue", stance.buttons[2]:GetAttribute("spell") == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("new form appears with correct spell after combat", stance.buttons[2]:IsShown()
            and stance.buttons[2]:GetAttribute("spell") == 71)
        forms[3], forms[4] = { texture = 60, spell = 99 }, { texture = 70, spell = 100 }
        env.fire("UPDATE_SHAPESHIFT_FORMS")
        check("fourth form is clickable without assigning a new bind", stance.buttons[4]:GetAttribute("spell") == 100
            and RikUI.Bindings.Scheme.SHAPESHIFTBUTTON4 == nil)
        forms[1].active, pets[2].allowed, pets[2].enabled = env.SECRET, env.SECRET, env.SECRET
        env.fire("UPDATE_SHAPESHIFT_FORM")
        env.fire("PET_BAR_UPDATE")
        check("secret state flags go directly to alpha sinks", stance.buttons[1].active.active == env.SECRET
            and pet.buttons[2].autoCastAllowed.active == env.SECRET
            and pet.buttons[2].autoCastEnabled.active == env.SECRET)
        pets[2] = nil
        env.fire("PET_BAR_UPDATE")
        check("removed pet action clears all prior art", pet.buttons[2].icon.texture == nil
            and pet.buttons[2].autoCastEnabled.active == false)
        forms[1].error, pets[1].error = true, true
        env.fire("UPDATE_SHAPESHIFT_FORM")
        env.fire("PET_BAR_UPDATE")
        check("API failures are reported", #env.printed > 0)
        forms, pets = {}, {}
        env.fire("UPDATE_SHAPESHIFT_FORMS")
        check("no known forms hides stance row", drivers[stance] == "hide")
        check("removed forms lose stale spell attributes", stance.buttons[1]:GetAttribute("spell") == nil)
        bars = loadBars(true)
        check("combat login defers companion frames", next(bars.ControlFrames) == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("companion frames initialize after combat", bars.ControlFrames.pet ~= nil)
    end)
    CreateFrame, RegisterStateDriver = originalCreate, originalDriver
    for name in pairs(saved) do _G[name] = saved[name] end
    GetPetActionInfo = saved.GetPetActionInfo
    PET_TEST_TEXTURE = nil
    env.inCombat = false
    check("control suite completes", ok, reason)
end
