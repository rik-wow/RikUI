-- Forever 1.60.1 Camelot talent groups; sources and beta status: docs/roles.md.
local core, setup = RikUI, RikUI.Setup
local ROLE_THRESHOLD = 10
local TALENT_TREE_COUNT = 3

local function integer(value, minimum)
    return not issecretvalue(value) and type(value) == "number"
        and value >= minimum and value < math.huge and value % 1 == 0
end

local function displayGroups(config)
    local groups, ids, seen = {}, {}, {}
    for _, treeID in ipairs(config.treeIDs) do
        assert(integer(treeID, 1), "invalid talent tree ID")
        for _, entry in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID)) do
            assert(integer(entry.groupID, 1), "invalid talent group")
            assert(not issecretvalue(entry.displayName) and type(entry.displayName) == "string",
                "unreadable talent tree name")
            assert(not seen[entry.groupID], "duplicate talent group")
            seen[entry.groupID] = true
            groups[#groups + 1] = { id = entry.groupID, name = entry.displayName }
            ids[#ids + 1] = entry.groupID
        end
    end
    -- Match the Camelot talent header's native display order, not localized names.
    assert(#groups == TALENT_TREE_COUNT, "incomplete talent tree groups")
    return groups, ids
end

local function groupPoints(group, entry)
    -- Camelot's native header displays zero for an omitted currency group.
    if not entry then return 0 end
    local currency = entry.currencyInfos
    assert(type(currency) == "table" and type(currency[1]) == "table",
        group.name .. ": talent currency data unavailable")
    local points = currency[1].spent
    assert(not issecretvalue(points), group.name .. ": talent points are secret")
    assert(integer(points, 0), group.name .. ": invalid talent points (" .. type(points) .. ")")
    return points
end

local function assignPoints(groups, currencies)
    assert(type(currencies) == "table", "talent currency response unavailable")
    local byID, total = {}, 0
    for _, entry in ipairs(currencies) do
        assert(integer(entry.traitNodeGroupID, 1), "invalid talent currency group")
        assert(not byID[entry.traitNodeGroupID], "duplicate talent currency group")
        byID[entry.traitNodeGroupID] = entry
    end
    for _, group in ipairs(groups) do
        group.points = groupPoints(group, byID[group.id])
        total = total + group.points
    end
    return total
end

local function readTalents()
    assert(type(C_ClassTalents) == "table" and type(C_Traits) == "table", "talent API unavailable")
    local configID = C_ClassTalents.GetActiveConfigID()
    assert(integer(configID, 1), "active talent config unavailable")
    local staged = C_Traits.ConfigHasStagedChanges(configID)
    assert(not issecretvalue(staged) and staged == false, "talent changes are uncommitted")
    local config = C_Traits.GetConfigInfo(configID)
    assert(type(config) == "table" and type(config.treeIDs) == "table", "talent config unavailable")
    local groups, ids = displayGroups(config)
    local total = assignPoints(groups, C_Traits.GetGroupCurrencyInfo(configID, ids))
    return groups, total
end

local function guess(preset)
    assert(type(preset.roles) == "table" and type(preset.roleOrder) == "table"
        and #preset.roleOrder > 0, "preset role order unavailable")
    local trees, total = readTalents()
    local best, most, seen = nil, -1, {}
    for _, role in ipairs(preset.roleOrder) do
        local entry, points = preset.roles[role], 0
        assert(not seen[role] and type(entry) == "table" and type(entry.trees) == "table"
            and #entry.trees > 0, "invalid role tree mapping")
        seen[role] = true
        local used = {}
        for _, index in ipairs(entry.trees) do
            assert(integer(index, 1) and trees[index] and not used[index], "invalid role tree index")
            used[index] = true
            points = points + trees[index].points
        end
        if points > most then best, most = role, points end
    end
    for role in pairs(preset.roles) do assert(seen[role], "role missing from preset order") end
    return total < ROLE_THRESHOLD and preset.roleOrder[1] or best, trees
end

-- nil, nil, reason means unknown, never a fabricated zero-point allocation.
function setup.GuessRole(class, presetName)
    local preset = setup.Source(class, presetName)
    if not preset then return nil, nil, "No preset for " .. tostring(class) end
    local ok, role, trees = pcall(guess, preset)
    if ok then return role, trees end
    local reason = not issecretvalue(role) and type(role) == "string" and role or "talent read failed"
    return nil, nil, reason
end
