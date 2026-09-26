-- One strip: native entries in the client's order, collapsed to learned ranks, then the class
-- profile; drawn from duration objects with membership resolved outside combat.
return function(check)
    local env = require("wow_stub")
    local loader = dofile("tests/load_addon.lua").Loadfile
    local restoreWidgets = require("widget_stub").install()
    local saved = { C_Spell = C_Spell, UnitClass = UnitClass, CreateFrame = CreateFrame, GameTooltip = GameTooltip }
    local learned, cooldowns, charges, counts, reads = {}, {}, {}, {}, {}
    local scans, nativeList, nativeSource = 0, {}, "absent"
    CreateFrame = function(...)
        local frame = saved.CreateFrame(...)
        function frame:GetFrameLevel() return 1 end
        function frame:SetCooldownFromDurationObject(value, clear) self.duration, self.clearWhenDone = value, clear end
        function frame:Clear() self.duration = nil end
        function frame:GetCountdownFontString()
            self.font = self.font or self:CreateFontString()
            return self.font
        end
        return frame
    end
    local FAMILIES = { ["Shield Bash"] = { 72, 1671, 1672 }, ["Shield Wall"] = { 871 }, Pummel = { 6552, 6554 } }
    local function spellsStub()
        RikUI.Spells = {
            Entry = function(name, class)
                if class == "WARRIOR" and FAMILIES[name] then return { icon = 123, ranks = FAMILIES[name] } end
            end,
            FamilyOf = function(id)
                for name, ranks in pairs(FAMILIES) do
                    for rank, rankID in ipairs(ranks) do if rankID == id then return name, rank end end
                end
            end,
            HighestKnownRank = function(name)
                assert(not env.inCombat, "membership scan in combat")
                scans = scans + 1
                return learned[name]
            end,
            KnownIDs = function()
                local set = {}
                for key, id in pairs(learned) do
                    if type(id) == "number" then set[id] = true end
                    if key == "ids" then for _, extra in ipairs(id) do set[extra] = true end end
                end
                return set
            end,
        }
    end
    local function native(spellID, extra)
        local entry = { spellID = spellID, baseSpellID = spellID, strip = true, auraIDs = {} }
        for key, value in pairs(extra or {}) do entry[key] = value end
        return entry
    end
    local function load(disabled, combat)
        env.frames, env.printed, env.timers, env.inCombat = {}, {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = { modules = { cooldowns = not disabled } } } }, nil
        UnitClass = function() return "Warrior", "WARRIOR" end
        for _, path in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/ui/media.lua", "src/setup/setup.lua",
            "src/setup/setup-apply.lua", "src/layout/layout.lua", "src/modules/cooldowns/cooldowns.lua",
            "src/modules/cooldowns/cooldowns-strip.lua" }) do assert(loader(path))("RikUI", {}) end
        RikUI.ClassCooldownProfiles.WARRIOR = { "Shield Bash", "Shield Wall", "Pummel" }
        spellsStub()
        RikUI.Cooldowns.Native = { Enable = function() end, ViewerState = function() return "hidden" end,
            Read = function() if nativeList == nil then return nil, nativeSource end return nativeList, nativeSource end,
            AuraIDs = function() return { player = {}, target = {} } end }
        C_Spell = {
            GetSpellCooldownDuration = function(id, ignoreGCD) reads[id] = ignoreGCD; return cooldowns[id] end,
            GetSpellChargeDuration = function(id) return charges[id] end,
            GetSpellDisplayCount = function(id) return counts[id] or "" end,
            GetSpellTexture = function(id) return id end,
            GetSpellCooldown = function() error("raw cooldown data forbidden") end,
            GetSpellCharges = function() error("raw charges forbidden") end,
        }
        GameTooltip = { SetOwner = function() end, SetSpellByID = function(_, id) GameTooltip.id = id end,
            Show = function() end, Hide = function() end }
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Cooldowns
    end
    local function printed(text)
        for _, line in ipairs(env.printed) do if line:find(text, 1, true) then return true end end
        return false
    end
    local function ids(panel)
        local out = {}
        for index, button in ipairs(panel.Buttons) do out[index] = button.spellID end
        return table.concat(out, ",")
    end
    local ok, reason = pcall(function()
        learned = { ["Shield Bash"] = 1671, Pummel = 6552, ids = { 5000 } }
        cooldowns[1671], charges[1671], counts[1671] = env.SECRET, env.SECRET, env.SECRET
        -- Blizzard's list: rank 1 (learned twin), rank 2 again, an uncatalogued learned spell, an
        -- uncatalogued unlearned one, an item-only entry, an unlearned family and a tracked buff.
        nativeList = { native(72), native(1671), native(5000), native(5001), native(nil), native(871),
            { spellID = 7000, strip = false, auraIDs = { 7000 } } }
        nativeSource = "provider"
        local panel = load()
        check("native entries lead in the client's order, collapsed to learned ranks, then the profile",
            ids(panel) == "1671,5000,6552")
        local s = panel.Stats
        check("merge stats count every skip", s.native == 2 and s.profile == 1 and s.unlearned == 2
            and s.duplicates == 2 and s.itemOnly == 1 and s.capped == 0 and panel.Source == "provider")
        local first = panel.Buttons[1]
        check("strip registers the cooldowns layout key growing upward at rest size",
            RikUI.Layout.Groups.cooldowns ~= nil and RikUI.Layout.Groups.cooldowns.grow == "UP"
            and panel.Frame:GetWidth() == 280 and panel.Frame:GetHeight() == 76 and panel.Frame:IsShown())
        check("rows fill from the bottom and centre", first.points[1][1] == "BOTTOMLEFT" and first.points[1][4] == 82
            and first.points[1][5] == 0 and panel.Buttons[2].points[1][4] == 122)
        check("opaque durations go straight to native widgets and ignore GCD", first.cooldown.duration == env.SECRET
            and first.recharge.duration == env.SECRET and reads[1671] == true)
        check("secret counts go straight to text", first.count.text == env.SECRET)
        check("buttons are display only", not first.attributes.type and not first.scripts.OnClick)
        env.runScript(first, "OnEnter")
        check("tooltip uses the resolved learned rank", GameTooltip.id == 1671)
        env.printed = {}
        panel:Debug()
        check("debug line reports counts and sources", printed("Cooldowns: 3 icons (native=2, profile=1")
            and printed("provider=provider") and printed("native viewers=hidden"))

        local many, extra = {}, {}
        for index = 1, 25 do many[index] = native(10000 + index); extra[index] = 10000 + index end
        learned.ids = extra
        nativeList = many
        env.fire("SPELLS_CHANGED")
        check("the strip caps at three rows of seven and grows a third row", #panel.Buttons == 21
            and panel.Stats.capped == 6 and panel.Frame:GetHeight() == 116
            and panel.Buttons[8].points[1][5] == 40 and panel.Buttons[15].points[1][4] == 2)

        nativeList, nativeSource = nil, "unreadable spell field"
        env.printed = {}
        env.fire("SPELLS_CHANGED")
        check("an unreadable native list keeps the last complete strip", #panel.Buttons == 21
            and printed("Cooldowns spellbook: native entries unreadable spell field"))

        nativeList, nativeSource = {}, "absent"
        local before = scans
        env.inCombat = true
        env.fire("SPELLS_CHANGED"); env.fire("SPELLS_CHANGED")
        check("combat membership rebuilds coalesce without spellbook scans",
            RikUI.Combat.Pending() == 1 and #panel.Buttons == 21 and scans == before)
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat rebuilds from the profile alone when the client offers nothing",
            ids(panel) == "1671,6552" and panel.Source == "absent")

        learned = {}
        env.fire("SPELLS_CHANGED")
        check("nothing learned hides the strip", #panel.Buttons == 0 and not panel.Frame:IsShown())

        panel = load(false, true)
        check("combat login defers construction", panel.Frame == nil)
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        check("deferred construction completes", panel.Frame ~= nil)
        panel = load(true)
        check("disabled module creates no frames", panel.Frame == nil)
    end)
    for key, value in pairs(saved) do _G[key] = value end
    restoreWidgets()
    env.inCombat = false
    check("cooldown strip suite completes", ok, reason)
end
