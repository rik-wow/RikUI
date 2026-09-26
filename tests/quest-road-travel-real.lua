-- Travel plan on compiled road networks: legs, times and planning cost.
-- Usage: luajit tests/quest-road-travel-real.lua <network dir> <faction> <all|none> startMap sx sy goalMap gx gy
local root=assert(arg[1]):gsub("\\","/")
local faction,flights=arg[2] or "Alliance",arg[3] or "all"
package.path="tests/?.lua;"..package.path
require("wow_stub")
RikUI={Secret={IsSecret=function() return false end}}
for _,name in ipairs({"schema","path-codec","roads","road-travel"}) do dofile("src/modules/questplanner/quest-"..name..".lua") end
local p=RikUI.QuestPlanner
UnitFactionGroup=function() return faction end
GetTime=function() return 0 end
C_TaxiMap={GetTaxiNodesForMap=function()
    local rows={}
    if flights=="all" then for id=1,4000 do rows[#rows+1]={nodeID=id,isUndiscovered=false} end end
    return rows
end}
local generated=dofile("tests/generated_stub.lua")
generated.Load(generated.Base(root),{"roads"})
C_AddOns={LoadAddOn=generated.PatchLoader(root)}
local identity={product="forever",build="1.60.1.69913",locale="enUS"}
local sw,start=p.Roads.Locate(tonumber(arg[4]),tonumber(arg[5]),tonumber(arg[6]))
local gw,goal=p.Roads.Locate(tonumber(arg[7]),tonumber(arg[8]),tonumber(arg[9]))
assert(sw and gw,"ends outside the road networks")
local graphs={}
for _,w in ipairs(p.RoadTravel.Worlds(sw,gw)) do
    if p.Roads.HasWorld(w) then
        local g;for _=1,1000000 do g=p.Roads.Prepare(identity,w);if g then break end end
        graphs[w]=g
    end
end
local began=os.clock()
local job=assert(p.RoadTravel.Begin(graphs,{world=sw,x=start.x,z=start.z},{world=gw,x=goal.x,z=goal.z}))
local result,steps,worst=nil,0,0
for i=1,1000000 do
    local t=os.clock();result=job:Step();worst=math.max(worst,os.clock()-t)
    if result then steps=i;break end
end
io.write(string.format("%s, flights %s: %s in %d steps, %.2fs cpu, worst step %.1f ms\n",faction,flights,result.status,steps,
    os.clock()-began,worst*1000))
for i,leg in ipairs(result.legs or {}) do
    io.write(string.format("  %d. %-9s %6.0fs  %s\n",i,leg.mode,leg.seconds,leg.text))
end
if result.seconds then io.write(string.format("  total %.0f s (%.1f min)\n",result.seconds,result.seconds/60)) end
