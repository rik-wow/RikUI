-- Real compiled roads + quest patches: route between map positions through the
-- same modules the client runs (network A*, patch decoding, NavMesh validation,
-- mesh/network joins) and follow each route to the end.
-- Usage: luajit tests/quest-roads-navigate-real.lua <network dir> <uiMapID> sx sy gx gy [sx sy gx gy ...]
package.path = "tests/?.lua;" .. package.path
require("wow_stub")
local root, mapID = arg[1], tonumber(arg[2])
assert(root and mapID and #arg >= 6, "usage: <network dir> <uiMapID> sx sy gx gy ...")
RikUI = {Secret = {IsSecret = function() return false end}}
for _, name in ipairs({"schema", "builds", "nav-geometry", "nav-funnel", "nav-follow", "nav-search", "navmesh", "nav-attach",
    "path-codec", "roads", "road-patches", "road-route", "road-follow", "road-navigate"}) do
    dofile("src/modules/questplanner/quest-" .. name .. ".lua")
end
local p = RikUI.QuestPlanner
local loaded = {}
local generated = dofile("tests/generated_stub.lua")
generated.Load(generated.Base(root), {"roads"})
C_AddOns = {LoadAddOn = generated.PatchLoader(root, function(addon) loaded[#loaded + 1] = addon end)}
local clientBuild = os.getenv("RIKUI_CLIENT_BUILD") or "1.60.1.69913"
p.Builds.Observe(clientBuild)
local identity = {product = "forever", build = p.Builds.DataBuild(clientBuild), locale = "enUS"}
local function finish(job, limit)
    for _ = 1, limit or 2000000 do local r = job:Step(16); if r then return r end end
    error("step limit")
end
local failures = 0
for at = 3, #arg, 4 do
    local sx, sy, gx, gy = tonumber(arg[at]), tonumber(arg[at + 1]), tonumber(arg[at + 2]), tonumber(arg[at + 3])
    local world, start, view = p.Roads.Locate(mapID, sx, sy)
    local _, goal = p.Roads.Locate(mapID, gx, gy)
    assert(world and goal, "positions outside road index")
    local graph, why
    for _ = 1, 100000 do graph, why = p.Roads.Prepare(identity, world); if graph or why ~= "loading" then break end end
    assert(graph, why)
    local before = #loaded
    local t0 = os.clock()
    local job = assert(p.RoadNavigate.Begin(graph, view, start, goal, {speed = 7, marker = true}))
    local result = finish(job)
    local cpu = os.clock() - t0
    if os.getenv("ROADS_DIAGNOSTICS") then
        local loader = p.RoadPatches.Begin(graph, view, {start, goal})
        if loader then
            local mesh
            repeat local value, _, done = loader:Step(128); if done then mesh=value;break end until false
            if mesh then
                local at, why = mesh:Locate(start)
                local job, reason = mesh:BeginMarkerApproach(start, goal, {maxWork=262144,markerRadius=8,
                    reachableApproach=true,commonApproach=true,uncertainVicinity=true})
                local direct = job and finish(job)
                io.write("DIRECT start=", tostring(at and at.id), " locate=", tostring(why),
                    " status=", tostring(direct and direct.status or reason), " detail=", tostring(direct and direct.detail), "\n")
            end
        end
    end
    local line = string.format("ROUTE %.3f,%.3f -> %.3f,%.3f status=%s", sx, sy, gx, gy, result.status)
    if result.status == "modeled" then
        local follow = assert(p.RoadFollow.Begin(result, function(pt) return p.Roads.Unproject(view, pt) end))
        -- Walk the polyline at 1-yard steps and require steady progress to the end.
        local walked, reversals, last = 0, 0, math.huge
        for i = 1, #result.points - 1 do
            local a, b = result.points[i], result.points[i + 1]
            local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2)
            for s = 0, math.floor(len) do
                local q = len > 0 and s / len or 0
                local d = follow.follow({x = a[1] + (b[1] - a[1]) * q, z = a[3] + (b[3] - a[3]) * q}, {speed = 7})
                if not d or d.status ~= "modeled" then reversals = reversals + 1000; break end
                if d.meters > last + 2 then reversals = reversals + 1 end
                last = d.meters; walked = walked + 1
            end
        end
        line = line .. string.format(" yd=%.0f nodes=%d meshStart=%s meshGoal=%s meshOnly=%s startLeg=%.0f goalLeg=%.0f addons=%d cpu=%.2fs followSteps=%d regressions=%d",
            result.meters, result.nodes or 0, tostring(result.meshStart), tostring(result.meshGoal), tostring(result.meshOnly),
            result.startLeg or 0, result.goalLeg or 0, #loaded - before, cpu, walked, reversals)
        if reversals > 0 then failures = failures + 1 end
    else
        line = line .. " detail=" .. tostring(result.detail)
        failures = failures + 1
    end
    io.write(line, "\n")
end
io.write(string.format("PATCH_STATS loads=%d cells=%d\n", p.RoadPatches.Stats().loads, p.RoadPatches.Stats().cells))
assert(failures == 0, failures .. " routes failed")
io.write("ROADS_NAVIGATE_OK\n")
