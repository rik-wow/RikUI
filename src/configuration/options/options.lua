-- Settings declarations and profile operations; layout lives in options-view.lua.
local core, options = RikUI, RikUI.Options
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.25, 3, 0.05
local state = { newName = "", deleteName = nil }

local MAX_PROFILE_NODES, MAX_PROFILE_DEPTH, MAX_NAME = 8192, 32, 64
local function copyTable(value, state, depth)
    state, depth = state or { nodes = 0, seen = {} }, depth or 0
    state.nodes = state.nodes + 1
    if state.nodes > MAX_PROFILE_NODES or depth > MAX_PROFILE_DEPTH then error("Profile is too large.", 0) end
    if type(value) ~= "table" then
        local kind = type(value)
        if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then error("Unsupported profile value.", 0) end
        if kind == "number" and (value ~= value or math.abs(value) == math.huge) then error("Invalid profile number.", 0) end
        return value
    end
    if state.seen[value] or getmetatable(value) then error("Profile contains a cycle or metatable.", 0) end
    state.seen[value] = true
    local result = {}
    for key, entry in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then error("Invalid profile key.", 0) end
        result[key] = copyTable(entry, state, depth + 1)
    end
    state.seen[value] = nil
    return result
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function trim(text)
    return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

local function run(command) SlashCmdList.RIKUI(command) end

local function selectProfile(name)
    if not InCombatLockdown() then return core:SetProfile(name) end
    core.Combat.Queue(function()
        local ok, reason = core:SetProfile(name)
        if not ok then core:Print(reason) end
    end)
    return nil, "Profile " .. name .. " will be selected when combat ends."
end

function options.CreateProfile(name, copyFrom)
    if not core.DB then return nil, "Still loading." end
    if type(name) ~= "string" then return nil, "Enter a profile name." end
    name = trim(name)
    if name == "" then return nil, "Enter a profile name." end
    if #name > MAX_NAME or name:find("[%c|]") then return nil, "Use a name of 1..64 characters without markup." end
    if core.DB.profiles[name] then return nil, "Profile already exists: " .. name end
    local source = copyFrom and core.DB.profiles[copyFrom]
    if copyFrom and type(source) ~= "table" then return nil, "Unknown source profile." end
    local ok, profile = pcall(copyTable, source or {})
    if not ok then return nil, profile end
    core.DB.profiles[name] = profile
    core:Changed()
    return true
end

function options.DeleteProfile(name)
    if not core.DB then return nil, "Still loading." end
    if name == core.CharDB.profile then return nil, "Switch away from the active profile before deleting it." end
    if type(name) ~= "string" or not core.DB.profiles[name] then return nil, "Unknown profile." end
    core.DB.profiles[name] = nil
    core:Changed()
    if state.deleteName == name then state.deleteName = nil end
    return true
end

local MODULE_TITLES = {
    chatbubbles = "Chat bubbles", combattext = "Combat text", combopoints = "Combo points",
    cooldownviewer = "Cooldown viewer", damagemeter = "Damage meter", extrabuttons = "Extra action buttons",
    hudframes = "Small HUD frames", lossofcontrol = "Loss of control", micromenu = "Micro menu",
    mirrortimers = "Breath and fatigue", questplanner = "Quest planner", questtimers = "Quest timers",
    questtracker = "Quest tracker", screentext = "Screen messages", swingtimer = "Swing timer",
    classcooldowns = "Class cooldowns", classauras = "Class effects", unitauras = "Unit auras", unitframes = "Unit frames", worldmap = "World map", xpbar = "Experience",
}

local function moduleTitle(name, module)
    return module.title or MODULE_TITLES[name] or (name:sub(1, 1):upper() .. name:sub(2))
end

function options.ModuleStatus(name)
    local state, reason = core:GetModuleState(name)
    if state == "enabled" then return "Running. Toggle changes apply after Reload UI." end
    if state == "disabled" then return "Disabled. Enable and reload to use this feature." end
    if state == "blocked" then
        local dependency = type(reason) == "string" and reason:match("^dependency unavailable: (.+)$")
        if dependency then
            local module = core.Modules[dependency]
            return "Needs " .. (module and moduleTitle(dependency, module) or dependency) .. ". Enable the required module and reload."
        end
        return "Could not start because of a module dependency. See Setup and support diagnostics."
    end
    if state == "failed" then return "Could not start. See Setup and support diagnostics for the error." end
    return "Waiting to start."
end

local function moduleToggle(name, module)
    return { type = "checkbox", key = "module." .. name, label = moduleTitle(name, module), reload = true,
        description = "", getDescription = function() return options.ModuleStatus(name) end,
        get = function() return core.Profile.modules[name] ~= false end,
        set = function(value) core.Profile.modules[name] = value == true end,
        pending = function() return (core.Profile.modules[name] ~= false) ~= (module.enabled ~= false) end }
end

local function action(key, label, text, callback)
    return { type = "button", key = key, label = label, text = text, action = callback,
        disabled = function() return InCombatLockdown() end }
end

local function moveFrames()
    if InCombatLockdown() then return end
    if core.Layout.IsMoving() then core.Layout.LockAll() else core.Layout.UnlockAll() end
    if core.Shell then core.Shell.Refresh() end
    if options.Panel() then options.Panel():Hide() end
    local moving = core.Layout.IsMoving and core.Layout.IsMoving()
    if moving and SettingsPanel and type(HideUIPanel) == "function" then HideUIPanel(SettingsPanel) end
end

local function layoutSpecs(specs)
    if not core.Layout then return end
    specs[#specs + 1] = { type = "heading", label = "Layout" }
    specs[#specs + 1] = { type = "slider", key = "scale", label = "Frame scale", protected = true,
        description = "Resize all RikUI frames together. Changes wait until combat ends.",
        min = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP,
        format = function(value) return string.format("%.0f%%", value * 100) end,
        get = function() return core.Layout.GetScale() end,
        set = function(value) return core.Layout.SetScale(value) end }
    if core.Layout.PresetOption then specs[#specs + 1] = core.Layout.PresetOption() end
    specs[#specs + 1] = action("move", "Frame positions", "Move frames", moveFrames)
    local reset = action("reset", "Default positions", "Reset positions", function() core.Layout.Reset() end)
    reset.confirm = function() return "Reset positions for " .. core.CharDB.profile .. "?" end
    specs[#specs + 1] = reset
end

local function generalSpecs()
    local specs = {}
    layoutSpecs(specs)
    specs[#specs + 1] = { type = "checkbox", key = "reducedMotion", label = "Reduce cosmetic motion", reload = true,
        description = "Remove RikUI fades, flashes and pulses. Cast and cooldown timers stay active. Reload to apply.",
        get = function() return core.Profile.reducedMotion == true end,
        set = function(value) core.Profile.reducedMotion = value == true end }
    specs[#specs + 1] = { type = "dropdown", key = "font", label = "Font", reload = true,
        description = "Choose RikUI's bundled font or the game's locale font. Reload to apply; world damage numbers require relogging.",
        choices = { { value = "bundled", label = "RikUI (Noto Sans)" }, { value = "game", label = "Game font" } },
        get = function() return core.Profile.font or "bundled" end,
        set = function(value) core.Profile.font = value end }
    specs[#specs + 1] = { type = "slider", key = "textScale", label = "Text size", reload = true,
        description = "Resize RikUI labels without resizing frames. Chat has its own font size. Reload to apply.",
        min = 0.85, max = 1.3, step = 0.05,
        format = function(value) return string.format("%.0f%%", value * 100) end,
        get = function() return core.Profile.textScale or 1 end,
        set = function(value) core.Profile.textScale = value end }
    return specs
end

local function moduleSpecs()
    local specs = { { type = "heading", label = "Enabled modules" } }
    for _, name in ipairs(sortedKeys(core.Modules)) do specs[#specs + 1] = moduleToggle(name, core.Modules[name]) end
    return specs
end

local function setupSpecs()
    local specs = { { type = "heading", label = "Setup" },
        { type = "checkbox", key = "autoPlacement", label = "Automatically update preset spell slots",
            description = "This character: fill empty preset slots and upgrade learned ranks. Re-sync still works when disabled.",
            get = function() return core.CharDB.autoPlacement ~= false end,
            set = function(value) core.CharDB.autoPlacement = value == true end } }
    if core:HasCommand("setup") then specs[#specs + 1] = action("wizard", "Configure your character", "Open wizard", function() run("setup") end) end
    if core:HasCommand("resync") then specs[#specs + 1] = action("resync", "Refresh preset spell slots", "Re-sync", function() core.Setup.Resync() end) end
    specs[#specs + 1] = { type = "button", key = "undo", label = "Last setup change", text = "Undo",
        disabled = function() return InCombatLockdown() or not core.CharDB.undo end,
        action = function() core.Setup.Undo() end }
    if core.Sharing then
        specs[#specs + 1] = action("export", "Share character preset", "Export", core.Sharing.OpenExport)
        specs[#specs + 1] = action("import", "Add a shared preset", "Import", core.Sharing.OpenImport)
    end
    specs[#specs + 1] = { type = "heading", label = "Support" }
    specs[#specs + 1] = action("debug", "Interface diagnostics", "Show in chat", function() core:Debug() end)
    if core.Store then
        specs[#specs + 1] = action("storage", "Saved data status", "Show in chat", function() run("store") end)
        specs[#specs + 1] = action("savebackup", "Retry settings backups", "Save now", function()
            core.Store.Flush()
            if core.Store.FlushMacros then core.Store.FlushMacros() end
            run("store")
        end)
    end
    return specs
end

local function moduleSpec(name, module, spec)
    local wrapped = {}
    for key, value in pairs(spec) do wrapped[key] = value end
    wrapped.disabled = function()
        local state = core:GetModuleState(name)
        return module.enabled == false or state == "failed" or state == "blocked"
            or (spec.disabled and spec.disabled()) or false
    end
    return wrapped
end

local function modulePages(pages)
    for _, name in ipairs(sortedKeys(core.Modules)) do
        local module = core.Modules[name]
        local declared = module.Options
        if type(declared) == "table" and type(declared.settings) == "table" then
            local specs = {}
            for index, spec in ipairs(declared.settings) do specs[index] = moduleSpec(name, module, spec) end
            local gameplay = name == "worldmap" or name == "experience" or name == "questplanner" or name == "loot"
            pages[#pages + 1] = { id = name, group = (declared.group == "System" or declared.group == "Gameplay" or declared.group == "Interface") and declared.group or (gameplay and "Gameplay" or "Interface"),
                title = declared.title or moduleTitle(name, module), specs = specs }
        end
    end
end

local function profileEntries(excludeActive)
    local entries = {}
    for _, name in ipairs(sortedKeys(core.DB.profiles)) do
        if not excludeActive or name ~= core.CharDB.profile then
            entries[#entries + 1] = { value = name, text = name }
        end
    end
    return entries
end

local function cannotCreate()
    return state.newName == "" or core.DB.profiles[state.newName] ~= nil
end

local function createProfile(copy)
    local name = state.newName
    local ok, reason = options.CreateProfile(name, copy and core.CharDB.profile or nil)
    if not ok then core:Print(reason); return end
    state.newName = ""
    local selected, pending = selectProfile(name)
    core:Print(selected and ("Profile created and selected: " .. name) or pending)
end

local function deleteProfile()
    local ok, reason = options.DeleteProfile(state.deleteName)
    core:Print(ok and "Profile deleted." or reason)
end

local function profileSpecs()
    return {
        { type = "heading", label = "Profiles" },
        { type = "dropdown", key = "profile", label = "Active profile", values = function() return profileEntries(false) end,
            get = function() return core.CharDB.profile end, set = selectProfile },
        { type = "heading", label = "New profile" },
        { type = "text", key = "newName", label = "Name",
            description = "Use a unique name. Create starts fresh; Copy keeps your current setup.",
            get = function() return state.newName end, set = function(value) state.newName = trim(value) end },
        { type = "button", key = "create", label = "Start from defaults", text = "Create", disabled = cannotCreate,
            action = function() createProfile(false) end },
        { type = "button", key = "copy", label = "Copy the active profile", text = "Copy", disabled = cannotCreate,
            action = function() createProfile(true) end },
        { type = "button", key = "profileexport", label = "Share this UI profile", text = "Export",
            action = function() core.Sharing.OpenProfileExport() end },
        { type = "button", key = "profileimport", label = "Save a shared UI profile", text = "Import",
            action = function() core.Sharing.OpenProfileImport() end },
        { type = "heading", label = "Delete" },
        { type = "dropdown", key = "deleteName", label = "Profile to delete", values = function() return profileEntries(true) end,
            get = function() return state.deleteName end, set = function(value) state.deleteName = value end },
        { type = "button", key = "delete", label = "Remove the chosen profile", text = "Delete", action = deleteProfile,
            confirm = function() return state.deleteName and ("Delete " .. state.deleteName .. "?") end,
            disabled = function()
                return state.deleteName == nil or state.deleteName == core.CharDB.profile or not core.DB.profiles[state.deleteName]
            end },
    }
end

function options.Pages()
    local pages = { { id = "general", group = "Interface", title = "General",
        description = "Your layout and everyday preferences.", specs = generalSpecs() } }
    modulePages(pages)
    pages[#pages + 1] = { id = "modules", group = "System", title = "Modules",
        description = "Choose which parts of RikUI to load. Apply changes with Reload UI.", specs = moduleSpecs() }
    pages[#pages + 1] = { id = "profiles", group = "System", title = "Profiles",
        description = "Switch profiles or create a separate setup.", specs = profileSpecs() }
    pages[#pages + 1] = { id = "setup", group = "System", title = "Setup and support",
        description = "Character setup, recovery and diagnostics.", specs = setupSpecs() }
    return pages
end
