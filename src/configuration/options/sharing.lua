-- Versioned portable payloads. The strict codec bounds parsing and never executes input.
local core = RikUI
local sharing = { Prefix = "!RIK3!", Limit = 21621 }
local LEGACY_PREFIX = "!RIK2!"
core.Sharing = sharing

function sharing.Encode(kind, data)
    local text, reason = core.Serialize({ kind = kind, data = data })
    if not text then return nil, reason end
    return sharing.Prefix .. #text .. ":" .. core.Codec.ChecksumHex(text) .. ":" .. text
end

local function payload(text)
    if type(text) ~= "string" or #text > sharing.Limit then return nil, "Sharing text exceeds the size limit." end
    if text:sub(1, #LEGACY_PREFIX) == LEGACY_PREFIX then return text:sub(#LEGACY_PREFIX + 1) end
    if text:sub(1, #sharing.Prefix) ~= sharing.Prefix then return nil, "Expected a RikUI !RIK3! or !RIK2! sharing string." end
    local length, sum, body = text:sub(#sharing.Prefix + 1):match("^(%d+):(%x+):([%w_]+)$")
    if not length or #length > 5 or #sum ~= 8 or tonumber(length) ~= #body then
        return nil, "Sharing text is incomplete or has an invalid header."
    end
    if core.Codec.ChecksumHex(body) ~= sum:lower() then return nil, "Sharing checksum mismatch. Copy the full export again." end
    return body
end

function sharing.Decode(text, kind)
    local body, reason = payload(text)
    if not body then return nil, reason end
    local envelope
    envelope, reason = core.Deserialize(body)
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
