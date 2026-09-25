-- Typed persisted defaults. Unit values and client secrets never pass through here.
local core, runtime = RikUI, RikUI.Runtime
local DEFAULT_PROFILE = "Default"
local MAX_PROFILE_NAME = 64
local PROFILE_DEFAULTS = { modules = {}, positions = {}, scale = 1, textScale = 1, font = "bundled", reducedMotion = false, gryphons = false, ghosts = true,
    tooltip = { vendorValues = false, hideInCombat = false, ownedCounts = true, followCursor = false, scale = 1 },
    chat = { fontSize = 14, timestamps = true, locked = true, panel = true, classColors = true, shortTags = true,
        mentions = true, collapseRepeats = true, jumpButton = true, history = true, arrowHistory = true,
        stickyChannels = true, channelStrip = true, editColor = true, tabsVisible = true, nameClicks = true },
    panels = { questTextSize = 0 },
    bags = { autoRepair = false, itemLevels = false, repairGuild = false, autoSellJunk = false, columns = 10, capacityHUD = true, capacityLowOnly = false, capacityThreshold = 4 },
    barFade = { bar3 = true },
    questtracker = { collapsed = false, collapseInCombat = false, hideCompleted = false, readyFirst = false },
    minimap = { serverTime = false, coordinates = true, dayNight = true },
    swingtimer = { kiting = true, stopLead = 0.6 },
    druidmana = { show = true },
    nameplates = { threatText = true, selectedScale = 1.15, otherAlpha = 0.6 },
    unitframes = { healthText = "both", powerText = "both" },
    castbars = { widthScale = 1, height = 22, timeText = true },
    worldmap = { fog = true },
    xpbar = { compact = false, text = true, animations = true, ticks = true } }
local ACCOUNT_DEFAULTS = { version = 1, profiles = { Default = PROFILE_DEFAULTS }, community = {} }
local CHARACTER_DEFAULTS = { profile = DEFAULT_PROFILE, askRole = true, wizardDone = false, autoPlacement = true }
core.Defaults = { account = ACCOUNT_DEFAULTS, profile = PROFILE_DEFAULTS, character = CHARACTER_DEFAULTS }

local function invalid(value, default)
    if type(value) ~= type(default) then return true end
    return type(value) == "number" and (value ~= value or value == math.huge or value == -math.huge)
end

local function mergeDefaults(target, defaults, ancestors)
    ancestors = ancestors or {}
    if type(target) ~= "table" or ancestors[target] then target = {} end
    ancestors[target] = true
    for key, value in pairs(defaults) do
        if type(value) == "table" then target[key] = mergeDefaults(target[key], value, ancestors)
        elseif invalid(target[key], value) then target[key] = value end
    end
    ancestors[target] = nil
    return target
end

local function normalizeProfile(profile)
    profile = core.ProfileSchema.Repair(profile, PROFILE_DEFAULTS)
    return mergeDefaults(profile, PROFILE_DEFAULTS, { [RikUIDB] = true, [RikUIDB.profiles] = true })
end

function core:IsProfileName(name)
    return type(name) == "string" and #name > 0 and #name <= MAX_PROFILE_NAME
        and name:match("^%S") ~= nil and name:match("%S$") ~= nil and not name:find("[%c|]")
end

function core:GetProfileNames()
    local names = {}
    for name, profile in pairs(self.DB and self.DB.profiles or {}) do
        if self:IsProfileName(name) and type(profile) == "table" then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

function runtime.BindProfile()
    RikUIDB = mergeDefaults(RikUIDB, ACCOUNT_DEFAULTS)
    RikUICharDB = mergeDefaults(RikUICharDB, CHARACTER_DEFAULTS)
    if not core:IsProfileName(RikUICharDB.profile) then RikUICharDB.profile = DEFAULT_PROFILE end
    for name, profile in pairs(RikUIDB.profiles) do
        if core:IsProfileName(name) then RikUIDB.profiles[name] = normalizeProfile(profile) end
    end
    local name = RikUICharDB.profile
    RikUIDB.profiles[name] = normalizeProfile(RikUIDB.profiles[name])
    core.DB, core.CharDB, core.Profile = RikUIDB, RikUICharDB, RikUIDB.profiles[name]
    if core.Media and core.Media.Configure then core.Media.Configure() end
    runtime.ConfigureModules()
end

function core:Changed()
    if self.Store and self.Store.Touch then runtime.Invoke("Save changed settings", self.Store.Touch) end
end

local STARTUP_SETTINGS = { "font", "textScale", "reducedMotion" }

function runtime.CaptureProfileState()
    runtime.loadedProfile, runtime.loadedSettings = core.Profile, {}
    for _, key in ipairs(STARTUP_SETTINGS) do runtime.loadedSettings[key] = core.Profile[key] end
end

function core:ProfileSelectionNeedsReload()
    return runtime.loadedProfile ~= nil and runtime.loadedProfile ~= self.Profile
end

function core:ProfileNeedsReload()
    if not runtime.loadedProfile then return false end
    if self:ProfileSelectionNeedsReload() then return true end
    for _, key in ipairs(STARTUP_SETTINGS) do
        if runtime.loadedSettings[key] ~= self.Profile[key] then return true end
    end
    for name, module in pairs(self.Modules) do
        if (self.Profile.modules[name] ~= false) ~= (module.enabled ~= false) then return true end
    end
    return false
end

-- Module activation flags still take effect on reload, not during a profile switch.
function core:SetProfile(name)
    if not runtime.initialized then return nil, "Still loading." end
    if InCombatLockdown() then return nil, "Cannot switch profiles in combat." end
    if self.Setup and (self.Setup.IsApplying() or (self.Setup.IsUndoing and self.Setup.IsUndoing())) then
        return nil, "Finish the pending Setup operation before switching profiles."
    end
    if not self:IsProfileName(name) or type(self.DB.profiles[name]) ~= "table" then return nil, "Unknown profile." end
    if self.Layout and self.Layout.StopMoving then
        local ok = runtime.Invoke("Stop profile layout", self.Layout.StopMoving)
        if not ok then return nil, "Could not stop the current layout. See /rik errors." end
    end
    if self.Profile ~= self.DB.profiles[name] then runtime.profileRevision = (runtime.profileRevision or 0) + 1 end
    self.Profile = normalizeProfile(self.DB.profiles[name])
    self.DB.profiles[name] = self.Profile
    self.CharDB.profile = name
    self:Changed()
    if self.Layout and self.Layout.Apply then runtime.Invoke("Apply profile layout", self.Layout.Apply) end
    return true
end
