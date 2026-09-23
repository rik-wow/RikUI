return function(check)
    local savedCore, savedCVar, savedRegistry = RikUI, C_CVar, EventRegistry
    local seen, writes, warnings = { [3] = true }, 0, {}
    local active = { stopped = false, acknowledged = false }
    local callbacks = { ["Supertracking.OnChanged"] = { [active] = function() end } }
    function active:GetTutorialCVar() return "closedInfoFrames" end
    function active:GetTutorialFlag() return 8 end
    function active:StopTimer() self.stopped = true end
    function active:AcknowledgeTutorial() self.acknowledged = true; callbacks["Supertracking.OnChanged"][self] = nil end
    local ok, reason = pcall(function()
        RikUI = { Print = function(_, message) warnings[#warnings + 1] = message end }
        C_CVar = {
            GetCVarBitfield = function(name, flag) assert(name == "closedInfoFrames"); return seen[flag] end,
            SetCVarBitfield = function(name, flag, value) assert(name == "closedInfoFrames"); seen[flag] = value; writes = writes + 1 end,
        }
        EventRegistry = { GetCallbackTables = function() return { callbacks } end }
        assert(loadfile("src/platform/tutorials.lua"))()
        check("tutorial acknowledgement succeeds", RikUI.Tutorials.Acknowledge(8))
        check("tutorial uses one bit without clearing other acknowledgements", seen[3] and seen[8] and writes == 1)
        check("already running tutorial timer is cancelled and deactivated", active.stopped and active.acknowledged)
        check("acknowledgement is idempotent", RikUI.Tutorials.Acknowledge(8) and writes == 1)
        check("missing tutorial enum is harmless", not RikUI.Tutorials.Acknowledge(nil) and writes == 1)
        C_CVar.SetCVarBitfield = function() error("refused") end
        check("failed writes are reported", not RikUI.Tutorials.Acknowledge(9) and #warnings == 1)
        RikUI.Tutorials.Acknowledge(9)
        check("failed acknowledgement warns once", #warnings == 1)
        C_CVar = {}
        check("unavailable bitfield API is harmless", not RikUI.Tutorials.Acknowledge(10))
    end)
    RikUI, C_CVar, EventRegistry = savedCore, savedCVar, savedRegistry
    check("tutorial suite completes", ok, reason)
end
