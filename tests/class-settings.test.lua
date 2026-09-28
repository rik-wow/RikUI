-- Per-class editable lists: shipped defaults, profile overrides, validation and change notices.
return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local savedClass = UnitClass
    local function load(profile)
        widgets.loadAddon(env, { "data/spells.lua", "data/spells-paladin.lua", "data/spells-druid.lua",
            "src/modules/cooldowns/cooldowns.lua", "data/class-cooldowns-paladin.lua", "data/class-cooldowns-druid.lua",
            "src/modules/auras/auras.lua", "src/modules/auras/auras-class.lua", "data/class-auras-paladin.lua",
            "data/class-auras-druid.lua", "src/core/class-settings.lua" }, profile or { modules = { cooldowns = false, classauras = false, auras = false } })
        return RikUI.ClassSettings
    end
    local function joined(list) return table.concat(list, ",") end
    local ok, reason = pcall(function()
        local settings = load()
        local shipped = joined(RikUI.ClassCooldownProfiles.PALADIN)
        check("the class list defaults to the shipped table and is a copy", joined(settings.List("PALADIN", "cooldowns")) == shipped
            and settings.List("PALADIN", "cooldowns") ~= RikUI.ClassCooldownProfiles.PALADIN and not settings.IsCustom("PALADIN", "cooldowns"))
        check("every class with shipped data is listed alphabetically", joined(settings.Classes()) == "DRUID,PALADIN")
        local changes = {}
        settings.OnChange(function(class, kind) changes[#changes + 1] = class .. ":" .. kind end)
        local capOk, capReason = settings.Add("PALADIN", "cooldowns", "Consecration")
        check("a full class list refuses another spell and says why", capOk == nil and capReason:find("12", 1, true))
        check("a catalogue spell can be added once there is room and is saved in the profile",
            settings.Remove("PALADIN", "cooldowns", "Holy Strike") == true and settings.Add("PALADIN", "cooldowns", "Consecration") == true
            and settings.List("PALADIN", "cooldowns")[#RikUI.ClassCooldownProfiles.PALADIN] == "Consecration"
            and settings.IsCustom("PALADIN", "cooldowns") and RikUI.Profile.classes.PALADIN.cooldowns[#RikUI.ClassCooldownProfiles.PALADIN] == "Consecration"
            and changes[1] == "PALADIN:cooldowns")
        local candidates = settings.Candidates("PALADIN", "cooldowns")
        local listed = {}
        for _, name in ipairs(candidates) do listed[name] = true end
        check("candidates are the class's other catalogue spells, sorted", not listed["Consecration"] and not listed["Judgement"]
            and listed["Holy Light"] and candidates[1] < candidates[2])
        local twiceOk, twiceReason = settings.Add("PALADIN", "cooldowns", "Consecration")
        settings.Remove("PALADIN", "cooldowns", "Exorcism")
        local unknownOk, unknownReason = settings.Add("PALADIN", "cooldowns", "Fireball")
        check("unknown and repeated spells are refused with a reason", unknownOk == nil and unknownReason:find("Fireball", 1, true)
            and twiceOk == nil and twiceReason:find("already", 1, true))
        settings.Move("PALADIN", "cooldowns", "Judgement", 1)
        local moved = settings.List("PALADIN", "cooldowns")
        check("a spell moves down one place and the first cannot move up", moved[2] == "Judgement" and moved[1] == RikUI.ClassCooldownProfiles.PALADIN[2]
            and settings.Move("PALADIN", "cooldowns", moved[1], -1) == true and settings.List("PALADIN", "cooldowns")[1] == moved[1])
        check("removing works and saving the shipped order drops the override", settings.Remove("PALADIN", "cooldowns", "Consecration") == true
            and settings.Set("PALADIN", "cooldowns", RikUI.ClassCooldownProfiles.PALADIN) == true
            and not settings.IsCustom("PALADIN", "cooldowns") and RikUI.Profile.classes == nil or RikUI.Profile.classes.PALADIN == nil)
        local tooMany = {}
        for index = 1, 13 do tooMany[index] = "Holy Light" end
        local limitOk, limitReason = settings.Set("PALADIN", "cooldowns", tooMany)
        check("the strip's twelve-spell cap is enforced", limitOk == nil and limitReason:find("12", 1, true))
        check("effect groups resolve with the shipped enchant flag and note a pending reload only after an edit",
            joined(settings.Effects("PALADIN").harmful) == joined(RikUI.ClassAuraProfiles.PALADIN.harmful)
            and settings.Effects("PALADIN").enchants == RikUI.ClassAuraProfiles.PALADIN.enchants and not settings.NeedsReload()
            and settings.Add("PALADIN", "harmful", "Consecration") == true and settings.NeedsReload()
            and joined(settings.Effects("PALADIN").harmful) == joined(RikUI.ClassAuraProfiles.PALADIN.harmful) .. ",Consecration")
        local sixOk = settings.Set("PALADIN", "harmful", { "Hammer of Justice", "Turn Undead", "Repentance", "Consecration", "Exorcism", "Holy Wrath" })
        local sevenOk = settings.Set("PALADIN", "harmful", { "Hammer of Justice", "Turn Undead", "Repentance", "Consecration", "Exorcism", "Holy Wrath", "Holy Shock" })
        check("target effect groups cap at six", sixOk == true and sevenOk == nil)
        check("a reset removes the override and reports through the change notice", settings.Reset("PALADIN", "harmful") == true
            and not settings.IsCustom("PALADIN", "harmful") and changes[#changes] == "PALADIN:harmful")
        check("another class can be edited before it is played", settings.Move("DRUID", "cooldowns", RikUI.ClassCooldownProfiles.DRUID[1], 1) == true
            and settings.IsCustom("DRUID", "cooldowns") and not settings.IsCustom("PALADIN", "cooldowns"))
        local projected = RikUI.ProfileSchema.Project({ classes = { PALADIN = { cooldowns = { "Judgement" }, harmful = { "Repentance" } } } })
        check("the profile schema keeps per-class lists", projected.classes.PALADIN.cooldowns[1] == "Judgement")
        local badOk = pcall(RikUI.ProfileSchema.Project, { classes = { PALADIN = { cooldowns = { 42 } } } })
        local longOk = pcall(RikUI.ProfileSchema.Project, { classes = { PALADIN = { cooldowns = tooMany } } })
        check("the profile schema rejects non-names and over-long lists", not badOk and not longOk)
        RikUI.Profile.classes = { PALADIN = { cooldowns = { "Holy Light" } } }
        check("a saved override replaces the shipped list wholesale", joined(settings.List("PALADIN", "cooldowns")) == "Holy Light"
            and settings.IsCustom("PALADIN", "cooldowns"))
    end)
    restore()
    UnitClass = savedClass
    env.inCombat = false
    check("Class settings suite completes", ok, reason)
end
