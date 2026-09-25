-- Portable UI preferences only: no account/character records, history or undo journals.
local core, sharing = RikUI, RikUI.Sharing
function sharing.ExportProfile(name)
    if not core.Profile then return nil, "Still loading." end
    local profile = core.Profile
    if name ~= nil then
        if not core:IsProfileName(name) or not core.DB or type(core.DB.profiles[name]) ~= "table" then
            return nil, "Unknown profile."
        end
        profile = core.DB.profiles[name]
    end
    local ok, value = pcall(core.ProfileSchema.Project, profile, true)
    if not ok then return nil, value end
    return sharing.Encode("profile", value)
end

function sharing.ImportProfile(name, text)
    if InCombatLockdown() then return nil, "Cannot import a profile in combat." end
    if not core.DB then return nil, "Still loading." end
    if not core:IsProfileName(name) then return nil, "Use a new name of 1..64 characters without markup." end
    if core.DB.profiles[name] ~= nil then return nil, "Profile already exists: " .. name end
    local value, reason = sharing.Decode(text, "profile")
    if not value then return nil, reason end
    local ok, profile = pcall(core.ProfileSchema.Project, value, false)
    if not ok then return nil, profile end
    core.DB.profiles[name] = profile
    core:Changed()
    return true
end

function sharing.OpenProfileExport(name)
    local text, reason = sharing.ExportProfile(name)
    if not text then core:Print(reason); return nil end
    return sharing.OpenDialog("Export UI profile", text, nil,
        "Copy with Ctrl-C. Shares UI preferences and frame positions; excludes chat history and character data.")
end

function sharing.OpenProfileImport()
    return sharing.OpenDialog("Import UI profile", nil, sharing.ImportProfile,
        "Enter a new profile name and paste below. Your current profile stays selected.",
        "Saved. Select the new profile in Profiles, then reload to apply all module settings.")
end

core:RegisterCommand("profileexport", function() sharing.OpenProfileExport() end, "Copy UI preferences: /rik profileexport")
core:RegisterCommand("profileimport", function() sharing.OpenProfileImport() end, "Import UI preferences: /rik profileimport")
