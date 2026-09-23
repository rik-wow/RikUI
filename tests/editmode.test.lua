-- Edit Mode re-applies its stored anchor and size to its systems whenever a layout applies. The guard
-- puts RikUI's values back after it, from the layout events, never from hooks on the system's own
-- methods (on 69977 those left the methods nil for Blizzard's callers).
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local restore = widgets.install()
    local savedManager, savedRegistry = EditModeManagerFrame, EventRegistry
    local state = { active = false, callbacks = {} }

    local function load(combat, bare)
        state.active, state.callbacks = false, {}
        widgets.loadAddon(env, { "src/platform/editmode.lua" }, nil, combat, function()
            EditModeManagerFrame, EventRegistry = nil, nil
            if bare then return end
            EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame", UIParent)
            function EditModeManagerFrame:IsEditModeActive() return state.active end
            EventRegistry = { RegisterCallback = function(_, event, callback, owner)
                state.callbacks[event] = function() callback(owner) end
            end }
        end)
        return RikUI.EditMode
    end
    -- What Blizzard's system does on a layout apply: its own anchor, then its stored size.
    local function system()
        local frame = CreateFrame("Frame", nil, UIParent)
        function frame:ApplySystemAnchor() self:ClearAllPoints(); self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10) end
        function frame:UpdateSystemSetting() self:SetSize(430, 120) end
        function frame:UpdateSystem() self:ApplySystemAnchor(); self:UpdateSystemSetting() end
        return frame
    end
    -- EditModeManagerFrame applying a layout: the system updates, then the event reaches RikUI.
    local function applyLayout(frame, event)
        frame:UpdateSystem()
        env.fire(event or "EDIT_MODE_LAYOUTS_UPDATED")
        env.flushTimers()
    end

    local ok, reason = pcall(function()
        local editmode = load()
        local frame, runs = system(), 0
        local methods = { rawget(frame, "UpdateSystem"), rawget(frame, "ApplySystemAnchor"), rawget(frame, "UpdateSystemSetting") }
        local function reapply(target)
            runs = runs + 1
            target:SetSize(520, 260)
        end
        check("a frame with the Edit Mode methods is guarded", editmode.Guard(frame, "test", reapply) == true)
        check("guarding writes nothing by itself", runs == 0 and frame.width == nil)
        check("the system's own methods are left untouched", rawget(frame, "UpdateSystem") == methods[1]
            and rawget(frame, "ApplySystemAnchor") == methods[2] and rawget(frame, "UpdateSystemSetting") == methods[3])
        applyLayout(frame)
        check("after Edit Mode applies a layout RikUI's size is back", frame.width == 520 and frame.height == 260)
        applyLayout(frame, "PLAYER_SPECIALIZATION_CHANGED")
        check("a spec change's layout apply is answered too", frame.width == 520 and runs == 2)
        check("guarding the same frame twice adds no second guard", editmode.Guard(frame, "test", reapply) == true
            and #editmode.Guards == 1)

        state.active, runs = true, 0
        applyLayout(frame)
        check("while Edit Mode is open the frame is left to Edit Mode", runs == 0 and frame.width == 430
            and editmode.IsActive())
        state.active = false
        state.callbacks["EditMode.Exit"]()
        check("leaving Edit Mode puts RikUI's values back", runs == 1 and frame.width == 520)

        local plain = CreateFrame("Frame", nil, UIParent)
        check("a frame without the Edit Mode methods is accepted and left alone",
            editmode.Guard(plain, "plain", reapply) == false and #editmode.Guards == 1)
        check("a missing frame is refused without an error", editmode.Guard(nil, "missing", reapply) == false)

        local failing = system()
        editmode.Guard(failing, "failing", function() error("boom") end)
        env.printed = {}
        applyLayout(failing)
        applyLayout(failing)
        check("a failing re-apply is reported once and never breaks the others",
            #env.printed == 1 and env.printed[1]:find("failing", 1, true) ~= nil and env.printed[1]:find("boom", 1, true) ~= nil
            and frame.width == 520)

        editmode = load()
        frame, runs = system(), 0
        editmode.Guard(frame, "test", reapply)
        env.inCombat = true
        applyLayout(frame)
        applyLayout(frame)
        check("in combat the re-apply waits", runs == 0 and frame.width == 430)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("and runs once when combat ends", runs == 1 and frame.width == 520)

        editmode = load(false, true)
        frame = system()
        check("a client without Edit Mode's manager or event registry still guards",
            editmode.Guard(frame, "test", reapply) == true and editmode.IsActive() == false)
        applyLayout(frame)
        check("and answers a layout apply", frame.width == 520)
    end)
    EditModeManagerFrame, EventRegistry = savedManager, savedRegistry
    restore()
    env.inCombat = false
    check("edit mode suite completes", ok, reason)
end
