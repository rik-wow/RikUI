-- Production lazy-addon/window replay against an external compiled or installed regional set.
-- Args match quest-nav-visual; requires arg8 questID. No character observations are exported.
local root=assert(arg[1]):gsub("\\","/"):gsub("/$","")
local questID=assert(tonumber(arg[8]),"regional replay requires questID in arg8")
RikUI={};RikUI["Secret"]={IsSecret=function()return false end}
for _,name in ipairs({"schema","objectives","transfer","nav-geometry","nav-funnel","nav-follow","nav-search",
    "region-codec","regions","navmesh","steps","step-bindings","guide-data","observed-steps","hunts","targets","guidance","terrain"}) do
    dofile("src/modules/questplanner/quest-"..name..".lua")
end
local p=RikUI.QuestPlanner
local file=assert(io.open(assert(arg[2]),"rb"));local wire=file:read(131073);file:close()
local snapshot=assert(p.Transfer.Decode(wire:gsub("[\r\n]+$","")))
local context=snapshot.context
local target=assert(context.destinations[questID],"quest has no observed marker")
local selected
for _,row in ipairs(p.Guidance.Observed(snapshot,context,{pins={},skips={},avoids={}}))do if row.questID==questID then selected=row end end
assert(selected)
local catalog
local install=p.Regions.Install
p.Regions.Install=function(raw)catalog=raw;return assert(install(raw))end
assert(loadfile(root.."/RikUIQuestTerrain/catalog.lua"))()
local clock=0;local position=context.position;local world
if arg[3] then position={mapID=catalog.meta.uiMapID,x=assert(tonumber(arg[3])),y=assert(tonumber(arg[4]))}end
if arg[12]=="archived"then
    world=context.worldPosition
    if world then local pr=catalog.meta.projection
        position={mapID=catalog.meta.uiMapID,x=(pr.originY-world.x)/pr.width,y=(pr.originX-world.z)/pr.height}
    end
end
local liveModel={status="observed",selected=selected}
p.enabled=true;p.GetSnapshot=function()return snapshot end
p.Controller={Get=function()return p.Schema.Clone(liveModel)end,Peek=function()return liveModel end}
p.Context={Position=function()return position end,Frame=function()return {time=clock,position=position,world=world,speed=context.runSpeed,
    width=catalog.meta.projection.width,height=catalog.meta.projection.height,facing=0}end}
GetTime=function()return clock end
debugprofilestop=function()return os.clock()*1000 end
InCombatLockdown=function()return false end
local loads,loadCPU,loadPeak=0,0,0
C_AddOns={LoadAddOn=function(name)
    assert(name:match("^RikUIQuestTerrain_R%d%d%d$"),"unexpected addon")
    local before=os.clock()
    local toc=assert(io.open(root.."/"..name.."/"..name..".toc"))
    for line in toc:lines()do
        line=line:gsub("\r",""):match("^%s*(.-)%s*$")
        if line~=""and line:sub(1,1)~="#"then assert(line:match("^page%-%d+%.lua$"));assert(loadfile(root.."/"..name.."/"..line))()end
    end
    toc:close();local cost=(os.clock()-before)*1000
    loads=loads+1;loadCPU=loadCPU+cost;loadPeak=math.max(loadPeak,cost)
    return true
end}
local callback
CreateFrame=function()return {SetScript=function(_,_,fn)callback=fn end}end
local meta,raw,rows
local original=p.Terrain.Install
p.Terrain.Install=function(m,stream)
    meta,raw,rows=m,{},{}
    return original(m,function()
        local shard=stream()
        if shard then for _,poly in ipairs(shard.polygons)do raw[poly.id]=poly;rows[#rows+1]=poly end end
        return shard
    end)
end
p.Terrain.Start()
local frames,cpu,peak=0,0,0
for i=1,20000 do
    clock=clock+.02;local before=os.clock();callback(nil,.02);local cost=(os.clock()-before)*1000
    frames=frames+1;cpu=cpu+cost;peak=math.max(peak,cost)
    if p.Terrain.Guidance()then break end
    local status=p.Terrain.Status()
    assert(status.status~="invalid",status.detail)
    if status.status=="coverage-frontier"or status.status=="unknown-location"then
        error(status.status..": "..tostring(status.detail))
    end
end
assert(p.Terrain.Guidance(),"no regional guidance")
local at=0
local loader=assert(p.NavMesh.Begin(meta,function()at=at+1;if rows[at]then return {identity=meta.identity,polygons={rows[at]}}end end))
local mesh
repeat local value,why,done=loader:Step(64);if done then mesh=assert(value,why)end until mesh
print(string.format("Regional production preparation: %d frames %.3f ms CPU max %.3f; %d addons %.3f ms load CPU max %.3f; %d polygons %d portals",
    frames,cpu,peak,loads,loadCPU,loadPeak,meta.counts.polygons,meta.counts.portals))
local function tick(point,delta)
    position=mesh:Unproject(point);world=nil;clock=clock+(delta or .2);callback(nil,delta or .2)
end
local function replay(start,id,destination,archived)
    assert(id==questID,"one regional case per process")
    position=mesh:Unproject({start.x,0,start.z});world=archived and context.worldPosition or nil
    p.Terrain.Invalidate()
    for i=1,20000 do
        clock=clock+.02;callback(nil,i==1 and .6 or .02)
        local status=p.Terrain.Status()
        if p.Terrain.Guidance()then return status.status,p.Terrain.Guidance()end
        assert(status.status=="calculating"or status.status=="updating"or status.status=="loading",status.detail)
    end
    error("regional route replay exceeded bound")
end
return {mesh=mesh,meta=meta,raw=raw,snapshot=snapshot,selected=selected,replay=replay,tick=tick,
    move=function(point,delta)tick(point,delta);return p.Terrain.Guidance(),p.Terrain.Status()end}
