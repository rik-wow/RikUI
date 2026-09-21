-- Read-only replay: luajit tests/quest-marker-replay.lua <terrain addon> <packet> [mapX mapY]
-- External character inputs are never embedded in the repository.
local root=assert(arg[1]):gsub("\\","/"):gsub("/$","")
RikUI={}
RikUI["Secret"]={IsSecret=function() return false end}
for _,name in ipairs({"schema","transfer","nav-geometry","nav-search","navmesh"}) do
    dofile("src/modules/questplanner/quest-"..name..".lua")
end
local p,meta,shards=RikUI.QuestPlanner
local raw={}
p.Terrain={Install=function(m,s) meta,shards=m,s;return true end}
local namespace={}
local toc=assert(io.open(root.."/RikUIQuestTerrain.toc"))
for line in toc:lines() do
    line=line:gsub("\r",""):match("^%s*(.-)%s*$")
    if line~="" and line:sub(1,1)~="#" then
        assert(line:match("^[%w_%-]+%.lua$"))
        assert(loadfile(root.."/"..line))("RikUIQuestTerrain",namespace)
    end
end
toc:close()
for _,shard in ipairs(shards) do for _,poly in ipairs(shard.polygons) do raw[poly.id]=poly end end
local function checkCorridor(result)
    for index=1,#result.corridor-1 do
        local from,to=raw[result.corridor[index]],raw[result.corridor[index+1]]
        local connected=false
        for _,edge in ipairs(from.portals) do if edge.to==to.id then connected=true end end
        assert(connected,"invented corridor link")
        local midpoint=result.points[index*2+1]
        assert(p.NavGeometry.Contains(from.points,midpoint[1],midpoint[3]),"corridor left source polygon")
        assert(p.NavGeometry.Contains(to.points,midpoint[1],midpoint[3]),"corridor left target polygon")
    end
end
local loader=assert(p.NavMesh.Begin(meta,shards))
local mesh
repeat local value,reason,done=loader:Step(32);if done then mesh=assert(value,reason) end until mesh
local file=assert(io.open(assert(arg[2]),"rb"))
local wire=file:read(131073);file:close()
local snapshot=assert(p.Transfer.Decode(wire:gsub("[\r\n]+$","")))
assert(snapshot.identity.build==meta.identity.build and snapshot.identity.locale==meta.identity.locale
    and snapshot.identity.product==meta.identity.product,"identity mismatch")
local context=snapshot.context
-- Drive the production terrain coordinator with detached recorded observations.
local liveModel,livePosition,liveWorld
local onUpdate
CreateFrame=function() return {SetScript=function(_,_,callback) onUpdate=callback end} end
dofile("src/modules/questplanner/quest-terrain.lua")
p.enabled=true
p.GetSnapshot=function() return snapshot end
p.Controller={Get=function() return p.Schema.Clone(liveModel) end}
p.Context={Position=function() return p.Schema.Clone(livePosition) end,
    WorldPosition=function() return p.Schema.Clone(liveWorld) end,RunSpeed=function() return context.runSpeed end}
liveModel={status="observed"}
assert(p.Terrain.Install(meta,shards));p.Terrain.Start()
local loadFrames,loadPeak=0,0
while p.Terrain.Status().status=="loading" do
    local before=os.clock();onUpdate(nil,.2)
    loadPeak=math.max(loadPeak,(os.clock()-before)*1000);loadFrames=loadFrames+1
    assert(loadFrames<=math.ceil(meta.counts.polygons*2/32)+2,"loader exceeded work bound")
end
print(string.format("Production loader: %d headless frames, peak %.3f ms; native unverified",loadFrames,loadPeak))
assert(p.Terrain.Status().status=="ready","terrain did not load")
local function runtimeReplay(start,questID,destination,archived)
    livePosition=mesh:Unproject({start.x,0,start.z})
    liveWorld=archived and context.worldPosition or nil
    liveModel={status="observed",selected={questID=questID,destination=p.Schema.Clone(destination)}}
    p.Terrain.Invalidate()
    for _=1,20000 do
        onUpdate(nil,.2)
        local status=p.Terrain.Status().status
        if status~="updating" and status~="calculating" then
            local guidance=p.Terrain.Guidance()
            if guidance and guidance.approach then
                assert(guidance.approach.provenance.api==destination.api,"marker provenance lost")
                assert(guidance.revision==meta.revision,"mesh provenance lost")
                assert(guidance.approach.finalLegVerified==false,"gap promoted")
            end
            return status,guidance
        end
    end
    error("terrain coordinator exceeded replay bound")
end
local function startPoint()
    local world=context.worldPosition
    if world then
        local point={x=world.x,z=world.z}
        if world.verticalStatus=="observed-altitude" then point.height=world.height end
        return point
    end
    local pos=assert(context.position)
    return assert(mesh:Project(pos.mapID,pos.x,pos.y))
end
local maxSlice=0
local function replay(label,start,questID,destination)
    local runtimeStatus,runtimeRoute=runtimeReplay(start,questID,destination,label=="archived")
    local goal=assert(mesh:Project(destination.mapID,destination.x,destination.y))
    local located,issue=mesh:Locate(start)
    if not located then
        assert(runtimeStatus=="unknown-location" and not runtimeRoute,"runtime start admission differs")
        print(label,questID,"unknown-start",issue);return "unknown-start"
    end
    local job,reason=mesh:BeginMarkerApproach(start,goal,{maxWork=32768})
    if not job then print(label,questID,"unknown-target",reason);return "unknown-target" end
    local result
    repeat
        local before=os.clock();result=job:Step(64);maxSlice=math.max(maxSlice,(os.clock()-before)*1000)
    until result
    if result.status=="modeled" then
        assert(runtimeStatus==(result.approach and "modeled-approach" or "modeled") and runtimeRoute,
            "production terrain failed to publish the modeled route")
        local endpoint=result.points[#result.points]
        assert(mesh:Locate({x=endpoint[1],z=endpoint[3]}),"endpoint not uniquely grounded")
        assert(result.nativeVerified==false)
        checkCorridor(result)
        local displayed=runtimeRoute.points[#runtimeRoute.points]
        local projected=mesh:Project(displayed.mapID,displayed.x,displayed.y)
        assert(math.abs(projected.x-endpoint[1])<.00001 and math.abs(projected.z-endpoint[3])<.00001,
            "production guidance endpoint differs")
        if result.approach then
            assert(result.approach.gap<=1 and not result.approach.finalLegVerified)
            assert(math.sqrt((endpoint[1]-goal.x)^2+(endpoint[3]-goal.z)^2)>.0001,"gap drawn")
        end
        print(label,questID,result.status,string.format("%.3f yd; gap %.4f; %d polygons; work %d; endpoint checks %d",
            result.meters,result.approach and result.approach.gap or 0,#result.corridor,
            result.metrics.work,result.metrics.endpointChecks or 0))
    else
        assert(runtimeStatus==result.status and not runtimeRoute,"production failure differs")
        print(label,questID,result.status,result.detail)
    end
    return result.status
end
local destinations=0
for _,id in ipairs(snapshot.order) do
    local dest=context.destinations[id]
    if dest then destinations=destinations+1;replay("archived",startPoint(),id,dest)
    else print("archived",id,"no-observed-marker") end
end
assert(snapshot.observedCount>0,"empty snapshot")
print("Observed destinations replayed:",destinations)
if arg[3] then
    local x,y=assert(tonumber(arg[3])),assert(tonumber(arg[4]))
    local counts={}
    for dx=-1,1 do for dy=-1,1 do
        local point=assert(mesh:Project(meta.uiMapID,x+dx*.000499,y+dy*.000499))
        for _,id in ipairs(snapshot.order) do
            if (arg[8] and id==tonumber(arg[8]) or not arg[8] and snapshot.quests[id].objectivesComplete) and context.destinations[id] then
                local status=replay("rounded-screenshot-sample-"..dx.."-"..dy,point,id,context.destinations[id])
                counts[status]=(counts[status] or 0)+1
            end
        end
    end end
    for status,count in pairs(counts) do print("Screenshot samples only (not exact native position):",status,count) end
end
print(string.format("Maximum headless search slice %.3f ms; no native traversal tested",maxSlice))
-- Offline visualization/movement harness; never loaded by the addon.
return {mesh=mesh,raw=raw,meta=meta,snapshot=snapshot,replay=runtimeReplay,
    move=function(point)
        livePosition=mesh:Unproject(point);liveWorld=nil;onUpdate(nil,.2)
        return p.Terrain.Guidance(),p.Terrain.Status()
    end}
