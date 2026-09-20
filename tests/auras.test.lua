-- Player aura rows are Blizzard aura containers configured once; the module never reads auras.
return function(check)
    local env = require("wow_stub")
    local originalCreate = CreateFrame
    local API = { "C_UnitAuras", "C_Secrets", "BuffFrame", "DebuffFrame" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local auraReads = 0
    local function region(value)
        local methods = getmetatable(value).__index
        setmetatable(value, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function value:SetTexture(texture) self.texture = texture end
        function value:SetTexCoord(...) self.coords = { ... } end
        function value:SetColorTexture(...) self.color = { ... } end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetPoint(...) self.points = self.points or {}; table.insert(self.points, { ... }) end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        function value:SetText(text) self.text = text end
        function value:SetFormattedText(format, ...) self.format, self.args = format, { ... } end
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
        function frame:SetSize(w, h) self.width, self.height = w, h end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:SetAllPoints(target) self.anchor = target end
        function frame:SetAlpha(value) self.alpha = value end
        function frame:SetScale(value) self.scale = value end
        function frame:GetFrameLevel() return self.level or 1 end
        function frame:SetFrameLevel(level) self.level = level end
        function frame:SetHideCountdownNumbers(hidden) self.countdownHidden = hidden end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        return frame
    end
    C_UnitAuras = setmetatable({}, { __index = function()
        return function() auraReads = auraReads + 1 end
    end })
    C_Secrets = { ShouldAurasBeSecret = function() return false end }
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
    local function point(frame, name, relative, relativePoint, x, y)
        local p = frame.point
        return type(p) == "table" and p[1] == name and p[2] == relative and p[3] == relativePoint
            and near(p[4], x) and near(p[5], y)
    end
    local function descendant(object, ancestor)
        local parent = object and object.parent
        while parent do
            if parent == ancestor then return true end
            parent = parent.parent
        end
        return false
    end
    local function load(profile, combat, missingStock, missingContainer)
        env.frames, env.printed, env.inCombat, env.timers, auraReads = {}, {}, false, {}, 0
        env.auraContainerMissing = missingContainer == true
        RikUI, RikUIDB, RikUICharDB = nil, profile and { profiles = { Default = profile } } or nil, nil
        BuffFrame = (not missingStock) and stockFrame("BuffFrame") or nil
        DebuffFrame = (not missingStock) and stockFrame("DebuffFrame") or nil
        for _, file in ipairs({ "core.lua", "hide.lua", "media.lua", "setup.lua", "setup-apply.lua", "layout-geometry.lua", "layout.lua", "layout-rects.lua",
            "unitframes.lua", "unitframes-status.lua", "auras.lua", "auras-button.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Auras
    end
    local ok, reason = pcall(function()
        local module = load()
        local buffs, debuffs = module.Rows.buffs, module.Rows.debuffs
        local bc, dc = buffs and buffs.container, debuffs and debuffs.container
        local groups = RikUI.Layout.Groups
        check("proxies register with the shared layout at the top right", buffs and debuffs
            and groups.buffs.frames[1] == buffs and groups.debuffs.frames[1] == debuffs
            and groups.buffs.defaults.point == "TOPRIGHT" and groups.buffs.defaults.relativePoint == "TOPRIGHT"
            and groups.buffs.defaults.x < 0 and groups.buffs.defaults.y < 0)
        check("proxies carry the nominal row footprint", buffs.template == nil and near(buffs.width, 268)
            and near(buffs.height, 132) and near(debuffs.width, 268) and near(debuffs.height, 64)
            and groups.debuffs.defaults.x == groups.buffs.defaults.x
            and groups.debuffs.defaults.y + buffs.height <= groups.buffs.defaults.y)
        check("containers come from the Blizzard template as children of the proxies", bc and dc
            and bc.kind == "AuraContainer" and bc.template == "CustomAuraContainerTemplate" and bc.parent == buffs
            and dc.parent == debuffs and bc.unit == "player" and dc.unit == "player"
            and bc.previewEnabled == false and dc.previewEnabled == false)
        check("containers anchor to the proxy corner and flow right to left, downward",
            point(bc, "TOPRIGHT", buffs, "TOPRIGHT", 0, 0) and point(dc, "TOPRIGHT", debuffs, "TOPRIGHT", 0, 0)
            and bc.flow.anchor == "TOPRIGHT" and bc.flow.horizontal == -1 and bc.flow.vertical == -1
            and near(bc.flow.lineSize, 268) and near(dc.flow.lineSize, 268))
        local buffGroup, debuffGroup = bc.groups.buffs, dc.groups.debuffs
        check("buff container holds the HELPFUL group of 32 and the three enchant slots", buffGroup
            and buffGroup.filter == "HELPFUL" and buffGroup.options.maxFrameCount == 32
            and bc.enchants[0] and bc.enchants[1] and bc.enchants[2] and bc.groupOrder[1] == "buffs")
        check("group layout spaces 30 px icons by 4 px", buffGroup.options.layout.elementSpacing == 4
            and buffGroup.options.layout.lineSpacing == 4 and buffGroup.options.layout.groupSpacing == 4
            and buffGroup.options.layout.elementWidth == 30 and buffGroup.options.layout.elementHeight == 30
            and bc.enchantLayout.elementWidth == 30 and bc.enchantLayout.elementSpacing == 4)
        check("debuff container holds the HARMFUL group of 16", debuffGroup and debuffGroup.filter == "HARMFUL"
            and debuffGroup.options.maxFrameCount == 16 and dc.enchants[0] == nil)

        local button = bc:GetAuraGroupFrame("buffs", 1)
        local registered = button.registered
        check("the decorator sizes the Blizzard button and registers the icon", button.kind == "AuraButton"
            and button.template == "CustomAuraButtonTemplate" and near(button.width, 30)
            and registered.icon and registered.icon.kind == "Texture" and registered.icon.parent == button
            and registered.icon.coords ~= nil)
        check("the count sits on an overlay above the cooldown and is registered", registered.count
            and registered.count.kind == "FontString" and registered.count.fontSize == 12
            and registered.count.parent ~= button and descendant(registered.count, button)
            and registered.count.parent.level == registered.cooldown:GetFrameLevel() + 1)
        check("the cooldown child shows countdown numbers and is registered", registered.cooldown
            and registered.cooldown.kind == "Cooldown" and registered.cooldown.parent == button
            and registered.cooldown.countdownHidden == false)
        check("buff buttons cancel on right click and keep the neutral border", button.cancelButtons == "RightButtonUp"
            and #registered.dispel == 0 and #button.border == 4 and color(button.border[1].color, module.Colors.buff))
        local enchant = bc.enchants[0].frame
        check("enchant buttons use the same decorator with cancel", enchant.registered.icon ~= nil
            and enchant.registered.cooldown ~= nil and enchant.cancelButtons == "RightButtonUp" and near(enchant.width, 30))
        local debuff = dc:GetAuraGroupFrame("debuffs", 1)
        check("debuff buttons register their four border lines as dispel textures without cancel",
            #debuff.registered.dispel == 4 and debuff.registered.dispel[1].texture == debuff.border[1]
            and debuff.registered.dispel[1].options.style == 3
            and debuff.registered.dispel[1].options.showWhenHarmful == true
            and debuff.registered.dispel[1].options.showWithoutDispelType == true
            and debuff.registered.dispel[1].options.showWhenHelpful == false and debuff.cancelButtons == nil)
        check("buttons keep the Blizzard scripts and start hidden", next(button.scripts) == nil
            and next(debuff.scripts) == nil and button.shown == false and button.alpha == nil)
        check("the module never reads auras itself", auraReads == 0)
        check("stock buff and debuff frames are parked with events dropped", BuffFrame.parent == RikUIHiddenFrames
            and DebuffFrame.parent == RikUIHiddenFrames and BuffFrame.unregistered == 1 and DebuffFrame.unregistered == 1)
        env.fire("UNIT_AURA", "player")
        env.fire("PLAYER_REGEN_ENABLED")
        check("aura events are left to the container", auraReads == 0 and #env.printed == 0)

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        local output = table.concat(env.printed, "\n")
        check("debug reports the containers and aura secrecy", output:find("Auras containers=2", 1, true)
            and output:find("auras.ShouldAurasBeSecret()", 1, true))

        module = load(nil, false, false, true)
        check("a missing container template warns once and leaves the stock frames alone",
            next(module.Rows) == nil and printedContains("Auras container") and #env.printed == 1
            and BuffFrame.parent == UIParent)
        module = load(nil, true)
        check("combat login defers container creation and stock hiding", next(module.Rows) == nil
            and BuffFrame.parent == UIParent)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("containers and stock hiding follow after combat", module.Rows.buffs ~= nil
            and module.Rows.buffs.container ~= nil and BuffFrame.parent == RikUIHiddenFrames)
        module = load({ modules = { auras = false } })
        check("disabled module leaves the stock frames alone", next(module.Rows) == nil and BuffFrame.parent == UIParent)
        module = load(nil, false, true)
        check("missing stock globals are tolerated", module.Rows.buffs ~= nil and #env.printed == 0)
    end)
    CreateFrame = originalCreate
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat, env.auraContainerMissing = false, false
    check("aura suite completes", ok, reason)
end
