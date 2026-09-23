local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Fixed raid1-40 grid. Native rendering, clicks, state drivers and stock parking need a beta check.
return function(check)
    local env = require("wow_stub")
    local animate = dofile("tests/group_motion_stub.lua")
    local savedEnum = Enum
    Enum = { StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 2 } }
    local originalCreate, originalDriver = CreateFrame, RegisterStateDriver
    local API = { "UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax", "UnitPowerType", "UnitClass",
        "UnitReaction", "UnitExists", "UnitIsPlayer", "UnitLevel", "UnitName", "UnitThreatSituation", "GetThreatStatusColor",
        "UnitIsConnected", "UnitIsTapDenied", "UnitIsGroupLeader", "UnitGroupRolesAssigned", "UnitInRange",
        "CompactRaidFrameContainer", "CompactRaidFrameManager", "RAID_CLASS_COLORS", "FACTION_BAR_COLORS",
        "PowerBarColor" }
    local STOCK = { "CompactRaidFrameContainer", "CompactRaidFrameManager" }
    local PARTY_DRIVER = "[group:raid] hide; [@party1,exists] show; hide"
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local units, writes, drivers, templates = {}, 0, {}, {}
    local function protected()
        assert(not InCombatLockdown(), "protected raid frame write in combat")
        writes = writes + 1
    end
    -- The stub answers unknown keys with a no-op; lowercase fields must read as nil.
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
        animate(value)
        alphaSinks(value)
        function value:SetText(text) self.text = text end
        function value:SetFormattedText(format, ...) self.format, self.args = format, { ... } end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        function value:Show() self.shown = true end
        function value:Hide() self.shown = false end
        return value
    end
    CreateFrame = function(kind, name, parent, template)
        if template then protected(); templates[template] = true end
        local frame = originalCreate(kind, name, parent, template)
        capitalOnly(frame)
        animate(frame)
        function frame:EnableMouse(enabled) self.mouseEnabled = enabled end
        function frame:GetAlpha() error("do not read secret range alpha") end
        function frame:GetValue() error("do not read unit values") end
        alphaSinks(frame)
        local show, hide = frame.Show, frame.Hide
        function frame:Show() if template then protected() end; show(self) end
        function frame:Hide() if template then protected() end; hide(self) end
        frame.sets, frame.label, frame.owner = 0, name, parent
        function frame:SetAttribute(key, value) protected(); self.attributes[key] = value end
        function frame:SetSize(w, h) protected(); self.width, self.height = w, h end
        function frame:SetPoint(...) protected(); self.point = { ... } end
        function frame:SetMinMaxValues(min, max) self.min, self.max = min, max end
        function frame:SetValue(value, easing) self.value, self.easing, self.sets = value, easing, self.sets + 1 end
        function frame:SetStatusBarColor(...) self.color = { ... } end
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
    UnitExists = function(unit) return units[unit] ~= nil end
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
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/ui/motion.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua",
            "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua", "src/modules/unitframes/unitframes.lua", "src/modules/unitframes/unitframes-status.lua", "src/modules/unitframes/unitframes-motion.lua", "src/modules/unitframes/unitframes-party.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        -- A missing implementation is a red assertion rather than a crashed suite.
        local chunk = loadfile("src/modules/unitframes/unitframes-raid.lua")
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
            raid1 = { health = env.SECRET, healthMax = env.SECRET, power = 40, powerMax = 80, powerToken = "MANA",
                name = "Healbot", level = 14, class = "PRIEST", inRange = true, checked = true },
            raid2 = { health = 30, healthMax = 90, power = 10, powerMax = 100, powerToken = "RAGE",
                name = "Tanky", level = 15, class = "WARRIOR", inRange = false, checked = true },
        }
    end
    local ok, reason = pcall(function()
        fixture()
        local module = load()
        local raid = module.Raid
        assert(raid, "src/modules/unitframes/unitframes-raid.lua did not register UnitFrames.Raid")
        local holder, frames = raid.Holder, raid.Frames
        local one, two, five, six, last = frames[1], frames[2], frames[5], frames[6], frames[40]
        dofile("tests/group_motion_checks.lua")(check, env, module, raid, units, "raid")
        check("forty fixed secure unit buttons exist for raid1-40", #frames == 40 and one and last
            and one.template == "SecureUnitButtonTemplate" and last.unit == "raid40"
            and one.label == "RikUIUnit_raid1" and last:GetAttribute("unit") == "raid40")
        check("the raid grid uses no group header template", templates.SecureGroupHeaderTemplate == nil)
        check("each slot shows only while its raid unit exists", drivers[one] == "[@raid1,exists] show; hide"
            and drivers[last] == "[@raid40,exists] show; hide")
        check("party frames keep hiding in a raid and return when it ends",
            drivers[module.Party.Frames[1]] == PARTY_DRIVER)
        local groups = RikUI.Layout.Groups
        check("one raid holder registers with the layout under its own key", groups.raid
            and groups.raid.frames[1] == holder and #groups.raid.frames == 1 and groups.raid1 == nil)
        local defaults, partyDefaults = groups.raid.defaults, groups.party.defaults
        check("the raid grid has its own place at the top left and never blocks the party frames it replaces",
            defaults.point == "TOPLEFT" and defaults.x == 20 and defaults.y == -120
            and groups.raid.exclusive == "group" and groups.party.exclusive == "group")
        check("the party frames keep theirs", partyDefaults.point == "LEFT"
            and partyDefaults.x == 20 and partyDefaults.y == 0)
        check("slots fill columns of five from the top left", one.owner == holder and one.point[1] == "TOPLEFT"
            and one.point[2] == holder and one.point[4] == 0 and one.point[5] == 0
            and five.point[4] == 0 and near(five.point[5], 4 * two.point[5]) and two.point[5] < 0
            and six.point[4] > 0 and six.point[5] == 0)
        check("the grid is eight columns wide and the holder covers it", near(last.point[4], 7 * six.point[4])
            and near(last.point[5], five.point[5]) and near(holder.width, last.point[4] + one.width)
            and near(holder.height, one.height - five.point[5]))
        check("secret member health reaches the bar unchanged", one.health.value == env.SECRET
            and one.health.max == env.SECRET)
        check("raid health is class coloured", color(one.health.color, RAID_CLASS_COLORS.PRIEST)
            and color(two.health.color, RAID_CLASS_COLORS.WARRIOR))
        check("raid names use the shared font and the small frame drops level and health text",
            one.name.text == "Healbot" and one.name.fontPath == RikUI.Media.font
            and one.level.shown == false and one.health.text.shown == false)
        check("in-range raid members are opaque and out-of-range members fade", one.presentation.alpha == 1
            and two.presentation.alpha == raid.FadeAlpha and raid.FadeAlpha > 0 and raid.FadeAlpha < 1)

        units.raid2.inRange, units.raid2.checked = env.SECRET, env.SECRET
        env.printed = {}
        env.runScript(holder, "OnUpdate", 0.6)
        check("a secret raid range result goes to the boolean alpha sink uncompared", two.presentation.fromBoolean
            and two.presentation.fromBoolean[1] == env.SECRET and two.presentation.fromBoolean[3] == raid.FadeAlpha and #env.printed == 0)
        units.raid2.rangeError = true
        env.runScript(holder, "OnUpdate", 0.6)
        env.runScript(holder, "OnUpdate", 0.6)
        check("a failing raid range read is reported once and leaves the frame opaque", two.presentation.alpha == 1
            and printedContains("Unit frames range") and #env.printed == 1)
        units.raid2.rangeError, units.raid2.inRange, units.raid2.checked = nil, false, true
        env.runScript(holder, "OnUpdate", 0.2)
        check("the raid range poll waits for its interval", two.presentation.alpha == 1)
        env.runScript(holder, "OnUpdate", 0.4)
        check("the raid range poll fades once the interval passes", two.presentation.alpha == raid.FadeAlpha)


        local readRange, rangeReads, visibility = UnitInRange, 0, {}
        UnitInRange = function(unit) rangeReads = rangeReads + 1; return readRange(unit) end
        for _, frame in ipairs(frames) do
            visibility[frame] = rawget(frame, "IsVisible")
            frame.IsVisible = function() return false end
        end
        env.runScript(holder, "OnUpdate", 0.6)
        check("hidden raid members perform no range API reads", rangeReads == 0)
        one.IsVisible = function() return true end
        rangeReads = 0
        env.runScript(holder, "OnUpdate", 0.6)
        check("range polling reads only the visible member", rangeReads == 1)
        two.IsVisible = function() return env.SECRET end
        rangeReads = 0
        env.runScript(holder, "OnUpdate", 0.6)
        check("secret visibility keeps range updates without comparison", rangeReads == 2)
        for _, frame in ipairs(frames) do frame.IsVisible = visibility[frame] end
        UnitInRange = readRange

        local oneSets = one.health.sets
        units.raid2.health = 60
        env.fire("UNIT_HEALTH", "raid2")
        check("unit events refresh only the matching raid member", two.health.value == 60
            and one.health.sets == oneSets)
        units.raid3 = { health = 5, healthMax = 9, power = 1, powerMax = 2, powerToken = "MANA",
            name = "Latecomer", level = 10, class = "PRIEST", inRange = true, checked = true }
        env.fire("GROUP_ROSTER_UPDATE")
        check("roster updates refresh every raid slot", frames[3].name.text == "Latecomer"
            and frames[3].health.value == 5 and color(frames[3].health.color, RAID_CLASS_COLORS.PRIEST))
        units.raid2.threat = 3
        env.fire("UNIT_THREAT_SITUATION_UPDATE", "raid2")
        check("threat borders work on raid members", two.threat[1].shown == true)

        local before = writes
        env.inCombat = true
        units.raid2.health, units.raid2.inRange = 10, true
        env.fire("UNIT_HEALTH", "raid2")
        env.fire("GROUP_ROSTER_UPDATE")
        env.runScript(holder, "OnUpdate", 0.6)
        check("combat raid updates flow to sinks without protected writes", two.health.value == 10
            and two.presentation.alpha == 1 and writes == before)
        env.inCombat = false

        check("the stock raid container is parked with events dropped",
            CompactRaidFrameContainer.parent == RikUIHiddenFrames and CompactRaidFrameContainer.unregistered == 1)
        check("the stock raid manager stays where Blizzard put it", CompactRaidFrameManager.parent == UIParent
            and CompactRaidFrameManager.unregistered == nil)

        fixture()
        module = load(nil, true)
        check("combat login defers the raid grid and stock parking", module.Raid.Holder == nil
            and #module.Raid.Frames == 0 and CompactRaidFrameContainer.parent == UIParent)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("the raid grid and parking follow after combat", #module.Raid.Frames == 40
            and CompactRaidFrameContainer.parent == RikUIHiddenFrames)
        module = load({ modules = { unitframes = false } })
        check("disabled module builds no raid grid and leaves the stock container", #module.Raid.Frames == 0
            and CompactRaidFrameContainer.parent == UIParent)
        _G.RikTestAnimationsMissing = true
        module = load()
        local plain = module.Raid.Frames[1]
        check("raid missing animation APIs preserve static fills", plain.health.value == env.SECRET
            and plain.motion.fade == nil and plain.motion.range == nil)
        plain:Hide()
        check("raid fallback leave hides art immediately", not plain.presence:IsShown())
        plain:Show()
        check("raid fallback rejoin restores art", plain.presence:IsShown() and plain.health.easing == 0)
        _G.RikTestAnimationsMissing = nil
        module = load(nil, false, true)
        check("missing stock raid globals are tolerated", #module.Raid.Frames == 40 and #env.printed == 0)
    end)
    _G.RikTestAnimationsMissing = nil
    Enum = savedEnum
    CreateFrame, RegisterStateDriver = originalCreate, originalDriver
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("raid frame suite completes", ok, reason)
end
