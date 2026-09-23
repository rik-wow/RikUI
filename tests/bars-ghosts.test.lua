local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Recording renderer only: native pixels and combat protection need client acceptance.
return function(check)
    local env = require("wow_stub")
    local saved, names = {}, { "CreateFrame", "C_ActionBar", "HasAction", "GetActionTexture", "C_Spell", "C_Item", "GameTooltip" }
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local actions, presence, spellTexture, itemTexture = {}, false, 111, 222
    local writes = 0
    local function protected()
        assert(not InCombatLockdown(), "protected write in combat")
        writes = writes + 1
    end
    CreateFrame = function(kind, name, parent, template)
        protected()
        local f = saved.CreateFrame(kind, name, parent, template)
        local methods = getmetatable(f).__index
        setmetatable(f, { __index = function(t, k)
            if k:match("^[A-Z]") then return methods(t, k) end
        end })
        f.level = parent and (rawget(parent, "level") or 0) + 1 or 0
        function f:GetFrameLevel() return self.level end
        function f:SetFrameLevel(v) protected(); self.level = v end
        function f:SetAttribute(k, v) protected(); self.attributes[k] = v end
        function f:SetPoint(...) protected() end
        function f:SetScale(...) protected() end
        function f:EnableMouse(v) self.mouseEnabled = v end
        function f:SetShown(v) self.shown = v end
        function f:GetAlpha() return 1 end
        local texture, font = f.CreateTexture, f.CreateFontString
        local function region(r)
            function r:SetTexture(v) self.texture = v end
            function r:SetAlpha(v) self.alpha = v end
            function r:SetShown(v) self.shown = v end
            function r:SetTexCoord(...) self.coords = { ... } end
            return r
        end
        function f:CreateTexture(...) return region(texture(self, ...)) end
        function f:CreateFontString(...) return region(font(self, ...)) end
        local group = { Stop = function() end, Play = function() end, IsPlaying = function() return false end,
            SetScript = function() end, CreateAnimation = function() return setmetatable({}, { __index = function() return function() end end }) end }
        function f:CreateAnimationGroup() return group end
        return f
    end
    C_ActionBar = {
        HasAction = function(slot)
            if presence == "error" then error("unavailable") end
            if presence == env.SECRET then return env.SECRET end
            return actions[slot] ~= nil
        end,
        GetActionTexture = function(slot) return actions[slot] and actions[slot].icon end,
        GetActionDisplayCount = function() return "" end,
    }
    HasAction = C_ActionBar.HasAction
    GetActionTexture = C_ActionBar.GetActionTexture
    C_Spell = { GetSpellTexture = function() return spellTexture end }
    C_Item = { GetItemIconByID = function() return itemTexture end }
    GameTooltip = {
        SetPoint = function() end,
        SetOwner = function(self, owner) self.owner = owner end,
        IsOwned = function(self, owner) return self.owner == owner end,
        SetText = function(self, text) self.text, self.lines = text, {} end,
        AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
        Hide = function(self) self.shown = false end,
        Show = function(self) self.shown = true end,
        SetAction = function(self, slot)
            self.action, self.text = slot, nil
            self.shown = actions[slot] ~= nil
        end,
    }
    local function loadBars(profile, applied)
        env.frames, env.printed, env.timers, env.inCombat = {}, {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile or {} } }, { applied = applied }
        for _, file in ipairs({ "src/core/core.lua", "src/persistence/codec.lua", "src/platform/hooks.lua", "src/ui/media.lua",
            "data/spells.lua", "presets/warrior.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua",
            "src/setup/setup-snapshot.lua", "src/setup/setup-undo.lua", "src/layout/layout.lua",
            "src/modules/bars/bars.lua", "src/modules/bars/bars-skin.lua",
            "src/modules/bars/bars-ghosts.lua", "src/modules/bars/bars-stock.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.KNOWN_EVENTS.GET_ITEM_INFO_RECEIVED = true
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return RikUI.Bars
    end
    local ok, reason = pcall(function()
        local marker = { class = "WARRIOR", role = "dps", presetVersion = 1 }
        local bars = loadBars({}, marker)
        local button = bars.Frames.main.buttons[7]
        local ghost = button.ghost
        check("empty applied slot previews unlearned spell and level", ghost and ghost.shown
            and ghost.icon.texture == 111 and ghost.icon.alpha == 0.35 and ghost.levelText:GetText() == "Lv 12")
        assert(ghost, "ghost implementation missing")
        check("ghost is a plain mouse-transparent child", not ghost.template and ghost.parent == button
            and ghost.mouseEnabled == false and next(ghost.attributes) == nil)
        check("unassigned slots stay empty", not bars.Frames.bar4.buttons[1].ghost.shown)
        check("macro preview uses preset icon and earliest attack level", bars.Frames.main.buttons[5].ghost.icon.texture == 135358
            and bars.Frames.main.buttons[5].ghost.levelText:GetText() == "Lv 24")
        check("item preview uses item icon without an invented level", bars.Frames.main.buttons[12].ghost.icon.texture == 222
            and bars.Frames.main.buttons[12].ghost.levelText:GetText() == "")
        local battle = bars.Create("battle", 73, { positionKey = "main" })
        check("bonus page uses its own resolved entries", battle.buttons[8].ghost.levelText:GetText() == "Lv 12"
            and bars.Frames.main.buttons[8].ghost.levelText:GetText() == "Lv 38")
        local page = bars.Create("page6", 61, { positionKey = "main" })
        check("manual overlay follows absolute slots", page.buttons[1].ghost.levelText:GetText()
            == bars.Frames.bar2.buttons[1].ghost.levelText:GetText())
        env.runScript(button, "OnEnter")
        check("ghost hover names the preview and distinguishes it from an action", GameTooltip.text == "Overpower"
            and GameTooltip.shown and GameTooltip.lines[1] == "Preset preview - empty slot"
            and GameTooltip.lines[2] == "Preset level: 12")
        actions[7] = {} -- Occupied but texture unavailable: never imply an empty slot.
        env.fire("ACTIONBAR_SLOT_CHANGED", 7)
        check("action occupancy hides ghost even without action texture", not ghost.shown)
        check("hovered ghost tooltip refreshes to new action", GameTooltip.action == 7 and GameTooltip.text == nil)
        actions[7] = nil
        env.fire("ACTIONBAR_SLOT_CHANGED", 7)
        check("clearing the slot restores ghost", ghost.shown)
        env.inCombat = true
        local before = writes
        actions[7] = { icon = 333 }
        env.fire("ACTIONBAR_SLOT_CHANGED", 7)
        check("combat slot change hides ghost without protected writes", not ghost.shown and before == writes)
        actions[7] = nil
        env.fire("ACTIONBAR_SLOT_CHANGED", 7)
        local touches, messages = 0, #env.printed
        RikUI.Store = { Touch = function() touches = touches + 1 end }
        SlashCmdList.RIKUI("ghosts off")
        check("turning preview off clears hovered empty tooltip and schedules save quietly", not GameTooltip.shown
            and touches == 1 and #env.printed == messages)
        local decoded = assert(RikUI.Codec.Decode(assert(RikUI.Codec.Encode(RikUI.Profile))))
        check("settings codec retains explicit disabled preference", decoded.ghosts == false)
        check("combat toggle hides every ghost immediately", not ghost.shown and not battle.buttons[8].ghost.shown
            and RikUI.Profile.ghosts == false and before == writes)
        SlashCmdList.RIKUI("ghosts on")
        check("combat toggle restores empty previews only", ghost.shown and before == writes)
        presence = env.SECRET; bars.Refresh(7)
        check("opaque occupancy suppresses stale ghost", not ghost.shown)
        presence = "error"; bars.Refresh(7)
        check("failed occupancy suppresses stale ghost", not ghost.shown)
        presence = false; bars.Refresh(7)
        check("read recovery restores preview", ghost.shown)
        spellTexture = nil; bars.Refresh(7)
        check("unavailable spell texture falls back to catalog icon", ghost.icon.texture == RikUI.SpellData.Overpower.icon)
        C_Spell.GetSpellTexture = function() error("unavailable") end
        bars.Refresh(7)
        check("throwing icon reader uses catalog fallback", ghost.icon.texture == RikUI.SpellData.Overpower.icon)
        C_Spell, C_Item = nil, nil
        bars.Refresh()
        check("missing optional icon readers are safe", ghost.icon.texture == RikUI.SpellData.Overpower.icon
            and bars.Frames.main.buttons[12].ghost.icon.texture == 134400)
        C_Spell = { GetSpellTexture = function() return 111 end }
        C_Item = { GetItemIconByID = function() return 222 end }
        env.fire("GET_ITEM_INFO_RECEIVED", 6948, true)
        check("late item data replaces fallback without user action", bars.Frames.main.buttons[12].ghost.icon.texture == 222)
        env.inCombat = false
        RikUI.DB.profiles.Hidden = { ghosts = false }
        RikUI:SetProfile("Hidden")
        check("profile switch refreshes ghost preference", not ghost.shown)
        RikUI:SetProfile("Default")
        check("returning to enabled profile restores ghost", ghost.shown)
        local old = RikUI.Profile.ghosts
        SlashCmdList.RIKUI("ghosts invalid")
        check("invalid toggle preserves preference", RikUI.Profile.ghosts == old)
        RikUI.CharDB.applied = nil
        bars.Refresh()
        check("removing applied preset clears all previews", not ghost.shown)
        local applied = RikUI.Setup.Apply("WARRIOR", "tank",
            { macros = false, bars = false, binds = false, cvars = false, layout = false })
        check("Apply completion refreshes newly applied role without a slot event", applied.status == "applied"
            and bars.Frames.main.buttons[1].ghost.entry.spell == "Sunder Armor")
        local undone = RikUI.Setup.Undo()
        check("Undo completion clears previews of removed preset", undone.status == "undone"
            and not bars.Frames.main.buttons[1].ghost.shown)
        local refresh, completed = bars.Refresh, false
        bars.Refresh = function() error("display unavailable") end
        applied = RikUI.Setup.Apply("WARRIOR", "dps",
            { macros = false, bars = false, binds = false, cvars = false, layout = false,
                onComplete = function() completed = true end })
        check("cosmetic failure cannot fail Apply or suppress its completion", applied.status == "applied" and completed)
        undone = RikUI.Setup.Undo()
        check("cosmetic failure cannot fail Undo or retain its snapshot", undone.status == "undone" and not RikUI.CharDB.undo)
        bars.Refresh = refresh
        bars = loadBars({ ghosts = false }, marker)
        check("saved disabled preference survives reload", RikUI.Profile.ghosts == false
            and not bars.Frames.main.buttons[7].ghost.shown)
        bars = loadBars({}, nil)
        check("no applied preset does not suggest actions", not bars.Frames.main.buttons[7].ghost.shown)
    end)
    for _, name in ipairs(names) do _G[name] = saved[name] end
    env.inCombat = false
    if not ok then error(reason) end
end
