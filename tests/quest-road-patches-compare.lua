-- Two builds of the quest patch packs through the loader the client runs: every cell of the first
-- must decode to the same rows in the second. Used when the pack layout changes and the geometry
-- must not. This is a host check, not native gameplay acceptance.
-- Usage: luajit tests/quest-road-patches-compare.lua <list of patch files> <list of patch files>
-- Each list is a text file with one patch-NNN.lua path per line.
assert(arg[1] and arg[2], "usage: <first list> <second list>")
RikUI = {Secret = {IsSecret = function() return false end}}
for _, name in ipairs({"schema", "path-codec", "inflate"}) do dofile("src/modules/questplanner/quest-" .. name .. ".lua") end
RikUI.QuestPlanner.Roads = {}
dofile("src/modules/questplanner/quest-road-patches.lua")
local planner = RikUI.QuestPlanner
local roads, patches = planner.Roads, planner.RoadPatches

-- Registers one list's cells and returns them by world and cell key.
local function load(list)
    local cells, count, bytes = {}, 0, 0
    local register, compact = roads.Patch, roads.Patch2
    local world
    local function note(revision, key, ok, reason)
        assert(ok, reason)
        cells[world .. ":" .. key] = {revision = revision, key = key}; count = count + 1
    end
    roads.Patch = function(revision, key, ...) note(revision, key, register(revision, key, ...)) end
    roads.Patch2 = function(revision, key, ...) note(revision, key, compact(revision, key, ...)) end
    for path in io.lines(list) do
        path = path:gsub("\r", "")
        if path ~= "" then
            local file = assert(io.open(path, "rb"))
            local text = file:read("*a")
            file:close()
            bytes = bytes + #text
            world = assert(path:match("RikUIQuestRoads_W(%d+)_P%d+"), "pack folder expected: " .. path)
            assert(loadstring(text, path))()
        end
    end
    roads.Patch, roads.Patch2 = register, compact
    return cells, count, bytes
end

local function rows(revision, key)
    local graph = {revision = revision, cellYards = 128, catalog = {patchUnitsPerYard = 1024}}
    local result, reason
    local thread = coroutine.create(function() result, reason = patches.Decode(graph, key) end)
    while coroutine.status(thread) ~= "dead" do assert(coroutine.resume(thread)) end
    return result, reason
end

local function same(a, b)
    if #a ~= #b then return false end
    for index, row in ipairs(a) do
        local other = b[index]
        if row.id ~= other.id or #row.points ~= #other.points or #row.portals ~= #other.portals then return false end
        for k, point in ipairs(row.points) do
            local q = other.points[k]
            if point[1] ~= q[1] or point[2] ~= q[2] or point[3] ~= q[3] then return false end
        end
        for k, portal in ipairs(row.portals) do
            local q = other.portals[k]
            if portal.to ~= q.to then return false end
            for axis = 1, 3 do
                if portal.left[axis] ~= q.left[axis] or portal.right[axis] ~= q.right[axis] then return false end
            end
        end
    end
    return true
end

local first, firstCount, firstBytes = load(arg[1])
local second, secondCount, secondBytes = load(arg[2])
local cells, polygons, portals, different, started = 0, 0, 0, 0, os.clock()
for name, cell in pairs(first) do
    local other = assert(second[name], "cell missing from the second build: " .. name)
    local a = assert(rows(cell.revision, cell.key))
    local b = assert(rows(other.revision, other.key))
    if not same(a, b) then
        different = different + 1
        io.write("DIFFERENT cell ", name, "\n")
    end
    cells = cells + 1
    polygons = polygons + #a
    for _, row in ipairs(a) do portals = portals + #row.portals end
end
for name in pairs(second) do assert(first[name], "cell missing from the first build: " .. name) end
io.write(string.format("PATCH_COMPARE cells=%d polygons=%d portals=%d different=%d firstBytes=%d secondBytes=%d cpu=%.0fs\n",
    cells, polygons, portals, different, firstBytes, secondBytes, os.clock() - started))
assert(firstCount == cells and secondCount == cells, "a cell was registered twice")
assert(different == 0, different .. " cells differ")
io.write("PATCH_COMPARE_OK\n")
