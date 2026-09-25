-- Read-only support snapshot. Never invokes feature diagnostics or serializes settings.
local core, runtime = RikUI, RikUI.Runtime
local MAX_REPORT, MAX_MODULES, MAX_FIELD = 20000, 256, 512

local function plain(value)
    if core.Secret.IsSecret(value) then return "<unavailable>" end
    if type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean" then return "<unavailable>" end
    return tostring(value):gsub("[%c|]", " "):sub(1, MAX_FIELD)
end

local function read(reader, ...)
    if type(reader) ~= "function" then return "<unavailable>" end
    local ok, value = pcall(reader, ...)
    return ok and plain(value) or "<unavailable>"
end

local function moduleLines(lines)
    local names = {}
    for name in pairs(core.Modules) do names[#names + 1] = name end
    table.sort(names)
    lines[#lines + 1] = "Modules: " .. #names
    for index = 1, math.min(#names, MAX_MODULES) do
        local name = names[index]
        local state, reason = core:GetModuleState(name)
        local enabled = not core.Profile or core.Profile.modules[name] ~= false
        lines[#lines + 1] = plain(name) .. ": " .. plain(state) .. "; next reload=" .. (enabled and "on" or "off")
            .. (reason and ("; " .. plain(reason)) or "")
    end
    if #names > MAX_MODULES then lines[#lines + 1] = "Additional modules omitted: " .. (#names - MAX_MODULES) end
end

function core:SupportReport()
    local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local lines = { "RikUI support report",
        "Addon version: " .. read(metadata, runtime.addonName, "Version"),
        "Client version: " .. read(GetBuildInfo),
        "Startup: initialized=" .. tostring(runtime.initialized) .. "; logged in=" .. tostring(runtime.loggedIn),
        "Profile reload pending: " .. tostring(self:ProfileNeedsReload()),
        "Queued work: " .. self.Combat.Pending() }
    local ok, _, build = pcall(GetBuildInfo)
    lines[#lines + 1] = "Client build: " .. (ok and plain(build) or "<unavailable>")
    moduleLines(lines)
    lines[#lines + 1] = "Backups: " .. read(self.Store and self.Store.BackupSummary)
    local errors = self:GetErrors()
    lines[#lines + 1] = "Retained errors: " .. #errors
    for _, entry in ipairs(errors) do
        lines[#lines + 1] = plain(entry.context) .. ": " .. plain(entry.detail) .. " (x" .. plain(entry.count) .. ")"
    end
    local text = table.concat(lines, "\n")
    if #text > MAX_REPORT then text = text:sub(1, MAX_REPORT - 32) .. "\n[Report truncated]" end
    return text
end

function core:OpenSupportReport()
    local report = self:SupportReport()
    if self.Sharing and self.Sharing.OpenDialog and not InCombatLockdown() then
        return self.Sharing.OpenDialog("RikUI support report", report, nil,
            "Copy with Ctrl-C. Contains module state and recorded errors; review before sharing.")
    end
    for line in report:gmatch("[^\n]+") do self:Print(line) end
    return report
end

core:RegisterCommand("support", function(args)
    if args ~= "" then core:Print("Usage: /rik support"); return end
    core:OpenSupportReport()
end, "Copy runtime, backup and error diagnostics")

