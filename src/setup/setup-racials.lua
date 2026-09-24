-- Racial utilities share Ctrl-C/V. Displaced preset entries are preserved on
-- manual action page two; native paging already presents its slots 13..24.
local core, setup = RikUI, RikUI.Setup
function setup.AddRacials(preset)
    if not core.Racials or type(UnitRace) ~= "function" then return end
    local ok, _, _, raceID = pcall(UnitRace, "player")
    if not ok or (issecretvalue and issecretvalue(raceID)) then return end
    local names = core.Racials.ByRace[raceID]
    if not names then return end
    local data, utility = core.Spells.Catalog(preset.class), preset.bars.bar3 or {}
    local extra = preset.bars.extra or {}
    for index, name in ipairs(names) do
        if data[name] then
            local target, free = 10 + index, nil
            for slot = 1, 12 do if not extra[slot] then free = slot; break end end
            if not utility[target] or free then
                if utility[target] then extra[free] = utility[target] end
                utility[target] = { spell = name }
            end
        end
    end
    preset.bars.bar3 = utility
    if next(extra) then preset.bars.extra = extra end
end

