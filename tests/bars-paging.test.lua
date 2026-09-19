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
        assert(condition, "missing page visibility driver")
        for clause in (condition .. ";"):gmatch("(.-);") do
            local hasConditions, matched = false, false
            for options in clause:gmatch("%[([^%]]+)%]") do
                hasConditions = true
                local page = tonumber(options:match("^bar:(%d+)"))
                local bonus = tonumber(options:match("bonusbar:(%d+)"))
                if page == selectedPage and (not bonus or bonus == offset) then matched = true end
            end
            if matched or not hasConditions then return clause:match("(%a+)%s*$") == "show" end
        end
    end
    local function mainOverlays(bars)
        local overlays = { bars.Frames.main }
        for _, bar in pairs(bars.Frames) do
            if bar.positionKey == "main" then overlays[#overlays + 1] = bar end
        end
        return overlays
    end
    local function verifyPages(bars, offset, combat)
        local overlays = mainOverlays(bars)
        for page = 1, 6 do
            local firstAction = (page - 1) * 12 + 1
            if page == 1 and offset == 1 then firstAction = 73 end
            local shown, active = 0, nil
            for _, bar in ipairs(overlays) do
                if visible(drivers[bar], offset, page) then shown, active = shown + 1, bar end
            end
            local label = "page " .. page .. " bonus " .. offset .. " combat " .. tostring(combat)
            check("exactly one modeled main overlay: " .. label, shown == 1)
            for index = 1, 12 do
                check("native slot agrees for button " .. index .. ": " .. label,
                    active and active.buttons[index]:GetAttribute("action") == firstAction + index - 1)
            end
        end
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
        check("base hides for the observed bonus page", not visible(drivers[main], 1, 1))
        for page = 2, 6 do
            local overlay = bars.Frames["page" .. page]
            check("manual page " .. page .. " creates fixed overlay", overlay ~= nil)
            if overlay then
                check("manual page " .. page .. " shares main layout", overlay.point[4] == 31
                    and overlay.point[5] == 59 and overlay.scale == 0.75)
            end
        end
        for _, combat in ipairs({ false, true }) do
            env.inCombat = combat
            local before = writes
            for _, offset in ipairs({ 0, 1 }) do verifyPages(bars, offset, combat) end
            env.fire("ACTIONBAR_PAGE_CHANGED")
            env.fire("UPDATE_BONUS_ACTIONBAR")
            check("page and stance events never rewrite protected attributes", writes == before)
        end
        check("manual page takes precedence over bonus visibility", not visible(drivers[battle], 1, 2))
        RikUI.Profile.positions.main.x = 90
        bars.ApplyLayout()
        check("combat layout remains queued", battle.point[4] == 31)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        for _, bar in ipairs(mainOverlays(bars)) do
            check("page " .. bar.key .. " follows main layout after combat", bar.point[4] == 90)
        end
        class = "MAGE"
        bars = loadBars()
        check("class without recorded bonus pages creates no bonus overlay", bars.Frames.battle == nil)
        verifyPages(bars, 0, false)
        class = "WARRIOR"
        bars = loadBars(true)
        check("combat login queues all paging construction", next(bars.Frames) == nil and next(drivers) == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("combat queue completes overlays before driver installation", bars.Frames.battle
            and drivers[bars.Frames.battle] == "[bar:1,bonusbar:1] show; hide")
        verifyPages(bars, 1, false)
        bars = loadBars(false, true)
        check("disabled bars register no paging drivers", next(drivers) == nil and next(bars.Frames) == nil)
        failRegistration = true
        bars = loadBars()
        check("failed driver installation restores base and removes every driver",
            bars.Frames.main:IsShown() and next(drivers) == nil)
        for _, bar in ipairs(mainOverlays(bars)) do
            if bar ~= bars.Frames.main then check("failed driver hides " .. bar.key, not bar:IsShown()) end
        end
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
