-- Named sources share validation and never select or apply themselves.
local core, setup = RikUI, RikUI.Setup
local library = {}
core.PresetLibrary = library
core.CommunityPresets = core.CommunityPresets or {}

function library.ValidName(name)
    return type(name) == "string" and #name > 0 and #name <= 64
        and name:match("^%S") and name:match("%S$") and not name:find("[%c|]")
end

local function issues(preset, bundled)
    local result = setup.ValidateSharedPreset(preset)
    if bundled and (type(preset) ~= "table" or preset.author == nil) then
        result[#result + 1] = "author: bundled presets require attribution"
    end
    return result
end

function library.Get(class, name)
    if name == nil or name == "" then return core.Presets[class] end
    if not library.ValidName(name) then return nil, "Invalid preset name." end
    local imported = core.DB and core.DB.community and core.DB.community[name]
    local bundled = core.CommunityPresets[name]
    if imported and bundled then return nil, "Ambiguous preset name: " .. name end
    local preset = imported or bundled
    if type(preset) ~= "table" then return nil, "Preset unavailable: " .. name end
    if preset.class ~= class then return nil, "Preset is for a different class: " .. name end
    return preset
end

local function insert(name, preset, bundled)
    if not library.ValidName(name) then return nil, "Use a name of 1..64 characters without markup." end
    if core.CommunityPresets[name] ~= nil or (core.DB and core.DB.community[name] ~= nil) then
        return nil, "Preset name already exists: " .. name
    end
    local problems = issues(preset, bundled)
    if #problems > 0 then return nil, table.concat(problems, "\n") end
    local target = bundled and core.CommunityPresets or core.DB.community
    target[name] = setup.CopyState(preset)
    return true
end

function library.Register(name, preset)
    return insert(name, preset, true)
end

function library.Add(name, preset)
    if InCombatLockdown() then return nil, "Cannot import a preset in combat." end
    if not core.DB then return nil, "Still loading." end
    local ok, reason = insert(name, preset, false)
    if ok then core:Changed() end
    return ok, reason
end

local function names()
    local seen, result = {}, {}
    for _, sources in ipairs({ core.CommunityPresets, core.DB and core.DB.community or {} }) do
        for name in pairs(sources) do
            if library.ValidName(name) and not seen[name] then
                seen[name] = true; result[#result + 1] = name
            end
        end
    end
    table.sort(result)
    return result
end

function library.Entries(class)
    local entries = { { value = "", text = "Bundled class preset" } }
    for _, name in ipairs(names()) do
        local preset = library.Get(class, name)
        if preset and #issues(preset, core.CommunityPresets[name] ~= nil) == 0 then
            entries[#entries + 1] = { value = name,
                text = "Community: " .. name .. (preset.author and " — " .. preset.author or "") }
        end
    end
    return entries
end

function library.ValidateAll()
    local result = {}
    for _, sources in ipairs({ core.CommunityPresets, core.DB and core.DB.community or {} }) do
        for name, preset in pairs(sources) do
            local problems = issues(preset, sources == core.CommunityPresets)
            if not library.ValidName(name) then problems[#problems + 1] = "invalid name" end
            if core.CommunityPresets[name] and core.DB and core.DB.community[name] then
                problems[#problems + 1] = "ambiguous bundled/imported name"
            end
            if #problems == 0 then result[#result + 1] = tostring(name) .. ": community preset valid."
            else
                for _, problem in ipairs(problems) do result[#result + 1] = tostring(name) .. ": " .. problem end
            end
        end
    end
    table.sort(result)
    return result
end
