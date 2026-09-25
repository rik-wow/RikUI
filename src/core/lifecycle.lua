-- Startup composition. Persistence is optional and cannot prevent unrelated features starting.
local core, runtime = RikUI, RikUI.Runtime

local function restore(method)
    local callback = core.Store and core.Store[method]
    if type(callback) ~= "function" then return false end
    return runtime.Invoke("Settings " .. method, callback)
end

local function initialize(_, loadedAddon)
    if runtime.initialized or loadedAddon ~= runtime.addonName then return end
    restore("Restore")
    runtime.BindProfile()
    runtime.initialized = true
end

local function login()
    if runtime.loggedIn or not runtime.initialized then return end
    -- Macros are readable at login; bind again after even a partially failed restore.
    restore("RestoreCharacter")
    restore("RestoreLate")
    runtime.BindProfile()
    runtime.loadedProfile = core.Profile
    runtime.loggedIn = true
    runtime.StartModules()
end

core:RegisterEvent("ADDON_LOADED", initialize)
core:RegisterEvent("PLAYER_LOGIN", login)
core:RegisterEvent("PLAYER_REGEN_ENABLED", runtime.DrainCombat)
