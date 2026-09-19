-- The driver evaluator is a test model, not evidence of protected client behavior.
return function(check)
    local env = require("wow_stub")
    local originalCreate, originalDriver, originalClass = CreateFrame, RegisterStateDriver, UnitClass
    local originalUnregister = UnregisterStateDriver
    local drivers, writes, class, failRegistration = {}, 0, "WARRIOR", false
    local function protected()
        assert(not InCombatLockdown(), "protected paging write in combat")
        writes = writes + 1
    end
    CreateFrame = function(kind, name, parent, template)
        protected()
        local frame = originalCreate(kind, name, parent, template)
        local methods = getmetatable(frame).__index
        setmetatable(frame, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function frame:SetPoint(...) protected(); self.point = { ... } end
        function frame:ClearAllPoints() protected() end
        function frame:SetScale(value) protected(); self.scale = value end
        function frame:SetAttribute(key, value) protected(); self.attributes[key] = value end
        function frame:GetAlpha() return 0 end
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
        assert(state == "visibility", "only the native visibility driver is allowed")
        if failRegistration and frame.key == "main" then error("visibility unavailable") end
        drivers[frame] = condition
    end
    UnregisterStateDriver = function(frame)
        protected()
        drivers[frame] = nil
    end
    UnitClass = function() return class, class end
    local function loadBars(inCombat, disabled)
        env.frames, env.printed, env.inCombat = {}, {}, false
        drivers = {}
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = {
            modules = { bars = not disabled }, positions = { main = {
                point = "BOTTOM", relativePoint = "BOTTOM", x = 31, y = 59,
            } }, scale = 0.75,
        } } }, nil
        for _, file in ipairs({ "core.lua", "setup.lua", "setup-apply.lua", "data/bonus-pages.lua",
            "bars.lua", "bars-paging.lua", "bars-stock.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = inCombat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Bars
    end
    local function visible(condition, offset, selectedPage)
        local matched = selectedPage ~= 2 and condition:match("%[bar:1,bonusbar:" .. offset .. "%]")
        if matched then return condition:match("(%a+);") == "show" end
        return condition:match(";%s*(%a+)$") == "show"
    end
    local ok, reason = pcall(function()
        local bars = loadBars()
        local main, battle = bars.Frames.main, bars.Frames.battle
        check("observed Warrior Battle page creates overlay", battle ~= nil)
        assert(battle, "Battle overlay missing")
        check("probe-backed offset maps all fixed Battle slots", battle.firstAction == 73
            and battle.buttons[1]:GetAttribute("action") == 73
            and battle.buttons[12]:GetAttribute("action") == 84)
        check("Battle shares saved main position and scale", battle.point[4] == 31
            and battle.point[5] == 59 and battle.scale == 0.75)
        check("Battle receives only native visibility condition", drivers[battle] == "[bar:1,bonusbar:1] show; hide")
        check("base hides for the observed bonus page", drivers[main] == "[bar:1,bonusbar:1] hide; show")
        for _, combat in ipairs({ false, true }) do
            env.inCombat = combat
            local before = writes
            for _, offset in ipairs({ 0, 1 }) do
                local shown = 0
                for _, bar in ipairs({ main, battle }) do
                    if visible(drivers[bar], offset) then shown = shown + 1 end
                end
                check("exactly one modeled main page for offset " .. offset .. " combat " .. tostring(combat), shown == 1)
            end
            env.fire("UPDATE_BONUS_ACTIONBAR")
            check("stance event never rewrites protected attributes", writes == before)
        end
        check("manual page takes precedence over bonus visibility", not visible(drivers[battle], 1, 2))
        RikUI.Profile.positions.main.x = 90
        bars.ApplyLayout()
        check("combat layout remains queued", battle.point[4] == 31)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("all pages follow main layout after combat", battle.point[4] == 90 and main.point[4] == 90)
        class = "MAGE"
        bars = loadBars()
        check("class without recorded bonus pages creates no extra overlays", bars.Frames.battle == nil and next(drivers) == nil)
        class = "WARRIOR"
        bars = loadBars(true)
        check("combat login queues paging construction", bars.Frames.battle == nil and next(drivers) == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("combat queue completes overlays before driver installation", bars.Frames.battle
            and drivers[bars.Frames.battle] == "[bar:1,bonusbar:1] show; hide")
        bars = loadBars(false, true)
        check("disabled bars register no paging drivers", next(drivers) == nil and next(bars.Frames) == nil)
        failRegistration = true
        bars = loadBars()
        check("failed driver installation leaves base usable and extra overlay hidden",
            bars.Frames.main:IsShown() and not bars.Frames.battle:IsShown() and next(drivers) == nil)
        local reported = false
        for _, message in ipairs(env.printed) do
            if message:find("visibility unavailable", 1, true) then reported = true end
        end
        check("driver failure is reported explicitly", reported)
    end)
    CreateFrame, RegisterStateDriver, UnitClass = originalCreate, originalDriver, originalClass
    UnregisterStateDriver = originalUnregister
    env.inCombat = false
    check("paging suite completes", ok, reason)
end
