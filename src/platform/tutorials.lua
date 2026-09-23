-- Acknowledge tutorials whose stock targets RikUI replaces.
local core, tutorials = RikUI, {}
core.Tutorials = tutorials
local CVAR, warnings = "closedInfoFrames", {}

-- The supertrack tutorial can have armed its timer before PLAYER_LOGIN. Its owner is
-- available through the registry's public callback tables. Snapshot owners before
-- acknowledging: deactivation unregisters them, and does not itself cancel the timer.
local function stopActive(flag)
    if not EventRegistry or type(EventRegistry.GetCallbackTables) ~= "function" then return end
    local active = {}
    for _, events in pairs(EventRegistry:GetCallbackTables()) do
        for owner in pairs(events["Supertracking.OnChanged"] or {}) do
            if type(owner) == "table" and type(owner.GetTutorialCVar) == "function"
                and type(owner.GetTutorialFlag) == "function"
                and owner:GetTutorialCVar() == CVAR and owner:GetTutorialFlag() == flag then
                active[owner] = true
            end
        end
    end
    for owner in pairs(active) do
        if type(owner.StopTimer) == "function" then owner:StopTimer() end
        if type(owner.AcknowledgeTutorial) == "function" then owner:AcknowledgeTutorial() end
    end
end

function tutorials.Acknowledge(flag)
    if type(flag) ~= "number" or flag < 1 or flag % 1 ~= 0 then return false end
    local api = C_CVar
    if type(api) ~= "table" or type(api.SetCVarBitfield) ~= "function" then return false end
    local ok, reason = pcall(function()
        if type(api.GetCVarBitfield) ~= "function" or not api.GetCVarBitfield(CVAR, flag) then
            if api.SetCVarBitfield(CVAR, flag, true) == false then error("bitfield write refused") end
        end
        stopActive(flag)
    end)
    if not ok and not warnings[flag] then
        warnings[flag] = true
        core:Print("Tutorial acknowledgement: " .. tostring(reason))
    end
    return ok
end
