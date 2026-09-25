local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Recording widgets test cosmetic contracts; they do not emulate client protection.
return function(check)
    local env = require("wow_stub")
    local animate = dofile("tests/group_motion_stub.lua")
    local names = { "CreateFrame", "C_ActionBar", "GetActionTexture", "GetBindingKey",
        "ActionButtonDown", "ActionButtonUp", "MultiActionButtonDown", "MultiActionButtonUp",
        "GetActionButtonForID", "ActionButton1", "MultiBarBottomLeft", "GetActionCooldown" }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local actions, bindings, subscriptions, nativeCalls = {}, {}, {}, 0
    local native = { action = 1 }
    local function protected() assert(not InCombatLockdown(), "protected write in combat") end
    local function region(r, parent)
        r.parent = parent
        function r:SetParent(value) protected(); self.parent = value end
        function r:SetVertexColor(...) self.color = { ... } end
        function r:SetAlpha(v) self.alpha = v end
        function r:SetShown(v) self.shown = v end
        function r:SetTexture(v) self.texture = v end
        function r:SetFont(path, size, flags) self.fontPath, self.fontSize, self.fontFlags = path, size, flags; return true end
        function r:SetTexCoord(...) self.coords = { ... } end
        function r:SetAlphaFromBoolean(value, yes, no) self.active, self.yes, self.no = value, yes, no end
        function r:SetHeight(value) self.height = value end
        function r:SetWidth(value) self.width = value end
        function r:SetFormattedText(fmt, v) self.format, self.value = fmt, v end
        animate(r)
        return r
    end
    CreateFrame = function(kind, name, parent, template)
        protected()
        local f = saved.CreateFrame(kind, name, parent, template)
        local methods = getmetatable(f).__index
        setmetatable(f, { __index = function(t, k)
            if k:match("^[A-Z]") then return methods(t, k) end
        end })
        f.alpha, f.level = 1, parent and (rawget(parent, "level") or 0) + 1 or 0
        function f:GetFrameLevel() return self.level end
        function f:SetFrameLevel(level) protected(); self.level = level end
        function f:SetAttribute(k, v) protected(); self.attributes[k] = v end
        function f:ClearNormalTexture() self.normalTexture = nil; self.normalSet = true end
        function f:SetHighlightTexture(v) self.highlightTexture = v end
        function f:SetPushedTexture(v) self.pushedTexture = v end
        function f:SetPoint(...) protected() end
        function f:SetParent(v) protected(); self.parent = v end
        function f:SetScale(v) protected() end
        function f:SetAlpha(v) self.alpha = v end
        function f:GetAlpha() return self.alpha end
        function f:GetEffectiveAlpha() return self.alpha end
        function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
        function f:SetCooldownFromDurationObject(v) self.duration = v end
        function f:Clear() self.duration = nil; self.clears = (self.clears or 0) + 1 end
        function f:SetHideCountdownNumbers(v) self.hideNumbers = v end
        function f:SetDrawSwipe(v) self.drawSwipe = v end
        function f:SetSwipeTexture(v) self.swipeTexture = v end
        function f:SetMinimumCountdownDuration(v) self.minimumCountdown = v end
        local texture, font = f.CreateTexture, f.CreateFontString
        function f:CreateTexture(...) return region(texture(self, ...), self) end
        function f:CreateFontString(...) return region(font(self, ...), self) end
        function f:GetCountdownFontString() self.font = self.font or self:CreateFontString(); return self.font end
        local group = { Stop = function() end, Play = function() end, IsPlaying = function() return false end,
            SetScript = function() end, CreateAnimation = function() return setmetatable({}, { __index = function() return function() end end }) end }
        function f:CreateAnimationGroup() return group end
        return f
    end
    -- The suite's shared UIParent has only the minimal stub methods.
    local visible = UIParent.IsVisible
    UIParent.IsVisible = function() return true end
    C_ActionBar = {
        GetActionTexture = function(slot) return actions[slot] and 123 end,
        GetActionDisplayCount = function(slot) return actions[slot] and actions[slot].count or "" end,
        GetActionCooldownDuration = function(slot)
            if actions[slot] and actions[slot].failCooldown then error("cooldown unavailable") end
            return actions[slot] and actions[slot].cooldown
        end,
        GetActionChargeDuration = function(slot) return actions[slot] and actions[slot].charge end,
        IsUsableAction = function(slot)
            local a = actions[slot] or {}
            return a.usable, a.resource
        end,
        IsActionInRange = function(slot) return actions[slot] and actions[slot].range end,
        IsCurrentAction = function(slot)
            if actions[slot] and actions[slot].failCurrent then error("current action unavailable") end
            return actions[slot] and actions[slot].current or false
        end,
        IsAutoRepeatAction = function(slot) return actions[slot] and actions[slot].repeating or false end,
        EnableActionRangeCheck = function(slot, enabled) subscriptions[slot] = enabled end,
    }
    GetBindingKey = function(command) return bindings[command] end
    GetActionCooldown = function() error("raw cooldown reader must not render") end
    GetActionButtonForID = function() return native end
    ActionButton1 = native
    MultiBarBottomLeft = { actionButtons = { { action = 61 } } }
    for _, name in ipairs({ "ActionButtonDown", "ActionButtonUp", "MultiActionButtonDown", "MultiActionButtonUp" }) do
        _G[name] = function() nativeCalls = nativeCalls + 1 end
    end
    for _, event in ipairs({ "UPDATE_BINDINGS", "SPELL_UPDATE_CHARGES", "UPDATE_INVENTORY_ALERTS",
        "BAG_UPDATE_DELAYED", "SPELL_UPDATE_ICON", "ACTIONBAR_UPDATE_COOLDOWN", "ACTION_USABLE_CHANGED",
        "ACTION_RANGE_CHECK_UPDATE", "PLAYER_TARGET_CHANGED", "UNIT_POWER_UPDATE", "ACTIONBAR_UPDATE_STATE" }) do env.KNOWN_EVENTS[event] = true end
    local function color(button, r, g, b)
        local c = button.icon.color or {}
        return c[1] == r and c[2] == g and c[3] == b
    end
    local ok, reason = pcall(function()
        env.frames, env.printed, env.inCombat = {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        for _, file in ipairs({ "src/core/core.lua", "src/platform/hooks.lua", "src/ui/media.lua", "src/ui/motion.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/character/bindings.lua",
            "data/bonus-pages.lua", "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua", "src/modules/bars/bars.lua", "src/modules/bars/bars-skin.lua", "src/modules/bars/bars-ghosts.lua", "src/modules/bars/bars-paging.lua", "src/modules/bars/bars-state.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        RikUI.Bars.UpdateStockVisibility = function() end
        actions[1] = { cooldown = {}, charge = {}, count = env.SECRET, usable = true, range = true }
        actions[61], actions[73] = { usable = true, range = true }, { usable = true, range = true }
        bindings.ACTIONBUTTON1, bindings.MULTIACTIONBAR1BUTTON1 = "1", "SHIFT-1"
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        local bars, first = RikUI.Bars, RikUI.Bars.Frames.main.buttons[1]
        for name, bar in pairs(bars.Frames) do
            for _, button in ipairs(bar.buttons) do
                check(name .. " keeps ghost below hotkeys and feedback", button.ghost:GetFrameLevel() < button.stateOverlay:GetFrameLevel())
                check(name .. " uses flat media and trimmed icons", button.normalSet and button.normalTexture == nil
                    and button.highlightTexture == RikUI.Media.highlight and button.pushedTexture == RikUI.Media.highlight
                    and button.icon.coords[1] == 0.07 and button.icon.coords[2] == 0.93)
                check(name .. " uses consistent media type scale", button.hotkey.fontPath == RikUI.Media.font
                    and button.hotkey.fontSize == 12 and button.count.fontPath == RikUI.Media.font
                    and button.count.fontSize == 12 and button.cooldown.font.fontSize == 16
                    and button.chargeCooldown.font.fontSize == 11)
                check(name .. " keeps four one-pixel borders above cooldowns", #button.border == 4
                    and button.border[1].height == 1 and button.border[3].width == 1
                    and button.border[1].parent == button.stateOverlay)
            end
        end
        check("buttons have cosmetic hover and page fades", first.motion and first.motion.hoverIn and first.motion.entry)
        env.inCombat = true
        env.runScript(first, "OnEnter")
        check("hover animation starts without protected writes", first.motion.hoverIn.playing)
        env.runScript(first, "OnMouseDown", "LeftButton")
        check("mouse press animates feedback", first.motion.press.playing)
        env.runScript(first.cooldown, "OnCooldownDone")
        check("native cooldown completion animates feedback", first.motion.done.playing)
        env.runScript(first, "OnHide")
        check("hidden buttons stop feedback", not first.motion.press.playing and not first.motion.done.playing)
        env.inCombat = false
        actions[1].current = env.SECRET
        env.inCombat = true
        env.fire("ACTIONBAR_UPDATE_STATE")
        check("secret current action goes directly to active border", first.current.active == env.SECRET
            and first.current.yes == 1 and first.current.no == 0)
        actions[1].current, actions[1].repeating = false, true
        env.fire("ACTIONBAR_UPDATE_STATE")
        check("auto repeat has its own active border", first.current.active == false and first.repeating.active == true)
        actions[1].failCurrent = true
        env.fire("ACTIONBAR_UPDATE_STATE")
        check("failed current action clears stale border", first.current.active == false)
        actions[1].failCurrent, actions[1].repeating = nil, false
        env.inCombat = false
        -- Visibility is modeled explicitly; the stub does not execute native drivers.
        for _, bar in pairs(bars.Frames) do if bar.positionKey == "main" then bar:Hide() end end
        check("action button has native cooldown and charge widgets", first.cooldown and first.chargeCooldown)
        assert(first.cooldown and first.chargeCooldown, "cooldown state missing")
        check("main cooldown draws a textured pie swipe", first.cooldown.drawSwipe == true
            and first.cooldown.swipeTexture == "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
        check("global cooldowns of 1 s and 1.5 s show the pie without rounded-up numbers",
            first.cooldown.minimumCountdown > 1500 and first.cooldown.minimumCountdown < 2000
            and first.chargeCooldown.minimumCountdown == first.cooldown.minimumCountdown)
        check("slot duration objects feed widgets untouched", first.cooldown.duration == actions[1].cooldown
            and first.chargeCooldown.duration == actions[1].charge and first.cooldown.hideNumbers == false)
        check("text and flash share a visual frame above both cooldowns", first.stateOverlay
            and first.stateOverlay.level > first.cooldown.level and first.stateOverlay.level > first.chargeCooldown.level
            and first.hotkey.parent == first.stateOverlay and first.pressedFlash.parent == first.stateOverlay
            and first.count.parent == first.stateOverlay)
        check("existing count sink receives opaque display count", first.count.text == env.SECRET)
        check("labels reuse actual native commands", first.hotkey.text == "1"
            and bars.Frames.bar2.buttons[1].hotkey.text == "s1")
        check("each fixed slot enables native range notifications", subscriptions[1] and subscriptions[61])
        C_ActionBar.EnableActionRangeCheck(1, false)
        check("native bar hiding cannot disable owned slot range updates", subscriptions[1] == true)
        C_ActionBar.EnableActionRangeCheck(120, false)
        check("range subscription hook leaves unowned slots alone", subscriptions[120] == false)
        local bonus = bars.Create("bonus1", 73, { positionKey = "main" })
        bars.Frames.main:Hide()
        native.action = 73
        check("bonus row inherits main hotkeys", bonus.buttons[1].hotkey.text == "1")
        ActionButtonDown(1)
        check("native key flashes matching visible bonus only", bonus.buttons[1].pressedFlash.alpha == 1
            and first.pressedFlash.alpha == 0 and nativeCalls == 1)
        native.action = 1
        bonus:Hide()
        bars.Frames.main:Show()
        ActionButtonUp(1)
        check("release after page change clears previous flash", bonus.buttons[1].pressedFlash.alpha == 0)
        bars.Frames.main:Hide()
        for _, page in ipairs({ { "battle", 73 }, { "defensive", 85 }, { "berserker", 97 } }) do
            local overlay = assert(bars.Frames[page[1]], page[1] .. " overlay missing")
            local button = overlay.buttons[1]
            actions[page[2]] = { usable = true, range = true, cooldown = {}, count = "2" }
            env.fire("ACTIONBAR_SLOT_CHANGED", page[2])
            overlay:Show() -- The native visibility driver's result is modeled here.
            native.action = page[2]
            check(page[1] .. " shows its own action state and main binding",
                button:GetAttribute("action") == native.action and button.hotkey.text == "1"
                and button.cooldown.duration == actions[native.action].cooldown and button.count.text == "2")
            env.inCombat = true
            ActionButtonDown(1)
            check(page[1] .. " native key flashes the visible clicked slot in combat",
                button.pressedFlash.alpha == 1 and first.pressedFlash.alpha == 0)
            env.fire("UPDATE_BONUS_ACTIONBAR")
            check(page[1] .. " transition clears the old key flash", button.pressedFlash.alpha == 0)
            ActionButtonUp(1)
            env.inCombat = false
            overlay:Hide()
        end
        native.action = 1
        bars.Frames.main:Show()
        MultiActionButtonDown("MultiBarBottomLeft", 1)
        check("side bar native hook flashes correct fixed slot", bars.Frames.bar2.buttons[1].pressedFlash.alpha == 1)
        MultiActionButtonUp("MultiBarBottomLeft", 1)
        check("side bar release clears flash", bars.Frames.bar2.buttons[1].pressedFlash.alpha == 0)
        native.action = 13
        ActionButtonDown(1)
        check("different native page never flashes a misleading base button", first.pressedFlash.alpha == 0)
        ActionButtonUp(1)
        local manual = bars.Frames.page2.buttons[1]
        actions[13] = { usable = true, range = true, cooldown = {}, count = "3" }
        env.fire("ACTIONBAR_SLOT_CHANGED", 13)
        bars.Frames.main:Hide()
        bars.Frames.page2:Show()
        check("selected page inherits main labels and slot-owned state", manual.hotkey.text == "1"
            and manual.cooldown.duration == actions[13].cooldown and manual.count.text == "3")
        env.inCombat = true
        ActionButtonDown(1)
        check("native main key flashes the visible selected page in combat", manual.pressedFlash.alpha == 1
            and first.pressedFlash.alpha == 0)
        env.fire("ACTIONBAR_PAGE_CHANGED")
        check("page change clears the previous selected-page flash", manual.pressedFlash.alpha == 0)
        bars.Frames.page2:Hide()
        bars.Frames.page6:Show()
        native.action = 61
        ActionButtonDown(1)
        check("shared slot main key flashes only its main overlay", bars.Frames.page6.buttons[1].pressedFlash.alpha == 1
            and bars.Frames.bar2.buttons[1].pressedFlash.alpha == 0)
        ActionButtonUp(1)
        MultiActionButtonDown("MultiBarBottomLeft", 1)
        check("shared slot multibar key flashes only its multibar", bars.Frames.bar2.buttons[1].pressedFlash.alpha == 1
            and bars.Frames.page6.buttons[1].pressedFlash.alpha == 0)
        MultiActionButtonUp("MultiBarBottomLeft", 1)
        bars.Frames.page6:Hide()
        bars.Frames.main:Show()
        native.action = 1
        actions[1].range, actions[1].usable, actions[1].resource = false, false, true
        env.fire("ACTION_RANGE_CHECK_UPDATE", 1, false, true)
        check("out of range has red priority", color(first, 1, 0.2, 0.2))
        actions[1].range = true
        env.fire("ACTION_USABLE_CHANGED")
        check("resource shortage is blue", color(first, 0.2, 0.4, 1))
        actions[1].resource = false
        env.fire("ACTION_USABLE_CHANGED")
        check("unusable action is grey", color(first, 0.4, 0.4, 0.4))
        actions[1].usable = true
        actions[1].range = 0
        env.fire("PLAYER_TARGET_CHANGED")
        check("legacy numeric zero range is red", color(first, 1, 0.2, 0.2))
        actions[1].range, actions[1].usable, actions[1].resource = env.SECRET, env.SECRET, env.SECRET
        env.fire("ACTION_RANGE_CHECK_UPDATE", env.SECRET, env.SECRET, env.SECRET)
        env.fire("ACTION_USABLE_CHANGED")
        check("secret state takes neutral fallback", color(first, 1, 1, 1))
        bindings.ACTIONBUTTON1 = "BUTTON4"
        env.fire("UPDATE_BINDINGS")
        check("combat binding change refreshes short label", first.hotkey.text == "M4")
        actions[1].cooldown = {}
        env.fire("ACTIONBAR_UPDATE_COOLDOWN")
        check("combat cooldown event replaces duration object", first.cooldown.duration == actions[1].cooldown)
        actions[1].failCooldown = true
        env.fire("ACTIONBAR_UPDATE_COOLDOWN")
        check("failed cooldown read clears stale display", first.cooldown.duration == nil)
        actions[1] = nil
        env.fire("ACTIONBAR_SLOT_CHANGED", 1)
        check("empty action clears both timers and tint", first.cooldown.duration == nil
            and first.chargeCooldown.duration == nil and first.count.text == "" and color(first, 1, 1, 1))
        bindings.ACTIONBUTTON1 = nil
        env.fire("UPDATE_BINDINGS")
        check("unbound action clears stale label", first.hotkey.text == "")
        check("empty slot clears both active borders", first.current.active == false and first.repeating.active == false)
    end)
    env.inCombat = false
    UIParent.IsVisible = visible
    for _, name in ipairs(names) do _G[name] = saved[name] end
    if not ok then error(reason) end
end
