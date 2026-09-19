-- Contract tests use a recording renderer; native click/visual acceptance is separate.
return function(check)
    local env = require("wow_stub")
    local originalCreate = CreateFrame
    local saved = {}
    for _, key in ipairs({ "GetActionTexture", "GetActionCount", "HasAction", "PickupAction",
        "PlaceAction", "GetCursorInfo", "IsModifiedClick" }) do saved[key] = _G[key] end
    local originalActionBar = C_ActionBar
    local originalCVar = C_CVar.GetCVar
    local actions, reads, drags, locked, modified, cursor = {}, {}, {}, false, false, nil
    local protectedWrites, animations = 0, {}
    local inheritedClick = function() end
    local function protected()
        protectedWrites = protectedWrites + 1
        assert(not InCombatLockdown(), "protected frame write in combat")
    end
    local function recordRegion(region)
        function region:SetTexture(value) self.texture = value end
        function region:SetAlpha(value) self.alpha = value end
        function region:SetShown(value) self.shown = value end
        function region:SetTexCoord(...) self.coords = { ... } end
        function region:SetFormattedText(format, value) self.format, self.value = format, value end
        return region
    end
    CreateFrame = function(kind, name, parent, template)
        if template then protected() end
        local frame = originalCreate(kind, name, parent, template)
        local methods = getmetatable(frame).__index
        setmetatable(frame, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        frame.id, frame.alpha, frame.mouse = 0, 1, false
        if template then frame.scripts.OnClick = inheritedClick end
        function frame:SetID(value) protected(); self.id = value end
        function frame:GetID() return self.id end
        function frame:SetAttribute(key, value) protected(); self.attributes[key] = value end
        function frame:SetSize(w, h) protected(); self.width, self.height = w, h end
        function frame:SetPoint(...) protected(); self.point = { ... } end
        function frame:ClearAllPoints() protected(); self.point = nil end
        function frame:SetScale(value) protected(); self.scale = value end
        function frame:SetAlpha(value) self.alpha = value end
        function frame:GetAlpha() return self.alpha end
        function frame:IsMouseOver() return self.mouse end
        function frame:RegisterForClicks(...) self.clicks = { ... } end
        function frame:RegisterForDrag(...) self.drags = { ... } end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return recordRegion(texture(self, ...)) end
        function frame:CreateFontString(...) return recordRegion(font(self, ...)) end
        function frame:CreateAnimationGroup()
            local group = { scripts = {}, playing = false }
            function group:SetScript(name, fn) self.scripts[name] = fn end
            function group:IsPlaying() return self.playing end
            function group:Play() self.playing = true end
            function group:Stop() self.playing = false end
            function group:CreateAnimation()
                local animation = {}
                function animation:SetFromAlpha(value) self.from = value end
                function animation:SetToAlpha(value) self.to = value end
                function animation:SetDuration(value) self.duration = value end
                group.animation = animation
                return animation
            end
            function group:Finish()
                if not self.playing then return end
                self.playing = false
                if self.scripts.OnFinished then self.scripts.OnFinished(self) end
            end
            animations[#animations + 1] = group
            return group
        end
        return frame
    end
    GetActionTexture = function(slot)
        reads[slot] = (reads[slot] or 0) + 1
        if actions[slot] == "error" then error("texture unavailable") end
        return actions[slot] and actions[slot].texture
    end
    GetActionCount = function(slot) return actions[slot] and actions[slot].count or 0 end
    HasAction = function(slot) return actions[slot] ~= nil end
    C_CVar.GetCVar = function(name)
        if name == "lockActionBars" then return locked and "1" or "0" end
        return originalCVar(name)
    end
    IsModifiedClick = function(name) return name == "PICKUPACTION" and modified end
    GetCursorInfo = function() return cursor end
    PickupAction = function(slot)
        assert(not InCombatLockdown())
        drags[#drags + 1] = { "pickup", slot }
        cursor = "spell"
    end
    PlaceAction = function(slot)
        assert(not InCombatLockdown())
        drags[#drags + 1] = { "place", slot }
        actions[slot] = { texture = 987, count = 3 }
    end
    for _, event in ipairs({ "UPDATE_BINDINGS", "SPELL_UPDATE_CHARGES", "UPDATE_INVENTORY_ALERTS", "BAG_UPDATE_DELAYED", "SPELL_UPDATE_ICON" }) do
        env.KNOWN_EVENTS[event] = true
    end
    local function loadBars(profile, combat)
        env.frames, env.printed, env.timers, env.inCombat = {}, {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile or {} } }, nil
        for _, file in ipairs({ "core.lua", "media.lua", "setup.lua", "setup-apply.lua",
            "setup-snapshot.lua", "setup-undo.lua", "layout.lua", "bars.lua", "bars-skin.lua", "bars-stock.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Bars
    end
    local function finishFades()
        for _, animation in ipairs(animations) do animation:Finish() end
    end
    local ok, reason = pcall(function()
        actions[1], actions[61] = { texture = 123, count = 4 }, { texture = 456, count = 1 }
        local bars = loadBars({ scale = 0.8, positions = {
            main = { point = "TOP", relativePoint = "TOP", x = 9, y = -20 },
        } })
        check("bars module exposes Create and frame registry", bars and type(bars.Create) == "function"
            and type(bars.Frames) == "table")
        assert(bars and bars.Frames, "bars implementation missing")
        local starts = { main = 1, bar2 = 61, bar3 = 49, bar4 = 25, bar5 = 37 }
        for name, first in pairs(starts) do
            local bar = bars.Frames[name]
            check(name .. " has twelve fixed secure slots", bar and #bar.buttons == 12)
            for i, button in ipairs(bar.buttons) do
                check(name .. " slot " .. i .. " stays absolute", button:GetAttribute("action") == first + i - 1
                    and button:GetID() == 0 and button:GetAttribute("type") == "action")
                check(name .. " slot " .. i .. " keeps secure click", button.template == "SecureActionButtonTemplate"
                    and button:GetScript("OnClick") == inheritedClick)
            end
            check(name .. " honors profile scale", bar.scale == 0.8)
            check(name .. " uses no OnUpdate", bar:GetScript("OnUpdate") == nil)
        end
        local main, bar2, fade = bars.Frames.main, bars.Frames.bar2, bars.Frames.bar3
        local button = main.buttons[1]
        check("shared media and default-off gryphons exist", RikUI.Media ~= nil and RikUI.Profile.gryphons == false)
        check("main row owns hidden gryphons", type(main.gryphons) == "table" and not main.gryphons[1].shown)
        SlashCmdList.RIKUI("gryphons on")
        check("profile command shows referenced mirrored gryphons", RikUI.Profile.gryphons == true
            and main.gryphons[1].shown and main.gryphons[2].shown
            and main.gryphons[1].texture:find("UI-MainMenuBar-EndCap-Dwarf", 1, true)
            and main.gryphons[2].coords[1] == 1 and main.gryphons[2].coords[2] == 0)
        check("secondary rows do not acquire gryphons", bar2.gryphons == nil)
        local overlay = bars.Create("skinPage", 13, { positionKey = "main" })
        check("new overlays inherit skin and current gryphon preference", overlay.gryphons[1].shown
            and #overlay.buttons[1].border == 4)
        SlashCmdList.RIKUI("gryphons invalid")
        check("invalid preference leaves profile intact", RikUI.Profile.gryphons == true)
        env.inCombat = true
        SlashCmdList.RIKUI("gryphons off")
        check("combat preference defers visual writes", main.gryphons[1].shown and overlay.gryphons[1].shown)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("combat exit updates every main overlay", not main.gryphons[1].shown and not overlay.gryphons[1].shown)
        check("profile position overrides defaults", main.point[1] == "TOP" and main.point[2] == UIParent
            and main.point[3] == "TOP" and main.point[4] == 9 and main.point[5] == -20)
        check("missing position uses setup default", bar2.point[5] == RikUI.Setup.DefaultPositions.bar2.y)
        check("side bars run top to bottom", bars.Frames.bar4.height > bars.Frames.bar4.width
            and bars.Frames.bar4.buttons[2].point[5] < 0)
        check("main has bottom row geometry", main.width > main.height and main.buttons[2].point[4] > 0)
        check("both click phases honor native preference", table.concat(button.clicks, ",") == "AnyDown,AnyUp")
        check("icon and count read from absolute slot", button.icon.texture == 123 and button.count.value == 4)
        check("empty slots display empty texture", main.buttons[2].empty.shown and not main.buttons[2].icon.shown)
        check("single count is omitted", bar2.buttons[1].count:GetText() == "")

        reads = {}
        actions[1] = { texture = 789, count = env.SECRET }
        env.fire("ACTIONBAR_SLOT_CHANGED", 1)
        check("slot event refreshes only matching action", button.icon.texture == 789 and reads[1] == 1 and reads[61] == nil)
        check("opaque count is passed directly to sink", button.count.value == env.SECRET and button.count.format == "%d")
        actions[1] = nil
        env.fire("ACTIONBAR_SLOT_CHANGED", 1)
        check("clearing action removes icon and count", button.empty.shown and not button.icon.shown and button.count:GetText() == "")
        for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED" }) do
            reads = {}
            env.fire(event, 0)
            check(event .. " refreshes all bars", reads[1] and reads[72] and reads[48])
        end
        actions[1], actions[61] = "error", { texture = 654, count = 2 }
        env.fire("UPDATE_BINDINGS")
        check("one API failure leaves other slots fresh", bar2.buttons[1].icon.texture == 654)
        actions[1] = { texture = 789, count = 4 }

        local before = #drags
        locked, modified = true, false
        env.runScript(button, "OnDragStart")
        check("locked action cannot be picked up", #drags == before)
        modified = true
        env.runScript(button, "OnDragStart")
        check("pickup modifier overrides lock", drags[#drags][1] == "pickup" and drags[#drags][2] == 1)
        env.runScript(bar2.buttons[4], "OnReceiveDrag")
        check("drop places onto destination fixed slot", drags[#drags][1] == "place" and drags[#drags][2] == 64)
        check("drop refreshes destination immediately", bar2.buttons[4].icon.texture == 987)
        cursor = nil
        before = #drags
        env.runScript(button, "OnReceiveDrag")
        check("empty cursor cannot clear a slot", #drags == before)

        check("utility row starts transparent", fade.alpha == 0)
        fade.mouse = true
        env.runScript(fade.buttons[1], "OnEnter")
        check("utility button hover reveals row", fade.alpha == 1)
        env.runScript(fade.buttons[1], "OnLeave")
        env.flushTimers()
        finishFades()
        check("moving between buttons keeps row visible", fade.alpha == 1)
        fade.mouse = false
        env.runScript(fade, "OnLeave")
        env.flushTimers()
        finishFades()
        check("leaving utility row fades it out", fade.alpha == 0)

        before = protectedWrites
        env.inCombat, cursor = true, "spell"
        env.fire("PLAYER_REGEN_DISABLED")
        check("combat reveals utility row", fade.alpha == 1)
        local dragCount = #drags
        env.runScript(button, "OnDragStart")
        env.runScript(button, "OnReceiveDrag")
        check("combat rejects cursor operations", #drags == dragCount)
        RikUI.Profile.scale, RikUI.Profile.positions.main.x = 1.25, 55
        bars.ApplyLayout()
        bars.Create("extra", 109, { vertical = true })
        check("combat creation and layout writes are deferred", protectedWrites == before
            and bars.Frames.extra == nil and main.scale == 0.8)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        finishFades()
        check("queue builds requested absolute bar", bars.Frames.extra and bars.Frames.extra.buttons[12]:GetAttribute("action") == 120)
        check("queue refreshes current profile position and scale", main.scale == 1.25 and main.point[4] == 55)
        check("combat exit fades idle utility row", fade.alpha == 0)
        check("combat drag is never replayed", #drags == dragCount)
        local frames = #env.frames
        check("Create is idempotent for same name and range", bars.Create("main", 1) == main and #env.frames == frames)
        local same, status = bars.Create("main", 1)
        check("completed Create has no queued status", same == main and status == nil)
        check("Create rejects conflicting slot range", bars.Create("main", 13) == nil)
        check("Create rejects invalid arguments", bars.Create("", 1) == nil and bars.Create("bad", 0) == nil)

        RikUI.Presets.WARRIOR = { roles = { dps = {} }, bars = {}, macros = {} }
        local result = RikUI.Setup.Apply("WARRIOR", "dps", {
            macros = false, bars = false, binds = false, cvars = false,
        })
        check("Apply moves existing overlay to saved default", result.status == "applied"
            and main.point[4] == 0 and main.point[5] == 40)
        local undone = RikUI.Setup.Undo()
        check("Undo restores visible overlay position", undone.status == "undone" and main.point[4] == 55)
        check("Undo missing position falls back to default", RikUI.Profile.positions.bar2 == nil and bar2.point[5] == 82)

        local textureReader, countReader = GetActionTexture, GetActionCount
        C_ActionBar = { GetActionTexture = textureReader, GetActionUseCount = countReader }
        GetActionTexture, GetActionCount = nil, nil
        bars = loadBars()
        local modernButton = bars.Frames.main.buttons[1]
        check("modern-only action API populates icon and count", modernButton.icon.texture == 789
            and modernButton.count.value == 4)
        for _, event in ipairs({ "SPELL_UPDATE_CHARGES", "UPDATE_INVENTORY_ALERTS", "BAG_UPDATE_DELAYED" }) do
            actions[1].count = actions[1].count + 1
            env.fire(event)
            check(event .. " refreshes count", modernButton.count.value == actions[1].count)
        end
        actions[1].texture = 876
        env.fire("SPELL_UPDATE_ICON")
        check("spell icon changes refresh without slot reassignment", modernButton.icon.texture == 876)
        C_ActionBar.GetActionDisplayCount = function() return env.SECRET end
        env.fire("UPDATE_BINDINGS")
        check("modern display count goes directly to text sink", modernButton.count:GetText() == env.SECRET)
        GetActionTexture, GetActionCount, C_ActionBar = textureReader, countReader, originalActionBar

        bars = loadBars({ gryphons = true })
        check("saved gryphon preference survives initialization", RikUI.Profile.gryphons == true
            and bars.Frames.main.gryphons[1].shown)
        bars = loadBars({ modules = { bars = false } })
        check("disabled module creates no bars", next(bars.Frames) == nil)
        bars = loadBars(nil, true)
        check("login in combat creates no secure bars", next(bars.Frames) == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("login creation resumes after combat", bars.Frames.main and #bars.Frames.main.buttons == 12)
    end)
    CreateFrame = originalCreate
    for key, value in pairs(saved) do _G[key] = value end
    C_CVar.GetCVar = originalCVar
    C_ActionBar = originalActionBar
    env.inCombat = false
    check("bar behavior suite completes", ok, reason)
end
