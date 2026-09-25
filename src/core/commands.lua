-- Slash commands and diagnostics; registration order is stable.
local core, runtime = RikUI, RikUI.Runtime
local commands, commandOrder = {}, {}
local moduleOrder = runtime.moduleOrder
local reportFailure, invokeOwned = runtime.Report, runtime.InvokeOwned

local function reportValues(label, ok, ...)
    if not ok then reportFailure(label, ...) return end
    local count = select("#", ...)
    if count == 0 then core:Print(label .. ": no values returned") return end
    for i = 1, count do
        core:Print(label .. "[" .. i .. "] secret=" .. tostring(issecretvalue((select(i, ...)))))
    end
end

function core:Debug()
    if not runtime.initialized then self:Print("Still loading.") return end
    self:Print("debug: profile=" .. self.CharDB.profile .. ", modules=" .. #moduleOrder)
    local reported = false
    for _, name in ipairs(moduleOrder) do
        local module = self.Modules[name]
        if module.Debug then
            reported = true
            local function report(label, reader, ...)
                reportValues(name .. "." .. label, self.Secret.Read(reader, ...))
            end
            invokeOwned(module, "Debug " .. name, module.Debug, module, report)
        end
    end
    if not reported then self:Print("No module diagnostic dependencies registered yet.") end
end

function core:RegisterCommand(name, callback, description, owner)
    assert(type(name) == "string" and name:match("^[a-z]+$"), "Command names use lowercase letters")
    assert(type(callback) == "function" and type(description) == "string", "Command needs a callback and description")
    assert(not commands[name], "Command already registered: " .. name)
    if owner == nil then owner = runtime.owner end
    commands[name] = { callback = callback, description = description, owner = owner }
    table.insert(commandOrder, name)
end

function core:HasCommand(name)
    return type(name) == "string" and commands[name] ~= nil
end

local function showHelp()
    core:Print("Commands:")
    for _, name in ipairs(commandOrder) do
        core:Print("/rik " .. name .. " - " .. commands[name].description)
    end
end

core:RegisterCommand("profile", function(name)
    if not runtime.initialized then core:Print("Still loading."); return end
    if name == "" then
        core:Print("Saved profiles (* selected):")
        for _, saved in ipairs(core:GetProfileNames()) do
            core:Print((saved == core.CharDB.profile and "* " or "  ") .. saved)
        end
        return
    end
    local ok, reason = core:SetProfile(name)
    if not ok then core:Print(reason); return end
    core:Print("Selected profile: " .. core.CharDB.profile)
    if core:ProfileNeedsReload() then core:Print("Reload UI to apply all profile settings.") end
end, "List or select a saved profile: /rik profile [exact name]")

local function moduleStatus(name)
    local state, reason = core:GetModuleState(name)
    if not state then core:Print("Unknown module: " .. name); return end
    core:Print(name .. ": " .. state .. "; next reload=" .. (core.Profile.modules[name] ~= false and "on" or "off")
        .. (reason and ("; " .. reason) or ""))
end

core:RegisterCommand("module", function(args)
    if not runtime.initialized then core:Print("Still loading."); return end
    if args == "" then
        local names = {}
        for name in pairs(core.Modules) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do moduleStatus(name) end
        return
    end
    local name, action = args:match("^(%S+)%s+(%S+)$")
    if not name then name, action = args:match("^(%S+)$"), "status" end
    if not name or (action ~= "status" and action ~= "on" and action ~= "off") then
        core:Print("Usage: /rik module [name [status|on|off]]"); return
    end
    if action ~= "status" then
        local ok, reason = core:SetModuleEnabled(name, action == "on")
        if not ok then core:Print(reason); return end
        core:Print("Module choices saved. Reload UI to apply.")
    end
    moduleStatus(name)
end, "List modules or change next-reload choices: /rik module [name [status|on|off]]")

core:RegisterCommand("errors", function(args)
    if args == "clear" then core:ClearErrors(); core:Print("Session errors cleared."); return end
    if args ~= "" then core:Print("Usage: /rik errors [clear]"); return end
    local entries = core:GetErrors()
    core:Print("Retained session errors: " .. #entries .. " (up to 20 distinct errors)")
    for _, entry in ipairs(entries) do
        core:Print(entry.context .. ": " .. entry.detail .. " (x" .. entry.count .. ")")
    end
end, "Show session errors; use clear to reset")
core:RegisterCommand("help", showHelp, "Show available commands")
core:RegisterCommand("debug", function() core:Debug() end, "Show module dependency secrecy")
SLASH_RIKUI1 = "/rik"
SlashCmdList.RIKUI = function(message)
    if type(message) ~= "string" then showHelp() return end
    local name, args = message:match("^%s*(%S*)%s*(.-)%s*$")
    name = name:lower()
    if name == "" then showHelp() return end
    local command = commands[name]
    if not command then
        core:Print("Unknown command: " .. name)
        showHelp()
        return
    end
    invokeOwned(command.owner, "Command " .. name, command.callback, args)
end
