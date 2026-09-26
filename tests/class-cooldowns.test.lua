-- Native duration rendering with learned-spell membership kept outside combat.
return function(check)
    local env = require("wow_stub")
    local loader = dofile("tests/load_addon.lua").Loadfile
    local restoreWidgets = require("widget_stub").install()
    local saved = { C_Spell = C_Spell, UnitClass = UnitClass, CreateFrame = CreateFrame, GameTooltip = GameTooltip }
    local known, failures, cooldowns, charges, counts, reads = {}, {}, {}, {}, {}, {}
    local scans = 0
    CreateFrame = function(...)
        local frame = saved.CreateFrame(...)
        function frame:GetFrameLevel() return 1 end
        function frame:SetCooldownFromDurationObject(value, clear)
            self.duration, self.clearWhenDone = value, clear
        end
        function frame:Clear() self.duration = nil end
        function frame:SetScale(value) self.scale = value end
        function frame:GetCountdownFontString()
            self.font = self.font or self:CreateFontString()
            return self.font
        end
        return frame
    end
    for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USES",
        "SPELL_UPDATE_ICON" }) do env.KNOWN_EVENTS[event] = true end
    local function load(disabled, combat, class)
        env.frames, env.printed, env.timers, env.inCombat = {}, {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = { modules = { classcooldowns = not disabled } } } }, nil
        UnitClass = function() return class or "Warrior", class or "WARRIOR" end
        for _, path in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/ui/media.lua",
            "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout.lua", "src/modules/classcooldowns/classcooldowns.lua" }) do
            assert(loader(path))("RikUI", {})
        end
        RikUI.ClassCooldownProfiles.WARRIOR = { "Shield Bash", "Shield Wall", "Pummel" }
        RikUI.Spells = {
            Entry = function(name, requested)
                if requested == "WARRIOR" and (name == "Shield Bash" or name == "Shield Wall" or name == "Pummel") then
                    return { icon = 123, ranks = { 72, 1671 } }
                end
            end,
            HighestKnownRank = function(name)
                assert(not env.inCombat, "membership scan in combat")
                scans = scans + 1
                return known[name], failures[name]
            end,
        }
        C_Spell = {
            GetSpellCooldownDuration = function(id, ignoreGCD)
                reads[id] = ignoreGCD
                if failures.cooldown == id then error("unavailable cooldown") end
                return cooldowns[id]
            end,
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
        return RikUI.ClassCooldowns
    end
    local ok, reason = pcall(function()
        known = { ["Shield Bash"] = 1671, ["Shield Wall"] = 871 }
        cooldowns[1671], charges[1671], counts[1671] = env.SECRET, env.SECRET, env.SECRET
        local panel = load()
        local first = panel.Buttons[1]
        check("cooldown panel only shows learned families in profile order", #panel.Buttons == 2
            and first.spellID == 1671 and panel.Buttons[2].spellID == 871)
        check("cooldown panel registers one movable fixed footprint", RikUI.Layout.Groups.classcooldowns
            and panel.Frame:GetWidth() == 188 and panel.Frame:GetHeight() == 60)
        check("opaque durations go straight to native widgets and ignore GCD", first.cooldown.duration == env.SECRET
            and first.recharge.duration == env.SECRET and reads[1671] == true)
        check("secret counts go straight to text", first.count.text == env.SECRET)
        check("panel is display only", not first.attributes.type and not first.scripts.OnClick)
        env.runScript(first, "OnEnter")
        check("tooltip uses resolved learned rank", GameTooltip.id == 1671)
        local before = scans
        env.inCombat = true
        cooldowns[1671] = nil
        env.fire("SPELL_UPDATE_COOLDOWN", env.SECRET)
        check("combat cooldown updates clear expired state without spellbook scans",
            first.cooldown.duration == nil and scans == before)
        known["Shield Bash"], known.Pummel = 1672, 6552
        env.fire("SPELLS_CHANGED"); env.fire("PLAYER_TALENT_UPDATE"); env.fire("SPELLS_CHANGED")
        check("combat membership rebuild coalesces", RikUI.Combat.Pending() == 1 and first.spellID == 1671)
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat adopts training and talents", #panel.Buttons == 3
            and first.spellID == 1672 and panel.Buttons[3].spellID == 6552)
        failures["Shield Wall"] = "incomplete spellbook"
        known["Shield Bash"] = 72
        env.fire("SPELLS_CHANGED")
        check("failed scan preserves complete panel atomically", first.spellID == 1672 and #panel.Buttons == 3)
        failures["Shield Wall"] = nil
        known.Pummel = nil
        env.fire("SPELLS_CHANGED")
        check("successful unlearning hides old slots", #panel.Buttons == 2 and first.spellID == 72)
        cooldowns[871], failures.cooldown = {}, 72
        env.fire("SPELL_UPDATE_COOLDOWN")
        check("failed spell duration does not stop other spells", first.cooldown.duration == nil
            and panel.Buttons[2].cooldown.duration == cooldowns[871])
        local messages = #env.printed
        env.fire("SPELL_UPDATE_COOLDOWN")
        check("repeated API failures warn once", #env.printed == messages)
        failures.cooldown = nil
        C_Spell.GetSpellCooldownDuration = nil
        env.fire("SPELL_UPDATE_COOLDOWN")
        check("missing API clears stale duration", panel.Buttons[2].cooldown.duration == nil)
        local last = first.spellID
        RikUI.ClassCooldownProfiles.WARRIOR = { "Not a class spell" }
        env.fire("SPELLS_CHANGED")
        check("invalid profile preserves last complete panel", first.spellID == last)
        RikUI.ClassCooldownProfiles.WARRIOR = {}
        env.fire("SPELLS_CHANGED")
        check("empty profile hides the panel", not panel.Frame:IsShown() and #panel.Buttons == 0)
        -- Standing in for a native middle the client left empty (the level 4 paladin case).
        RikUI.ClassCooldownProfiles.WARRIOR = { "Shield Bash", "Shield Wall", "Pummel" }
        known = { ["Shield Bash"] = 1671, ["Shield Wall"] = 871 }
        local empty = { Essential = true, Utility = true }
        RikUI.CooldownViewer = { NativeEmpty = function(name) return empty[name] end }
        RikUI.Layout.Register(CreateFrame("Frame"), "cooldownessential",
            { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 414 })
        env.fire("SPELLS_CHANGED")
        local point = panel.Frame.points[1]
        check("empty native middle: the row stands in at the Essential place, scaled, rows centred",
            panel.standingIn == true and point[1] == "BOTTOM" and point[4] == 0 and point[5] == 414
            and panel.Frame.scale == 1.4 and panel.Buttons[1].points[1][4] == (188 - 60) / 2
            and panel.Buttons[2].points[1][4] == (188 - 60) / 2 + 32)
        empty.Utility = false
        env.fire("SPELLS_CHANGED")
        local own = RikUI.Layout.GetPosition("classcooldowns")
        point = panel.Frame.points[1]
        check("native entries present: the row keeps its own place, left-aligned, unscaled",
            panel.standingIn == false and point[4] == own.x and point[5] == own.y and panel.Frame.scale == 1
            and panel.Buttons[1].points[1][4] == 0)
        empty.Utility = nil
        env.fire("SPELLS_CHANGED")
        check("unreadable native configuration never stands in", panel.standingIn == false)
        RikUI.CooldownViewer = nil
        panel = load(false, true)
        check("combat login defers construction", panel.Frame == nil)
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        check("deferred construction completes", panel.Frame ~= nil)
        panel = load(true)
        check("disabled module creates no frames", panel.Frame == nil)
        panel = load(false, false, "UNKNOWN")
        check("unsupported class creates no frames", panel.Frame == nil)
    end)
    for key, value in pairs(saved) do _G[key] = value end
    restoreWidgets()
    env.inCombat = false
    check("class cooldown foundation suite completes", ok, reason)
end

