-- Automatic adaptive planning with installed corpus/terrain and archived native observations.
-- Historical observations remain replay inputs; this is not a native gameplay acceptance receipt.
-- Usage: luajit tests/quest-adaptive-installed.lua <AddOns root> <RIKQ packet> [questID] [frames] [flavor]
local root=assert(arg[1]):gsub("\\","/"):gsub("/$","")
RikUI={};RikUI["Secret"]={IsSecret=function() return false end}
local modules={"schema","objectives","transfer","nav-geometry","nav-funnel","nav-follow","nav-search",
    "region-codec","regions","navmesh","steps","step-bindings","guide-data","observed-steps","hunts","targets",
    "optimizer","area-optimizer","semantic-data","semantic-guidance","recommendations","guidance",
    "preferences","plan-state","plan-graph","plan-transitions","plan-learning","plan-costs","plan-search",
    "bag-scan","plan-services","plan-context","plan-runtime","controller","terrain"}
for _,name in ipairs(modules) do dofile("src/modules/questplanner/quest-"..name..".lua") end
local p=RikUI.QuestPlanner
local file=assert(io.open(assert(arg[2]),"rb"));local wire=file:read(131073);file:close()
local snapshot=assert(p.Transfer.Decode(wire:gsub("[\r\n]+$","")))
snapshot.origin=nil
local ctx=snapshot.context
ctx.origin="live"
local position={mapID=1426,x=.429,y=.472}
local elapsed,requested=0,false
local catalog,terrainCallback,mesh
local beginMesh=p.NavMesh.Begin
p.NavMesh.Begin=function(...)
    local loader,why=beginMesh(...)
    if not loader then return nil,why end
    local step=loader.Step
    loader.Step=function(self,...)
        local value,problem,done=step(self,...)
        if value then mesh=value end
        return value,problem,done
    end
    return loader
end
local install=p.Regions.Install
p.Regions.Install=function(raw) catalog=raw;return assert(install(raw)) end
assert(loadfile(root.."/RikUIQuestTerrain/catalog.lua"))()
GetTime=function() return elapsed end
debugprofilestop=function() return os.clock()*1000 end
InCombatLockdown=function() return false end
local addonLoads={}
C_AddOns={LoadAddOn=function(name)
    if addonLoads[name] then return true end
    local toc=assert(io.open(root.."/"..name.."/"..name..".toc"))
    for line in toc:lines() do
        line=line:gsub("\r",""):match("^%s*(.-)%s*$")
        if line~="" and line:sub(1,1)~="#" then
            assert(line:match("^[%w_%-]+%.lua$"))
            assert(loadfile(root.."/"..name.."/"..line))()
        end
    end
    toc:close();addonLoads[name]=true;return true
end}
p.enabled=true
p.GetSnapshot=function() return snapshot,{state="current"} end
p.PeekSnapshot=p.GetSnapshot
p.Request=function() requested=true end
p.Journal={Dialog=function() end,TurnedIn=function() return false end}
p.Context={
    Position=function() return position end,
    Frame=function() return {time=elapsed,position=position,speed=7,
        width=catalog.meta.projection.width,height=catalog.meta.projection.height} end,
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
p.Controller.Update(snapshot,{state="current"},"initial log")
assert(p.Controller.Toggle("pins",questID))
assert(p.Controller.Preference("flavor",arg[5] or "Balanced"))
p.Controller.Update(snapshot,{state="current"},"adaptive preferences")
local maxFrames=tonumber(arg[4]) or 3500
local firstRoute,changed,previous,routeFrames,loadFrames= nil,0,nil,0,0
local peak,total=0,0
local function refresh()
    requested=false;snapshot.generation=(snapshot.generation or 0)+1
    p.Controller.Update(snapshot,{state="current"},"poll")
end
for frame=1,maxFrames do
    elapsed=frame*.02
    local begin=os.clock()
    if requested or frame%10==0 then refresh() end
    p.Controller.Step();terrainCallback(nil,.02)
    local row=p.Controller.Peek().selected
    local point=row and row.destination
    local key=point and table.concat({point.mapID,point.x,point.y,point.scope or ""},":")
    if previous and key and previous~=key then changed=changed+1 end
    previous=key or previous
    local state=p.Terrain.Status().status
    if state=="loading" then loadFrames=loadFrames+1 end
    if p.Terrain.PeekGuidance() then
        firstRoute=firstRoute or frame;routeFrames=routeFrames+1
    end
    local cost=(os.clock()-begin)*1000
    total=total+cost;peak=math.max(peak,cost)
    if frame%500==0 then
        print("COLD",frame,state,"windows",p.Regions.Stats().windows,"changes",changed,"routes",routeFrames)
    end
end
local stats=p.Terrain.Stats()
print(string.format("COLD quest%d: first route frame %s; %d/%d route frames; %d loading frames; %d windows; %d destination changes; %d plans; CPU total/max %.3f/%.3fms",
    questID,tostring(firstRoute),routeFrames,maxFrames,loadFrames,p.Regions.Stats().windows,changed,stats.plans,total,peak))
if not p.Terrain.PeekGuidance() then
    local row=p.Controller.Peek().selected or {};local dest=row.destination or {}
    print("COLD FAILURE",p.Terrain.Status().detail,row.questID,row.actionID,dest.x,dest.y,dest.scope,row.hunt and row.hunt.objectiveID,row.detail)
end
assert(firstRoute and firstRoute<=600,"cold route did not prepare within 12 simulated seconds")
assert(p.Regions.Stats().windows<=4,"terrain window repeatedly rebuilt while stationary")
assert(changed<=4,"stationary destination repeatedly changed")
assert(p.Terrain.PeekGuidance(),"stationary route disappeared")
assert(p.Controller.Peek().adaptive,"ordinary controller did not use adaptive planner")
local planStats=p.Controller.Stats()
local trace=p.PlanRuntime.Replay()
assert(trace and #trace.candidateIDs>0,"installed corpus did not enter future graph")
assert(p.Transfer.EncodePlan(trace),"installed plan trace cannot be exported")
print("ADAPTIVE",arg[5] or "Balanced","candidates",#trace.candidateIDs,"actions",#trace.actions,
    "replans",planStats.replans,"callback/load max",planStats.maxCallbackMS,planStats.maxLoadMS,
    "memoryKiB",collectgarbage("count"),"missing resource/history facts stay unknown")
collectgarbage("collect");local coldHeap=collectgarbage("count")

-- Follow the selected route with repeated observations and partial live count updates.
local quality=dofile("tests/quest-route-quality.lua")
local movement=quality.New()
local start=assert(mesh:Project(position.mapID,position.x,position.y))
local located=assert(mesh:Locate(start))
local beforeWalk=p.Terrain.Stats()
local beforeRow=p.Controller.Peek().selected
local walkQuestID=beforeRow.questID
print("BEFORE WALK",p.Controller.Peek().actionID,beforeRow.questID,beforeRow.destination.x,beforeRow.destination.y,beforeRow.destination.scope,beforeRow.semantic and beforeRow.semantic.objectiveKey)
local callbacks,arrived={},false
for tick=1,16000 do
    elapsed=elapsed+.02
    if tick%500==0 then
        for _,objective in ipairs(snapshot.quests[walkQuestID].objectives or {}) do
            if objective.type=="item" and objective.numRequired and objective.numFulfilled<objective.numRequired-1 then
                objective.numFulfilled=objective.numFulfilled+1
                objective.text=objective.text:gsub("%d+/%d+",objective.numFulfilled.."/"..objective.numRequired)
                requested=true;break
            end
        end
    end
    local began=os.clock()
    if requested or tick%10==0 then refresh() end
    p.Controller.Step();terrainCallback(nil,.02)
    local route=p.Terrain.PeekGuidance()
    if not route then
        local row=p.Controller.Peek().selected or {};local dest=row.destination or {};local sem=row.semantic or {}
        print("WALK FAILURE",tick,p.Controller.Peek().actionID,row.questID,dest.mapID,dest.x,dest.y,dest.scope,sem.objectiveKey,sem.targetID,sem.method,
            "plans",p.Terrain.Stats().plans,"strategic",p.Controller.Stats().replans,"invalidations",p.Controller.Stats().cancelled)
    end
    assert(route,"route disappeared while walking: "..p.Terrain.Status().detail)
    callbacks[#callbacks+1]=(os.clock()-began)*1000
    if route.searching or route.meters<=1 then arrived=true;break end
    local aim=assert(mesh:Project(route.next.mapID,route.next.x,route.next.y))
    movement:Observe(located.point,aim,elapsed)
    local dx,dz=aim.x-located.point[1],aim.z-located.point[3]
    local distance=math.sqrt(dx*dx+dz*dz)
    assert(distance>0,"stationary aim")
    local step=math.min(.15,distance)
    located=assert(mesh:LocateContinued({x=located.point[1]+dx/distance*step,z=located.point[3]+dz/distance*step},located))
    position=mesh:Unproject(located.point)
end
assert(arrived,"walk exceeded bound")
local afterWalk=p.Terrain.Stats()
local timing=quality.Timing(callbacks)
print(string.format("LIVE WALK quest%d: %.3f yd; %d oscillations; plans/route changes %d/%d; callback p99/max %.3f/%.3fms",
    walkQuestID,movement.spatial,movement.aim.oscillations,afterWalk.plans-beforeWalk.plans,
    afterWalk.published-beforeWalk.published,timing.p99,timing.maximum))
assert(afterWalk.plans==beforeWalk.plans,"partial progress or movement restarted the path")
assert(afterWalk.published==beforeWalk.published,"partial progress replaced the walking route")
assert(not p.Controller.Peek().selected.step or p.Controller.Peek().selected.step.state~="completed","arrival completed the quest")
collectgarbage("collect");local finalHeap=collectgarbage("count")
print("REPLAY HEAP KiB cold/walk",coldHeap,finalHeap,"requested pin/actual walked",questID,walkQuestID)
assert(finalHeap<coldHeap*1.5+20000,"unbounded retained planner growth while walking")


