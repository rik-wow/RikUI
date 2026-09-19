-- Target and pet aura rows come from the shared aura factory; unit values only reach sinks.
return function(check)
    local env = require("wow_stub")
    local originalCreate = CreateFrame
    local API = { "C_UnitAuras", "C_PaperDollInfo", "C_Secrets", "GameTooltip" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local lists, durations, counts, failing, calls, writes = {}, {}, {}, {}, {}, 0
    local function protected()
        assert(not InCombatLockdown(), "protected aura write in combat")
        writes = writes + 1
    end
    local function region(value)
        local methods = getmetatable(value).__index
        setmetatable(value, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function value:SetTexture(texture) self.texture = texture end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetAlphaFromBoolean(active, yes, no) self.active, self.yes, self.no = active, yes, no end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        function value:SetText(text) self.text, self.format, self.args = text, nil, nil end
        function value:SetFormattedText(format, ...) self.format, self.args, self.text = format, { ... }, nil end
        function value:Show() self.shown = true end
        function value:Hide() self.shown = false end
        return value
    end
    CreateFrame = function(kind, name, parent, template)
        local frame = originalCreate(kind, name, parent, template)
        local methods = getmetatable(frame).__index
        setmetatable(frame, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        local secure = template ~= nil
        function frame:SetAttribute(key, value) protected(); self.attributes[key] = value end
        function frame:SetSize(w, h) if secure then protected() end; self.width, self.height = w, h end
        function frame:SetPoint(...) if secure then protected() end; self.point = { ... } end
        function frame:SetAllPoints(target) if secure then protected() end; self.anchor = target end
        function frame:SetScale(value) if secure then protected() end; self.scale = value end
        function frame:GetFrameLevel() return self.level or 1 end
        function frame:SetFrameLevel(level) self.level = level end
        function frame:SetCooldownFromDurationObject(duration, clearIfZero)
            self.duration, self.clearIfZero, self.start, self.length = duration, clearIfZero, nil, nil
        end
        function frame:SetCooldown(start, length) self.start, self.length, self.duration = start, length, nil end
        function frame:Clear() self.duration, self.start, self.length = nil, nil, nil end
        local show, hide = frame.Show, frame.Hide
        function frame:Show() if secure then protected() end; show(self) end
        function frame:Hide() if secure then protected() end; hide(self) end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        return frame
    end
    C_UnitAuras = {
        GetAuraDataByIndex = function(unit, index, filter)
            if failing[unit] then error("aura data unavailable") end
            return lists[unit] and lists[unit][filter][index]
        end,
        GetAuraDuration = function(unit, id) table.insert(calls, { unit, id }); return durations[id] end,
        GetAuraApplicationDisplayCount = function(unit, id) table.insert(calls, { unit, id }); return counts[id] end,
    }
    C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function() return nil end }
    C_Secrets = { ShouldAurasBeSecret = function() return false end }
    GameTooltip = {
        SetOwner = function(self, owner) self.owner = owner end,
        SetUnitAura = function(self, ...) self.aura = { ... } end,
        SetInventoryItem = function(self, ...) self.item = { ... } end,
        Hide = function(self) self.hidden = true end,
    }
    local function printedContains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.00001 end
    local function color(actual, expected)
        return type(actual) == "table" and near(actual[1], expected[1]) and near(actual[2], expected[2])
            and near(actual[3], expected[3])
    end
    local function calledWithSecret()
        for _, call in ipairs(calls) do
            if call[1] == env.SECRET or call[2] == env.SECRET then return true end
        end
        return false
    end
    local function shownCount(buttons)
        local total = 0
        for _, button in ipairs(buttons) do
            if button.shown then total = total + 1 end
        end
        return total
    end
    local function point(frame, name, relative, relativePoint, x, y)
        local p = frame.point
        return type(p) == "table" and p[1] == name and p[2] == relative and p[3] == relativePoint
            and near(p[4], x) and near(p[5], y)
    end
    local function filters() return { HELPFUL = {}, HARMFUL = {} } end
    local function load(profile, combat)
        env.frames, env.printed, env.inCombat, env.timers, writes, calls = {}, {}, false, {}, 0, {}
        lists = { player = filters(), target = filters(), pet = filters() }
        durations, counts, failing = {}, {}, {}
        RikUI, RikUIDB, RikUICharDB = nil, profile and { profiles = { Default = profile } } or nil, nil
        for _, file in ipairs({ "core.lua", "hide.lua", "media.lua", "setup.lua", "setup-apply.lua", "layout.lua",
            "unitframes.lua", "unitframes-status.lua", "auras.lua", "auras-status.lua", "auras-units.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.UnitAuras
    end
    local function aura(id, fields)
        local data = { name = "Aura " .. tostring(id), icon = 1000 + id, applications = 1, auraInstanceID = id }
        for key, value in pairs(fields or {}) do data[key] = value end
        return data
    end
    local ok, reason = pcall(function()
        local module = load({ modules = { auras = false } })
        local frames = RikUI.UnitFrames.Frames
        local debuffs, buffs, pet = module.Rows.targetdebuffs, module.Rows.targetbuffs, module.Rows.petdebuffs
        check("target and pet rows are plain children of their unit frames", debuffs and buffs and pet
            and debuffs.parent == frames.target and buffs.parent == frames.target and pet.parent == frames.petframe
            and debuffs.template == nil and debuffs.unit == "target" and pet.unit == "pet"
            and debuffs.filter == "HARMFUL" and buffs.filter == "HELPFUL" and pet.filter == "HARMFUL")
        check("rows hold 12 large debuffs, 16 small buffs and 8 small pet debuffs", #debuffs.buttons == 12
            and #buffs.buttons == 16 and #pet.buttons == 8 and debuffs.buttons[1].width == 30
            and buffs.buttons[1].width == 22 and pet.buttons[1].width == 22
            and debuffs.buttons[1].template == nil and debuffs.buttons[1].cooldown.kind == "Cooldown")
        check("debuffs sit above the frame and buffs above the debuffs",
            point(debuffs, "BOTTOMLEFT", frames.target, "TOPLEFT", 0, 4)
            and point(buffs, "BOTTOMLEFT", debuffs, "TOPLEFT", 0, 4)
            and point(pet, "BOTTOMLEFT", frames.petframe, "TOPLEFT", 0, 4))
        check("buttons fill left to right and upward from the bottom left corner",
            point(debuffs.buttons[1], "BOTTOMLEFT", debuffs, "BOTTOMLEFT", 0, 0)
            and point(debuffs.buttons[2], "BOTTOMLEFT", debuffs, "BOTTOMLEFT", 34, 0)
            and point(debuffs.buttons[7], "BOTTOMLEFT", debuffs, "BOTTOMLEFT", 0, 34)
            and point(buffs.buttons[9], "BOTTOMLEFT", buffs, "BOTTOMLEFT", 0, 26)
            and near(debuffs.width, 6 * 34 - 4) and near(debuffs.height, 2 * 34 - 4))
        check("unit rows follow their frame instead of the layout and have no cancel layer",
            RikUI.Layout.Groups.targetdebuffs == nil and RikUI.Layout.Groups.targetbuffs == nil
            and debuffs.cancel == nil and buffs.cancel == nil and shownCount(debuffs.buttons) == 0)
        check("one factory builds every row", type(RikUI.Auras.CreateRow) == "function"
            and module.CreateRow == nil and #debuffs.buttons[1].border == 4 and debuffs.buttons[1].count ~= nil)

        local emphasis = RikUI.Auras.Emphasis
        lists.target.HARMFUL = { aura(31, { dispelName = "Magic", isFromPlayerOrPlayerPet = true, applications = 3 }),
            aura(32, { isFromPlayerOrPlayerPet = false, dispelName = "Poison" }),
            aura(33, { isFromPlayerOrPlayerPet = env.SECRET }), aura(34, { sourceUnit = "pet" }),
            aura(35, { sourceUnit = "raid3" }), aura(36) }
        durations[31], counts[31] = { id = "d31" }, "3"
        env.fire("UNIT_AURA", "target")
        local first, second, third = debuffs.buttons[1], debuffs.buttons[2], debuffs.buttons[3]
        check("target debuffs show icon, count, dispel border and duration-object timer",
            shownCount(debuffs.buttons) == 6 and first.icon.texture == 1031 and first.count.text == "3"
            and color(first.border[1].color, RikUI.Auras.Colors.Magic) and first.cooldown.duration == durations[31]
            and first.cooldown.clearIfZero == true and color(second.border[1].color, RikUI.Auras.Colors.Poison))
        check("the duration and count APIs are asked about the target", calls[1][1] == "target" and calls[1][2] == 31)
        check("player-cast debuffs keep full size and full icon alpha", first.scale == 1 and first.icon.active == true
            and first.icon.yes == 1 and first.icon.no == emphasis.alpha)
        check("other casters' debuffs shrink and dim", second.scale == emphasis.scale and second.icon.active == false
            and emphasis.scale < 1 and emphasis.alpha < 1)
        check("a secret caster flag reaches only the alpha sink and keeps full scale", third.scale == 1
            and third.icon.active == env.SECRET)
        check("a missing flag falls back to a readable source unit", debuffs.buttons[4].scale == 1
            and debuffs.buttons[5].scale == emphasis.scale and debuffs.buttons[6].scale == 1)

        lists.target.HELPFUL = { aura(41, { isFromPlayerOrPlayerPet = false }) }
        env.fire("UNIT_AURA", "target")
        check("target buffs fill the smaller row with the neutral border", shownCount(buffs.buttons) == 1
            and buffs.buttons[1].icon.texture == 1041 and buffs.buttons[1].scale == emphasis.scale
            and color(buffs.buttons[1].border[1].color, RikUI.Auras.Colors.buff))
        env.runScript(first, "OnEnter")
        check("hovering a target debuff shows the target aura tooltip", GameTooltip.aura[1] == "target"
            and GameTooltip.aura[2] == 1 and GameTooltip.aura[3] == "HARMFUL" and GameTooltip.owner == first)

        calls, env.printed = {}, {}
        lists.target.HARMFUL = { { icon = env.SECRET, applications = env.SECRET, auraInstanceID = env.SECRET,
            dispelName = env.SECRET, duration = env.SECRET, expirationTime = env.SECRET,
            isFromPlayerOrPlayerPet = env.SECRET, sourceUnit = env.SECRET } }
        env.fire("UNIT_AURA", "target")
        check("secret aura values reach the sinks without error", first.icon.texture == env.SECRET
            and #env.printed == 0 and shownCount(debuffs.buttons) == 1 and first.scale == 1
            and first.count.text == "" and color(first.border[1].color, RikUI.Auras.Colors.none))
        check("a secret instance never reaches the duration or count APIs", not calledWithSecret()
            and first.cooldown.duration == nil and first.cooldown.start == nil)

        lists.target.HARMFUL = { aura(31), aura(32) }
        env.fire("UNIT_AURA", "player")
        env.fire("UNIT_AURA", "focus")
        check("other units' aura events leave the target rows alone", shownCount(debuffs.buttons) == 1)
        env.fire("UNIT_AURA", env.SECRET)
        check("a secret event unit refreshes the unit rows", shownCount(debuffs.buttons) == 2)

        lists.target = filters()
        env.fire("PLAYER_TARGET_CHANGED")
        check("losing the target clears both rows", shownCount(debuffs.buttons) == 0 and shownCount(buffs.buttons) == 0
            and first.cooldown.duration == nil)
        lists.target.HARMFUL = { aura(31), aura(32), aura(33) }
        env.fire("PLAYER_TARGET_CHANGED")
        check("a new target fills the rows again", shownCount(debuffs.buttons) == 3)

        local before = writes
        env.inCombat = true
        lists.target.HARMFUL = { aura(31, { isFromPlayerOrPlayerPet = false }), aura(32) }
        env.fire("UNIT_AURA", "target")
        check("combat updates redraw without protected writes", shownCount(debuffs.buttons) == 2
            and first.scale == emphasis.scale and writes == before and module.blocked == false)
        failing.target = true
        env.printed = {}
        env.fire("UNIT_AURA", "target")
        env.fire("UNIT_AURA", "target")
        check("a throwing combat read keeps the display and warns once", shownCount(debuffs.buttons) == 2
            and module.blocked == true and printedContains("Unit auras read") and #env.printed == 1
            and RikUI.Auras.blocked == false)
        env.fire("PLAYER_TARGET_CHANGED")
        check("a blocked target change never shows the previous target's auras", shownCount(debuffs.buttons) == 0
            and module.blocked == true)
        failing.target = nil
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat re-reads the rows", shownCount(debuffs.buttons) == 2 and module.blocked == false)

        lists.pet.HARMFUL = { aura(51, { dispelName = "Disease" }) }
        env.fire("UNIT_AURA", "pet")
        check("pet debuffs fill the pet row", shownCount(pet.buttons) == 1 and pet.buttons[1].icon.texture == 1051
            and color(pet.buttons[1].border[1].color, RikUI.Auras.Colors.Disease))
        lists.pet = filters()
        env.fire("UNIT_PET", "player")
        check("a pet change clears and re-reads the pet row", shownCount(pet.buttons) == 0)
        lists.pet.HARMFUL = { aura(51) }
        env.fire("UNIT_PET", "target")
        check("another unit's pet change is ignored", shownCount(pet.buttons) == 0)
        env.fire("PLAYER_ENTERING_WORLD")
        check("entering the world refreshes every row", shownCount(pet.buttons) == 1)

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        local output = table.concat(env.printed, "\n")
        check("debug reports the unit aura read and blocked state",
            output:find("unitauras.GetAuraDataByIndex(target,1,HARMFUL)", 1, true)
            and output:find("Unit auras blocked=false", 1, true))

        module = load()
        lists.player.HELPFUL = { aura(11) }
        lists.target.HARMFUL = { aura(31) }
        env.fire("PLAYER_ENTERING_WORLD")
        check("player and unit rows coexist under both modules", shownCount(RikUI.Auras.Rows.buffs.buttons) == 1
            and shownCount(module.Rows.targetdebuffs.buttons) == 1)
        failing.target = true
        env.printed = {}
        env.fire("UNIT_AURA", "target")
        env.fire("UNIT_AURA", "player")
        check("a blocked target read leaves the player module unblocked", module.blocked == true
            and RikUI.Auras.blocked == false and #env.printed == 1)

        module = load({ modules = { auras = false, unitframes = false } })
        check("missing unit frames skip the rows with one line", next(module.Rows) == nil
            and printedContains("Unit auras attach") and #env.printed == 1)

        module = load({ modules = { auras = false } }, true)
        check("combat login defers row creation", next(module.Rows) == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("rows follow after combat", module.Rows.targetdebuffs ~= nil and module.Rows.petdebuffs ~= nil)
    end)
    CreateFrame = originalCreate
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("unit aura suite completes", ok, reason)
end
