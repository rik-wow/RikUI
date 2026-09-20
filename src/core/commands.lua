-- Slash commands and diagnostics; registration order is stable.
local core, runtime = RikUI, RikUI.Runtime
local commands, commandOrder = {}, {}
local moduleOrder = runtime.moduleOrder
local reportFailure, invoke = runtime.Report, runtime.Invoke

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
            invoke("Debug " .. name, module.Debug, module, report)
        end
    end
    if not reported then self:Print("No module diagnostic dependencies registered yet.") end
end

function core:RegisterCommand(name, callback, description)
    assert(type(name) == "string" and name:match("^[a-z]+$"), "Command names use lowercase letters")
    assert(type(callback) == "function" and type(description) == "string", "Command needs a callback and description")
    assert(not commands[name], "Command already registered: " .. name)
    commands[name] = { callback = callback, description = description }
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
    invoke("Command " .. name, command.callback, args)
end
