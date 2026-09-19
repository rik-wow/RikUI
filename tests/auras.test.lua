-- Aura values only reach sinks; the cancel layer is secure and touched only out of combat.
return function(check)
    local env = require("wow_stub")
    local originalCreate, originalDriver = CreateFrame, RegisterStateDriver
    local API = { "C_UnitAuras", "C_PaperDollInfo", "C_Secrets", "GetInventoryItemTexture", "GetTime", "GameTooltip",
        "BuffFrame", "DebuffFrame" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local lists, durations, counts, enchants, calls = { HELPFUL = {}, HARMFUL = {} }, {}, {}, {}, {}
    local failing, now, writes, drivers = false, 100, 0, {}
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
        function value:SetTexCoord(...) self.coords = { ... } end
        function value:SetColorTexture(...) self.color = { ... } end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:Show() self.shown = true end
        function value:Hide() self.shown = false end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        function value:SetText(text) self.text, self.format, self.args = text, nil, nil end
        function value:SetFormattedText(format, ...) self.format, self.args, self.text = format, { ... }, nil end
        return value
    end
    CreateFrame = function(kind, name, parent, template)
        if template then protected() end
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
        function frame:ClearAllPoints() if secure then protected() end end
        function frame:SetScale(value) if secure then protected() end; self.scale = value end
        function frame:GetFrameLevel() return self.level or 1 end
        function frame:SetFrameLevel(level) self.level = level end
        function frame:RegisterForClicks(...) self.clicks = { ... } end
        function frame:SetCooldownFromDurationObject(duration, clearIfZero)
            self.duration, self.clearIfZero, self.start, self.length = duration, clearIfZero, nil, nil
        end
        function frame:SetCooldown(start, length) self.start, self.length, self.duration = start, length, nil end
        function frame:Clear() self.duration, self.start, self.length = nil, nil, nil; self.clears = (self.clears or 0) + 1 end
        local show, hide = frame.Show, frame.Hide
        function frame:Show() if secure then protected() end; show(self) end
        function frame:Hide() if secure then protected() end; hide(self) end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        return frame
    end
    RegisterStateDriver = function(frame, state, condition)
        protected()
        assert(state == "visibility")
        drivers[frame] = condition
    end
    C_UnitAuras = {
        GetAuraDataByIndex = function(unit, index, filter)
            assert(unit == "player", "aura reads target the player")
            if failing then error("aura data unavailable") end
            return lists[filter][index]
        end,
        GetAuraDuration = function(_, id)
            table.insert(calls, id)
            if durations[id] == "error" then error("duration unavailable") end
            return durations[id]
        end,
        GetAuraApplicationDisplayCount = function(_, id) table.insert(calls, id); return counts[id] end,
    }
    C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function(slot) return enchants[slot] end }
    C_Secrets = { ShouldAurasBeSecret = function() return false end }
    GetInventoryItemTexture = function(_, slot) return 5000 + slot end
    GetTime = function() return now end
    GameTooltip = {
        SetOwner = function(self, owner) self.owner = owner end,
        SetUnitAura = function(self, ...) self.aura = { ... } end,
        SetInventoryItem = function(self, ...) self.item = { ... } end,
        Hide = function(self) self.hidden = true end,
    }
    local function stockFrame(name)
        local f = { parent = UIParent, events = { UNIT_AURA = true }, label = name }
        function f:GetParent() return self.parent end
        function f:SetParent(value) assert(not InCombatLockdown(), "stock frame reparented in combat"); self.parent = value end
        function f:UnregisterAllEvents() self.events = {}; self.unregistered = (self.unregistered or 0) + 1 end
        function f:GetName() return self.label end
        return f
    end
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
        for _, id in ipairs(calls) do
            if id == env.SECRET then return true end
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
    local function load(profile, combat, missingStock)
        env.frames, env.printed, env.inCombat, env.timers, writes, drivers, calls = {}, {}, false, {}, 0, {}, {}
        lists, durations, counts, enchants, failing = { HELPFUL = {}, HARMFUL = {} }, {}, {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, profile and { profiles = { Default = profile } } or nil, nil
        BuffFrame = (not missingStock) and stockFrame("BuffFrame") or nil
        DebuffFrame = (not missingStock) and stockFrame("DebuffFrame") or nil
        for _, file in ipairs({ "core.lua", "hide.lua", "media.lua", "setup.lua", "setup-apply.lua", "layout.lua",
            "unitframes.lua", "unitframes-status.lua", "auras.lua", "auras-status.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Auras
    end
    local function aura(id, fields)
        local data = { name = "Aura " .. tostring(id), icon = 1000 + id, applications = 1, auraInstanceID = id }
        for key, value in pairs(fields or {}) do data[key] = value end
        return data
    end
    local ok, reason = pcall(function()
        local module = load()
        local buffs, debuffs = module.Rows.buffs, module.Rows.debuffs
        local cancel = buffs.cancel
        check("buff and debuff rows exist as plain frames", buffs and debuffs and buffs.template == nil
            and debuffs.template == nil and buffs.filter == "HELPFUL" and debuffs.filter == "HARMFUL")
        check("rows hold 32 buff and 16 debuff display buttons", #buffs.buttons == 32 and #debuffs.buttons == 16
            and buffs.buttons[1].template == nil and buffs.buttons[1].cooldown.kind == "Cooldown")
        local groups = RikUI.Layout.Groups
        check("rows register with the shared layout at the top right", groups.buffs.frames[1] == buffs
            and groups.debuffs.frames[1] == debuffs and groups.buffs.defaults.point == "TOPRIGHT"
            and groups.buffs.defaults.relativePoint == "TOPRIGHT" and groups.buffs.defaults.x < 0
            and groups.buffs.defaults.y < 0)
        check("debuff default sits under the buff rows", groups.debuffs.defaults.x == groups.buffs.defaults.x
            and groups.debuffs.defaults.y + buffs.height <= groups.buffs.defaults.y)
        check("cancel layer is a child of the buff row hidden by a combat driver", cancel and cancel.parent == buffs
            and drivers[cancel] == "[combat] hide; show" and #cancel.buttons == 32)
        local cancelButton = cancel.buttons[1]
        check("cancel buttons are secure cancelaura buttons over their display buttons",
            cancelButton.template == "SecureActionButtonTemplate" and cancelButton:GetAttribute("type2") == "cancelaura"
            and cancelButton.anchor == buffs.buttons[1] and cancelButton.shown == false)
        check("display buttons start hidden", shownCount(buffs.buttons) == 0 and shownCount(debuffs.buttons) == 0)
        check("stock buff and debuff frames are parked with events dropped", BuffFrame.parent == RikUIHiddenFrames
            and DebuffFrame.parent == RikUIHiddenFrames and BuffFrame.unregistered == 1 and DebuffFrame.unregistered == 1)

        lists.HELPFUL = { aura(11, { duration = 120, expirationTime = 100120 }), aura(12, { applications = 3 }),
            aura(13, { duration = 30, expirationTime = 130 }), aura(14, { duration = 0, expirationTime = 0 }) }
        durations[11], counts[11], counts[12] = { id = "d11" }, "", "3"
        env.fire("UNIT_AURA", "player")
        local first, second, third, fourth = buffs.buttons[1], buffs.buttons[2], buffs.buttons[3], buffs.buttons[4]
        check("buffs show their icons", shownCount(buffs.buttons) == 4 and first.icon.texture == 1011
            and second.icon.texture == 1012 and buffs.buttons[5].shown == false)
        check("buff timers come from the aura duration object", first.cooldown.duration == durations[11]
            and first.cooldown.clearIfZero == true)
        check("counts come from the client display count", first.count.text == "" and second.count.text == "3")
        check("a missing duration object falls back to readable times", third.cooldown.start == 100
            and third.cooldown.length == 30 and fourth.cooldown.clears == 1 and fourth.cooldown.length == nil)
        check("buffs keep the neutral border", color(first.border[1].color, module.Colors.buff))
        check("cancel buttons carry the aura index and filter", cancel.buttons[1]:GetAttribute("index") == 1
            and cancel.buttons[1]:GetAttribute("filter") == "HELPFUL" and cancel.buttons[4]:GetAttribute("index") == 4
            and shownCount(cancel.buttons) == 4 and cancel.buttons[1].clicks[1] == "RightButtonUp")

        C_UnitAuras.GetAuraApplicationDisplayCount = nil
        env.fire("UNIT_AURA", "player")
        check("without the display count API readable applications drive the count", first.count.text == ""
            and second.count.format == "%d" and second.count.args[1] == 3)
        C_UnitAuras.GetAuraApplicationDisplayCount = function(_, id) table.insert(calls, id); return counts[id] end

        lists.HARMFUL = { aura(21, { dispelName = "Magic" }), aura(22, { dispelName = "Poison" }), aura(23) }
        env.fire("UNIT_AURA", "player")
        check("debuffs show with dispel-type borders", shownCount(debuffs.buttons) == 3
            and color(debuffs.buttons[1].border[1].color, module.Colors.Magic)
            and color(debuffs.buttons[2].border[1].color, module.Colors.Poison)
            and color(debuffs.buttons[3].border[1].color, module.Colors.none))
        check("debuff rows have no cancel layer", debuffs.cancel == nil)

        calls, env.printed = {}, {}
        lists.HELPFUL = { { name = env.SECRET, icon = env.SECRET, applications = env.SECRET, auraInstanceID = env.SECRET,
            dispelName = env.SECRET, duration = env.SECRET, expirationTime = env.SECRET } }
        lists.HARMFUL = { { icon = env.SECRET, dispelName = env.SECRET, auraInstanceID = env.SECRET } }
        env.fire("UNIT_AURA", "player")
        check("secret aura values reach the sinks unchanged without error", first.icon.texture == env.SECRET
            and debuffs.buttons[1].icon.texture == env.SECRET and #env.printed == 0 and shownCount(buffs.buttons) == 1)
        check("a secret aura instance never reaches the duration or count APIs", not calledWithSecret()
            and first.cooldown.duration == nil and first.cooldown.start == nil and first.count.text == "")
        check("a secret dispel type keeps the neutral debuff border",
            color(debuffs.buttons[1].border[1].color, module.Colors.none))

        lists.HELPFUL = { aura(11), aura(12) }
        durations[12] = "error"
        env.printed = {}
        env.fire("UNIT_AURA", "player")
        check("a failing duration read is reported once and the timer cleared", printedContains("Auras duration")
            and #env.printed == 1 and second.cooldown.duration == nil and second.shown == true)
        durations[12] = nil

        env.fire("UNIT_AURA", "target")
        lists.HELPFUL = { aura(11) }
        env.fire("UNIT_AURA", "target")
        check("other units' aura events are ignored", shownCount(buffs.buttons) == 2)
        env.fire("UNIT_AURA", env.SECRET)
        check("a secret event unit refreshes the rows", shownCount(buffs.buttons) == 1)

        local before = writes
        env.inCombat = true
        lists.HELPFUL = { aura(11), aura(12), aura(13) }
        env.fire("UNIT_AURA", "player")
        check("combat updates redraw the display without protected writes", shownCount(buffs.buttons) == 3
            and writes == before and shownCount(cancel.buttons) == 1 and module.blocked == false)
        failing = true
        env.printed = {}
        env.fire("UNIT_AURA", "player")
        env.fire("UNIT_AURA", "player")
        check("a throwing combat read keeps the last display and warns once", shownCount(buffs.buttons) == 3
            and module.blocked == true and printedContains("Auras read") and #env.printed == 1)
        lists.HELPFUL[1] = env.SECRET
        failing = false
        env.fire("UNIT_AURA", "player")
        check("a secret aura record also keeps the last display", shownCount(buffs.buttons) == 3 and module.blocked == true)
        lists.HELPFUL = { aura(11), aura(12), aura(13), aura(14) }
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat re-reads the auras and syncs the cancel layer", shownCount(buffs.buttons) == 4
            and module.blocked == false and shownCount(cancel.buttons) == 4
            and cancel.buttons[4]:GetAttribute("index") == 4)

        lists.HELPFUL = { aura(11) }
        enchants[16] = { enchantID = 7, remainingTimeMs = 60000, chargesRemaining = 5, hasExpirationTime = true }
        env.fire("WEAPON_ENCHANT_CHANGED")
        check("a weapon enchant takes the first buff slot with the item icon and charges", first.icon.texture == 5016
            and first.count.format == "%d" and first.count.args[1] == 5 and second.icon.texture == 1011
            and shownCount(buffs.buttons) == 2)
        check("the enchant timer snapshots the remaining time as its duration", first.cooldown.start == 100
            and first.cooldown.length == 60)
        check("the enchant cancel button targets the inventory slot", cancel.buttons[1]:GetAttribute("target-slot") == 16
            and cancel.buttons[1]:GetAttribute("index") == nil and cancel.buttons[2]:GetAttribute("index") == 1
            and cancel.buttons[2]:GetAttribute("target-slot") == nil)
        enchants[16].remainingTimeMs = 30000
        env.fire("WEAPON_SLOT_CHANGED")
        check("a ticking enchant keeps its snapshot duration", first.cooldown.start == 70 and first.cooldown.length == 60)
        enchants[16].remainingTimeMs = 90000
        env.fire("WEAPON_ENCHANT_CHANGED")
        check("a refreshed enchant takes a new snapshot", first.cooldown.start == 100 and first.cooldown.length == 90)
        enchants[16].hasExpirationTime = false
        env.fire("WEAPON_ENCHANT_CHANGED")
        check("a permanent enchant shows without a timer", first.shown == true and first.cooldown.length == nil)
        enchants[16] = nil
        env.fire("WEAPON_ENCHANT_CHANGED")
        check("a removed enchant returns the slot to the auras", first.icon.texture == 1011
            and cancel.buttons[1]:GetAttribute("index") == 1 and cancel.buttons[1]:GetAttribute("target-slot") == nil)

        enchants[17] = { enchantID = 8, remainingTimeMs = 10000, chargesRemaining = 0, hasExpirationTime = true }
        env.fire("WEAPON_ENCHANT_CHANGED")
        env.runScript(first, "OnEnter")
        check("hovering an enchant shows the inventory item tooltip", GameTooltip.item[1] == "player"
            and GameTooltip.item[2] == 17 and GameTooltip.owner == first and first.count.text == "")
        env.runScript(cancel.buttons[2], "OnEnter")
        check("hovering a buff shows the aura tooltip", GameTooltip.aura[1] == "player" and GameTooltip.aura[2] == 1
            and GameTooltip.aura[3] == "HELPFUL")
        env.runScript(cancel.buttons[2], "OnLeave")
        check("leaving hides the tooltip", GameTooltip.hidden == true)
        enchants[17] = nil

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        local output = table.concat(env.printed, "\n")
        check("debug reports aura dependency secrecy and the blocked state",
            output:find("auras.GetAuraDataByIndex(player,1,HELPFUL)", 1, true)
            and output:find("auras.ShouldAurasBeSecret()", 1, true) and output:find("Auras blocked=false", 1, true))

        C_UnitAuras.GetAuraDuration, C_UnitAuras.GetAuraApplicationDisplayCount = nil, nil
        module = load()
        lists.HELPFUL = { aura(11, { applications = 2, duration = 10, expirationTime = 110 }) }
        env.printed = {}
        env.fire("UNIT_AURA", "player")
        first = module.Rows.buffs.buttons[1]
        check("missing aura APIs fall back to readable fields", first.cooldown.start == 100 and first.cooldown.length == 10
            and first.count.args[1] == 2 and #env.printed == 0)
        C_UnitAuras.GetAuraDuration = function(_, id) table.insert(calls, id); return durations[id] end
        C_UnitAuras.GetAuraApplicationDisplayCount = function(_, id) table.insert(calls, id); return counts[id] end

        module = load(nil, true)
        check("combat login defers row creation and stock hiding", next(module.Rows) == nil
            and BuffFrame.parent == UIParent)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("rows and stock hiding follow after combat", module.Rows.buffs ~= nil
            and BuffFrame.parent == RikUIHiddenFrames)
        module = load({ modules = { auras = false } })
        check("disabled module leaves the stock frames alone", next(module.Rows) == nil and BuffFrame.parent == UIParent)
        module = load(nil, false, true)
        check("missing stock globals are tolerated", module.Rows.buffs ~= nil and #env.printed == 0)
    end)
    CreateFrame, RegisterStateDriver = originalCreate, originalDriver
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("aura suite completes", ok, reason)
end
