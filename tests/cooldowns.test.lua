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
        local entry = { spellID = spellID, baseSpellID = spellID, strip = true, auraIDs = { spellID } }
        for key, value in pairs(extra or {}) do entry[key] = value end
        return entry
    end
    local function load(disabled, combat, cells)
        env.frames, env.printed, env.timers, env.inCombat = {}, {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = { modules = { cooldowns = not disabled, auras = false } } } }, nil
        UnitClass = function() return "Warrior", "WARRIOR" end
        for _, path in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/ui/media.lua", "src/ui/primitives.lua",
            "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout.lua", "src/modules/auras/auras.lua",
            "src/modules/auras/auras-button.lua", "src/modules/cooldowns/cooldowns.lua",
            "src/modules/cooldowns/cooldowns-strip.lua", "src/modules/cooldowns/cooldowns-cells.lua" }) do
            assert(loader(path))("RikUI", {})
        end
        RikUI.ClassCooldownProfiles.WARRIOR = { "Shield Bash", "Shield Wall", "Pummel" }
        RikUI.ClassAuraCells.WARRIOR = cells
        spellsStub()
        RikUI.Cooldowns.Native = { Enable = function() end, ViewerState = function() return "hidden" end,
            Read = function() if nativeList == nil then return nil, nativeSource end return nativeList, nativeSource end }
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
        nativeList = { native(72), native(1671), native(5000, { hasAura = true, auraIDs = { 5000, 5100 } }), native(5001),
            native(nil), native(871), { spellID = 7000, strip = false, selfAura = true, hasAura = true, auraIDs = { 7000 } } }
        nativeSource = "provider"
        local panel = load()
        check("native entries lead in the client's order, collapsed to learned ranks, tracked ones as cells, then the profile",
            ids(panel) == "1671,5000,7000,6552")
        local s = panel.Stats
        check("merge stats count every skip", s.native == 3 and s.cells == 0 and s.profile == 1 and s.unlearned == 2
            and s.duplicates == 2 and s.itemOnly == 1 and s.capped == 0 and panel.Source == "provider")
        local first = panel.Buttons[1]
        local function slot(unit, index)
            local container = _G["RikUIAuras_cooldowns_" .. unit]
            return container and container.slots["cell" .. index]
        end
        check("a plain cooldown gets no aura slot", slot("player", 1) == nil and slot("target", 1) == nil)
        local target = slot("target", 2)
        check("an aura-backed entry hosts a target slot over its cell, watching every listed ID",
            target and target.enabled and target.filter == "HARMFUL|PLAYER"
            and target.options.candidateFilters.includeSpellIDs[5000] and target.options.candidateFilters.includeSpellIDs[5100]
            and target.frame.points[1][1] == "TOPLEFT" and target.frame.points[1][2] == panel.Buttons[2]
            and target.frame.registered.icon ~= nil and target.frame.registered.cooldown ~= nil)
        local tracked = slot("player", 3)
        check("a tracked entry is a dim cell under a player slot", tracked and tracked.filter == "HELPFUL"
            and tracked.options.candidateFilters.includeSpellIDs[7000] and tracked.frame.points[1][2] == panel.Buttons[3]
            and panel.Buttons[3].icon.alpha == 0.55 and panel.Buttons[2].icon.alpha == 1)
        local container = _G.RikUIAuras_cooldowns_target
        local updates = container.updates
        env.fire("PLAYER_TARGET_CHANGED")
        check("a target change refreshes the target slots", container.updates == updates + 1)
        check("strip registers the cooldowns layout key growing upward at rest size",
            RikUI.Layout.Groups.cooldowns ~= nil and RikUI.Layout.Groups.cooldowns.grow == "UP"
            and panel.Frame:GetWidth() == 280 and panel.Frame:GetHeight() == 76 and panel.Frame:IsShown())
        check("rows fill from the bottom and centre", first.points[1][1] == "BOTTOMLEFT" and first.points[1][4] == 62
            and first.points[1][5] == 0 and panel.Buttons[2].points[1][4] == 102)
        check("opaque durations go straight to native widgets and ignore GCD", first.cooldown.duration == env.SECRET
            and first.recharge.duration == env.SECRET and reads[1671] == true)
        check("secret counts go straight to text", first.count.text == env.SECRET)
        check("buttons are display only", not first.attributes.type and not first.scripts.OnClick)
        env.runScript(first, "OnEnter")
        check("tooltip uses the resolved learned rank", GameTooltip.id == 1671)
        env.printed = {}
        panel:Debug()
        check("debug line reports counts and sources", printed("Cooldowns: 4 icons (native=3, cells=0, profile=1")
            and printed("provider=provider") and printed("native viewers=hidden"))

        local many, extra = {}, {}
        for index = 1, 25 do many[index] = native(10000 + index); extra[index] = 10000 + index end
        learned.ids = extra
        nativeList = many
        env.fire("SPELLS_CHANGED")
        check("the strip caps at three rows of seven and grows a third row", #panel.Buttons == 21
            and panel.Stats.capped == 6 and panel.Frame:GetHeight() == 116
            and panel.Buttons[8].points[1][5] == 40 and panel.Buttons[15].points[1][4] == 2)
        check("cells that lost their aura entry disable their slots without removing them",
            slot("target", 2) and not slot("target", 2).enabled and slot("player", 3) and not slot("player", 3).enabled)

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

        -- A class cell: one icon for a family set, watching every rank of every family.
        learned = { ["Shield Bash"] = 1671, Pummel = 6552 }
        panel = load(false, false, { { label = "Bash", unit = "player", families = { "Shield Wall", "Shield Bash" } } })
        check("a class cell takes the first learned family's icon and sits after native entries",
            ids(panel) == "1671,6552" and panel.Stats.cells == 1 and panel.Stats.duplicates == 1
            and panel.Buttons[1].spellName == "Bash" and panel.Buttons[1].icon.alpha == 0.55)
        local cell = slot("player", 1)
        check("the class cell's slot watches every rank of every family", cell and cell.enabled
            and cell.options.candidateFilters.includeSpellIDs[72] and cell.options.candidateFilters.includeSpellIDs[1672]
            and cell.options.candidateFilters.includeSpellIDs[871] and cell.frame.points[1][2] == panel.Buttons[1])
        learned = { Pummel = 6552 }
        env.fire("SPELLS_CHANGED")
        check("a class cell with nothing learned is left out", ids(panel) == "6552" and panel.Stats.cells == 0)

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
