-- Layout registry contracts; protected writes fail even when a callback catches errors.
return function(check)
    local env = require("wow_stub")
    local originalCreate, originalParent = CreateFrame, UIParent
    local protectedWrites, combatWrites = 0, 0
    local function renderer(kind, name, parent, template)
        local f = originalCreate(kind, name, parent, template)
        local methods = getmetatable(f).__index
        setmetatable(f, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        f.scale, f.width, f.height = 1, 100, 30
        local function write()
            if f.secure then
                protectedWrites = protectedWrites + 1
                if InCombatLockdown() then combatWrites = combatWrites + 1; error("secure write in combat") end
            end
        end
        local hook, show, hide = f.HookScript, f.Show, f.Hide
        function f:HookScript(...) write(); return hook(self, ...) end
        function f:Show() write(); return show(self) end
        function f:Hide() write(); return hide(self) end
        function f:SetScale(value) write(); self.scale = value end
        function f:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
        function f:SetPoint(...) write(); self.point = { ... }; self.dragCenter = nil end
        function f:ClearAllPoints() write(); self.point = nil end
        function f:SetSize(w, h) write(); self.width, self.height = w, h end
        function f:GetWidth() return self.width end
        function f:GetHeight() return self.height end
        function f:SetMovable(value) write(); self.movable = value end
        function f:SetClampedToScreen(value) self.clamped = value end
        function f:SetFrameStrata(value) self.strata = value end
        function f:EnableMouse(value) self.mouseEnabled = value end
        function f:RegisterForDrag(...) self.dragButtons = { ... } end
        function f:StartMoving() write(); self.moving = true end
        function f:StopMovingOrSizing() write(); self.moving = false end
        function f:GetCenter()
            if self.dragCenter then return unpack(self.dragCenter) end
            if not self.parent then return 960, 540 end
            local p = self.point
            local cx, cy = self.parent:GetCenter()
            local ratio = self.parent:GetEffectiveScale() / self:GetEffectiveScale()
            return cx * ratio + (p and p[4] or 0), cy * ratio + (p and p[5] or 0)
        end
        return f
    end
    CreateFrame = renderer
    UIParent = renderer("Frame", "TestUIParent")
    UIParent.scale = 0.75
    -- No screen size: this suite covers the legacy movers, which save drops by their centre.
    UIParent.width, UIParent.height = nil, nil
    local defaults = { point = "CENTER", relativePoint = "CENTER", x = 25, y = -40 }
    local function boot(db, character, combat)
        env.frames, env.printed, env.inCombat = {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, db, character
        for _, file in ipairs({ "core.lua", "media.lua", "setup.lua", "setup-apply.lua",
            "setup-snapshot.lua", "setup-undo.lua", "layout-geometry.lua", "layout.lua", "layout-rects.lua", "motion.lua", "skin.lua", "layout-unlock.lua", "layout-drag.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Layout
    end
    local function register(layout, key, position)
        local frame = CreateFrame("Frame", key, UIParent)
        frame.secure = true
        layout.Register(frame, key, position or defaults)
        return frame
    end
    local function contains(text)
        for _, line in ipairs(env.printed) do if line:find(text, 1, true) then return true end end
        return false
    end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.00001 end
    local ok, reason = pcall(function()
        local layout = boot({ profiles = { Default = { scale = 0.8 } } })
        local target = register(layout, "example")
        check("registered frame receives defaults and profile scale", target.point[4] == 25 and target.scale == 0.8)
        local alternate = register(layout, "example")
        SlashCmdList.RIKUI("move")
        check("/rik move unlocks every group and never moves a registered frame itself", layout.IsMoving()
            and layout.IsUnlocked("example") and not target.moving)
        SlashCmdList.RIKUI("move")
        check("/rik move again locks them", not layout.IsMoving())
        -- A frame that drags itself (the bag header did) reports where it was dropped.
        target.dragCenter = { 1500, 800 }
        check("a dropped frame's centre is saved", layout.SaveCenter("example", target, RikUI.Profile))
        layout.Apply()
        local saved = RikUI.Profile.positions.example
        check("without a screen size the drop is kept as a centre offset with UIParent scale conversion",
            saved.point == "CENTER" and saved.relativePoint == "CENTER" and near(saved.x, 300) and near(saved.y, 125))
        check("all frames sharing key follow drop", target.point[4] == saved.x and alternate.point[5] == saved.y)
        local centerX, centerY = target:GetCenter()
        local account, character = RikUIDB, RikUICharDB
        layout = boot(account, character)
        target = register(layout, "example")
        check("reload uses saved position", target.point[1] == "CENTER" and near(target.point[4], 300))
        local reloadedX, reloadedY = target:GetCenter()
        check("reload preserves physical center at non-unit parent and frame scales",
            near(centerX * 0.6, reloadedX * target:GetEffectiveScale())
            and near(centerY * 0.6, reloadedY * target:GetEffectiveScale()))
        local group = layout.Register(target, "example", defaults)
        check("re-registering same frame does not duplicate group membership", #group.frames == 1)
        check("registered target remains anchored to UIParent", target.point[2] == UIParent)
        SlashCmdList.RIKUI("scale 1.25")
        check("scale command persists and applies to every registered frame", RikUI.Profile.scale == 1.25
            and target.scale == 1.25)
        for _, value in ipairs({ "", "0", "-1", "nan", "inf", "1 2" }) do
            SlashCmdList.RIKUI("scale " .. value)
            check("invalid scale is rejected: " .. value, RikUI.Profile.scale == 1.25)
        end
        SlashCmdList.RIKUI("move")
        local before = protectedWrites
        env.inCombat = true
        env.fire("PLAYER_REGEN_DISABLED")
        SlashCmdList.RIKUI("move")
        SlashCmdList.RIKUI("move reset")
        SlashCmdList.RIKUI("scale 2")
        check("combat locks every group and refuses all layout mutations", not layout.IsMoving()
            and not layout.IsUnlocked("example") and contains("combat") and protectedWrites == before
            and combatWrites == 0)
        check("combat never changes a saved position", near(saved.x, 300)
            and RikUI.Profile.positions.example == saved and RikUI.Profile.scale == 1.25)
        RikUI.Profile.positions.example = { point = "TOP", relativePoint = "BOTTOM", x = 7, y = 8 }
        layout.Apply()
        layout.Apply()
        check("layout apply is deferred in combat", protectedWrites == before)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("queued layout applies latest profile after combat", target.point[1] == "TOP" and target.point[4] == 7)
        SlashCmdList.RIKUI("move reset")
        check("reset copies defaults and keeps scale", target.point[4] == 25 and target.point[5] == -40
            and RikUI.Profile.positions.example ~= defaults and RikUI.Profile.scale == 1.25)
        RikUI.Profile.positions.example.x = 90
        SlashCmdList.RIKUI("move reset")
        check("editing saved position never mutates defaults", target.point[4] == 25)
        RikUI.Profile.positions.example = { point = "bad", relativePoint = false, x = 0/0, y = math.huge }
        RikUI.Profile.scale = -4
        layout.Apply()
        check("malformed saved coordinates and scale fall back", target.point[1] == "CENTER"
            and target.point[4] == 25 and target.point[5] == -40 and target.scale == 1)
        SlashCmdList.RIKUI("scale 0.8")
        check("scale applies while a position is malformed", target.scale == 0.8
            and RikUI.Profile.positions.example.point == "bad")
        SlashCmdList.RIKUI("move reset")
        check("reset replaces a malformed position with the default", RikUI.Profile.positions.example.x == 25)
        local savedCenter = target.GetCenter
        target.GetCenter = function() return nil end
        check("a frame without geometry cannot be saved and keeps its coordinates",
            not layout.SaveCenter("example", target, RikUI.Profile) and RikUI.Profile.positions.example.x == 25)
        target.GetCenter = savedCenter
        RikUI.DB.profiles.Other = { scale = 0.6, positions = {
            example = { point = "LEFT", relativePoint = "LEFT", x = 11, y = 12 },
        } }
        SlashCmdList.RIKUI("move")
        check("profile switch applies layout and locks every group", RikUI:SetProfile("Other")
            and target.scale == 0.6 and target.point[4] == 11 and not layout.IsMoving())
        check("the new profile's position stands", RikUI.Profile.positions.example.x == 11)
        check("unknown profile is rejected", not RikUI:SetProfile("Missing") and RikUI.CharDB.profile == "Other")
        env.inCombat = true
        check("profile switching in combat is refused", not RikUI:SetProfile("Default") and RikUI.CharDB.profile == "Other")
        env.inCombat = false

        RikUI.Presets.WARRIOR = { roles = { dps = {} }, bars = {}, macros = {},
            positions = { main = { point = "BOTTOM", relativePoint = "BOTTOM", x = 10, y = 20 } } }
        RikUI.Profile.positions.duringApply = { point = "CENTER", relativePoint = "CENTER", x = 777, y = 0 }
        local capture = RikUI.Setup.CaptureSnapshot
        RikUI.Setup.CaptureSnapshot = function(...)
            local snapshot, failure = capture(...)
            register(layout, "duringApply")
            return snapshot, failure
        end
        local applied = RikUI.Setup.Apply("WARRIOR", "dps", { macros = false, bars = false, binds = false, cvars = false })
        RikUI.Setup.CaptureSnapshot = capture
        check("late registration cannot expand a captured Apply write set", RikUI.Profile.positions.duringApply.x == 777)
        check("setup writes registered defaults alongside partial preset overrides", applied.status == "applied"
            and target.point[4] == 25 and RikUI.Profile.positions.main.x == 10)
        local undone = RikUI.Setup.Undo()
        check("setup undo restores registered frames", undone.status == "undone" and target.point[4] == 11)
        check("Undo preserves late registered position", RikUI.Profile.positions.duringApply.x == 777)
        layout = boot(nil, nil, true)
        before = protectedWrites
        target = register(layout, "late")
        check("combat registration does not touch target", protectedWrites == before and target.point == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("combat registration applies after regen", target.point[4] == 25)
        check("no protected write attempted in combat", combatWrites == 0)
    end)
    CreateFrame, UIParent = originalCreate, originalParent
    env.inCombat = false
    check("layout mover suite completes", ok, reason)
end
