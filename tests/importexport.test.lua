return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local files = { "data/spells.lua", "presets/warrior.lua", "src/persistence/codec.lua",
        "src/setup/preset-schema.lua", "src/setup/preset-library.lua", "src/ui/skin.lua",
        "src/configuration/wizard/wizard-controls.lua" }
    local f = io.open("src/configuration/options/sharing.lua", "r")
    if f then f:close(); files[#files+1] = "src/configuration/options/sharing.lua" end
    files[#files+1] = "src/configuration/options/importexport.lua"
    local ok, reason = pcall(function()
        widgets.loadAddon(env, files)
        local sharing = RikUI.Sharing
        check("sharing service exists", sharing ~= nil)
        if not sharing then return end
        local text = sharing.ExportPreset("WARRIOR")
        check("export has versioned prefix", text and text:sub(1,6) == "!RIK3!")
        local portable = sharing.Encode("profile", { scale = 1.1 })
        local corrupted = portable:gsub("n1_2e1z", "n1_2e2z", 1)
        check("sharing refuses valid-looking copy corruption", corrupted ~= portable and sharing.Decode(corrupted, "profile") == nil)
        check("sharing accepts existing v2 exports", sharing.Decode("!RIK2!" .. RikUI.Serialize({kind="profile", data={scale=1.1}}), "profile").scale == 1.1)
        check("sharing checksum uses standard Adler32", RikUI.Codec.Checksum and RikUI.Codec.Checksum("Wikipedia") == 0x11e60398)
        check("sharing rejects missing integrity header", sharing.Decode("!RIK3!TE", "profile") == nil)
        check("sharing refuses corrupt imports without storing", sharing.ImportPreset("Corrupt", text:sub(1, -2)) == nil
            and RikUI.DB.community.Corrupt == nil)
        local parsed = sharing.Decode(text, "preset")
        check("envelope retains all roles and macro text", parsed and parsed.roles.tank
            and parsed.macros.Execute.body == RikUI.Presets.WARRIOR.macros.Execute.body)
        local narrowed = sharing.Decode(sharing.ExportPreset("WARRIOR", "tank"), "preset")
        check("role export preserves source but narrows choices", narrowed and #narrowed.roleOrder == 1
            and narrowed.roles.tank and not narrowed.roles.dps and not narrowed.roleOverrides.fury)
        check("bad role rejected", sharing.ExportPreset("WARRIOR", "ghost") == nil)
        check("bad prefix and payload rejected", sharing.Decode("!RIK1!bad", "preset") == nil
            and sharing.Decode(text .. "x", "preset") == nil and sharing.Decode(text, "profile") == nil)
        check("oversized envelope rejected", sharing.Decode("!RIK2!" .. string.rep("a",21601), "preset") == nil)
        local imported = sharing.ImportPreset("Shared", text)
        check("import stores without applying", imported and RikUI.DB.community.Shared and not RikUI.CharDB.applied)
        check("collision does not overwrite", sharing.ImportPreset("Shared", text) == nil)
        sharing.OpenExport()
        local window = sharing.Window
        check("export window selects copy text", window and window:IsShown() and window.edit:GetText() == text
            and not window.importButton:IsShown())
        window.edit:SetText("changed")
        env.runScript(window.edit, "OnTextChanged", true)
        check("export text is read only", window.edit:GetText() == text)
        sharing.OpenImport()
        window.name:SetText("From dialog"); window.edit:SetText(text)
        check("pasting does not import", RikUI.DB.community["From dialog"] == nil)
        env.click(window.importButton)
        check("explicit import stores and reports success", RikUI.DB.community["From dialog"] ~= nil
            and window.status:GetText():find("Saved",1,true))
        env.inCombat = true
        window.name:SetText("Combat")
        env.click(window.importButton)
        check("combat import action refuses mutation", RikUI.DB.community.Combat == nil)
        env.inCombat = false
        env.runScript(window.edit, "OnEscapePressed")
        check("escape closes sharing", not window:IsShown())
    end)
    check("sharing suite completes", ok, reason)
    restore()
end
