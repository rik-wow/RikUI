local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Cast values only reach sinks and the fill is a client duration object; native timer rendering needs a beta check.
return function(check)
    local env = require("wow_stub")
    local originalCreate = CreateFrame
    local API = { "UnitCastingInfo", "UnitChannelInfo", "UnitCastingDuration", "UnitChannelDuration", "C_DurationUtil",
        "C_StringUtil", "GetTime", "PlayerCastingBarFrame", "CastingBarFrame",
        "PetCastingBarFrame" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local casts, channels, now, writes, bindings, formatters = {}, {}, 100, 0, {}, {}
    local function protected()
        assert(not InCombatLockdown(), "protected castbar write in combat")
        writes = writes + 1
    end
    local function region(value)
        local methods = getmetatable(value).__index
        setmetatable(value, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function value:SetTexture(texture) self.texture = texture end
        function value:SetTexCoord(...) self.coords = { ... } end
        function value:SetColorTexture(...) self.color = { ... } end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetAlphaFromBoolean(active, yes, no) self.active, self.yes, self.no = active, yes, no end
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
        function frame:SetAttribute(key, value) protected(); self.attributes[key] = value end
        function frame:SetSize(w, h) protected(); self.width, self.height = w, h end
        function frame:SetPoint(...) protected(); self.point = { ... } end
        function frame:ClearAllPoints() protected() end
        function frame:SetScale(value) protected(); self.scale = value end
        function frame:SetMinMaxValues(min, max) self.min, self.max = min, max end
        function frame:SetValue(value) self.value = value end
        function frame:SetStatusBarColor(...) self.color = { ... } end
        function frame:SetStatusBarTexture(texture) self.texture = texture end
        function frame:SetTimerDuration(duration, interpolation, direction)
            self.timer = { duration = duration, interpolation = interpolation, direction = direction }
        end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        return frame
    end
    UnitCastingInfo = function(unit)
        local cast = casts[unit]
        if not cast then return end
        if cast.error then error("cast info unavailable") end
        return cast.name, cast.text, cast.texture, cast.startMs, cast.endMs, false, cast.castID, cast.notInterruptible, 1
    end
    UnitChannelInfo = function(unit)
        local channel = channels[unit]
        if not channel then return end
        return channel.name, channel.text, channel.texture, channel.startMs, channel.endMs, false,
            channel.notInterruptible, 1, false, 0
    end
    UnitCastingDuration = function(unit) return casts[unit] and casts[unit].duration end
    UnitChannelDuration = function(unit) return channels[unit] and channels[unit].duration end
    GetTime = function() return now end
    local function recorder(list)
        local object = { last = {} }
        setmetatable(object, { __index = function(_, key)
            return function(self, ...) self.last[key] = { ... } end
        end })
        table.insert(list, object)
        return object
    end
    C_DurationUtil = { CreateDurationTextBinding = function() return recorder(bindings) end }
    C_StringUtil = { CreateSecondsFormatter = function() return recorder(formatters) end }
    local function stockFrame(name)
        local f = { parent = UIParent, events = { UNIT_SPELLCAST_START = true }, label = name }
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
        env.frames, env.printed, env.inCombat, env.timers, writes = {}, {}, false, {}, 0
        bindings, formatters, casts, channels = {}, {}, {}, {}
        RikUI, RikUIDB, RikUICharDB = nil, profile and { profiles = { Default = profile } } or nil, nil
        PlayerCastingBarFrame = (not missingStock) and stockFrame("PlayerCastingBarFrame") or nil
        CastingBarFrame = nil
        PetCastingBarFrame = (not missingStock) and stockFrame("PetCastingBarFrame") or nil
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua",
            "src/modules/unitframes/unitframes.lua", "src/modules/unitframes/unitframes-status.lua", "src/modules/castbars/castbars.lua", "src/modules/castbars/castbars-status.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.CastBars
    end
    local function playerCast(castID, duration)
        casts.player = { name = "Frostbolt", text = "Frostbolt", texture = 135846, startMs = 100000, endMs = 102500,
            castID = castID or "Cast-1", notInterruptible = false, duration = duration }
    end
    local function secretCast(duration)
        return { name = env.SECRET, text = env.SECRET, texture = env.SECRET, startMs = env.SECRET, endMs = env.SECRET,
            castID = env.SECRET, notInterruptible = env.SECRET, duration = duration }
    end
    local ok, reason = pcall(function()
        local module = load()
        local player, target = module.Bars.castplayer, module.Bars.casttarget
        local directions = Enum.StatusBarTimerDirection
        check("two castbars exist for the player and target", player and target and player.unit == "player"
            and target.unit == "target")
        check("castbars are plain frames with a status bar child", player.template == nil
            and player.bar.kind == "StatusBar" and player.bar.texture == RikUI.Media.statusbar)
        local groups = RikUI.Layout.Groups
        check("castbars register with the shared layout", groups.castplayer.frames[1] == player
            and groups.casttarget.frames[1] == target)
        local dp, dt, cp, ct, dpet = groups.player.defaults, groups.target.defaults, groups.castplayer.defaults,
            groups.casttarget.defaults, groups.petframe.defaults
        check("defaults sit directly under the player and target frames", cp.x == dp.x and ct.x == dt.x
            and cp.y + player.height <= dp.y and ct.y == cp.y and cp.y > 232)
        check("pet frame default sits beside the player frame, mirroring ToT", dpet.y == dp.y and dpet.x < dp.x
            and groups.tot.defaults.x > dt.x)
        check("only the target bar has a shield", target.shield ~= nil and player.shield == nil
            and target.shield.active == false)
        check("castbars start hidden", player.shown == false and target.shown == false)
        check("stock casting bar is parked with events dropped", PlayerCastingBarFrame.parent == RikUIHiddenFrames
            and PlayerCastingBarFrame.unregistered == 1)

        playerCast("Cast-1", { id = "d1" })
        env.fire("UNIT_SPELLCAST_START", "player", "Cast-1", 116)
        check("player cast shows icon and name", player.shown == true and player.icon.texture == 135846
            and player.bar.text.text == "Frostbolt" and player.bar.text.fontPath == RikUI.Media.font)
        check("player cast fill comes from the duration object with elapsed direction", player.bar.timer
            and player.bar.timer.duration == casts.player.duration
            and player.bar.timer.direction == directions.ElapsedTime and player.bar.manual == nil)
        local binding = bindings[1]
        check("timer text uses a duration text binding with a seconds formatter", binding
            and binding.last.SetFontString[1] == player.time and binding.last.SetDuration[1] == casts.player.duration
            and binding.last.SetEnabled[1] == true and binding.last.SetFormatter[1] == formatters[1]
            and formatters[1].last.SetMillisecondsThreshold ~= nil)
        check("casts use the cast colour", color(player.bar.color, module.Colors.cast))
        env.fire("UNIT_SPELLCAST_STOP", "player", "Cast-2", 116)
        check("a stop for a different readable cast keeps the bar", player.shown == true)
        env.fire("UNIT_SPELLCAST_STOP", "player", "Cast-1", 116)
        check("a matching stop hides the bar and disables the timer text", player.shown == false
            and binding.last.SetEnabled[1] == false and player.time.text == "")

        env.fire("UNIT_SPELLCAST_START", "player", "Cast-1", 116)
        env.fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-1", 116, "Creature-0-1")
        check("interrupted casts turn red, say so and fill", player.shown == true
            and color(player.bar.color, module.Colors.interrupted) and player.bar.text.text == "Interrupted"
            and player.bar.value == 1 and player.bar.max == 1 and #env.timers == 1)
        env.flushTimers()
        check("interrupted bar hides after the hold", player.shown == false)
        env.fire("UNIT_SPELLCAST_START", "player", "Cast-1", 116)
        env.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-1", 116)
        check("failed casts say Failed", player.bar.text.text == "Failed"
            and color(player.bar.color, module.Colors.interrupted))
        env.flushTimers()
        env.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-9", 116)
        check("a failure while idle stays hidden", player.shown == false and #env.timers == 0)
        env.fire("UNIT_SPELLCAST_START", "player", "Cast-1", 116)
        env.fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-1", 116)
        playerCast("Cast-3", { id = "d3" })
        env.fire("UNIT_SPELLCAST_START", "player", "Cast-3", 116)
        env.flushTimers()
        check("a new cast during the interrupt hold stays visible", player.shown == true
            and player.bar.text.text == "Frostbolt" and color(player.bar.color, module.Colors.cast))
        env.fire("UNIT_SPELLCAST_STOP", "player", "Cast-3", 116)

        playerCast("Cast-1", { id = "d1" })
        env.fire("UNIT_SPELLCAST_START", "player", "Cast-1", 116)
        casts.player.duration = { id = "d2" }
        env.fire("UNIT_SPELLCAST_DELAYED", "player", "Cast-1", 116)
        check("delays re-read the duration object", player.bar.timer.duration == casts.player.duration
            and binding.last.SetDuration[1] == casts.player.duration)
        env.fire("UNIT_SPELLCAST_STOP", "player", "Cast-1", 116)

        channels.player = { name = "Blizzard", text = "Blizzard", texture = 135857, startMs = 100000, endMs = 108000,
            notInterruptible = false, duration = { id = "c1" } }
        env.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-4", 10)
        check("channels fill with remaining direction and the channel colour", player.shown == true
            and player.bar.timer.duration == channels.player.duration
            and player.bar.timer.direction == directions.RemainingTime
            and color(player.bar.color, module.Colors.channel) and player.icon.texture == 135857)
        channels.player.duration = { id = "c2" }
        env.fire("UNIT_SPELLCAST_CHANNEL_UPDATE", "player", "Cast-4", 10)
        check("channel updates re-read the duration object", player.bar.timer.duration == channels.player.duration)
        env.fire("UNIT_SPELLCAST_STOP", "player", "Cast-4", 10)
        check("a cast stop does not end a channel", player.shown == true)
        env.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-4", 10, "Creature-0-1")
        check("a channel stopped by someone shows Interrupted", player.shown == true
            and player.bar.text.text == "Interrupted")
        env.flushTimers()
        env.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-4", 10)
        env.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-4", 10, nil)
        check("a completed channel hides the bar", player.shown == false)
        channels.player = nil

        casts.target = secretCast({ id = "t1" })
        env.printed = {}
        env.fire("UNIT_SPELLCAST_START", "target", env.SECRET, env.SECRET)
        check("secret target cast values reach the sinks unchanged", target.shown == true
            and target.bar.text.text == env.SECRET and target.icon.texture == env.SECRET
            and target.shield.active == env.SECRET and target.bar.timer.duration == casts.target.duration
            and #env.printed == 0)
        env.fire("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target")
        check("not-interruptible event shows the shield", target.shield.active == true)
        env.fire("UNIT_SPELLCAST_INTERRUPTIBLE", "target")
        check("interruptible event hides the shield", target.shield.active == false)
        env.fire("UNIT_SPELLCAST_STOP", "target", env.SECRET, env.SECRET)
        check("a stop with a secret cast id hides the target bar", target.shown == false)
        env.fire("PLAYER_TARGET_CHANGED")
        check("target change picks up an in-progress cast", target.shown == true)
        env.fire("UNIT_SPELLCAST_CHANNEL_STOP", "target", env.SECRET, env.SECRET, env.SECRET)
        check("a channel stop does not end a cast", target.shown == true)
        casts.target = nil
        env.fire("PLAYER_TARGET_CHANGED")
        check("target change with no cast hides the bar", target.shown == false)
        channels.target = secretCast({ id = "t2" })
        env.fire("PLAYER_TARGET_CHANGED")
        check("target change picks up a channel", target.shown == true
            and target.bar.timer.direction == directions.RemainingTime)
        env.fire("UNIT_SPELLCAST_CHANNEL_STOP", "target", env.SECRET, env.SECRET, env.SECRET)
        check("a secret interrupter ends a channel plainly", target.shown == false and #env.timers == 0)
        env.fire("PLAYER_TARGET_CHANGED")
        channels.target = nil
        env.fire("UNIT_SPELLCAST_STOP", env.SECRET, env.SECRET, env.SECRET)
        check("a secret event unit refreshes every bar without error", target.shown == false and #env.printed == 0)

        local before = writes
        env.inCombat = true
        playerCast("Cast-5", { id = "d5" })
        env.fire("UNIT_SPELLCAST_START", "player", "Cast-5", 116)
        env.fire("UNIT_SPELLCAST_STOP", "player", "Cast-5", 116)
        env.fire("PLAYER_TARGET_CHANGED")
        check("combat casts flow to sinks without protected writes", writes == before and player.shown == false)
        env.inCombat = false

        casts.target = { error = true }
        env.printed = {}
        env.fire("UNIT_SPELLCAST_START", "target", "x", 1)
        env.fire("UNIT_SPELLCAST_START", "target", "x", 1)
        check("reader failures are reported once and contained", printedContains("Castbars cast info")
            and #env.printed == 1 and target.shown == false)
        casts.target = nil

        env.printed = {}
        SlashCmdList.RIKUI("debug")
        local output = table.concat(env.printed, "\n")
        check("debug reports cast dependency secrecy", output:find("castbars.UnitCastingInfo(player)", 1, true)
            and output:find("castbars.UnitCastingInfo(target)", 1, true)
            and output:find("castbars.UnitCastingDuration(target)", 1, true) and not output:find("<secret>", 1, true))

        module = load()
        player, target = module.Bars.castplayer, module.Bars.casttarget
        playerCast("Cast-1", nil)
        now = 100.5
        env.fire("UNIT_SPELLCAST_START", "player", "Cast-1", 116)
        check("a missing duration object falls back to readable times", player.bar.timer == nil
            and near(player.bar.max, 2.5) and near(player.bar.value, 0.5) and #bindings == 0)
        now = 101.5
        env.runScript(player, "OnUpdate", 0.1)
        check("fallback fill advances on update with a remaining-time text", near(player.bar.value, 1.5)
            and player.time.format == "%.1f" and near(player.time.args[1], 1))
        now = 104
        env.runScript(player, "OnUpdate", 0.1)
        check("fallback fill clamps once the cast time passes", near(player.bar.value, 2.5)
            and near(player.time.args[1], 0) and player.shown == true)
        env.fire("UNIT_SPELLCAST_STOP", "player", "Cast-1", 116)
        check("fallback stop clears the manual fill", player.shown == false and player.bar.manual == nil)
        channels.player = { name = "Blizzard", text = "Blizzard", texture = 1, startMs = 100000, endMs = 108000 }
        now = 102
        env.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-4", 10)
        check("fallback channels drain from full", near(player.bar.max, 8) and near(player.bar.value, 6))
        env.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-4", 10, nil)
        channels.player = nil
        casts.target = secretCast(nil)
        env.printed = {}
        env.fire("UNIT_SPELLCAST_START", "target", env.SECRET, 1)
        env.fire("UNIT_SPELLCAST_START", "target", env.SECRET, 1)
        check("secret times with no duration object show a full bar and warn once", target.shown == true
            and target.bar.max == 1 and target.bar.value == 1 and target.bar.manual == nil
            and printedContains("Castbars fill") and #env.printed == 1)
        casts.target = nil
        UnitCastingDuration = function() return env.SECRET end
        playerCast("Cast-1", nil)
        now = 100.5
        env.fire("UNIT_SPELLCAST_START", "player", "Cast-1", 116)
        check("a secret duration value is treated as unavailable", player.bar.timer == nil and near(player.bar.max, 2.5))
        env.fire("UNIT_SPELLCAST_STOP", "player", "Cast-1", 116)
        UnitCastingDuration = function(unit) return casts[unit] and casts[unit].duration end

        module = load()
        local focus, pet = module.Bars.castfocus, module.Bars.castpet
        groups = RikUI.Layout.Groups
        check("focus and pet castbars exist at their unit frame's width", focus and pet and focus.unit == "focus"
            and pet.unit == "pet" and focus.width == 160 and pet.width == 110 and module.Bars.castplayer.width == 220)
        check("the focus bar has a shield and the pet bar does not", focus.shield ~= nil and pet.shield == nil)
        local df, dpf = groups.focus.defaults, groups.petframe.defaults
        local dcf, dcp = groups.castfocus.defaults, groups.castpet.defaults
        check("the focus bar sits above the focus frame and the pet bar under the pet frame",
            dcf.x == df.x and dcf.y >= df.y + 36 and dcp.x == dpf.x and dcp.y + pet.height <= dpf.y)
        check("the stock pet casting bar is parked with events dropped",
            PetCastingBarFrame.parent == RikUIHiddenFrames and PetCastingBarFrame.unregistered == 1)
        casts.focus = secretCast({ id = "f1" })
        env.fire("PLAYER_FOCUS_CHANGED")
        check("a focus change picks up an in-progress cast", focus.shown == true and pet.shown == false)
        casts.focus = nil
        env.fire("PLAYER_FOCUS_CHANGED")
        check("a focus change with no cast hides the bar", focus.shown == false)
        casts.pet = secretCast({ id = "p1" })
        env.fire("UNIT_SPELLCAST_START", "pet", "Cast-9", 1)
        check("a pet cast shows the pet bar only", pet.shown == true and focus.shown == false)
        casts.pet = nil
        env.fire("UNIT_PET", "player")
        check("a pet change with no cast hides the pet bar", pet.shown == false and #env.printed == 0)

        module = load(nil, true)
        check("combat login defers bar creation and stock hiding", next(module.Bars) == nil
            and PlayerCastingBarFrame.parent == UIParent)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("bars and stock hiding follow after combat", module.Bars.castplayer ~= nil
            and PlayerCastingBarFrame.parent == RikUIHiddenFrames)
        module = load({ modules = { castbars = false } })
        check("disabled module leaves the stock castbar alone", next(module.Bars) == nil
            and PlayerCastingBarFrame.parent == UIParent)
        module = load(nil, false, true)
        check("missing stock globals are tolerated", module.Bars.castplayer ~= nil and #env.printed == 0)
    end)
    CreateFrame = originalCreate
    for name, value in pairs(saved) do _G[name] = value end
    env.inCombat = false
    check("castbar suite completes", ok, reason)
end
