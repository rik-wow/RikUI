-- Named immutable-at-import sources. Reading a source never selects or applies it.
local core, setup = RikUI, RikUI.Setup
local library = {}
core.PresetLibrary = library

function library.ValidName(name)
    return type(name) == "string" and #name > 0 and #name <= 64
        and name:match("^%S") and name:match("%S$") and not name:find("[%c|]")
end

function library.Get(class, name)
    if name == nil or name == "" then return core.Presets[class] end
    if not library.ValidName(name) then return nil, "Invalid preset name." end
    local preset = core.DB and core.DB.community and core.DB.community[name]
    if type(preset) ~= "table" then return nil, "Preset unavailable: " .. name end
    if preset.class ~= class then return nil, "Preset is for a different class: " .. name end
    return preset
end

function library.Add(name, preset)
    if InCombatLockdown() then return nil, "Cannot import a preset in combat." end
    if not core.DB then return nil, "Still loading." end
    if not library.ValidName(name) then return nil, "Use a name of 1..64 characters without markup." end
    if core.DB.community[name] ~= nil then return nil, "Preset name already exists: " .. name end
    local issues = setup.ValidateSharedPreset(preset)
    if #issues > 0 then return nil, table.concat(issues, "\n") end
    core.DB.community[name] = setup.CopyState(preset)
    core:Changed()
    return true
end

function library.Entries(class)
    local entries = { { value = "", text = "Bundled class preset" } }
    local names = {}
    for name in pairs(core.DB and core.DB.community or {}) do
        if library.ValidName(name) then names[#names + 1] = name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local preset = library.Get(class, name)
        if preset and #setup.ValidateSharedPreset(preset) == 0 then
            entries[#entries + 1] = { value = name, text = name }
        end
    end
    return entries
end
