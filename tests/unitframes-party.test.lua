-- Fixed party1-4 buttons. Native rendering, clicks, state drivers and secret errors need a beta check.
return function(check)
    local env = require("wow_stub")
    local originalCreate, originalDriver = CreateFrame, RegisterStateDriver
    local API = { "UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax", "UnitPowerType", "UnitClass",
        "UnitReaction", "UnitIsPlayer", "UnitLevel", "UnitName", "UnitThreatSituation", "GetThreatStatusColor",
        "UnitIsConnected", "UnitIsTapDenied", "UnitIsGroupLeader", "UnitGroupRolesAssigned", "UnitInRange",
        "PlayerFrame", "TargetFrame", "PetFrame", "TargetFrameToT", "PartyFrame", "CompactPartyFrame",
        "RAID_CLASS_COLORS", "FACTION_BAR_COLORS", "PowerBarColor" }
    local STOCK = { "PlayerFrame", "TargetFrame", "PetFrame", "TargetFrameToT", "PartyFrame", "CompactPartyFrame" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local units, writes, drivers, templates = {}, 0, {}, {}
    local function protected()
        assert(not InCombatLockdown(), "protected party frame write in combat")
        writes = writes + 1
    end
    local function capitalOnly(value)
        local methods = getmetatable(value).__index
        setmetatable(value, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
    end
    local function alphaSinks(value)
        function value:SetAlpha(alpha) self.alpha, self.fromBoolean = alpha, nil end
        function value:SetAlphaFromBoolean(flag, yes, no) self.alpha, self.fromBoolean = nil, { flag, yes, no } end
    end
    local function region(value)
        capitalOnly(value)
        alphaSinks(value)
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
        if template then protected(); templates[template] = true end
        local frame = originalCreate(kind, name, parent, template)
        capitalOnly(frame)
        alphaSinks(frame)
        frame.sets, frame.label, frame.owner = 0, name, parent
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
        return record[key]
    end
    UnitHealth = function(unit) return field(unit, "health") end
    UnitHealthMax = function(unit) return field(unit, "healthMax") end
    UnitPower = function(unit) return field(unit, "power") end
    UnitPowerMax = function(unit) return field(unit, "powerMax") end
    UnitPowerType = function(unit) return 0, field(unit, "powerToken"), 1, 0, 0 end
    UnitClass = function(unit) return "Class", field(unit, "class"), 1 end
    UnitReaction = function(unit) return field(unit, "reaction") end
    UnitIsPlayer = function(unit) return units[unit] ~= nil end
    UnitLevel = function(unit) return field(unit, "level") end
    UnitName = function(unit) return field(unit, "name"), nil end
    UnitThreatSituation = function(unit) return field(unit, "threat") end
    GetThreatStatusColor = function(status) return 0.1 * status, 0.5, 0.9 end
    UnitIsConnected = function(unit) return field(unit, "connected") ~= false end
    UnitIsTapDenied = function() return false end
    UnitIsGroupLeader = function(unit) return field(unit, "leader") end
    UnitGroupRolesAssigned = function(unit) return field(unit, "role") end
    UnitInRange = function(unit)
        if field(unit, "rangeError") then error("range unavailable") end
        return field(unit, "inRange"), field(unit, "checked")
    end
    RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 } }
    FACTION_BAR_COLORS = { [5] = { r = 0, g = 1, b = 0 } }
    PowerBarColor = { RAGE = { r = 1, g = 0, b = 0 }, MANA = { r = 0, g = 0, b = 1 } }
    local function stockFrame(name)
        local f = { parent = UIParent, events = { GROUP_ROSTER_UPDATE = true }, label = name }
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
        env.frames, env.printed, env.inCombat, writes, drivers, templates = {}, {}, false, 0, {}, {}
        RikUI, RikUIDB, RikUICharDB = nil, profile and { profiles = { Default = profile } } or nil, nil
        for _, name in ipairs(STOCK) do _G[name] = (not missingStock) and stockFrame(name) or nil end
        for _, file in ipairs({ "core.lua", "hide.lua", "media.lua", "setup.lua", "setup-apply.lua",
            "layout.lua", "unitframes.lua", "unitframes-status.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        -- A missing implementation is a red assertion rather than a crashed suite.
        local chunk = loadfile("unitframes-party.lua")
        if chunk then chunk("RikUI", {}) end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.UnitFrames
    end
    local function fixture()
        units = {
            player = { health = 1, healthMax = 2, power = 1, powerMax = 2, powerToken = "RAGE", name = "Probey",
                level = 12, class = "WARRIOR" },
            party1 = { health = env.SECRET, healthMax = env.SECRET, power = 40, powerMax = 80, powerToken = "MANA",
                name = "Healbot", level = 14, class = "PRIEST", leader = true, role = "HEALER",
                inRange = true, checked = true },
            party2 = { health = 30, healthMax = 90, power = 10, powerMax = 100, powerToken = "RAGE",
                name = "Tanky", level = 15, class = "WARRIOR", leader = false, role = "TANK",
                inRange = false, checked = true },
        }
    end
    local ok, reason = pcall(function()
        fixture()
        local module = load()
        local party = module.Party
        assert(party, "unitframes-party.lua did not register UnitFrames.Party")
        local holder, frames = party.Holder, party.Frames
        local one, two, three, four = frames[1], frames[2], frames[3], frames[4]
        check("four fixed secure unit buttons exist for party1-4", one and two and three and four
            and #frames == 4 and one.template == "SecureUnitButtonTemplate" and four.unit == "party4"
            and one.label == "RikUIUnit_party1")
        check("no group header template is used", templates.SecureGroupHeaderTemplate == nil
            and templates.SecureUnitButtonTemplate == true)
        check("left click targets and right click toggles the unit menu", two:GetAttribute("*type1") == "target"
            and two:GetAttribute("*type2") == "togglemenu" and two:GetAttribute("unit") == "party2"
            and table.concat(two.clicks, ",") == "AnyUp")
        check("each frame shows with its member and hides solo and in raids",
            drivers[one] == "[group:raid] hide; [@party1,exists] show; hide"
            and drivers[four] == "[group:raid] hide; [@party4,exists] show; hide")
        local groups = RikUI.Layout.Groups
        check("one holder registers with the layout under the party key", groups.party
            and groups.party.frames[1] == holder and #groups.party.frames == 1 and groups.party1 == nil)
        local defaults = groups.party.defaults
        check("the default sits on the left edge at middle height", defaults.point == "LEFT"
            and defaults.relativePoint == "LEFT" and defaults.x > 0 and defaults.x < 100 and defaults.y == 0)
        check("frames stack downwards inside the holder", one.owner == holder and one.point[1] == "TOPLEFT"
            and one.point[2] == holder and one.point[5] == 0 and two.point[5] < 0
            and near(three.point[5], 2 * two.point[5]) and near(four.point[5], 3 * two.point[5])
            and holder.height >= 4 * one.height and holder.width == one.width)
        check("secret member health reaches the bar unchanged", one.health.value == env.SECRET
            and one.health.max == env.SECRET)
        check("health is class coloured and power token coloured", color(one.health.color, RAID_CLASS_COLORS.PRIEST)
            and color(two.health.color, RAID_CLASS_COLORS.WARRIOR) and color(one.power.color, PowerBarColor.MANA)
            and one.power.value == 40)
        check("names use the shared font", one.name.text == "Healbot" and two.name.text == "Tanky"
            and one.name.fontPath == RikUI.Media.font)
        check("the leader icon marks only the leader", one.leader.shown == true and one.leader.alpha == 1
            and two.leader.shown == false and type(one.leader.texture) == "string")
        check("readable roles show a letter", one.role.text == "H" and two.role.text == "T" and three.role.text == "")
        check("in-range members are opaque and out-of-range members fade", one.alpha == 1
            and two.alpha == party.FadeAlpha and party.FadeAlpha > 0 and party.FadeAlpha < 1)

        units.party2.checked = false
        env.runScript(holder, "OnUpdate", 0.6)
        check("an unchecked range never fades", two.alpha == 1)
        units.party2.inRange, units.party2.checked = env.SECRET, env.SECRET
        env.printed = {}
        env.runScript(holder, "OnUpdate", 0.6)
        check("a secret range result goes to the boolean alpha sink uncompared", two.fromBoolean
            and two.fromBoolean[1] == env.SECRET and two.fromBoolean[2] == 1
            and two.fromBoolean[3] == party.FadeAlpha and #env.printed == 0)
        units.party2.rangeError = true
        env.runScript(holder, "OnUpdate", 0.6)
        env.runScript(holder, "OnUpdate", 0.6)
        check("a failing range read is contained, reported once and leaves the frame opaque", two.alpha == 1
            and printedContains("Unit frames range") and #env.printed == 1)
        units.party2.rangeError, units.party2.inRange, units.party2.checked = nil, false, true
        env.runScript(holder, "OnUpdate", 0.2)
        check("the range poll waits for its interval", two.alpha == 1)
        env.runScript(holder, "OnUpdate", 0.4)
        check("the range poll fades once the interval passes", two.alpha == party.FadeAlpha)

        units.party1.leader, units.party1.role = env.SECRET, env.SECRET
        env.printed = {}
        env.fire("PARTY_LEADER_CHANGED")
        check("a secret leader flag goes to the boolean alpha sink", one.leader.shown == true
            and one.leader.fromBoolean and one.leader.fromBoolean[1] == env.SECRET
            and one.leader.fromBoolean[2] == 1 and one.leader.fromBoolean[3] == 0 and #env.printed == 0)
        check("a secret role shows no letter", one.role.text == "")
        units.party1.leader, units.party2.leader, units.party1.role = false, true, "DAMAGER"
        env.fire("PARTY_LEADER_CHANGED")
        check("leader changes move the icon", one.leader.shown == false and two.leader.shown == true
            and one.role.text == "D")

        local oneSets = one.health.sets
        units.party2.health = 60
        env.fire("UNIT_HEALTH", "party2")
        check("unit events refresh only the matching member", two.health.value == 60 and one.health.sets == oneSets)
        units.party3 = { health = 5, healthMax = 9, power = 1, powerMax = 2, powerToken = "MANA", name = "Latecomer",
            level = 10, class = "PRIEST", leader = false, role = "NONE", inRange = true, checked = true }
        env.fire("GROUP_ROSTER_UPDATE")
        check("roster updates refresh every member", three.name.text == "Latecomer" and three.health.value == 5
            and three.role.text == "" and color(three.health.color, RAID_CLASS_COLORS.PRIEST))
        units.party2.threat = 3
        env.fire("UNIT_THREAT_SITUATION_UPDATE", "party2")
        check("threat borders work on members", two.threat[1].shown == true and near(two.threat[1].color[1], 0.3))

        local before = writes
        env.inCombat = true
        units.party2.health, units.party2.inRange = 10, true
        env.fire("UNIT_HEALTH", "party2")
        env.fire("GROUP_ROSTER_UPDATE")
        env.runScript(holder, "OnUpdate", 0.6)
        check("combat updates flow to sinks without protected writes", two.health.value == 10 and two.alpha == 1
            and writes == before)
        env.inCombat = false

        check("stock party frames are parked with events dropped", PartyFrame.parent == RikUIHiddenFrames
            and CompactPartyFrame.parent == RikUIHiddenFrames and PartyFrame.unregistered == 1)
        check("the core unit frames still build and park", module.Frames.player ~= nil
            and PlayerFrame.parent == RikUIHiddenFrames)

        fixture()
        module = load(nil, true)
        check("combat login defers party frames and stock parking", module.Party.Holder == nil
            and #module.Party.Frames == 0 and PartyFrame.parent == UIParent)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("party frames and parking follow after combat", #module.Party.Frames == 4
            and PartyFrame.parent == RikUIHiddenFrames)
        module = load({ modules = { unitframes = false } })
        check("disabled module builds nothing and leaves the stock party frame", #module.Party.Frames == 0
            and PartyFrame.parent == UIParent)
        module = load(nil, false, true)
        check("missing stock party globals are tolerated", #module.Party.Frames == 4 and #env.printed == 0)
    end)
    CreateFrame, RegisterStateDriver = originalCreate, originalDriver
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("party frame suite completes", ok, reason)
end
