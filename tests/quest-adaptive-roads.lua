-- Adaptive planning on the installed corpus and road network, from an archived
-- native observation: the planner's choice, its decision replay, then a
-- simulated walk that follows road guidance's aim to arrival.
-- This is a host replay, not native gameplay acceptance.
-- Usage: luajit tests/quest-adaptive-roads.lua <AddOns root> <RIKQ packet> [questID] [frames] [flavor] [x y] [churn frames]
-- churn: invalidate the controller every N frames, as rapid quest-state events do in game.
local root=assert(arg[1]):gsub("\\","/"):gsub("/$","")
RikUI={CharDB={},Changed=function() end};RikUI["Secret"]={IsSecret=function() return false end}
local modules={"schema","objectives","transfer","nav-geometry","nav-funnel","nav-follow","nav-search",
    "path-codec","nav-attach","region-codec","terrain-packs","regions","navmesh",
    "roads","road-patches","road-route","road-follow","road-navigate","road-travel","road-guidance",
    "steps","step-bindings","guide-data","observed-steps","hunts","targets",
    "optimizer","area-optimizer","semantic-data","semantic-guidance","recommendations","guidance",
    "preferences","plan-state","plan-graph","plan-transitions","plan-learning","plan-costs","plan-search",
    "bag-scan","plan-services","plan-rewards","plan-travel","plan-context","plan-runtime","controller","terrain"}
for _,name in ipairs(modules) do dofile("src/modules/questplanner/quest-"..name..".lua") end
local p=RikUI.QuestPlanner
local file=assert(io.open(assert(arg[2]),"rb"));local wire=file:read(131073);file:close()
local snapshot=assert(p.Transfer.Decode(wire:gsub("[\r\n]+$","")))
snapshot.origin=nil
local ctx=snapshot.context
ctx.origin="live"
local position={mapID=1426,x=tonumber(arg[6]) or .429,y=tonumber(arg[7]) or .472}
local elapsed,requested=0,false
local terrainCallback
-- ROADS_ROOT: load road addons from a compiled, not yet installed, network.
local roadsRoot=(os.getenv("ROADS_ROOT") or root):gsub("\\","/")
local function home(name) return name:match("^RikUIQuestRoads") and roadsRoot or root end
assert(loadfile(roadsRoot.."/RikUIQuestRoads/index.lua"))()
local world,_,view=p.Roads.Locate(position.mapID,position.x,position.y)
assert(world,"start position has no road network")
GetTime=function() return elapsed end
debugprofilestop=function() return os.clock()*1000 end
InCombatLockdown=function() return false end
local addonLoads,loadMS={},0
C_AddOns={LoadAddOn=function(name)
    if addonLoads[name] then return true end
    local began=os.clock()
    local base=home(name)
    local toc=io.open(base.."/"..name.."/"..name..".toc")
    if not toc then return false end
    for line in toc:lines() do
        line=line:gsub("\r",""):match("^%s*(.-)%s*$")
        if line~="" and line:sub(1,1)~="#" then assert(loadfile(base.."/"..name.."/"..line))() end
    end
    toc:close();addonLoads[name]=true
    loadMS=math.max(loadMS,(os.clock()-began)*1000)
    return true
end}
p.enabled=true
p.GetSnapshot=function() return snapshot,{state="current"} end
p.PeekSnapshot=p.GetSnapshot
p.Request=function() requested=true end
p.Journal={Dialog=function() end,TurnedIn=function() return false end}
p.Context={
    Position=function() return position end,
    Frame=function() return {time=elapsed,position=position,speed=7,width=view.projection.width,height=view.projection.height} end,
    Call=function(fn,...) if type(fn)=="function" then return pcall(fn,...) end return false end,
    History=function(ids)
        local result={};for _,id in ipairs(ids) do result[id]=(ctx.history or {})[id] end;return result
    end,
    Read=function()
        local value=p.Schema.Clone(ctx)
        value.position=position;value.observedAt=elapsed
        return value
    end,
}
CreateFrame=function() return {SetScript=function(_,_,fn) terrainCallback=fn end} end
p.Terrain.Start()
local questID=tonumber(arg[3]) or 315
local flavor=arg[5] or "Balanced"
p.Controller.Update(snapshot,{state="current"},"initial log")
assert(p.Controller.Toggle("pins",questID))
assert(p.Controller.Preference("flavor",flavor))
p.Controller.Update(snapshot,{state="current"},"adaptive preferences")
local function refresh()
    requested=false;snapshot.generation=(snapshot.generation or 0)+1
    p.Controller.Update(snapshot,{state="current"},"poll")
end
local maxFrames=tonumber(arg[4]) or 3500
local churn=tonumber(arg[8])
local firstRoute,routeFrames,peak,slow=nil,0,0,0
for frame=1,maxFrames do
    elapsed=frame*.02
    local began=os.clock()
    if churn and frame%churn==0 then p.Controller.Invalidate(true);requested=true end
    if requested or frame%10==0 then refresh() end
    p.Controller.Step();terrainCallback(nil,.02)
    if p.Terrain.PeekGuidance() then firstRoute=firstRoute or frame;routeFrames=routeFrames+1 end
    local cost=(os.clock()-began)*1000
    if cost>=15 and slow<8 then
        slow=slow+1
        print(string.format("SLOW frame %d %.0fms terrain=%s road=%s",frame,cost,p.Terrain.Status().status,tostring(p.RoadGuidance.Status().detail)))
    end
    peak=math.max(peak,cost)
end
local status=p.Terrain.Status()
print(string.format("ROADS COLD %s quest%d: first route frame %s; %d/%d route frames; road mode %s; status %s; max callback %.1fms; max addon load %.1fms",
    flavor,questID,tostring(firstRoute),routeFrames,maxFrames,tostring(p.RoadGuidance.Active()),status.status,peak,loadMS))
assert(p.RoadGuidance.Active(),"road mode did not engage")
assert(firstRoute and firstRoute<=600,"cold road route did not prepare within 12 simulated seconds: "..tostring(status.detail))
if churn then
    -- In game, quest events invalidate the planner several times a second; the
    -- route must still appear and stay up. Decision and walk run without churn.
    assert(routeFrames>=(maxFrames-firstRoute)*.9,"route kept disappearing under invalidation churn")
    print("ROADS_CHURN_OK")
    os.exit(0)
end
assert(p.Controller.Peek().adaptive,"ordinary controller did not use adaptive planner")
local decision=assert(p.PlanRuntime.Replay(),"current displayed decision has no evidence")
local packet=assert(p.Transfer.EncodePlan(decision))
local replay=p.PlanRuntime.RerunReplay(assert(p.Transfer.DecodePlan(packet)),{searchRevision=p.PlanSearch.REVISION,
    corpusRevision=p.SemanticData.Status().revision,identity=snapshot.identity})
assert(replay.status=="match","displayed decision replay differs: "..tostring(replay.reason or replay.phase))
local trace=p.PlanRuntime.ReplaySearch()
print("ROADS DECISION",replay.status,trace and #trace.candidateIDs or 0,"candidates")

-- Walk: step .15 yd toward the displayed aim until the route ends.
local function toNav(point)
    local pr=view.projection
    return pr.originY-point.x*pr.width,pr.originX-point.y*pr.height
end
local before=p.RoadGuidance.Stats()
local walked,arrived,ticks=0,false,0
for tick=1,60000 do
    ticks=tick
    elapsed=elapsed+.02
    if requested or tick%10==0 then refresh() end
    p.Controller.Step();terrainCallback(nil,.02)
    local route=p.Terrain.PeekGuidance()
    assert(route,"road route disappeared while walking: "..tostring(p.Terrain.Status().detail))
    if route.meters<=1.5 then arrived=true;break end
    local px,pz=toNav(position)
    local ax,az=toNav(route.next)
    local dx,dz=ax-px,az-pz
    local distance=math.sqrt(dx*dx+dz*dz)
    if distance<.01 then arrived=route.meters<=3;break end
    local step=math.min(.15,distance)
    px,pz=px+dx/distance*step,pz+dz/distance*step;walked=walked+step
    local pr=view.projection
    position={mapID=position.mapID,x=(pr.originY-px)/pr.width,y=(pr.originX-pz)/pr.height}
end
local after=p.RoadGuidance.Stats()
print(string.format("ROADS WALK %s quest%d: walked %.1f yd in %d ticks; arrived %s; road plans %d, route swaps %d, off-route replans %d",
    flavor,p.Controller.Peek().selected and p.Controller.Peek().selected.questID or 0,walked,ticks,tostring(arrived),
    after.plans-before.plans,after.published-before.published,after.replans-before.replans))
assert(arrived,"walk did not reach the end of the road route")
assert(after.replans==before.replans,"walking along the route triggered off-route replans")
print("ROADS_ADAPTIVE_OK")
