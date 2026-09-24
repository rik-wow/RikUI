-- Typed persisted defaults. Unit values and client secrets never pass through here.
local core, runtime = RikUI, RikUI.Runtime
local DEFAULT_PROFILE = "Default"
local PROFILE_DEFAULTS = { modules = {}, positions = {}, scale = 1, gryphons = false, ghosts = true,
    tooltip = { hideInCombat = false, ownedCounts = true, followCursor = false },
    chat = { fontSize = 14, timestamps = true, locked = true, panel = true, classColors = true, shortTags = true,
        mentions = true, collapseRepeats = true, jumpButton = true, history = true, arrowHistory = true,
        stickyChannels = true, channelStrip = true, editColor = true, tabsVisible = true, nameClicks = true },
    bags = { autoRepair = false },
    barFade = { bar3 = true },
    questtracker = { collapsed = false, collapseInCombat = false },
    minimap = { serverTime = false },
    worldmap = { fog = true },
    xpbar = { compact = false, text = true, animations = true, ticks = true } }
local ACCOUNT_DEFAULTS = { version = 1, profiles = { Default = PROFILE_DEFAULTS }, community = {} }
local CHARACTER_DEFAULTS = { profile = DEFAULT_PROFILE, askRole = true, wizardDone = false }
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
    return mergeDefaults(profile, PROFILE_DEFAULTS, { [RikUIDB] = true, [RikUIDB.profiles] = true })
end

function runtime.BindProfile()
    RikUIDB = mergeDefaults(RikUIDB, ACCOUNT_DEFAULTS)
    RikUICharDB = mergeDefaults(RikUICharDB, CHARACTER_DEFAULTS)
    if RikUICharDB.profile == "" then RikUICharDB.profile = DEFAULT_PROFILE end
    for name, profile in pairs(RikUIDB.profiles) do
        RikUIDB.profiles[name] = normalizeProfile(profile)
    end
    local name = RikUICharDB.profile
    RikUIDB.profiles[name] = normalizeProfile(RikUIDB.profiles[name])
    core.DB, core.CharDB, core.Profile = RikUIDB, RikUICharDB, RikUIDB.profiles[name]
    runtime.ConfigureModules()
end

function core:Changed()
    if self.Store and self.Store.Touch then runtime.Invoke("Save changed settings", self.Store.Touch) end
end

-- Module activation flags still take effect on reload, not during a profile switch.
function core:SetProfile(name)
    if not runtime.initialized then return nil, "Still loading." end
    if InCombatLockdown() then return nil, "Cannot switch profiles in combat." end
    if self.Setup and (self.Setup.IsApplying() or (self.Setup.IsUndoing and self.Setup.IsUndoing())) then
        return nil, "Finish the pending Setup operation before switching profiles."
    end
    if type(name) ~= "string" or type(self.DB.profiles[name]) ~= "table" then return nil, "Unknown profile." end
    if self.Layout and self.Layout.StopMoving then self.Layout.StopMoving() end
    self.Profile = normalizeProfile(self.DB.profiles[name])
    self.DB.profiles[name] = self.Profile
    self.CharDB.profile = name
    self:Changed()
    if self.Layout then self.Layout.Apply() end
    return true
end
