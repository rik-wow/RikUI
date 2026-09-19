-- Secret unit values must reach the sinks untouched; native rendering, clicks and menus need a beta check.
return function(check)
    local env = require("wow_stub")
    local originalCreate, originalDriver = CreateFrame, RegisterStateDriver
    local API = { "UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax", "UnitPowerType", "UnitClass",
        "UnitReaction", "UnitIsPlayer", "UnitLevel", "UnitName", "UnitExists", "UnitThreatSituation",
        "GetThreatStatusColor", "UnitIsConnected", "UnitIsTapDenied" }
    local STOCK = { "PlayerFrame", "TargetFrame", "PetFrame", "TargetFrameToT" }
    local saved, savedStock = {}, {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    for _, name in ipairs(STOCK) do savedStock[name] = _G[name] end
    local savedColors = { RAID_CLASS_COLORS, FACTION_BAR_COLORS, PowerBarColor }
    local units, writes, drivers = {}, 0, {}
    local function protected()
        assert(not InCombatLockdown(), "protected unit frame write in combat")
        writes = writes + 1
    end
    local function region(value)
        local methods = getmetatable(value).__index
        setmetatable(value, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function value:SetTexture(texture) self.texture = texture end
        function value:SetColorTexture(...) self.color = { ... } end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetShown(shown) self.shown = shown end
        function value:Show() self.shown = true end
        function value:Hide() self.shown = false end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        function value:SetText(text) self.text = text end
        function value:SetFormattedText(format, ...) self.format, self.args = format, { ... } end
        return value
    end
    CreateFrame = function(kind, name, parent, template)
        if template then protected() end
        local frame = originalCreate(kind, name, parent, template)
        local methods = getmetatable(frame).__index
        setmetatable(frame, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        frame.sets = 0
        function frame:SetAttribute(key, value) protected(); self.attributes[key] = value end
        function frame:SetSize(w, h) protected(); self.width, self.height = w, h end
        function frame:SetPoint(...) protected(); self.point = { ... } end
        function frame:ClearAllPoints() protected() end
        function frame:SetScale(value) protected(); self.scale = value end
        function frame:RegisterForClicks(...) self.clicks = { ... } end
        function frame:SetMinMaxValues(min, max) self.min, self.max = min, max end
        function frame:SetValue(value) self.value, self.sets = value, self.sets + 1 end
        function frame:SetStatusBarColor(...) self.color = { ... } end
        function frame:SetStatusBarTexture(texture) self.texture = texture end
        local show, hide = frame.Show, frame.Hide
        function frame:Show() protected(); show(self) end
        function frame:Hide() protected(); hide(self) end
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
    local function field(unit, key)
        local record = units[unit]
        if not record then return nil end
        if record.error then error("unit data unavailable") end
        return record[key]
    end
    UnitHealth = function(unit) return field(unit, "health") end
    UnitHealthMax = function(unit) return field(unit, "healthMax") end
    UnitPower = function(unit) return field(unit, "power") end
    UnitPowerMax = function(unit) return field(unit, "powerMax") end
    UnitPowerType = function(unit) return 1, field(unit, "powerToken"), 1, 0, 0 end
    UnitClass = function(unit) return "Class", field(unit, "class"), 1 end
    UnitReaction = function(unit, target) assert(target == "player"); return field(unit, "reaction") end
    UnitIsPlayer = function(unit) return field(unit, "isPlayer") end
    UnitLevel = function(unit) return field(unit, "level") end
    UnitName = function(unit) return field(unit, "name"), nil end
    UnitExists = function(unit) return units[unit] ~= nil end
    UnitThreatSituation = function(unit, mob) return field(mob or unit, "threat") end
    GetThreatStatusColor = function(status) return 0.1 * status, 0.5, 0.9 end
    UnitIsConnected = function(unit) return field(unit, "connected") ~= false end
    UnitIsTapDenied = function(unit) return field(unit, "tapped") == true end
    RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    FACTION_BAR_COLORS = { [2] = { r = 1, g = 0, b = 0 }, [4] = { r = 1, g = 1, b = 0 }, [5] = { r = 0, g = 1, b = 0 } }
    PowerBarColor = { RAGE = { r = 1, g = 0, b = 0 }, MANA = { r = 0, g = 0, b = 1 } }
    local function stockFrame(name)
        local f = { parent = UIParent, events = { UNIT_HEALTH = true }, label = name }
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
        return type(actual) == "table" and near(actual[1], expected.r) and near(actual[2], expected.g)
            and near(actual[3], expected.b)
    end
    local function load(profile, combat, missingStock)
        env.frames, env.printed, env.inCombat, writes, drivers = {}, {}, false, 0, {}
        RikUI, RikUIDB, RikUICharDB = nil, profile and { profiles = { Default = profile } } or nil, nil
        for _, name in ipairs(STOCK) do _G[name] = (not missingStock) and stockFrame(name) or nil end
        for _, file in ipairs({ "core.lua", "hide.lua", "media.lua", "setup.lua", "setup-apply.lua",
            "layout.lua", "unitframes.lua", "unitframes-status.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.UnitFrames
    end
    local function fixture()
        units = {
            player = { health = env.SECRET, healthMax = 100, power = env.SECRET, powerMax = 100, powerToken = "RAGE",
                name = "Probey", level = 12, isPlayer = true, class = "WARRIOR" },
            target = { health = env.SECRET, healthMax = env.SECRET, power = 30, powerMax = 60, powerToken = "MANA",
                name = "Kobold Vermin", level = 3, isPlayer = false, reaction = 2, threat = 3 },
            targettarget = { health = 7, healthMax = 9, power = 1, powerMax = 2, powerToken = "RAGE",
                name = "Probey", level = 12, isPlayer = true, class = "WARRIOR" },
        }
    end
    local ok, reason = pcall(function()
        fixture()
        local module = load()
        local frames = module.Frames
        local player, target, tot, pet = frames.player, frames.target, frames.tot, frames.petframe
        check("four secure unit buttons exist", player and target and tot and pet
            and player.template == "SecureUnitButtonTemplate" and pet.template == "SecureUnitButtonTemplate")
        check("left click targets and right click toggles the unit menu", player:GetAttribute("*type1") == "target"
            and player:GetAttribute("*type2") == "togglemenu" and target:GetAttribute("unit") == "target"
            and tot:GetAttribute("unit") == "targettarget" and pet:GetAttribute("unit") == "pet"
            and table.concat(player.clicks, ",") == "AnyUp")
        local groups = RikUI.Layout.Groups
        check("frames register with the shared layout", groups.player and groups.player.frames[1] == player
            and groups.target.frames[1] == target and groups.tot.frames[1] == tot and groups.petframe.frames[1] == pet)
        check("the pet frame does not share the pet action row's layout key", groups.pet == nil
            and RikUI.Setup.DefaultPositions.pet.y ~= groups.petframe.defaults.y)
        local dp, dt, dtot, dpet = groups.player.defaults, groups.target.defaults, groups.tot.defaults, groups.petframe.defaults
        check("defaults sit centre-bottom above the bars: player left, target right, ToT beyond target, pet beyond player",
            dp.point == "BOTTOM" and dp.x < 0 and dt.x > 0 and dp.y == dt.y and dtot.x > dt.x and dtot.y == dt.y
            and dpet.x < dp.x and dpet.y == dp.y and dpet.x == -dtot.x)
        check("setup layout step learns the unit frame keys", RikUI.Setup.DefaultPositions.tot ~= nil)
        GameTooltip.unit, GameTooltip.shown = nil, false
        env.runScript(target, "OnEnter")
        check("hovering a frame shows its unit tooltip at the default anchor", GameTooltip.unit == "target"
            and GameTooltip.owner == target and GameTooltip.anchorType == "ANCHOR_NONE"
            and rawget(GameTooltip, "point")[2] == GameTooltipDefaultContainer and GameTooltip.shown == true)
        GameTooltip.unit = nil
        target:UpdateTooltip()
        check("the owner refresh re-sets the unit while hovered", GameTooltip.unit == "target")
        env.runScript(target, "OnLeave")
        check("leaving hides the tooltip", GameTooltip.shown == false)
        local setUnit = GameTooltip.SetUnit
        GameTooltip.SetUnit = function() error("unit tooltip unavailable") end
        env.printed = {}
        env.runScript(pet, "OnEnter")
        env.runScript(player, "OnEnter")
        check("a failing unit tooltip is reported once and contained", printedContains("Unit frames tooltip")
            and #env.printed == 1)
        GameTooltip.SetUnit = setUnit
        check("secret player health reaches the bar and text unchanged", player.health.value == env.SECRET
            and player.health.min == 0 and player.health.max == 100 and player.health.text.format == "%d / %d"
            and player.health.text.args[1] == env.SECRET and player.health.text.args[2] == 100)
        check("secret target maximum reaches SetMinMaxValues", target.health.max == env.SECRET
            and target.health.value == env.SECRET)
        check("secret player power fills the power bar", player.power.value == env.SECRET
            and player.power.text.args[1] == env.SECRET)
        check("readable target power shows current / max", target.power.value == 30 and target.power.max == 60
            and target.power.text.format == "%d / %d" and target.power.text.args[1] == 30
            and target.power.text.args[2] == 60)
        check("no percent is computed anywhere", not tostring(player.health.text.format):find("%%%%")
            and not tostring(target.health.text.format):find("%%%%"))
        check("players are class coloured", color(player.health.color, RAID_CLASS_COLORS.WARRIOR)
            and color(tot.health.color, RAID_CLASS_COLORS.WARRIOR))
        check("NPCs are reaction coloured", color(target.health.color, FACTION_BAR_COLORS[2]))
        check("power bars use the power token colour", color(player.power.color, PowerBarColor.RAGE)
            and color(target.power.color, PowerBarColor.MANA))
        check("name and level text use the shared font", player.name.text == "Probey"
            and player.name.fontPath == RikUI.Media.font and player.level.format == "%d" and player.level.args[1] == 12
            and target.level.args[1] == 3 and target.name.text == "Kobold Vermin")
        check("bars use the shared statusbar media", player.health.texture == RikUI.Media.statusbar
            and pet.power.texture == RikUI.Media.statusbar)
        check("readable threat colours the target border", target.threat[1].shown == true
            and near(target.threat[1].color[1], 0.3) and near(target.threat[1].color[2], 0.5)
            and #target.threat == 4)
        check("absent threat hides the player border", player.threat[1].shown == false)
        check("target, ToT and pet visibility come from state drivers", drivers[target] == "[@target,exists] show; hide"
            and drivers[tot] == "[@targettarget,exists] show; hide" and drivers[pet] == "[@pet,exists] show; hide"
            and drivers[player] == nil)
        check("stock unit frames are parked with events dropped", PlayerFrame.parent == RikUIHiddenFrames
            and TargetFrame.parent == RikUIHiddenFrames and PetFrame.parent == RikUIHiddenFrames
            and TargetFrameToT.parent == RikUIHiddenFrames and PlayerFrame.unregistered == 1
            and TargetFrameToT.unregistered == 1)

        local playerSets, targetSets = player.power.sets, target.power.sets
        units.target.power = 45
        env.fire("UNIT_POWER_UPDATE", "target", "MANA")
        check("power events refresh only the matching unit", target.power.value == 45
            and target.power.sets == targetSets + 1 and player.power.sets == playerSets)
        units.target.health, units.target.healthMax = 20, 50
        env.fire("UNIT_HEALTH", "target")
        check("health events refresh the matching unit", target.health.value == 20 and target.health.max == 50
            and target.health.text.args[1] == 20 and target.health.text.args[2] == 50)
        units.player.level = 13
        env.fire("UNIT_LEVEL", "player")
        check("level events refresh level text", player.level.args[1] == 13)
        units.target.level = -1
        env.fire("UNIT_LEVEL", "target")
        check("unknown levels show ??", target.level.text == "??")
        units.target.powerToken = "RAGE"
        env.fire("UNIT_DISPLAYPOWER", "target")
        check("display power events recolour the power bar", color(target.power.color, PowerBarColor.RAGE))

        local before = writes
        env.inCombat = true
        units.player.health = 55
        units.target.threat = 2
        env.fire("UNIT_HEALTH", "player")
        env.fire("UNIT_THREAT_SITUATION_UPDATE", "target")
        env.fire("PLAYER_TARGET_CHANGED")
        check("combat updates flow to sinks without protected writes", player.health.value == 55
            and near(target.threat[1].color[1], 0.2) and writes == before)
        env.inCombat = false

        units.target.threat = env.SECRET
        env.printed = {}
        env.fire("UNIT_THREAT_SITUATION_UPDATE", "target")
        check("secret threat leaves the border hidden without errors", target.threat[1].shown == false
            and #env.printed == 0)
        units.target.threat = 0
        env.fire("UNIT_THREAT_SITUATION_UPDATE", "target")
        check("zero threat hides the border", target.threat[1].shown == false)
        units.target.threat = 1
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat rereads threat", target.threat[1].shown == true and near(target.threat[1].color[1], 0.1))

        units.player.class = env.SECRET
        env.fire("UNIT_FACTION", "player")
        check("secret class token falls back to the neutral colour", color(player.health.color, module.Colors.neutral)
            and #env.printed == 0)
        units.player.class = "MONK"
        env.fire("UNIT_FACTION", "player")
        check("unknown class token falls back to the neutral colour", color(player.health.color, module.Colors.neutral))
        units.player.class = "WARRIOR"
        units.target.reaction = env.SECRET
        env.fire("UNIT_FACTION", "target")
        check("secret reaction falls back to the neutral colour", color(target.health.color, module.Colors.neutral))
        units.target.reaction = 4
        env.fire("UNIT_FACTION", "target")
        check("reaction changes recolour", color(target.health.color, FACTION_BAR_COLORS[4]))
        units.target.tapped = true
        env.fire("UNIT_FACTION", "target")
        check("tapped units are grey", color(target.health.color, module.Colors.tapped))
        units.target.tapped, units.target.connected = nil, false
        env.fire("UNIT_CONNECTION", "target")
        check("disconnected units are grey", color(target.health.color, module.Colors.disconnected))
        units.target.connected = nil
        units.target.powerToken = env.SECRET
        env.fire("UNIT_DISPLAYPOWER", "target")
        check("secret power token falls back to the neutral power colour", color(target.power.color, module.Colors.power))

        units.targettarget.name = "Rat"
        env.fire("UNIT_TARGET", "target")
        check("target's target changes refresh the ToT frame", tot.name.text == "Rat")
        units.targettarget.name = "Bat"
        env.fire("PLAYER_TARGET_CHANGED")
        check("target changes refresh the ToT frame", tot.name.text == "Bat")
        units.targettarget.health = 8
        env.runScript(tot, "OnUpdate", 0.6)
        check("the ToT frame polls like Blizzard's", tot.health.value == 8)
        units.pet = { health = 3, healthMax = 4, power = 5, powerMax = 6, powerToken = "MANA", name = "Wolf",
            level = 12, isPlayer = false, reaction = 5 }
        env.fire("UNIT_PET", "player")
        check("pet events refresh the pet frame", pet.name.text == "Wolf" and pet.health.value == 3
            and color(pet.health.color, FACTION_BAR_COLORS[5]))
        env.fire("UNIT_HEALTH", env.SECRET)
        check("a secret event unit refreshes every frame without error", target.health.value == 20)

        units.target.error = true
        env.printed = {}
        env.fire("UNIT_HEALTH", "target")
        env.fire("UNIT_HEALTH", "target")
        check("reader failures are reported once and contained", printedContains("Unit frames health")
            and #env.printed == 1)
        units.target.error = nil

        units.player.health = env.SECRET
        env.printed = {}
        SlashCmdList.RIKUI("debug")
        local output = table.concat(env.printed, "\n")
        check("debug reports dependency secrecy without values", output:find("unitframes.UnitHealth(player)[1] secret=true", 1, true)
            and output:find("unitframes.UnitPower(player)[1] secret=true", 1, true)
            and output:find("unitframes.UnitHealth(target)[1] secret=false", 1, true)
            and output:find("unitframes.UnitThreatSituation(player)", 1, true)
            and output:find("unitframes.UnitClass(target)[2] secret=false", 1, true)
            and output:find("unitframes.UnitReaction(target)", 1, true)
            and not output:find("<secret>", 1, true))

        fixture()
        module = load(nil, true)
        check("combat login defers frame creation and stock hiding", next(module.Frames) == nil
            and PlayerFrame.parent == UIParent)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("frames and stock hiding follow after combat", module.Frames.player ~= nil
            and PlayerFrame.parent == RikUIHiddenFrames)
        module = load({ modules = { unitframes = false } })
        check("disabled module leaves stock frames alone", next(module.Frames) == nil
            and PlayerFrame.parent == UIParent)
        module = load(nil, false, true)
        check("missing stock globals are tolerated", module.Frames.player ~= nil and #env.printed == 0)
    end)
    CreateFrame, RegisterStateDriver = originalCreate, originalDriver
    for name, value in pairs(saved) do _G[name] = value end
    for _, name in ipairs(STOCK) do _G[name] = savedStock[name] end
    RAID_CLASS_COLORS, FACTION_BAR_COLORS, PowerBarColor = savedColors[1], savedColors[2], savedColors[3]
    env.inCombat = false
    check("unit frame suite completes", ok, reason)
end
