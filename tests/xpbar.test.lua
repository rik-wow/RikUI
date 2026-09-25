local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The bar's numbers may be secret for addon code on 69913 (unverified), so the suite checks both
-- the readable path and that a secret reaches the StatusBar sinks without arithmetic or a print.
return function(check)
    local env = require("wow_stub")
    local originalCreate = CreateFrame
    local API = { "UnitXP", "UnitXPMax", "GetXPExhaustion", "GameRulesUtil", "IsXPUserDisabled", "C_Reputation",
        "StatusTrackingBarManager", "UnitLevel", "GetTime" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local stub = {}
    local function animationGroup()
        local group = { plays = 0 }
        function group:CreateAnimation(kind)
            local animation = { kind = kind }
            function animation:SetFromAlpha(value) self.from = value end
            function animation:SetToAlpha(value) self.to = value end
            function animation:SetDuration(value) self.duration = value end
            function animation:SetOffset(x, y) self.offset = { x, y } end
            group.animation = animation
            return animation
        end
        function group:Stop() self.playing = false end
        function group:Play() self.plays = self.plays + 1; self.playing = true end
        return group
    end
    local function region(value)
        function value:SetTexture(texture) self.texture = texture end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
        function value:SetAlpha(alpha) self.alpha = alpha end
        function value:SetShown(shown) self.shown = shown end
        function value:CreateAnimationGroup() return animationGroup() end
        return value
    end
    CreateFrame = function(kind, name, parent, template)
        local frame = originalCreate(kind, name, parent, template)
        local methods = getmetatable(frame).__index
        setmetatable(frame, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function frame:SetParent(value)
            assert(not InCombatLockdown(), "frame reparented in combat")
            self.parent = value
        end
        function frame:GetParent() return self.parent end
        function frame:SetSize(w, h) self.width, self.height = w, h end
        function frame:SetHeight(h) self.height = h end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
        function frame:SetMinMaxValues(low, high) self.low, self.high = low, high end
        function frame:SetValue(value, easing) self.value, self.easing = value, easing end
        function frame:SetStatusBarTexture(texture) self.texture = texture end
        function frame:SetStatusBarColor(...) self.color = { ... } end
        function frame:CreateAnimationGroup() return animationGroup() end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        return frame
    end
    local function printedContains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function tooltipContains(text)
        if tostring(GameTooltip.text):find(text, 1, true) then return true end
        for _, line in ipairs(GameTooltip.lines) do
            if tostring(line.text):find(text, 1, true) then return true end
        end
        return false
    end
    local function hover(row)
        GameTooltip.lines, GameTooltip.text = {}, nil
        env.runScript(row, "OnEnter")
    end
    local function parked(frame) return frame.parent == RikUIHiddenFrames and RikUI.Hide.IsHidden(frame) end
    local function installClient()
        stub.now = 0
        GetTime = function() return stub.now end
        stub.xp, stub.xpMax, stub.rested, stub.capped, stub.disabled = 300, 1000, 200, false, false
        stub.faction, stub.xpError = nil, nil
        StatusTrackingBarManager = CreateFrame("Frame", "StatusTrackingBarManager", UIParent)
        UnitXP = function()
            if stub.xpError then error(stub.xpError) end
            return stub.xp
        end
        UnitXPMax = function() return stub.xpMax end
        GetXPExhaustion = function() return stub.rested end
        GameRulesUtil = { IsPlayerAtEffectiveMaxLevel = function() return stub.capped end }
        IsXPUserDisabled = function() return stub.disabled end
        C_Reputation = { GetWatchedFactionData = function() return stub.faction end }
    end
    local function load(profile, combat, prepare)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        installClient()
        if prepare then prepare() end
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes = false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/ui/motion.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua",
            "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua", "src/modules/unitframes/unitframes.lua", "src/modules/unitframes/unitframes-status.lua", "src/modules/xpbar/xpbar.lua", "src/modules/xpbar/xpbar-details.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.XPBar
    end
    local EASE, IMMEDIATE = Enum.StatusBarInterpolation.ExponentialEaseOut, Enum.StatusBarInterpolation.Immediate
    local HONORED = { factionID = 72, name = "Stormwind", reaction = 6, currentReactionThreshold = 3000,
        nextReactionThreshold = 9000, currentStanding = 4500 }
    local ok, reason = pcall(function()
        local module = load()
        local holder, group = module.Holder, RikUI.Layout.Groups.xpbar
        local xp, rep = module.Rows.xp, module.Rows.reputation
        check("the bar registers with the layout under key xpbar, hanging below the main bar", holder and group
            and group.frames[1] == holder and group.defaults.point == "TOP"
            and group.defaults.relativePoint == "BOTTOM" and group.defaults.x == 0)
        check("a levelling character sees one readable experience row and no reputation row", xp.shown == true
            and rep.shown == false and holder.shown == true and holder.height == 18 and holder.width == 498)
        check("the first fill lands without easing", xp.bar.low == 0 and xp.bar.high == 1000 and xp.bar.value == 300
            and xp.bar.easing == IMMEDIATE)
        check("the rested segment reaches to experience plus rested", xp.rested.shown == true
            and xp.rested.high == 1000 and xp.rested.value == 500)
        check("rows use the RikUI statusbar media, flat border and distinct rested colour",
            xp.bar.texture == RikUI.Media.statusbar and #xp.rikBorder == 4
            and xp.rikBorder[1].texture == RikUI.Media.border and xp.rested.color[3] ~= xp.bar.color[3])

        stub.xp = 450
        env.fire("PLAYER_XP_UPDATE", "player")
        check("an experience gain eases the fill and flashes the row", xp.bar.value == 450 and xp.bar.easing == EASE
            and xp.flashAnim.plays == 1 and xp.rested.value == 650)
        check("earned XP floats above the bar", xp.gainText and xp.gainText.text == "+150 XP"
            and xp.gainAnim and xp.gainAnim.plays == 1)
        env.fire("PLAYER_XP_UPDATE", "player")
        check("duplicate XP events do not replay the gain flash", xp.flashAnim.plays == 1)
        stub.xp = 460
        env.fire("PLAYER_XP_UPDATE", "pet")
        check("other units do not update the player XP bar", xp.bar.value == 450 and xp.flashAnim.plays == 1)
        stub.xp = 450
        check("detailed XP labels include remaining experience", xp.caption:GetText():find("550 to level", 1, true))
        module.SetOption("compact", true)
        check("compact mode restores thin bars and hides labels", holder.height == 8 and not xp.caption.shown)
        check("compact mode clears the floating gain", xp.gainText.alpha == 0 and not xp.gainAnim.playing)
        check("XP rise uses cosmetic translation", xp.gainAnim.animation.offset[2] == 14
            and xp.gainAnim.animation.duration == 0.85 and xp.gainAnim.plays == 1)
        module.SetOption("compact", false)
        RikUI.Profile.reducedMotion = true
        module.Details.ShowGain(xp, 999)
        check("global reduced motion suppresses existing gain animation", xp.gainAnim.plays == 1 and not xp.gainAnim.playing)
        RikUI.Profile.reducedMotion = false
        module.SetOption("text", false)
        check("labels can be disabled independently", holder.height == 18 and not xp.caption.shown)
        module.SetOption("text", true)
        module.SetOption("ticks", false)
        check("progress ticks can be disabled", not xp.ticks[1].shown)
        module.SetOption("ticks", true)
        module.SetOption("animations", false)
        stub.xp = 470
        env.fire("PLAYER_XP_UPDATE", "player")
        check("reduced motion uses immediate fill without flashing", xp.bar.easing == IMMEDIATE and xp.flashAnim.plays == 1)
        module.SetOption("animations", true)
        stub.xp = 450
        env.fire("PLAYER_XP_UPDATE", "player")
        check("XP correction does not count as a gain", xp.flashAnim.plays == 1)
        env.runScript(xp, "OnMouseUp", "RightButton")
        check("right-click toggles compact mode", RikUI.Profile.xpbar.compact == true)
        module.SetOption("compact", false)
        env.fire("PLAYER_LEVEL_UP", 13)
        check("level-up has its own highlight animation", xp.levelAnim.plays == 1)
        stub.rested = nil
        env.fire("UPDATE_EXHAUSTION")
        check("losing rested experience hides the rested segment without a flash", xp.rested.shown == false
            and xp.flashAnim.plays == 1)

        hover(xp)
        check("hovering the experience row shows the readable numbers", GameTooltip.owner == xp
            and tooltipContains("450 / 1000") and tooltipContains("45%") and tooltipContains("550 XP") and tooltipContains("Last gain: 20 XP"))
        stub.rested = 200
        hover(xp)
        check("the experience tooltip names the rested amount", tooltipContains("Rested") and tooltipContains("200"))

        stub.now = 120
        hover(xp)
        check("XP tooltip shows observed session total and hourly pace", tooltipContains("Session: 170 XP")
            and tooltipContains("5100 XP/hour") and tooltipContains("About 7 minutes"))
        check("session pace is opt-in without idle callbacks", not RikUI.Profile.xpbar.pace and not xp:GetScript("OnUpdate"))
        module.SetOption("pace", true)
        check("visible session pace includes rate and ETA", xp.caption:GetText():find("5100 XP/h", 1, true)
            and xp.caption:GetText():find("~7m to level", 1, true))
        stub.now = 240; env.runScript(xp, "OnUpdate", 1)
        RikUI.DB.profiles.PaceOff = { xpbar = { pace = false } }
        RikUI:SetProfile("PaceOff")
        check("profile switch turns pace off live", not xp:GetScript("OnUpdate") and xp.caption:GetText():find("550 to level", 1, true))
        RikUI:SetProfile("Default")
        check("profile switch restores pace without resetting session", xp:GetScript("OnUpdate") and xp.caption:GetText():find("2550 XP/h", 1, true))
        check("pace updates during idle time without XP events", xp.caption:GetText():find("2550 XP/h", 1, true)
            and xp.caption:GetText():find("~13m to level", 1, true))
        module.SetOption("compact", true)
        check("compact mode removes pace callback", not xp:GetScript("OnUpdate") and not xp.caption.shown)
        module.SetOption("compact", false)
        module.SetOption("text", false)
        check("hidden labels remove pace callback", not xp:GetScript("OnUpdate"))
        module.SetOption("text", true)
        module.SetOption("pace", false)
        check("normal label returns when pace disabled", xp.caption:GetText():find("550 to level", 1, true) and not xp:GetScript("OnUpdate"))
        module.SetOption("pace", true)
        local resetSession
        for _, option in ipairs(module.Options.settings) do if option.key == "resetSession" then resetSession = option end end
        check("XP session reset is available", resetSession ~= nil)
        if resetSession then
            resetSession.action()
            hover(xp)
            check("reset removes old gains without changing XP", tooltipContains("Session: 0 XP")
                and not tooltipContains("XP/hour") and stub.xp == 450)
            check("fresh pace label explicitly waits for data", xp.caption:GetText():find("Pace: gathering XP", 1, true))
            stub.now = -1
            env.runScript(xp, "OnUpdate", 1)
            check("backward clock displays unavailable pace", xp.caption:GetText():find("Pace unavailable", 1, true))
            hover(xp)
            check("clock rollback never produces invalid rate", not tooltipContains("XP/hour"))
        end
        stub.xp = env.SECRET
        env.fire("PLAYER_XP_UPDATE", "player")
        check("a secret experience value reaches the sink and drops the rested segment silently",
            xp.bar.value == env.SECRET and xp.rested.shown == false and #env.printed == 0)
        hover(xp)
        check("a secret experience value leaves the tooltip without numbers or errors",
            GameTooltip.owner == xp and not tooltipContains("/") and #env.printed == 0)
        stub.xp, stub.xpError = 450, "xp unavailable"
        env.fire("PLAYER_XP_UPDATE", "player")
        env.fire("PLAYER_XP_UPDATE", "player")
        check("a failing experience read is reported once and contained", printedContains("XP bar experience")
            and #env.printed == 1)
        stub.xpError, env.printed = nil, {}
        stub.now = 300
        hover(xp)
        check("unreadable XP gaps suppress session rate", tooltipContains("unreadable gaps") and not tooltipContains("XP/hour"))
        module.Refresh()
        check("visible pace identifies incomplete observations", xp.caption:GetText():find("Pace: gaps; reset session", 1, true))
        GetTime = function() error("clock unavailable") end
        hover(xp)
        check("missing clock does not abort XP tooltip", tooltipContains("Session:"))
        GetTime = function() return stub.now end

        stub.faction = HONORED
        env.fire("UPDATE_FACTION")
        check("a watched faction adds a reputation row under the experience row", rep.shown == true
            and holder.height == 32 and rep.bar.low == 3000 and rep.bar.high == 9000 and rep.bar.value == 4500)
        check("the reputation row fades in and takes its standing colour", rep.fade.plays == 1
            and rep.bar.color[2] > rep.bar.color[1])
        hover(rep)
        check("hovering the reputation row shows the faction and its progress", GameTooltip.owner == rep
            and tooltipContains("Stormwind") and tooltipContains("1500 / 6000"))
        check("watching a faction establishes a quiet baseline", rep.flashAnim.plays == 0)
        stub.faction = { factionID = 72, name = "Stormwind", reaction = 6,
            currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 4600 }
        env.fire("UPDATE_FACTION")
        check("reputation gains flash the watched bar", rep.flashAnim.plays == 1)
        env.fire("UPDATE_FACTION")
        stub.faction.currentStanding = 4550
        env.fire("UPDATE_FACTION")
        check("duplicate reputation events and losses stay quiet", rep.flashAnim.plays == 1)
        RikUI.Profile.reducedMotion = true
        stub.faction.currentStanding = 4700
        env.fire("UPDATE_FACTION")
        RikUI.Profile.reducedMotion = false
        env.fire("UPDATE_FACTION")
        check("reduced motion skips reputation gains without replay later", rep.flashAnim.plays == 1)
        stub.faction.factionID, stub.faction.currentStanding = 47, 5000
        env.fire("UPDATE_FACTION")
        check("switching watched factions never celebrates a gain", rep.flashAnim.plays == 1)
        stub.faction = { factionID = 72, name = "Stormwind", reaction = 8, currentReactionThreshold = 42000,
            nextReactionThreshold = 42000, currentStanding = 42000 }
        env.fire("UPDATE_FACTION")
        check("a capped standing draws a full bar", rep.bar.low == 0 and rep.bar.high == 1 and rep.bar.value == 1)
        stub.faction = { factionID = 72, name = "Stormwind", reaction = env.SECRET,
            currentReactionThreshold = env.SECRET, nextReactionThreshold = env.SECRET, currentStanding = env.SECRET }
        env.fire("UPDATE_FACTION")
        check("secret reputation values reach the sinks without printing", rep.bar.value == env.SECRET
            and rep.bar.high == env.SECRET and #env.printed == 0)

        check("unreadable reputation never produces a gain", rep.flashAnim.plays == 1)
        stub.faction = HONORED
        env.fire("UPDATE_FACTION")
        check("readable reputation after a gap rebaselines quietly", rep.flashAnim.plays == 1)
        stub.capped, stub.faction = true, HONORED
        env.fire("PLAYER_LEVEL_UP", 60)
        check("level cap removes pace update callback", not xp:GetScript("OnUpdate"))
        check("at the level cap only the reputation row remains", xp.shown == false and rep.shown == true
            and holder.shown == true and holder.height == 12)
        stub.faction = { factionID = 0 }
        env.fire("UPDATE_FACTION")
        check("the level cap without a watched faction hides the whole bar", holder.shown == false)
        stub.capped = false
        env.inCombat = true
        env.fire("PLAYER_XP_UPDATE", "player")
        env.inCombat = false
        check("the bar returns in combat without a protected write", holder.shown == true and xp.shown == true)
        stub.disabled = true
        env.fire("PLAYER_XP_UPDATE", "player")
        check("switched-off experience gain hides the experience row", holder.shown == false)

        check("the stock tracking bars are parked once the bar exists", parked(StatusTrackingBarManager))
        RikUI.Profile.showStockBars = true
        module.UpdateStock()
        check("showing stock bars returns the tracking bars", StatusTrackingBarManager.parent == UIParent)
        RikUI.Profile.showStockBars = false
        module.UpdateStock()
        check("hiding stock bars parks them again", parked(StatusTrackingBarManager))

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports the bar state", printedContains("XP bar holder=true"))

        module = load(nil, true)
        check("a combat login builds nothing and parks nothing", module.Holder == nil
            and StatusTrackingBarManager.parent == UIParent)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat builds the bar and parks the stock bars", module.Holder ~= nil
            and module.Rows.xp.bar.value == 300 and parked(StatusTrackingBarManager))

        module = load(nil, false, function() C_Reputation, GameRulesUtil, StatusTrackingBarManager = nil, nil, nil end)
        check("a client without the reputation and level-cap helpers still draws experience",
            module.Rows.xp.shown == true and module.Rows.reputation.shown == false and #env.printed == 0)

        module = load({ modules = { xpbar = false } })
        check("a disabled module leaves the stock tracking bars untouched", module.Holder == nil
            and StatusTrackingBarManager.parent == UIParent and RikUI.Layout.Groups.xpbar == nil)
    end)
    CreateFrame = originalCreate
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("xp bar suite completes", ok, reason)
end
