-- RikUI core. Loaded before data and modules; see docs/core.md for contracts.
local addonName = ...
local DEFAULT_PROFILE = "Default"
local PROFILE_DEFAULTS = { modules = {}, positions = {}, scale = 1, gryphons = false, tooltip = { hideInCombat = false },
    chat = { fontSize = 14, timestamps = true, locked = true, panel = true, classColors = true, shortTags = true,
        mentions = true, collapseRepeats = true, jumpButton = true, history = true, arrowHistory = true,
        stickyChannels = true, channelStrip = true, editColor = true, tabsVisible = true, nameClicks = true },
    questtracker = { collapsed = false } }
local ACCOUNT_DEFAULTS = { version = 1, profiles = { Default = PROFILE_DEFAULTS }, community = {} }
local CHARACTER_DEFAULTS = { profile = DEFAULT_PROFILE, askRole = true, wizardDone = false }

local core = { Modules = {}, Data = {}, Presets = {}, Secret = {}, Combat = {} }
RikUI = core
local frame = CreateFrame("Frame")
local events, rejectedEvents, moduleOrder, startedModules = {}, {}, {}, {}
local commands, commandOrder, combatQueue = {}, {}, {}
local initialized, loggedIn, draining = false, false, false

-- Only persisted configuration goes through this function, never unit values.
local function mergeDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = mergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

function core:Print(message)
    if issecretvalue(message) then message = "<secret>" end
    print("|cff80c0ffRikUI:|r " .. tostring(message))
end

local function reportFailure(context, reason)
    local detail = "unknown error"
    if not issecretvalue(reason) and type(reason) == "string" then detail = reason end
    core:Print(context .. ": " .. detail)
end

local function invoke(context, callback, ...)
    local ok, reason = pcall(callback, ...)
    if not ok then reportFailure(context, reason) end
    return ok
end

function core:RegisterEvent(event, callback)
    assert(type(event) == "string" and type(callback) == "function", "RegisterEvent needs an event and callback")
    if rejectedEvents[event] then return false end
    if not events[event] then
        local ok, registered = pcall(frame.RegisterEvent, frame, event)
        if not ok or registered == false then
            rejectedEvents[event] = true
            self:Print("Could not register event: " .. event)
            return false
        end
        events[event] = {}
    end
    table.insert(events[event], callback)
    return true
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handlers = events[event]
    if not handlers then return end
    -- Subscribers added during dispatch start receiving the next event.
    local count = #handlers
    for i = 1, count do invoke("Event " .. event, handlers[i], event, ...) end
end)

local function configureModule(name)
    local flags = core.Profile.modules
    if flags[name] == nil then flags[name] = true end
    core.Modules[name].enabled = flags[name] == true
end

local function enableModule(name)
    local module = core.Modules[name]
    if not module.enabled or startedModules[name] then return end
    startedModules[name] = true
    if module.OnEnable then invoke("Module " .. name, module.OnEnable, module) end
end

function core:RegisterModule(name, module)
    assert(type(name) == "string" and name ~= "" and type(module) == "table", "RegisterModule needs a name and table")
    assert(not self.Modules[name], "Module already registered: " .. name)
    self.Modules[name] = module
    table.insert(moduleOrder, name)
    if initialized then configureModule(name) end
    if loggedIn then enableModule(name) end
    return module
end

local function initialize(_, loadedAddon)
    if initialized or loadedAddon ~= addonName then return end
    -- On a client that writes saved variables and never reads them back, store.lua has the settings.
    if core.Store then core.Store.Restore() end
    RikUIDB = mergeDefaults(RikUIDB, ACCOUNT_DEFAULTS)
    RikUICharDB = mergeDefaults(RikUICharDB, CHARACTER_DEFAULTS)
    if type(RikUICharDB.profile) ~= "string" or RikUICharDB.profile == "" then
        RikUICharDB.profile = DEFAULT_PROFILE
    end
    for name, profile in pairs(RikUIDB.profiles) do
        RikUIDB.profiles[name] = mergeDefaults(profile, PROFILE_DEFAULTS)
    end
    local name = RikUICharDB.profile
    RikUIDB.profiles[name] = mergeDefaults(RikUIDB.profiles[name], PROFILE_DEFAULTS)
    core.DB, core.CharDB, core.Profile = RikUIDB, RikUICharDB, RikUIDB.profiles[name]
    initialized = true
    for _, moduleName in ipairs(moduleOrder) do configureModule(moduleName) end
end

-- Module enable/disable changes still take effect on reload.
function core:SetProfile(name)
    if not initialized then return nil, "Still loading." end
    if InCombatLockdown() then return nil, "Cannot switch profiles in combat." end
    if self.Setup and (self.Setup.IsApplying() or (self.Setup.IsUndoing and self.Setup.IsUndoing())) then
        return nil, "Finish the pending Setup operation before switching profiles."
    end
    if type(name) ~= "string" or type(self.DB.profiles[name]) ~= "table" then
        return nil, "Unknown profile."
    end
    if self.Layout and self.Layout.StopMoving then self.Layout.StopMoving() end
    self.Profile = mergeDefaults(self.DB.profiles[name], PROFILE_DEFAULTS)
    self.CharDB.profile = name
    if self.Bars then self.Bars.ApplyLayout()
    elseif self.Layout then self.Layout.Apply() end
    return true
end

local function login()
    if loggedIn or not initialized then return end
    loggedIn = true
    for _, name in ipairs(moduleOrder) do enableModule(name) end
end

-- Keep the pcall success flag separate from every opaque return value.
function core.Secret.Read(reader, ...)
    return pcall(reader, ...)
end

function core.Secret.IsSecret(value)
    return issecretvalue(value)
end

local function deliver(sink, ok, ...)
    if not ok then return false, ... end
    return pcall(sink, ...)
end

function core.Secret.Apply(sink, reader, ...)
    return deliver(sink, core.Secret.Read(reader, ...))
end

local function reportValues(label, ok, ...)
    if not ok then reportFailure(label, ...) return end
    local count = select("#", ...)
    if count == 0 then core:Print(label .. ": no values returned") return end
    for i = 1, count do
        core:Print(label .. "[" .. i .. "] secret=" .. tostring(issecretvalue((select(i, ...)))))
    end
end

function core:Debug()
    if not initialized then self:Print("Still loading.") return end
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

local function drainCombatQueue()
    if draining or InCombatLockdown() then return end
    draining = true
    while #combatQueue > 0 and not InCombatLockdown() do
        local callback = table.remove(combatQueue, 1)
        invoke("Combat queue", callback)
    end
    draining = false
end

function core.Combat.Queue(callback)
    assert(type(callback) == "function", "Combat.Queue needs a function")
    if not InCombatLockdown() and not draining then
        return invoke("Combat queue", callback)
    end
    table.insert(combatQueue, callback)
    return true
end

core:RegisterEvent("ADDON_LOADED", initialize)
core:RegisterEvent("PLAYER_LOGIN", login)
core:RegisterEvent("PLAYER_REGEN_ENABLED", drainCombatQueue)
