-- Actual locally compiled terrain integration gate; no game UI or process access.
-- Usage: luajit tests/quest-terrain-data.lua <generated-addon-directory>
local root=assert(arg[1],"generated terrain addon directory required"):gsub("\\","/"):gsub("/$","")
RikUI={Secret={IsSecret=function() return false end}}
for _,name in ipairs({"schema","nav-geometry","nav-funnel","nav-follow","nav-search","navmesh"}) do
    dofile("src/modules/questplanner/quest-"..name..".lua")
end
local planner,meta,shards=RikUI.QuestPlanner
planner.Terrain={Install=function(m,s) meta,shards=m,s; return true end}
local namespace={}
local toc=assert(io.open(root.."/RikUIQuestTerrain.toc","r"))
for line in toc:lines() do
    line=line:gsub("\r",""):match("^%s*(.-)%s*$")
    if line~="" and line:sub(1,1)~="#" then
        assert(line:match("^[%w_%-]+%.lua$"),"unexpected generated TOC path")
        assert(loadfile(root.."/"..line))("RikUIQuestTerrain",namespace)
    end
end
toc:close()
assert(meta and shards,"generated addon did not register")
local raw={}
for _,shard in ipairs(shards) do for _,poly in ipairs(shard.polygons) do raw[poly.id]=poly end end
local loadJob=assert(planner.NavMesh.Begin(meta,shards))
local count,maxSlice,started=0,0,os.clock()
local mesh
repeat
    local before=os.clock()
    local value,reason,done=loadJob:Step(32)
    maxSlice=math.max(maxSlice,(os.clock()-before)*1000); count=count+1
    if done then mesh=assert(value,reason); break end
until false
local loadMS=(os.clock()-started)*1000
local probes=assert(loadfile(root.."/validation-probes.lua"))()
local function center(poly)
    local point={0,0,0}
    for _,vertex in ipairs(poly.points) do for axis=1,3 do point[axis]=point[axis]+vertex[axis]/#poly.points end end
    return point
end
local centers={}
for id,poly in pairs(raw) do centers[id]=center(poly) end
local function oracle(from,to)
    local distances,settled={[from]=0},{}
    while true do
        local chosen,cost
        for id,value in pairs(distances) do
            if not settled[id] and (cost==nil or value<cost or (value==cost and id<chosen)) then chosen,cost=id,value end
        end
        if not chosen then return nil end
        if chosen==to then return cost end
        settled[chosen]=true
        for _,edge in ipairs(raw[chosen].portals) do
            local midpoint=planner.NavGeometry.Midpoint(edge.left,edge.right)
            local candidate=cost+planner.NavGeometry.Distance(centers[chosen],midpoint)+planner.NavGeometry.Distance(midpoint,centers[edge.to])
            if not distances[edge.to] or candidate<distances[edge.to] then distances[edge.to]=candidate end
        end
    end
end
local tested,maxWork,pathSlice=0,0,0
for _,probe in ipairs(probes) do
    local a,b=assert(centers[probe.from]),assert(centers[probe.to])
    local first,last={x=a[1],height=a[2],z=a[3]},{x=b[1],height=b[2],z=b[3]}
    local locatedStart,locatedGoal=assert(mesh:Locate(first)),assert(mesh:Locate(last))
    local job=assert(mesh:Begin(first,last,{maxWork=131072}))
    local route
    repeat
        local before=os.clock(); route=job:Step(64)
        pathSlice=math.max(pathSlice,(os.clock()-before)*1000)
    until route
    assert(route.status=="modeled",route.detail)
    local exact=assert(oracle(probe.from,probe.to))
        +planner.NavGeometry.Distance(locatedStart.point,a)+planner.NavGeometry.Distance(locatedGoal.point,b)
    assert(math.abs((route.metrics.baselineGraphMeters or route.graphMeters)-exact)<.0001,string.format("A* %.8f differs from Dijkstra+endpoint connectors %.8f",route.graphMeters,exact))
    assert(route.walkPoints and route.meters<=route.graphMeters+.001,"funnel worsened usable length")
    print(string.format("Route quality: center %.3f yd, funnel %.3f yd, reduction %.2f%%",route.graphMeters,route.meters,100*(1-route.meters/route.graphMeters)))
    assert(planner.NavGeometry.Distance(route.points[1],locatedStart.point)<.0001,"wrong start")
    assert(planner.NavGeometry.Distance(route.points[#route.points],locatedGoal.point)<.0001,"wrong goal")
    assert(route.nativeVerified==false and route.globalOptimal==false,"overclaimed path")
    for index=1,#route.corridor-1 do
        local source,target=raw[route.corridor[index]],raw[route.corridor[index+1]]
        local midpoint=route.points[index*2+1]
        assert(planner.NavGeometry.Contains(source.points,midpoint[1],midpoint[3]),"corridor exits source polygon")
        assert(planner.NavGeometry.Contains(target.points,midpoint[1],midpoint[3]),"corridor exits target polygon")
    end
    if route.metrics.baselineFunnelMeters then
        assert(route.meters<=route.metrics.baselineFunnelMeters+.001,"alternative worsened baseline")
        print(string.format("Corridor choice: %s; baseline %.3f yd, chosen %.3f yd; %d/%d complete alternatives",
            route.corridorChoice,route.metrics.baselineFunnelMeters,route.meters,
            route.metrics.completedAlternatives,route.metrics.alternatives))
    end
    tested=tested+1; maxWork=math.max(maxWork,route.metrics.work)
end
assert(tested>=3,"real-data path probes missing")
print(string.format("Actual terrain: %d polygons, %d portals; %d paths match Dijkstra; max work %d",
    meta.counts.polygons,meta.counts.portals,tested,maxWork))
print(string.format("Headless LuaJIT only: load %.2fms over %d slices, max load slice %.3fms; max path slice %.3fms; native unverified",
    loadMS,count,maxSlice,pathSlice))
