-- Offline actual-data visual and movement replay. Same first four arguments as quest-marker-replay;
-- fifth is a NEW external output prefix; optional thirteenth selects a modeled floor.
-- No private character identity is exported. Floor choices never establish quest-target facts.
local output=assert(arg[5],"external output prefix required")
local stride=tonumber(arg[7]) or .35
local delta=tonumber(arg[9]) or .2
local deviation=tonumber(arg[11]) or 0
assert(deviation>=0 and deviation<=1,"deviation outside replay bounds")
assert(delta>=.01 and delta<=.25,"frame delta outside replay bounds")
assert(stride>=.05 and stride<=1.4,"stride outside modeled replay bounds")
local h=dofile(arg[14]=="regional" and "tests/quest-region-replay.lua" or "tests/quest-marker-replay.lua")
local p,mesh=RikUI.QuestPlanner,h.mesh
dofile("src/modules/questplanner/quest-guidance.lua")
local displayFrames,displayPeak=0,0
local hints={}
if arg[6]=="legacy" then
    -- Reproduce the old exit-midpoint steering for before/after comparisons.
    p.NavGeometry.CorridorAim=function(route,_,index)
        return route.points[index<#route.corridor and index*2+1 or #route.points],{},index
    end
end
local start=assert(mesh:Project(h.meta.uiMapID,assert(tonumber(arg[3])),assert(tonumber(arg[4]))))
if arg[12]=="archived" then
    local world=assert(h.snapshot.context.worldPosition,"archived world position missing")
    start={x=world.x,z=world.z}
    if world.verticalStatus=="observed-altitude" then start.height=world.height end
end
local questID=tonumber(arg[8]) or 99158
local destination=assert(h.snapshot.context.destinations[questID],"scenario marker missing")
local goal=assert(mesh:Project(destination.mapID,destination.x,destination.y))
local selectedFloor=tonumber(arg[13])
local automatic=p.Targets.Floor(p.Targets.Match(h.snapshot,questID,destination),h.meta.corpusRevision or h.meta.revision,mesh:MarkerFloors(goal),destination)
if selectedFloor then goal.height=assert(mesh:MarkerFloors(goal)[selectedFloor],"modeled floor missing").height
elseif automatic then goal.height=automatic.height end
local job=assert(mesh:BeginMarkerApproach(start,goal,{maxWork=math.max(32768,mesh:Metadata().counts.portals*2+1),markerRadius=8,reachableApproach=true,commonApproach=true,uncertainVicinity=true}))
local route
repeat route=job:Step(64) until route
assert(route.status=="modeled",route.detail)
local status,guidance=h.replay(start,questID,destination,arg[12]=="archived")
assert(guidance,status)
if automatic and not selectedFloor then
    assert(p.Terrain.Floors().selected==0 and guidance.destinationFloor.source=="quest-text-model-inference")
    assert(guidance.destinationFloor.height==goal.height and not guidance.destinationFloor.questTargetVerified)
end
if selectedFloor then
    assert(p.Terrain.SelectFloor(selectedFloor))
    for _=1,20000 do
        guidance,status=h.move(assert(mesh:Locate(start)).point,.2)
        if guidance then break end
        assert(status.status=="calculating" or status.status=="updating",status.detail)
    end
    assert(guidance and guidance.destinationFloor,"selected floor route unavailable")
    assert(guidance.destinationFloor.height==goal.height and not guidance.destinationFloor.questTargetVerified)
end
local samples,reversals,hidden,closeAims={},0,0,0
local sampleHeights={}
local corridorIndex={}
for index,id in ipairs(route.corridor) do corridorIndex[id]=index end
local progress=1
local pos=assert(mesh:Locate(start)).point
local lastDX,lastDZ
local done=false
local peak=0
local qualityModule=dofile("tests/quest-route-quality.lua")
local quality=qualityModule.New()
local callbackTimes,copyTimes={},{}
local initialStats=p.Terrain.Stats()
for tick=1,6000 do
    local before=os.clock()
    h.tick(pos,delta)
    local callbackMS=(os.clock()-before)*1000
    callbackTimes[#callbackTimes+1]=callbackMS;peak=math.max(peak,callbackMS)
    local copyStart=os.clock()
    local g,state=p.Terrain.Guidance(),p.Terrain.Status()
    copyTimes[#copyTimes+1]=(os.clock()-copyStart)*1000
    if not g then
        local old=samples[#samples] or {}
        error(string.format("movement lost guidance: %s / %s at %d pos %.9f,%.9f,%.9f prior %.9f,%.9f",
            state.status,state.detail or "",tick,pos[1],pos[2],pos[3],old[1] or 0,old[2] or 0))
    end
    local displayStart=os.clock()
    local position=assert(mesh:Unproject(pos))
    local hint=assert(p.Guidance.Instruction(g,position,0,h.meta.projection.width,h.meta.projection.height))
    hints[hint.text]=true
    local world,mini={},{}
    for _,point in ipairs(g.points) do
        world[#world+1]={point.x*1000,point.y*600}
        mini[#mini+1]=p.NavGeometry.MinimapPoint(point,position,h.meta.projection.width,h.meta.projection.height,200,200,100,0)
    end
    local worldDots=p.NavGeometry.ScreenAnts(world,1000,600,(tick*delta*20)%14,256,false)
    local miniDots=p.NavGeometry.ScreenAnts(mini,200,200,(tick*delta*20)%14,96,true)
    assert(#worldDots<=256 and #miniDots<=96,"display pool overflow")
    displayFrames=displayFrames+1;displayPeak=math.max(displayPeak,(os.clock()-displayStart)*1000)
    local endpoint=assert(mesh:Project(g.points[#g.points].mapID,g.points[#g.points].x,g.points[#g.points].y))
    if g.meters<.5 and math.sqrt((pos[1]-endpoint.x)^2+(pos[3]-endpoint.z)^2)<.5 then
        if goal.height then assert(math.abs(pos[2]-goal.height)<1,"arrival on wrong floor") end
        quality:Observe(pos,nil,tick*delta)
        done=true;break
    end
    local target=assert(mesh:Project(g.next.mapID,g.next.x,g.next.y))
    quality:Observe(pos,target,tick*delta)
    local dx,dz=target.x-pos[1],target.z-pos[3]
    local distance=math.sqrt(dx*dx+dz*dz)
    if math.abs(dx)+math.abs(dz)<1 then hidden=hidden+1 end
    if distance<3 and math.sqrt((pos[1]-endpoint.x)^2+(pos[3]-endpoint.z)^2)>6 then closeAims=closeAims+1 end
    assert(distance>.000001,"stuck on exact waypoint")
    dx,dz=dx/distance,dz/distance
    if lastDX and dx*lastDX+dz*lastDZ<0 then reversals=reversals+1 end
    lastDX,lastDZ=dx,dz
    samples[#samples+1]={pos[1],pos[3],target.x,target.z}
    sampleHeights[#sampleHeights+1]=pos[2]
    -- Fixed steps deliberately cross waypoints, as a moving player does.
    local nextPoint={x=pos[1]+dx*stride,z=pos[3]+dz*stride}
    local located,reason=mesh:LocateContinued(nextPoint,{id=route.corridor[progress],point=pos})
    assert(located,"steering left known floor: "..tostring(reason))
    local index=assert(corridorIndex[located.id],"movement left the selected corridor")
    assert(index>=progress,"movement reversed polygon progress")
    progress=index;pos=located.point
    -- Model a small voluntary sideways move inside the same convex floor polygon.
    -- Reject the perturbation at walls, floor ambiguity and polygon boundaries.
    if deviation>0 then
        local offset=deviation*math.sin(tick*.37)
        local sideways=mesh:Locate({x=pos[1]-dz*offset,z=pos[3]+dx*offset})
        if sideways and sideways.id==located.id then pos=sideways.point end
    end
end
local uniqueHints=0
for _ in pairs(hints) do uniqueHints=uniqueHints+1 end
assert(uniqueHints>1,"actual movement did not change instructions")
print(string.format("Route display: %d frames, %d distinct instructions, %.3f ms peak headless display CPU",displayFrames,uniqueHints,displayPeak))
local function encode(value)
    if type(value)=="number" then assert(value==value and math.abs(value)<math.huge);return string.format("%.12g",value) end
    if type(value)=="boolean" then return tostring(value) end
    if type(value)=="string" then return '"'..value:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n")..'"' end
    local result={}
    if #value>0 then
        for _,item in ipairs(value) do result[#result+1]=encode(item) end
        return "["..table.concat(result,",").."]"
    end
    local keys={};for key in pairs(value) do keys[#keys+1]=key end;table.sort(keys)
    for _,key in ipairs(keys) do result[#result+1]=encode(key)..":"..encode(value[key]) end
    return "{"..table.concat(result,",").."}"
end
local finalStats=p.Terrain.Stats()
local endpoint=route.walkPoints[#route.walkPoints]
local metrics={evidence="automated-replay",durationSeconds=#samples*delta,walkingYards=quality.spatial,
    horizontalYards=quality.distance,funnelYards=route.meters,graphYards=route.graphMeters,
    excessOverSelectedFunnelPercent=(quality.spatial/route.meters-1)*100,
    aim=quality.aim,movement=quality.movement,
    plansDuringMovement=finalStats.plans-initialStats.plans,routeChanges=finalStats.published-initialStats.published,
    plansPerMinute=(finalStats.plans-initialStats.plans)*60/math.max(delta,#samples*delta),
    finalPoint=pos,endpoint=endpoint,endpointError= p.NavGeometry.Distance(pos,endpoint),
    callbackMS=qualityModule.Timing(callbackTimes),publicCopyMS=qualityModule.Timing(copyTimes)}
metrics.stationaryAllocation=qualityModule.Allocations(function() h.tick(pos,delta) end,100)
local movingA=mesh:LocateContinued({x=pos[1]+.01,z=pos[3]}, {id=route.corridor[progress],point=pos})
local movingB=mesh:LocateContinued({x=pos[1]-.01,z=pos[3]}, {id=route.corridor[progress],point=pos})
if movingA and movingB and movingA.id==movingB.id then
    metrics.localMovementAllocation=qualityModule.Allocations(function(at) h.tick(at%2==0 and movingA.point or movingB.point,delta) end,100)
end
print("QUALITY "..encode(metrics))
local polygons={}
local ids={}
for id in pairs(h.raw) do ids[#ids+1]=id end
table.sort(ids)
for _,id in ipairs(ids) do
    local poly=h.raw[id]
    polygons[#polygons+1]={id,poly.points}
end
assert(h.meta.source.sha256:match("^[a-fA-F0-9]+$"),"invalid source hash")
local data="{\"meshSourceSha256\":\""..h.meta.source.sha256.."\",\"startMap\":"..encode({tonumber(arg[3]),tonumber(arg[4])})
    ..",\"startSource\":\""..(arg[12]=="archived" and "archived world position" or "supplied map position").."\""
    ..",\"selectedModelFloor\":"..(selectedFloor or "null")..",\"automaticModelFloor\":"..(not selectedFloor and automatic and automatic.index or "null")
    ..",\"targetModelHeight\":"..(goal.height or "null")
    ..",\"stride\":"..stride..",\"polygons\":"..encode(polygons)..",\"corridor\":"..encode(route.corridor)
    ..",\"delta\":"..delta..",\"deviation\":"..deviation..",\"quality\":"..encode(metrics)
    ..",\"funnel\":"..encode(route.walkPoints)..",\"coarse\":"..encode(route.points)..",\"samples\":"..encode(samples)..",\"sampleHeights\":"..encode(sampleHeights)
    ..",\"marker\":"..encode({goal.x,goal.z})..",\"complete\":"..tostring(done)
    ..",\"reversals\":"..reversals..",\"hidden\":"..hidden.."}"
local function write(suffix,value)
    local existing=io.open(output..suffix,"rb")
    if existing then existing:close();error("output already exists") end
    local file=assert(io.open(output..suffix,"wb"));assert(file:write(value));file:close()
end
write(".json",data)
local html=[=[<!doctype html><meta charset="utf-8"><title>RikUI deployed navmesh replay</title>
<style>body{margin:0;background:#111925;color:#edf3fc;font:16px system-ui}header{padding:16px 24px}h1{font-size:22px;margin:0 0 8px}p{margin:6px 0;color:#c3cddd}button,input{vertical-align:middle}svg{width:100%;height:75vh;background:#172332}label{margin-right:20px}#info{color:#70dfcd}.mesh{fill:#284957;stroke:#54717d;stroke-width:.12}.corridor{fill:#356a6b}.coarse{stroke:#ffb35c;stroke-width:.65;fill:none}.motion{stroke:#63ffba;stroke-width:.7;fill:none}</style>
<header><h1>Actual navmesh · archived quest marker</h1><p>Actual companion polygons and production Lua steering. Start: <span id="startSource"></span> <span id="startMap"></span>. Marker: archived build 69913 observation.</p>
<p>Model simulation only: collision, native movement and interaction are unverified. Reaching the modeled endpoint does not establish native arrival or quest completion.</p>
<label><input id="coarse" type="checkbox" checked>Orange: center graph</label><label><input id="motion" type="checkbox" checked>Green: simulated movement</label>
<button id="play">Play</button> <input id="step" type="range" min="0" value="0" style="width:32%"> <button id="fit">Fit route</button><p id="info"></p></header>
<svg id="view" xmlns="http://www.w3.org/2000/svg"><g id="mesh"></g><polyline id="route" class="coarse"/><polyline id="trace" class="motion"/><circle id="marker" fill="#ff78cb" r="1.4"/><line id="arrow" stroke="#fff" stroke-width="1.2"/><circle id="player" fill="#fff" r="1"/></svg>
<script>
const d=DATA,ns="http://www.w3.org/2000/svg",el=id=>document.getElementById(id),xy=p=>[-p[0],-p[p.length===3?2:1]],pair=p=>xy(p).join(",");
el("startSource").textContent=d.startSource;
el("startMap").textContent=d.startMap.map(v=>(v*100).toFixed(1)).join(", ");
const corridor=new Set(d.corridor);for(const [id,points] of d.polygons){const n=document.createElementNS(ns,"polygon");n.setAttribute("points",points.map(pair).join(" "));n.setAttribute("class","mesh"+(corridor.has(id)?" corridor":""));const title=document.createElementNS(ns,"title");title.textContent="Polygon "+id+" · height "+points[0][1].toFixed(2);n.appendChild(title);el("mesh").appendChild(n)}
el("route").setAttribute("points",d.coarse.map(pair).join(" "));el("trace").setAttribute("points",d.samples.map(p=>pair(p.slice(0,2))).join(" "));
const m=xy(d.marker);el("marker").setAttribute("cx",m[0]);el("marker").setAttribute("cy",m[1]);
let box;function fit(){const pts=d.coarse.map(xy),xs=pts.map(p=>p[0]),ys=pts.map(p=>p[1]);box=[Math.min(...xs)-15,Math.min(...ys)-15,Math.max(...xs)-Math.min(...xs)+30,Math.max(...ys)-Math.min(...ys)+30];renderBox()}
function renderBox(){el("view").setAttribute("viewBox",box.join(" "))}
function frame(){const i=+el("step").value,s=d.samples[i],a=xy(s.slice(0,2)),b=xy(s.slice(2));el("player").setAttribute("cx",a[0]);el("player").setAttribute("cy",a[1]);["x1","y1","x2","y2"].forEach((k,j)=>el("arrow").setAttribute(k,[...a,...b][j]));el("info").textContent="Step "+i+" / "+(d.samples.length-1)+" · "+d.reversals+" reversals (>90°) · "+d.hidden+" near-waypoint arrow hides · "+(d.complete?"reached modeled approach":"did not reach approach")+" · drag to pan, wheel to zoom"}
el("step").max=d.samples.length-1;el("step").oninput=frame;el("fit").onclick=fit;
for(const [id,target] of [["coarse","route"],["motion","trace"]])el(id).onchange=()=>el(target).style.display=el(id).checked?"":"none";
let playing=false;el("play").onclick=()=>{playing=!playing;el("play").textContent=playing?"Pause":"Play"};setInterval(()=>{if(playing){el("step").value=(+el("step").value+4)%d.samples.length;frame()}},80);
el("view").onwheel=e=>{e.preventDefault();const f=e.deltaY>0?1.15:1/1.15;box=[box[0]+box[2]*(1-f)/2,box[1]+box[3]*(1-f)/2,box[2]*f,box[3]*f];renderBox()};
let drag;el("view").onpointerdown=e=>{drag=[e.clientX,e.clientY,...box];el("view").setPointerCapture(e.pointerId)};el("view").onpointerup=()=>drag=null;el("view").onpointermove=e=>{if(drag){const scale=Math.max(box[2]/el("view").clientWidth,box[3]/el("view").clientHeight);box[0]=drag[2]-(e.clientX-drag[0])*scale;box[1]=drag[3]-(e.clientY-drag[1])*scale;renderBox()}};
fit();frame();
</script>]=]
write(".html",(html:gsub("DATA",function() return data end,1)))
print(string.format("MOVEMENT complete=%s steps=%d reversals=%d hidden=%d max-refresh=%.3fms output=%s",
    tostring(done),#samples,reversals,hidden,peak,output))
print("CLOSE_AIMS (<3yd outside final6yd)",closeAims)
if arg[6]=="require-complete" then assert(done and reversals==0,"movement regression") end
