-- The client's cooldown manager as a data source: provider and API reads, the cvar that keeps
-- its viewers hidden, its data-changed callback and the aura ID sets for the effect rows.
return function(check)
    local env = require("wow_stub")
    local loader = dofile("tests/load_addon.lua").Loadfile
    local restoreWidgets = require("widget_stub").install()
    local saved = { C_Spell = C_Spell, UnitClass = UnitClass, CreateFrame = CreateFrame, C_CVar = C_CVar,
        CooldownViewerSettings = CooldownViewerSettings, C_CooldownViewer = C_CooldownViewer,
        EventRegistry = EventRegistry, ShowUIPanel = ShowUIPanel, InCombatLockdown = InCombatLockdown }
    local savedCategories = Enum.CooldownViewerCategory
    local baseCreate = CreateFrame
    CreateFrame = function(...)
        local frame = baseCreate(...)
        function frame:GetFrameLevel() return 1 end
        function frame:SetCooldownFromDurationObject(value) self.duration = value end
        function frame:Clear() self.duration = nil end
        function frame:GetCountdownFontString()
            self.font = self.font or self:CreateFontString()
            return self.font
        end
        return frame
    end
    local CATEGORIES = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3, HiddenActive = -1, HiddenPassive = -2 }
    local FAMILIES = { ["Shield Bash"] = { 72, 1671, 1672 }, ["Shield Wall"] = { 871 }, Pummel = { 6552, 6554 } }
    local learned = { ["Shield Bash"] = 1671, Pummel = 6552, ids = { 5000 } }
    local cvar, cvarWrites, lists, infos, layoutLoaded, callbacks, shown = "1", 0, {}, {}, true, {}, 0
    local provider = {
        GetOrderedCooldownIDsForCategory = function(_, category) return lists[category] or {} end,
        GetCooldownInfoForID = function(_, id) return infos[id] end,
        GetLayoutManager = function() return layoutLoaded and {} or false end,
    }
    local function spellsStub()
        RikUI.Spells = {
            Entry = function(name, class) if class == "WARRIOR" and FAMILIES[name] then return { icon = 1, ranks = FAMILIES[name] } end end,
            FamilyOf = function(id)
                for name, ranks in pairs(FAMILIES) do
                    for rank, rankID in ipairs(ranks) do if rankID == id then return name, rank end end
                end
            end,
            HighestKnownRank = function(name) return learned[name] end,
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
    local function load(profile, charDB)
        env.frames, env.printed, env.timers, env.inCombat = {}, {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile or { modules = {} } } }, charDB
        UnitClass = function() return "Warrior", "WARRIOR" end
        Enum.CooldownViewerCategory = CATEGORIES
        C_CVar = {
            GetCVarBool = function(name) assert(name == "cooldownViewerEnabled"); return cvar == "1" end,
            SetCVar = function(name, value)
                assert(not env.inCombat and name == "cooldownViewerEnabled")
                cvar, cvarWrites = value, cvarWrites + 1
                env.fire("CVAR_UPDATE", name, value)
            end,
        }
        CooldownViewerSettings = { GetDataProvider = function() return provider end }
        C_CooldownViewer = nil
        EventRegistry = { RegisterCallback = function(_, event, fn) callbacks[event] = fn end }
        ShowUIPanel = function(frame) assert(frame == CooldownViewerSettings); shown = shown + 1 end
        C_Spell = { GetSpellCooldownDuration = function() return env.SECRET end,
            GetSpellChargeDuration = function() return env.SECRET end,
            GetSpellDisplayCount = function() return env.SECRET end, GetSpellTexture = function(id) return id end }
        for _, path in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/ui/media.lua", "src/setup/setup.lua",
            "src/setup/setup-apply.lua", "src/layout/layout.lua", "src/modules/cooldowns/cooldowns.lua",
            "src/modules/cooldowns/cooldowns-strip.lua", "src/modules/cooldowns/cooldowns-native.lua" }) do
            assert(loader(path))("RikUI", {})
        end
        RikUI.ClassCooldownProfiles.WARRIOR = { "Shield Bash", "Shield Wall", "Pummel" }
        spellsStub()
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return RikUI.Cooldowns
    end
    local function info(spellID, extra)
        local row = { spellID = spellID, hasAura = false, selfAura = false, flags = 0, isKnown = true, isInvisible = false }
        for key, value in pairs(extra or {}) do row[key] = value end
        return row
    end
    local function ids(panel)
        local out = {}
        for index, button in ipairs(panel.Buttons) do out[index] = button.spellID end
        return table.concat(out, ",")
    end
    local function printed(text)
        for _, line in ipairs(env.printed) do if line:find(text, 1, true) then return true end end
        return false
    end
    local ok, reason = pcall(function()
        lists[0], lists[1], lists[2] = { 10, 11 }, { 12 }, { 13 }
        infos[10] = info(72)
        infos[11] = info(5000, { hasAura = true, linkedSpellIDs = { 5100 } })
        infos[12] = info(6552)
        infos[13] = info(7000, { hasAura = true, selfAura = true, overrideSpellID = 7001 })
        local panel = load()
        check("login turns the native viewers off and remembers that RikUI did it", cvar == "0"
            and RikUI.CharDB.cooldownsHidNative == true and printed("replaces Blizzard's cooldown viewer"))
        check("provider lists lead the strip in their order, catalogued ranks upgraded, tracked entries as cells",
            ids(panel) == "1671,5000,6552,7001" and panel.Source == "provider")
        local function entry(index) return (panel.Native.Read())[index] end
        check("entries carry every aura ID the client lists, with overrides and linked spells",
            entry(2).auraIDs[1] == 5000 and entry(2).auraIDs[2] == 5100 and not entry(2).selfAura
            and entry(4).selfAura and entry(4).spellID == 7001 and entry(4).auraIDs[1] == 7000 and entry(4).auraIDs[2] == 7001
            and entry(1).hasAura == false and #entry(1).auraIDs == 1)
        infos[11].flags = 1
        check("hidden-aura entries say so", entry(2).hideAura == true)
        infos[11].flags = 0

        env.printed = {}
        C_CVar.SetCVar("cooldownViewerEnabled", "1")
        check("an outside flip turns the viewers off again without a second notice", cvar == "0"
            and not printed("replaces Blizzard's cooldown viewer"))
        env.inCombat = true
        cvar = "1"; env.fire("CVAR_UPDATE", "cooldownViewerEnabled", "1")
        check("in combat the flip waits", cvar == "1")
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat turns the viewers off", cvar == "0")

        lists[0] = { 11, 10 }
        assert(callbacks["CooldownViewerSettings.OnDataChanged"], "data-changed callback registered")()
        check("a data change rebuilds after the client's notify pass, not inside it", ids(panel) == "1671,5000,6552,7001" and #env.timers == 1)
        env.flushTimers()
        check("the rebuild follows the provider's new order", ids(panel) == "5000,1671,6552,7001")

        layoutLoaded = false
        env.fire("COOLDOWN_VIEWER_DATA_LOADED")
        check("a provider without its layout data reads as default order", panel.Source == "provider-default-order")
        layoutLoaded = true

        CooldownViewerSettings = nil
        C_CooldownViewer = {
            GetCooldownViewerCategorySet = function(category, allowUnlearned)
                assert(allowUnlearned == false)
                return category == 0 and { 10, 11, 14, 15 } or {}
            end,
            GetCooldownViewerCooldownInfo = function(id) return infos[id] end,
        }
        infos[14] = info(6554, { isKnown = false })
        infos[15] = info(871, { flags = 2 })
        learned["Shield Wall"] = 871
        env.fire("SPELLS_CHANGED")
        check("without the settings frame the API supplies the list, minus unknown and hidden-by-default entries",
            ids(panel) == "1671,5000,871,6552" and panel.Source == "api")

        infos[10].spellID = env.SECRET
        env.printed = {}
        env.fire("SPELLS_CHANGED")
        check("a secret field keeps the last strip and warns", ids(panel) == "1671,5000,871,6552"
            and printed("Cooldowns spellbook: native entries"))
        infos[10].spellID = 72

        C_CooldownViewer = nil
        env.fire("SPELLS_CHANGED")
        check("no native source at all leaves the profile alone", ids(panel) == "1671,871,6552" and panel.Source == "absent")

        check("Tracked spells opens the client's settings window", panel.Native.OpenSettings() == nil)
        CooldownViewerSettings = { GetDataProvider = function() return provider end }
        check("Tracked spells opens the client's settings window when it exists", panel.Native.OpenSettings() == true and shown == 1)

        cvar = "0"
        panel = load({ modules = { cooldowns = false } }, { cooldownsHidNative = true })
        check("a disabled module gives the viewers back when RikUI had hidden them", cvar == "1"
            and RikUI.CharDB.cooldownsHidNative == nil)
        cvar = "0"
        panel = load({ modules = { cooldowns = false } }, {})
        check("a disabled module leaves a viewer setting it never touched", cvar == "0")
    end)
    for key, value in pairs(saved) do _G[key] = value end
    Enum.CooldownViewerCategory = savedCategories
    CreateFrame = baseCreate
    restoreWidgets()
    env.inCombat = false
    check("cooldown native source suite completes", ok, reason)
end
