-- Active racial abilities verified against build 69913 ChrRaces, SkillLineAbility,
-- SpellName and SpellMisc on 2026-09-23. See docs/class-presets.md.
local core = RikUI
core.Racials = { ByRace = {
    [1] = { "Will to Survive", "Perception" },
    [2] = { "Blood Fury", "Shatter Curse" },
    [3] = { "Stoneform", "Find Treasure" },
    [4] = { "Elune's Light", "Shadowmeld" },
    [5] = { "Will of the Forsaken", "Cannibalize" },
    [6] = { "War Stomp", "Cultivation" },
    [7] = { "Escape Artist", "Eureka!" },
    [8] = { "Berserking", "Rapid Regeneration" },
    [95] = { "Walk on Air", "Read Ley Line" },
    [96] = { "Walk on Air", "Skysight" },
} }
local entries = {
    { "Will to Survive", 1259718, 136129 }, { "Perception", 20600, 136090 },
    { "Blood Fury", 20572, 135726 }, { "Shatter Curse", 1299026, 136082 },
    { "Stoneform", 20594, 136225 }, { "Find Treasure", 2481, 135725 },
    { "Elune's Light", 1259799, 136057 }, { "Shadowmeld", 20580, 132089 },
    { "Will of the Forsaken", 7744, 136187 }, { "Cannibalize", 20577, 132278 },
    { "War Stomp", 20549, 132368 }, { "Cultivation", 20552, 133938 },
    { "Escape Artist", 20589, 132309 }, { "Berserking", 20554, 135727 },
    { "Rapid Regeneration", 1260270, 1850550 }, { "Walk on Air", 1259416, 132845 },
    { "Read Ley Line", 1259705, 236219 }, { "Skysight", 1259686, 1029587 },
}
local eureka = { WARRIOR = 1259813, ROGUE = 1259812, PRIEST = 1259823, MAGE = 1259817, WARLOCK = 1259821 }
function core.Racials.AddToCatalog(class, data)
    for _, entry in ipairs(entries) do
        data[entry[1]] = { ranks = { entry[2] }, icon = entry[3] }
    end
    if eureka[class] then data["Eureka!"] = { ranks = { eureka[class] }, icon = 4226119 } end
end
for class, data in pairs(core.SpellCatalogs) do core.Racials.AddToCatalog(class, data) end

