-- Labelled setup settings. See docs/core.md for selection and snapshot contracts.
local core = RikUI
local cvars = {}
core.CVars = cvars

cvars.List = {
    { name = "cameraDistanceMaxZoomFactor", value = 2.6, label = "Maximum camera zoom" },
    { name = "cameraSmoothStyle", value = 0, label = "Disable camera following" },
    { name = "nameplateShowEnemies", value = 1, label = "Show enemy nameplates" },
    { name = "nameplateShowFriends", value = 0, label = "Hide friendly nameplates" },
    { name = "nameplateMotion", value = 1, label = "Stack nameplates" },
    { name = "autoLootDefault", value = 1, label = "Enable auto loot" },
    { name = "SpellQueueWindow", value = 400, label = "Spell queue window (400 ms)" },
    { name = "floatingCombatTextCombatDamage", value = 1, label = "Show floating damage" },
    { name = "floatingCombatTextCombatHealing", value = 1, label = "Show floating healing" },
    { name = "showTimestamps", value = "%H:%M ", label = "Show chat timestamps (24-hour)" },
    { name = "chatBubbles", value = 1, label = "Show chat bubbles" },
    { name = "chatBubblesParty", value = 0, label = "Hide party chat bubbles" },
    { name = "screenshotQuality", value = 10, label = "Maximum screenshot quality" },
}

local function skip(name, reason)
    core:Print("Skipped " .. name .. ": " .. reason)
end

local function readCurrent(name)
    if not C_CVar or type(C_CVar.GetCVarInfo) ~= "function" then
        skip(name, "CVar lookup unavailable")
        return nil
    end
    local ok, value = pcall(C_CVar.GetCVarInfo, name)
    if not ok then skip(name, "CVar lookup failed") return nil end
    if value == nil then skip(name, "unknown CVar") return nil end
    return value
end

local function capture(selection)
    local prior = {}
    for _, entry in ipairs(cvars.List) do
        if selection == nil or selection[entry.name] == true then
            prior[entry.name] = readCurrent(entry.name)
        end
    end
    return prior
end

local function applyEntry(entry)
    if not C_CVar or type(C_CVar.SetCVar) ~= "function" then
        skip(entry.name, "CVar setter unavailable")
        return
    end
    local value = tostring(entry.value)
    local ok, accepted = pcall(C_CVar.SetCVar, entry.name, value)
    if not ok then skip(entry.name, "CVar write failed") return end
    if accepted ~= true then skip(entry.name, "CVar write rejected") return end
    core:Print("Applied " .. entry.name .. " = " .. value)
end

function cvars.Snapshot()
    return capture()
end

function cvars.Apply(selection)
    assert(selection == nil or type(selection) == "table", "CVars.Apply needs a selection table or nil")
    -- Finish the snapshot before SetCVar can trigger changes to other settings.
    local prior = capture(selection)
    for _, entry in ipairs(cvars.List) do
        if prior[entry.name] ~= nil then applyEntry(entry) end
    end
    return prior
end

core:RegisterCommand("cvars", function() cvars.Apply() end, "Apply the recommended game settings")
