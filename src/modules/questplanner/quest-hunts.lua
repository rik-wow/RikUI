-- Hunting guidance is a search policy, never a spawn map or quest completion.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local hunts,previous,areas={},{},{}
planner.Hunts=hunts
local identityKey,mapKey,revision=nil,nil,0
local RECEIPT_SECONDS,AREA_SECONDS,RECEIPT_DISTANCE,AREA_RADIUS=8,300,35,25
local FRAME_DISTANCE,EXIT_MARGIN,ENTER_DISTANCE,INNER_MARGIN,QUEST_LIMIT=3,15,2,5,40
local function identity(v) return table.concat({v.product,v.build,v.locale},":") end
local function distance(a,b,frame)
    if not a or not b or a.mapID~=b.mapID or not frame.width or not frame.height then return math.huge end
    return math.sqrt(((a.x-b.x)*frame.width)^2+((a.y-b.y)*frame.height)^2)
end
local function record(key,count,ctx,frame,anchor)
    local old=previous[key]
    previous[key]={count=count,time=ctx.observedAt,point=schema.Clone(ctx.position),
        instance=frame.world and frame.world.mapID,anchor=anchor}
    if not old or count<=old.count or ctx.observedAt-old.time>RECEIPT_SECONDS or ctx.observedAt<=old.time
        or distance(old.point,ctx.position,frame)>RECEIPT_DISTANCE or frame.taxi~=false
        or not frame.world or old.instance~=frame.world.mapID then return end
    if not anchor or not planner.Terrain.ProgressConnected(old.anchor,anchor) then return end
    local area=areas[key]
    -- Keep an existing productive anchor stable while fighting around it.
    if area and distance(area.point,anchor,frame)<=AREA_RADIUS and planner.Terrain.ProgressConnected(area.point,anchor) then
        area.time=ctx.observedAt;return
    end
    areas[key]={point=anchor,time=ctx.observedAt};revision=revision+1
end
local function observeQuest(snapshot,id,ctx,frame,anchor,seen)
    if snapshot.quests[id].objectivesComplete==true then return end
    local binding=planner.StepBindings.Match(snapshot,id)
    for index,objective in ipairs(snapshot.quests[id].objectives or {}) do
        local objectiveID=binding and binding.ids[index]
        if objectiveID and binding.navigation[objectiveID] and objective.finished~=true
            and schema.Integer(objective.numFulfilled,0,1000000) then
            local k=id..":"..objectiveID;seen[k]=true
            record(k,objective.numFulfilled,ctx,frame,anchor)
        end
    end
end
function hunts.Suspend() previous={} end
function hunts.Observe(snapshot,ctx)
    if snapshot.origin=="imported-untrusted" or ctx.origin~="live" or not schema.Number(ctx.observedAt,0,2147483647) then previous={};return end
    local key=identity(snapshot.identity)
    if key~=identityKey then identityKey=key;previous={};areas={};revision=revision+1 end
    local frame=planner.Context.Frame and planner.Context.Frame()
    if not frame or not ctx.position or distance(frame.position,ctx.position,frame)>FRAME_DISTANCE then previous={};return end
    local currentMap=tostring(ctx.position.mapID)..":"..tostring(frame.world and frame.world.mapID)
    if currentMap~=mapKey then previous={};areas={};mapKey=currentMap;revision=revision+1 end
    local anchor=planner.Terrain and planner.Terrain.ProgressAnchor and planner.Terrain.ProgressAnchor(frame)
    local seen={}
    for at,id in ipairs(snapshot.order) do
        if at>QUEST_LIMIT then break end
        observeQuest(snapshot,id,ctx,frame,anchor,seen)
    end
    for k in pairs(previous) do if not seen[k] then previous[k]=nil end end
    for k,area in pairs(areas) do
        if not seen[k] or ctx.observedAt-area.time>AREA_SECONDS or ctx.observedAt<area.time
            or (anchor and area.point.corpusRevision~=anchor.corpusRevision) then areas[k]=nil;revision=revision+1 end
    end
end
function hunts.Revision() return revision end
function hunts.Destination(snapshot,id,step,point)
    local policy=step and step.state=="active" and step.navigation
    -- A client waypoint can name a required entrance; only relax quest-level POIs.
    if not policy or not point or (point.scope~="current-map-quest-poi" and point.scope~="semantic-objective-area") then return point end
    local value=schema.Clone(policy);value.objectiveID=step.active.objectiveID
    local area=identity(snapshot.identity)==identityKey and areas[id..":"..value.objectiveID]
    if area and area.point.mapID==point.mapID then
        value.radius,value.source,value.basis=AREA_RADIUS,"observed-progress","Recent objective progress near this connected modeled position; not a verified spawn."
        return schema.Clone(area.point),value
    end
    return point,value
end
local function pause() coroutine.yield() end
local function trimArrays(route,count,target)
    for at=#route.corridor,count+1,-1 do route.corridor[at]=nil;route.surfaces[at]=nil;pause() end
    for at=#route.portals,count,-1 do route.portals[at]=nil;pause() end
    for at=#route.points,count*2+1,-1 do route.points[at]=nil;pause() end
    route.points[#route.points+1]=target
end
local function clipPoint(route,radius)
    local points=route.walkPoints
    if route.meters<=radius then return 1,schema.Clone(points[1]) end
    for i=2,#points do
        pause()
        if route.suffix[i]<=radius then
            local a,b=points[i-1],points[i]
            local span=route.suffix[i-1]-route.suffix[i]
            local t=span>0 and (route.suffix[i-1]-radius)/span or 0
            return i-1,{a[1]+t*(b[1]-a[1]),a[2]+t*(b[2]-a[2]),a[3]+t*(b[3]-a[3])}
        end
    end
end
local function repull(route)
    local geometry=planner.NavGeometry
    local points,crossings,corners=geometry.StringPull(route,nil,nil,pause)
    if not points then return nil,crossings end
    route.walkPoints,route.crossings,route.corners=points,crossings,corners
    route.meters,route.suffix=0,{}
    for i=#points,1,-1 do
        if i<#points then route.meters=route.meters+geometry.Distance(points[i],points[i+1]) end
        route.suffix[i]=route.meters;pause()
    end
    route.destinationFloor,route.approach=nil,nil
    route.seconds=route.meters/(route.speed or 7)
    return true
end
-- Run inside the sliced finalizer. Only shorten an already validated connected corridor.
function hunts.Trim(route,hint)
    if not hint or route.status~="modeled" or not route.walkPoints or not route.suffix then return true end
    if route.approach and route.approach.kind~="observed-marker-vicinity" then return true end
    local geometry,original=planner.NavGeometry,route.walkPoints
    local at,target=clipPoint(route,hint.radius)
    local count=1
    for i,crossing in ipairs(route.crossings) do
        if crossing<=at then count=i+1 end
        pause()
    end
    if not geometry.Contains(route.surfaces[count],target[1],target[3]) then return nil,"Hunt approach left corridor" end
    target[2]=geometry.Height(route.surfaces[count],target[1],target[3]) or target[2]
    local region={}
    for i=count,#route.corridor do region[route.corridor[i]]=true;pause() end
    route.hunt={hint=schema.Clone(hint),region=region,center=original[#original],endpoint=target}
    trimArrays(route,count,target)
    return repull(route)
end
function hunts.Display(mesh,route,location)
    local hunt=route.hunt
    if not hunt then return end
    local geometry=planner.NavGeometry
    local allowed=hunt.region[location.id]
    if not allowed and hunt.searching and hunt.lastLocation and mesh.ConnectedNearby then
        allowed=mesh:ConnectedNearby(hunt.lastLocation,location,FRAME_DISTANCE)
    end
    -- Entry at the approach; a wider exit margin allows ordinary hunting movement.
    local gap=geometry.Distance(location.point,hunt.center)
    if not allowed or gap>hunt.hint.radius+EXIT_MARGIN then hunt.searching=false;return end
    if not hunt.searching and geometry.Distance(location.point,hunt.endpoint)>ENTER_DISTANCE and gap>hunt.hint.radius-INNER_MARGIN then return end
    hunt.searching,hunt.lastLocation=true,location
    local point=mesh:Unproject(location.point)
    hunt.projectedEndpoint=hunt.projectedEndpoint or mesh:Unproject(hunt.endpoint)
    return {path={prefix={point},tail={},first=1},next=point,meters=0,seconds=0,status="hunting",
        hunt=hunt.hint,huntEndpoint=hunt.projectedEndpoint,searching=true,speed=nil,nativeVerified=false,revision=route.revision,
        detail="Search for targets; quest progress determines completion"}
end
