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
        RikUI.Profile.font = "game"
        RikUI.Profile.bags.capacityLowOnly = true
        RikUI.Profile.bags.capacityThreshold = 7
        RikUI.Profile.durability = { showPercent = false }
        RikUI.Profile.panels.questTextSize = 20
        RikUI.Profile.panels.skins = { spells = false }
        RikUI.Profile.positions.main = { point="CENTER", relativePoint="CENTER", x=120, y=-30 }
        local text, err = sharing.ExportProfile()
        check("profile export succeeds", text ~= nil, err)
        local data = sharing.Decode(text, "profile")
        check("export excludes private and transient fields", not data.chatHistory and not data.layoutUndo and not data.chat.secret)
        check("export includes appearance and anchors", data.borderColor[3] == 0.3 and data.positions.main.x == 120 and data.barFade.main == false)
        check("shared font choice round trips", data.font == "game")
        check("capacity warning policy round trips", data.bags.capacityLowOnly == true and data.bags.capacityThreshold == 7)
        check("durability visibility round trips", data.durability and data.durability.showPercent == false)
        local function defaultCoverage(defaults, shared, path)
            for key, value in pairs(defaults) do
                local name = path .. "." .. tostring(key)
                check("portable default has shared representation " .. name, shared and shared[key] ~= nil)
                if type(value) == "table" then defaultCoverage(value, shared and shared[key], name) end
            end
        end
        defaultCoverage(RikUI.Defaults.profile, data, "profile")
        check("quest prose size round trips", data.panels.questTextSize == 20)
        check("window selection round trips", data.panels.skins.spells == false)
        local active = RikUI.Profile
        check("import creates a separate profile", sharing.ImportProfile("Backup", text) == true
            and RikUI.DB.profiles.Backup ~= active and RikUI.Profile == active and RikUI.CharDB.profile == "Default")
        check("import retains portable inventory preferences", RikUI.DB.profiles.Backup.bags.capacityThreshold == 7
            and RikUI.DB.profiles.Backup.durability.showPercent == false)
        check("duplicate profile cannot overwrite", sharing.ImportProfile("Backup", text) == nil)
        check("bad profile names refused", sharing.ImportProfile("|bad", text) == nil)
        local mutations = {
            function(p) p.scale = 0 end,
            function(p) p.font = "unknown" end,
            function(p) p.panels.questTextSize = 99 end,
            function(p) p.chat.fontSize = "huge" end,
            function(p) p.positions.main.point = "BAD" end,
            function(p) p.positions.main.extra = true end,
            function(p) p.modules.foo = "yes" end,
            function(p) p.chatHistory = {} end,
            function(p) p.bags.columns = 1 end,
            function(p) p.bags.capacityLowOnly = 1 end,
            function(p) p.bags.capacityThreshold = 21 end,
            function(p) p.bags.capacityThreshold = 1.5 end,
            function(p) p.durability.showPercent = "yes" end,
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
