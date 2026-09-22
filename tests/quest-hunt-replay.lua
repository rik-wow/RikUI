-- Installed Forever terrain + actual quest packet; arguments match regional replay.
local h=dofile("tests/quest-region-replay.lua")
local p,mesh=RikUI.QuestPlanner,h.mesh
assert(h.selected.questID==313 and h.selected.hunt,"requires actual Wendigo quest")
local start=assert(mesh:Project(h.meta.uiMapID,tonumber(arg[3]),tonumber(arg[4])))
local goal=assert(mesh:Project(h.selected.destination.mapID,h.selected.destination.x,h.selected.destination.y))
local job=assert(mesh:BeginMarkerApproach(start,goal,{maxWork=math.max(32768,h.meta.counts.portals*2+1),
    markerRadius=8,reachableApproach=true,commonApproach=true,uncertainVicinity=true}))
local reference
repeat reference=job:Step(64,true) until reference
assert(reference.status=="modeled",reference.detail)
local _,g=h.replay(start,313,h.selected.destination)
assert(g.hunt and not g.searching,"expected a hunt approach")
local length=g.meters
assert(length<reference.meters-119 and length>reference.meters-125,"search approach did not remove marker tail")
local Q=dofile("tests/quest-route-quality.lua")
local quality,callbacks=Q.New(),{}
local stats=p.Terrain.Stats()
local located=assert(mesh:Locate(start))
local done=false
for tick=1,6000 do
    local began=os.clock()
    g=h.move(located.point,.02)
    callbacks[#callbacks+1]=(os.clock()-began)*1000
    assert(g,"lost hunt route")
    if g.searching then
        quality:Observe(located.point,nil,tick*.02);done=true;break
    end
    local aim=assert(mesh:Project(g.next.mapID,g.next.x,g.next.y))
    quality:Observe(located.point,aim,tick*.02)
    local dx,dz=aim.x-located.point[1],aim.z-located.point[3]
    local d=math.sqrt(dx*dx+dz*dz)
    assert(d>0,"stuck hunt aim")
    located=assert(mesh:LocateContinued({x=located.point[1]+dx/d*.15,z=located.point[3]+dz/d*.15},located),"left connected floor")
end
assert(done,"never entered hunting mode")
assert(p.Guidance.Instruction(g,nil,nil,nil,nil).ending,"hunt must stop directional arrow")
assert(h.selected.step.state=="active" and h.selected.step.active.objectiveID=="q313.wendigo-manes","proximity completed quest")
local after=p.Terrain.Stats()
assert(after.plans==stats.plans and after.published==stats.published,"hunting approach replanned while walking")
local allocations=Q.Allocations(function() h.tick(located.point,.02) end,100)
local timing=Q.Timing(callbacks)
print(string.format("INSTALLED HUNT: original %.3f yd; search approach %.3f yd; walked %.3f yd; tail avoided %.3f yd; heading oscillations %d; route changes %d; plans %d; callback p99/max %.3f/%.3f ms; stationary %.1f bytes/frame; active quest313 3/8",
    reference.meters,length,quality.spatial,reference.meters-length,quality.aim.oscillations,
    after.published-stats.published,after.plans-stats.plans,timing.p99,timing.maximum,allocations.bytesPerCallback))

-- The production coordinator must retain hunt semantics on precise modeled progress anchors.
local function progressFrame()
    return {position=mesh:Unproject(located.point),world={mapID=h.meta.worldMapID,x=located.point[1],z=located.point[3]}}
end
local beforeWindows=p.Regions.Stats().windows
local anchor=assert(p.Terrain.ProgressAnchor(progressFrame()),"expected a uniquely grounded productive anchor")
h.selected.destination=anchor;h.selected.hunt.radius=25;h.selected.hunt.source="observed-progress"
local function refreshRoute()
    p.Terrain.Invalidate()
    for _=1,20000 do
        local value,state=h.move(located.point,.02)
        if value then return value end
        assert(state.status=="updating" or state.status=="calculating" or state.status=="loading",state.detail)
    end
    error("route refresh exceeded bound")
end
local learned=refreshRoute()
assert(learned.searching and learned.hunt.source=="observed-progress","learned floor anchor lost area guidance")
assert(p.Regions.Stats().windows==beforeWindows,"nearby productive anchor unnecessarily reloaded terrain")
local quest=h.snapshot.quests[313]
quest.objectives[1].numFulfilled,quest.objectives[1].text,quest.objectives[1].finished=8,"8/8 Wendigo Mane",true
quest.objectivesComplete=true
local turnin
for _,row in ipairs(p.Guidance.Observed(h.snapshot,h.snapshot.context,{pins={},skips={},avoids={}})) do
    if row.questID==313 then turnin=row end
end
assert(turnin and turnin.kind=="turnin" and not turnin.hunt and turnin.step.state~="completed")
for key in pairs(h.selected) do h.selected[key]=nil end
for key,value in pairs(turnin) do h.selected[key]=value end
local nextRoute=refreshRoute()
assert(not nextRoute.hunt and not nextRoute.searching,"turn-in retained hunting destination semantics")
print("INSTALLED STAGES: learned modeled floor retains 25-yard hunt; 8/8 restores turn-in navigation; proximity completes neither quest nor turn-in")
