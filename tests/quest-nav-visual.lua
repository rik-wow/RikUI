-- Offline actual-data visual and movement replay. Same first four arguments as quest-marker-replay;
-- fifth is a NEW external output prefix. No private character identity is exported.
local output=assert(arg[5],"external output prefix required")
local stride=tonumber(arg[7]) or .35
local delta=tonumber(arg[9]) or .2
assert(delta>=.01 and delta<=.25,"frame delta outside replay bounds")
assert(stride>=.05 and stride<=1.4,"stride outside modeled replay bounds")
local h=dofile("tests/quest-marker-replay.lua")
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
local questID=tonumber(arg[8]) or 99158
local destination=assert(h.snapshot.context.destinations[questID],"scenario marker missing")
local goal=assert(mesh:Project(destination.mapID,destination.x,destination.y))
local job=assert(mesh:BeginMarkerApproach(start,goal,{maxWork=32768}))
local route
repeat route=job:Step(64) until route
assert(route.status=="modeled",route.detail)
local status,guidance=h.replay(start,questID,destination,false)
assert(guidance,status)
local samples,reversals,hidden,closeAims={},0,0,0
local corridorIndex={}
for index,id in ipairs(route.corridor) do corridorIndex[id]=index end
local progress=1
local pos=assert(mesh:Locate(start)).point
local lastDX,lastDZ
local done=false
local peak=0
for tick=1,6000 do
    local before=os.clock()
    local g,state=h.move(pos,delta)
    peak=math.max(peak,(os.clock()-before)*1000)
    if not g then error("movement lost guidance: "..state.status.." at "..tick) end
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
    if math.sqrt((pos[1]-endpoint.x)^2+(pos[3]-endpoint.z)^2)<.5 then done=true;break end
    local target=assert(mesh:Project(g.next.mapID,g.next.x,g.next.y))
    local dx,dz=target.x-pos[1],target.z-pos[3]
    local distance=math.sqrt(dx*dx+dz*dz)
    if math.abs(dx)+math.abs(dz)<1 then hidden=hidden+1 end
    if distance<3 and math.sqrt((pos[1]-endpoint.x)^2+(pos[3]-endpoint.z)^2)>6 then closeAims=closeAims+1 end
    assert(distance>.000001,"stuck on exact waypoint")
    dx,dz=dx/distance,dz/distance
    if lastDX and dx*lastDX+dz*lastDZ<0 then reversals=reversals+1 end
    lastDX,lastDZ=dx,dz
    samples[#samples+1]={pos[1],pos[3],target.x,target.z}
    -- Fixed steps deliberately cross waypoints, as a moving player does.
    local nextPoint={x=pos[1]+dx*stride,z=pos[3]+dz*stride}
    local located,reason=mesh:Locate(nextPoint)
    assert(located,"steering left known floor: "..tostring(reason))
    local index=assert(corridorIndex[located.id],"movement left the selected corridor")
    assert(index>=progress,"movement reversed polygon progress")
    progress=index;pos=located.point
end
local uniqueHints=0
for _ in pairs(hints) do uniqueHints=uniqueHints+1 end
assert(uniqueHints>1,"actual movement did not change instructions")
print(string.format("Route display: %d frames, %d distinct instructions, %.3f ms peak headless display CPU",displayFrames,uniqueHints,displayPeak))
local function encode(value)
    if type(value)=="number" then return string.format("%.12g",value) end
    local result={}
    for _,item in ipairs(value) do result[#result+1]=encode(item) end
    return "["..table.concat(result,",").."]"
end
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
    ..",\"stride\":"..stride..",\"polygons\":"..encode(polygons)..",\"corridor\":"..encode(route.corridor)
    ..",\"coarse\":"..encode(route.points)..",\"samples\":"..encode(samples)
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
<header><h1>Actual navmesh · archived quest marker</h1><p>Actual companion polygons and production Lua steering. Start: rounded screenshot <span id="startMap"></span>. Marker: archived build 69913 observation.</p>
<p>Model simulation only: collision, native movement and interaction are unverified. Reaching the modeled endpoint does not establish native arrival or quest completion.</p>
<label><input id="coarse" type="checkbox" checked>Orange: center graph</label><label><input id="motion" type="checkbox" checked>Green: simulated movement</label>
<button id="play">Play</button> <input id="step" type="range" min="0" value="0" style="width:32%"> <button id="fit">Fit route</button><p id="info"></p></header>
<svg id="view" xmlns="http://www.w3.org/2000/svg"><g id="mesh"></g><polyline id="route" class="coarse"/><polyline id="trace" class="motion"/><circle id="marker" fill="#ff78cb" r="1.4"/><line id="arrow" stroke="#fff" stroke-width="1.2"/><circle id="player" fill="#fff" r="1"/></svg>
<script>
const d=DATA,ns="http://www.w3.org/2000/svg",el=id=>document.getElementById(id),xy=p=>[-p[0],-p[p.length===3?2:1]],pair=p=>xy(p).join(",");
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
