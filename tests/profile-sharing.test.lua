return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local ok, reason = pcall(function()
        widgets.loadAddon(env, { "src/persistence/codec.lua", "src/ui/skin.lua",
            "src/configuration/wizard/wizard-controls.lua", "src/configuration/options/sharing.lua",
            "src/configuration/options/importexport.lua" })
        local file = io.open("src/configuration/options/profile-sharing.lua", "r")
        if file then file:close(); dofile("src/configuration/options/profile-sharing.lua") end
        local sharing = RikUI.Sharing
        check("profile sharing available", type(sharing.ExportProfile) == "function")
        if not sharing.ExportProfile then return end
        RikUI.Profile.chatHistory = { "private" }
        RikUI.Profile.layoutUndo = { private = true }
        RikUI.Profile.chat.secret = "private"
        RikUI.Profile.borderColor = { 0.1, 0.2, 0.3 }
        RikUI.Profile.barFade.main = false
        RikUI.Profile.positions.main = { point="CENTER", relativePoint="CENTER", x=120, y=-30 }
        local text, err = sharing.ExportProfile()
        check("profile export succeeds", text ~= nil, err)
        local data = sharing.Decode(text, "profile")
        check("export excludes private and transient fields", not data.chatHistory and not data.layoutUndo and not data.chat.secret)
        check("export includes appearance and anchors", data.borderColor[3] == 0.3 and data.positions.main.x == 120 and data.barFade.main == false)
        local active = RikUI.Profile
        check("import creates a separate profile", sharing.ImportProfile("Backup", text) == true
            and RikUI.DB.profiles.Backup ~= active and RikUI.Profile == active and RikUI.CharDB.profile == "Default")
        check("duplicate profile cannot overwrite", sharing.ImportProfile("Backup", text) == nil)
        check("bad profile names refused", sharing.ImportProfile("|bad", text) == nil)
        local mutations = {
            function(p) p.scale = 0 end,
            function(p) p.chat.fontSize = "huge" end,
            function(p) p.positions.main.point = "BAD" end,
            function(p) p.positions.main.extra = true end,
            function(p) p.modules.foo = "yes" end,
            function(p) p.chatHistory = {} end,
            function(p) p.bags.columns = 1 end,
            function(p) p.borderColor[4] = 1 end,
        }
        for i, mutate in ipairs(mutations) do
            local bad = RikUI.Setup.CopyState(data); mutate(bad)
            check("malformed profile atomic rejection " .. i, sharing.ImportProfile("Bad"..i, sharing.Encode("profile",bad)) == nil
                and RikUI.DB.profiles["Bad"..i] == nil)
        end
        check("preset payload cannot become profile", sharing.ImportProfile("Wrong", sharing.Encode("preset",data)) == nil)
        env.inCombat = true
        check("combat profile import refused", sharing.ImportProfile("Combat",text) == nil and not RikUI.DB.profiles.Combat)
        env.inCombat = false
        sharing.OpenProfileExport()
        check("profile export uses copy dialog", sharing.Window.edit:GetText() == text and not sharing.Window.importButton:IsShown())
        sharing.OpenProfileImport()
        sharing.Window.name:SetText("Dialog"); sharing.Window.edit:SetText(text)
        check("profile paste is inert", not RikUI.DB.profiles.Dialog)
        env.click(sharing.Window.importButton)
        check("profile explicit save preserves selection", RikUI.DB.profiles.Dialog and RikUI.Profile == active)
    end)
    check("profile sharing suite completes", ok, reason)
    restore()
end
