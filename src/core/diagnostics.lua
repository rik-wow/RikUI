-- Bounded blocked-action evidence; unavailable metadata must not erase an incident.
local core, runtime = RikUI, RikUI.Runtime
local MAX_RECORDS, MAX_FIELD, MAX_STACK = 20, 512, 4096
local TAINT_LOG_LEVEL = "1"

local function plain(value, limit)
    if core.Secret.IsSecret(value) or type(value) ~= "string" then return nil end
    return value:sub(1, limit or MAX_FIELD):gsub("[%c|]", " ")
end

local function read(reader, ...)
    if type(reader) ~= "function" then return nil end
    local ok, value = pcall(reader, ...)
    if not ok or core.Secret.IsSecret(value) then return nil end
    return value
end

local function clean(row)
    if type(row) ~= "table" or core.Secret.IsSecret(row) then return nil end
    local combat = rawget(row, "combat")
    if core.Secret.IsSecret(combat) or type(combat) ~= "boolean" then combat = nil end
    return { event = plain(rawget(row, "event")), func = plain(rawget(row, "func")) or "<unavailable>",
        at = plain(rawget(row, "at")), combat = combat, zone = plain(rawget(row, "zone")),
        stack = plain(rawget(row, "stack"), MAX_STACK) }
end

local function history()
    local source = core.DB and core.DB.blockedActions
    local rows = {}
    if type(source) ~= "table" or core.Secret.IsSecret(source) then return rows end
    for index = 1, MAX_RECORDS do
        local row = clean(rawget(source, index))
        if row then rows[#rows + 1] = row end
    end
    return rows
end

function core:GetBlockedActions() return history() end

function core:ClearBlockedActions()
    if self.DB then self.DB.blockedActions = {} end
end

core:RegisterCommand("blocked", function(args)
    if args == "clear" then core:ClearBlockedActions(); core:Print("Blocked-action history cleared."); return end
    if args ~= "" then core:Print("Usage: /rik blocked [clear]"); return end
    local rows = core:GetBlockedActions()
    core:Print("Retained blocked actions: " .. #rows)
    for _, row in ipairs(rows) do
        core:Print((row.at or "<unavailable>") .. " " .. (row.event or "<unavailable>") .. ": "
            .. row.func .. "; combat=" .. (row.combat == nil and "<unavailable>" or tostring(row.combat)))
    end
end, "Inspect or clear blocked-action diagnostics")

local function enableTaintLog()
    local set = C_CVar and C_CVar.SetCVar or SetCVar
    if type(set) == "function" then pcall(set, "taintLog", TAINT_LOG_LEVEL) end
end

local function record(event, addon, func)
    if core.Secret.IsSecret(addon) or addon ~= runtime.addonName then return end
    local row = clean({ event = event, func = func, at = read(date, "%Y-%m-%d %H:%M:%S"),
        combat = read(InCombatLockdown), zone = read(GetRealZoneText), stack = read(debugstack, 3, 12, 0) })
    local rows, reported = history(), false
    for _, previous in ipairs(rows) do
        if previous.func == row.func then reported = true; break end
    end
    table.insert(rows, 1, row)
    rows[MAX_RECORDS + 1] = nil
    if core.DB then core.DB.blockedActions = rows end
    -- Loading the addon never writes this CVar.
    enableTaintLog()
    if not reported then
        core:Print("Blocked call " .. row.func .. (row.combat == true and " in combat" or "")
            .. " was recorded in RikUI diagnostics.")
    end
end

core:RegisterEvent("ADDON_ACTION_BLOCKED", record)
core:RegisterEvent("ADDON_ACTION_FORBIDDEN", record)
