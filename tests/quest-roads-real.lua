-- Real compiled road network: load the addon files as the client would,
-- then check A* against plain Dijkstra on random node pairs.
-- Usage: luajit tests/quest-roads-real.lua <network dir> <worldMapID> [pairs]
package.path = "tests/?.lua;" .. package.path
require("wow_stub")
local root, world, pairsWanted = arg[1], tonumber(arg[2]), tonumber(arg[3] or 40)
assert(root and world, "usage: quest-roads-real.lua <network dir> <world> [pairs]")
RikUI = {Secret = {IsSecret = function() return false end}}
for _, name in ipairs({"schema", "path-codec", "roads", "road-route", "road-follow"}) do
    dofile("src/modules/questplanner/quest-" .. name .. ".lua")
end
local p = RikUI.QuestPlanner
local function readToc(addon)
    local files = {}
    for line in io.lines(root .. "/" .. addon .. "/" .. addon .. ".toc") do
        if line:match("%.lua$") then files[#files + 1] = line end
    end
    return files
end
dofile(root .. "/RikUIQuestRoads/index.lua")
C_AddOns = {LoadAddOn = function(addon)
    for _, file in ipairs(readToc(addon)) do dofile(root .. "/" .. addon .. "/" .. file) end
    return true
end}
local identity = {product = "forever", build = "1.60.1.69913", locale = "enUS"}
local started = os.clock()
local graph, why
for _ = 1, 100000 do graph, why = p.Roads.Prepare(identity, world); if graph or why ~= "loading" then break end end
assert(graph, why)
local loadSeconds = os.clock() - started
local nodes = graph:Nodes()
local function dijkstra(s, t)
    local dist, done = {[s] = 0}, {}
    while true do
        local u, best = nil, math.huge
        for n, d in pairs(dist) do if not done[n] and d < best then u, best = n, d end end
        if not u then return nil end
        if u == t then return best end
        done[u] = true
        local first, last = graph:EdgeRange(u)
        for e = first, last do
            local v, cost = graph:Edge(e)
            if best + cost < (dist[v] or math.huge) then dist[v] = best + cost end
        end
    end
end
math.randomseed(7)
local checked, agree, unreachable, maxWork, routeSeconds = 0, 0, 0, 0, 0
while checked < pairsWanted do
    local s, t = math.random(nodes), math.random(nodes)
    local sx, sz = graph:Node(s)
    local tx, tz = graph:Node(t)
    local expected = dijkstra(s, t)
    local job = assert(p.RoadRoute.Begin(graph, {x = sx, z = sz}, {x = tx, z = tz}))
    local t0 = os.clock()
    local result
    for _ = 1, 100000 do result = job:Step(64); if result then break end end
    routeSeconds = math.max(routeSeconds, os.clock() - t0)
    checked = checked + 1
    if not expected then
        unreachable = unreachable + 1
    elseif result.status == "modeled" and result.cost <= expected + 1e-6 then
        agree = agree + 1
        maxWork = math.max(maxWork, result.metrics.work)
    end
end
io.write(string.format("ROADS world=%d nodes=%d load=%.2fs pairs=%d agree=%d unreachable=%d maxWork=%d maxRouteCPU=%.3fs\n",
    world, nodes, loadSeconds, checked, agree, unreachable, maxWork, routeSeconds))
assert(agree + unreachable == checked, "A* disagreed with Dijkstra")
io.write("ROADS_REAL_OK\n")
