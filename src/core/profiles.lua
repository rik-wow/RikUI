-- Typed persisted defaults. Unit values and client secrets never pass through here.
local core, runtime = RikUI, RikUI.Runtime
local DEFAULT_PROFILE = "Default"
local PROFILE_DEFAULTS = { modules = {}, positions = {}, scale = 1, textScale = 1, font = "bundled", reducedMotion = false, gryphons = false, ghosts = true,
    tooltip = { hideInCombat = false, ownedCounts = true, followCursor = false, scale = 1 },
    chat = { fontSize = 14, timestamps = true, locked = true, panel = true, classColors = true, shortTags = true,
        mentions = true, collapseRepeats = true, jumpButton = true, history = true, arrowHistory = true,
        stickyChannels = true, channelStrip = true, editColor = true, tabsVisible = true, nameClicks = true },
    panels = { questTextSize = 0 },
    bags = { autoRepair = false, columns = 10, capacityHUD = true, capacityLowOnly = false, capacityThreshold = 4 },
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

-- Restored data must obey the same supported values as the public settings controls.
local LIMITS = {
    { false, "scale", 0.25, 3 }, { false, "textScale", 0.85, 1.3 },
    { "tooltip", "scale", 0.75, 1.5 }, { "bags", "columns", 10, 16, true },
    { "bags", "capacityThreshold", 0, 20, true }, { "castbars", "widthScale", 0.75, 1.5 },
    { "castbars", "height", 16, 36, true }, { "nameplates", "selectedScale", 1, 1.5 },
    { "nameplates", "otherAlpha", 0.2, 1 },
}
local CHOICES = {
    { false, "font", { bundled = true, game = true } },
    { "unitframes", "healthText", { both = true, current = true, hidden = true } },
    { "unitframes", "powerText", { both = true, current = true, hidden = true } },
}

local function normalizeProfile(profile)
    profile = mergeDefaults(profile, PROFILE_DEFAULTS, { [RikUIDB] = true, [RikUIDB.profiles] = true })
    for _, rule in ipairs(LIMITS) do
        local target = rule[1] and profile[rule[1]] or profile
        local defaults = rule[1] and PROFILE_DEFAULTS[rule[1]] or PROFILE_DEFAULTS
        local value = target[rule[2]]
        if value < rule[3] or value > rule[4] or (rule[5] and value % 1 ~= 0) then
            target[rule[2]] = defaults[rule[2]]
        end
    end
    for _, rule in ipairs(CHOICES) do
        local target = rule[1] and profile[rule[1]] or profile
        local defaults = rule[1] and PROFILE_DEFAULTS[rule[1]] or PROFILE_DEFAULTS
        if not rule[3][target[rule[2]]] then target[rule[2]] = defaults[rule[2]] end
    end
    return profile
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
    if core.Media and core.Media.Configure then core.Media.Configure() end
    runtime.ConfigureModules()
end

function core:Changed()
    if self.Store and self.Store.Touch then runtime.Invoke("Save changed settings", self.Store.Touch) end
end

function core:ProfileNeedsReload()
    return runtime.loadedProfile ~= nil and runtime.loadedProfile ~= self.Profile
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
    if self.Profile ~= self.DB.profiles[name] then runtime.profileRevision = (runtime.profileRevision or 0) + 1 end
    self.Profile = normalizeProfile(self.DB.profiles[name])
    self.DB.profiles[name] = self.Profile
    self.CharDB.profile = name
    self:Changed()
    if self.Layout then self.Layout.Apply() end
    return true
end
