-- Versioned portable payloads. The strict codec bounds parsing and never executes input.
local core = RikUI
local sharing = { Prefix = "!RIK2!", Limit = 21606 }
core.Sharing = sharing

function sharing.Encode(kind, data)
    local text, reason = core.Serialize({ kind = kind, data = data })
    if not text then return nil, reason end
    return sharing.Prefix .. text
end

function sharing.Decode(text, kind)
    if type(text) ~= "string" or #text > sharing.Limit then return nil, "Sharing text exceeds the size limit." end
    if text:sub(1, #sharing.Prefix) ~= sharing.Prefix then return nil, "Expected a !RIK2! RikUI sharing string." end
    local envelope, reason = core.Deserialize(text:sub(#sharing.Prefix + 1))
    if not envelope then return nil, reason end
    if type(envelope) ~= "table" or envelope.kind ~= kind or type(envelope.data) ~= "table" then
        return nil, "This is not a RikUI " .. kind .. " export."
    end
    for key in pairs(envelope) do
        if key ~= "kind" and key ~= "data" then return nil, "Unknown sharing envelope field." end
    end
    return envelope.data
end

function sharing.ExportPreset(class, role, presetName)
    local preset, reason = core.Setup.Source(class, presetName)
    if not preset then return nil, reason end
    local issues = core.Setup.ValidateSharedPreset(preset)
    if #issues > 0 then return nil, table.concat(issues, "\n") end
    preset = core.Setup.CopyState(preset)
    if role and role ~= "" then
        if not preset.roles[role] then return nil, "Unknown role: " .. role end
        preset.roles, preset.roleOrder = { [role] = preset.roles[role] }, { role }
        preset.roleOverrides = { [role] = (preset.roleOverrides or {})[role] or {} }
    end
    return sharing.Encode("preset", preset)
end

function sharing.ImportPreset(name, text)
    if InCombatLockdown() then return nil, "Cannot import a preset in combat." end
    local preset, reason = sharing.Decode(text, "preset")
    if not preset then return nil, reason end
    return core.PresetLibrary.Add(name, preset)
end
