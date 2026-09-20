local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Shared hide helper: reversible parking, combat queueing and native reattachment.
return function(check)
    local env = require("wow_stub")
    local function frame(parent)
        local f = { parent = parent, events = { UNIT_HEALTH = true }, writes = 0 }
        function f:GetParent() return self.parent end
        function f:SetParent(value)
            if self.nativeWrite then self.nativeWrite = nil
            else assert(not InCombatLockdown(), "frame reparented in combat") end
            self.parent, self.writes = value, self.writes + 1
        end
        function f:UnregisterAllEvents() self.events = {}; self.unregistered = (self.unregistered or 0) + 1 end
        function f:GetName() return "Fake" end
        return f
    end
    local ok, reason = pcall(function()
        env.frames, env.inCombat, env.printed = {}, false, {}
        EditModeManagerFrame.hooks.OnShow = nil
        RikUIDB, RikUICharDB = nil, nil
        assert(loadfile("src/core/core.lua"))("RikUI", {})
        assert(loadfile("src/platform/hide.lua"))("RikUI", {})
        local hide = RikUI.Hide
        check("helper exposes Frame, Restore and IsHidden", type(hide.Frame) == "function"
            and type(hide.Restore) == "function" and type(hide.IsHidden) == "function")
        check("non-frame arguments are refused", hide.Frame(42) == nil and hide.Frame({}) == nil)

        local a = frame(UIParent)
        check("Frame hides immediately out of combat", hide.Frame(a, true) == true and a.parent ~= UIParent
            and a.parent:IsShown() == false and hide.IsHidden(a) == true)
        local hidden = a.parent
        check("hidden parent is the shared container", hidden == RikUIHiddenFrames and hidden.parent == UIParent)
        check("keepEvents leaves native events registered", a.events.UNIT_HEALTH == true and a.unregistered == nil)

        local b = frame(UIParent)
        hide.Frame(b, false)
        check("keepEvents false unregisters events once", b.parent == hidden and b.unregistered == 1 and next(b.events) == nil)
        hide.Frame(b, false)
        check("repeated hide neither unregisters again nor rewrites the parent", b.unregistered == 1 and b.writes == 1)

        local restored
        check("Restore returns the frame to its original parent",
            hide.Restore(a, function(f) restored = f end) == true and a.parent == UIParent and restored == a
            and hide.IsHidden(a) == false)
        check("Restore of an unknown frame is refused", hide.Restore(frame(UIParent)) == nil)

        hide.Frame(a, true)
        local other = frame(UIParent)
        a:SetParent(other)
        check("native reparent while hidden is re-parked", a.parent == hidden)
        hide.Restore(a)
        check("restore follows the latest native parent", a.parent == other)

        env.inCombat = true
        local c = frame(UIParent)
        check("combat hide is queued without a parent write", hide.Frame(c, true) == true and c.parent == UIParent
            and c.writes == 0 and hide.IsHidden(c) == true)
        hide.Restore(c)
        hide.Frame(c, true)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("queued work applies the latest request after combat", c.parent == hidden and c.writes == 1)
        env.inCombat = true
        c.nativeWrite = true
        c:SetParent(UIParent)
        check("native combat reparent waits for the queue", c.parent == UIParent)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("queued repair re-parks after combat", c.parent == hidden)

        env.printed = {}
        env.runScript(EditModeManagerFrame, "OnShow")
        check("opening Edit Mode prints exactly one warning line", #env.printed == 1
            and env.printed[1]:find("Edit Mode", 1, true) ~= nil)
        env.runScript(EditModeManagerFrame, "OnShow")
        check("each Edit Mode open prints one line", #env.printed == 2)
    end)
    env.inCombat = false
    check("hide helper suite completes", ok, reason)
end
