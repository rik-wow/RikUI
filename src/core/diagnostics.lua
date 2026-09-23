-- Blocked-action evidence. When the client blocks or forbids a protected call
-- and names RikUI, record which function, when, and whether in combat, so the
-- tainting code can be found instead of guessed. The first block also switches
-- on the client's taint log, so Logs/taint.log names the source of later ones.
local core, runtime = RikUI, RikUI.Runtime
local MAX_RECORDS = 20
local TAINT_LOG_LEVEL = "1"   -- 1 logs blocked actions with the tainting source
local reported = {}

local function enableTaintLog()
    local set = C_CVar and C_CVar.SetCVar or SetCVar
    if type(set) == "function" then pcall(set, "taintLog", TAINT_LOG_LEVEL) end
end

local function record(event, addon, func)
    if addon ~= runtime.addonName then return end
    local db = core.DB
    local row = { event = event, func = tostring(func), at = date and date("%Y-%m-%d %H:%M:%S") or nil,
        combat = InCombatLockdown and InCombatLockdown() or false,
        zone = GetRealZoneText and GetRealZoneText() or nil,
        stack = debugstack and debugstack(3, 12, 0) or nil }
    if db then
        db.blockedActions = db.blockedActions or {}
        table.insert(db.blockedActions, 1, row)
        for index = #db.blockedActions, MAX_RECORDS + 1, -1 do db.blockedActions[index] = nil end
    end
    -- Only now: loading RikUI never writes CVars. Later blocks then show their source.
    enableTaintLog()
    if not reported[row.func] then
        reported[row.func] = true
        core:Print("Blocked call " .. row.func .. (row.combat and " in combat" or "")
            .. " was recorded; Logs/taint.log names the code that caused it.")
    end
end

core:RegisterEvent("ADDON_ACTION_BLOCKED", function(event, addon, func) record(event, addon, func) end)
core:RegisterEvent("ADDON_ACTION_FORBIDDEN", function(event, addon, func) record(event, addon, func) end)
