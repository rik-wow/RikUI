-- One active regional mesh and a sliced path request. No quest/world facts are inferred here.
local core,planner=RikUI,RikUI.QuestPlanner
local schema,terrain=planner.Schema,{}
planner.Terrain=terrain
local mesh,loader,request,route,driver=nil,nil,nil,nil,nil
local meta,live
local selectedKey,lastAttempt,elapsed=nil,nil,0
local lastLocation,locationAge=nil,0
local floorKey,floorChoices,floorIndex=nil,{},0
local floorSuggestion
local CONTINUITY_SECONDS=.5
local STEERING_INTERVAL = .05
local LOAD_MS, LOAD_BATCHES, LOAD_FALLBACK_BATCHES = 4, 32, 4
local SEARCH_MS, SEARCH_BATCHES, SEARCH_FALLBACK_BATCHES = 2, 16, 4
local state={status="unavailable",detail="Terrain datasource is not installed"}
local display
local stats={plans=0,published=0,generation=0}
function terrain.Stats() return schema.Clone(stats) end
local function setState(status,detail)
    if state.status==status and state.detail==detail then return end
    state={status=status,detail=detail}
    if planner.View and planner.View.Refresh then planner.View.Refresh() end
end
local function same(a,b) return a.product==b.product and a.build==b.build and a.locale==b.locale end
local function clear(forgetLocation)
    if request then request:Cancel(); request=nil end
    route,display,selectedKey,lastAttempt=nil,nil,nil,nil
    if forgetLocation then lastLocation,locationAge=nil,0 end
end
function terrain.Invalidate()
    clear()
    if loader then setState("loading","Preparing terrain guidance")
    elseif mesh then setState("updating","Updating walking route") end
end
function terrain.Retry()
    if not planner.enabled then return nil,"Quest planner is disabled" end
    if not mesh and not loader then return nil,state.detail end
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    if model.status=="paused" then return nil,"Resume quest guidance before retrying" end
    if not model.selected or not model.selected.destination then return nil,"Choose a quest with a map location" end
    terrain.Invalidate()
    return true
end
function terrain.Install(meta,shards)
    local value,reason=planner.NavMesh.Begin(meta,shards)
    if not value then return nil,reason end
    if loader then loader:Cancel() end
    clear(true); mesh=nil; loader=value
    floorKey,floorChoices,floorIndex,floorSuggestion=nil,{},0,nil
    setState("loading","Preparing terrain guidance")
    return true
end
function terrain.Status() return schema.Clone(state) end
function terrain.Guidance()
    if not display then return end
    local result={}
    for key,value in pairs(display) do if key~="path" then result[key]=schema.Clone(value) end end
    result.points={}
    for _,point in ipairs(display.path.prefix) do result.points[#result.points+1]=schema.Clone(point) end
    for at=display.path.first,#display.path.tail do result.points[#result.points+1]=schema.Clone(display.path.tail[at]) end
    return result
end
function terrain.PeekGuidance() return display end
local function selected()
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    local row=model.selected
    local position
    if live then position=live.position else position=planner.Context.Position() end
    if not position then return nil,nil,"Player position is unavailable" end
    if not row or not row.destination or model.status=="paused" or model.status=="updating" then return nil,position end
    return row,position
end
local function destinationKey(row)
    local target=row.destination
    return string.format("%d:%d:%.17g:%.17g:%s:%s:%s:%s",row.questID,target.mapID,target.x,target.y,
        target.scope or "",target.api or "",row.kind or "",(row.stepIdentity~="snapshot-slot" and row.stepIdentity~="quest-marker" and row.stepID or "")..":"..(row.targetHint and row.targetHint.id or ""))
end
local function refreshFloors(row,goal)
    local key=mesh:Revision()..":"..destinationKey(row)..":"..(row.destinationSignature or "")
    if floorKey~=key then
        floorKey,floorIndex=key,0
        floorChoices=row.destination.scope=="current-map-quest-poi" and mesh:MarkerFloors(goal) or {}
        floorSuggestion=planner.Targets and planner.Targets.Floor(row.targetHint,mesh:Revision(),floorChoices,row.destination)
    end
end
function terrain.Floors()
    if not mesh or not planner.enabled then return {choices={},selected=0} end
    local row=selected()
    if not row then return {choices={},selected=0} end
    local snapshot=(planner.PeekSnapshot or planner.GetSnapshot)()
    if not snapshot or not same(meta.identity,snapshot.identity) then return {choices={},selected=0} end
    local goal=mesh:Project(row.destination.mapID,row.destination.x,row.destination.y)
    if not goal then return {choices={},selected=0} end
    refreshFloors(row,goal)
    return {key=floorKey,choices=schema.Clone(floorChoices),selected=floorIndex,automatic=schema.Clone(floorSuggestion)}
end
function terrain.SelectFloor(index,key)
    local floors=terrain.Floors()
    if key and key~=floors.key then return nil,"Quest destination changed; choose its floor again" end
    if #floors.choices==0 then return nil,"No distinct modeled floors at this quest marker" end
    if not schema.Integer(index,0,#floors.choices) then return nil,"Choose an available floor or Auto" end
    if floorIndex==index then return true end
    floorIndex=index;terrain.Invalidate()
    return true
end
local function destinationFloor()
    if floorIndex==0 then return schema.Clone(floorSuggestion) end
    local floor=schema.Clone(floorChoices[floorIndex])
    floor.source,floor.questTargetVerified="user-selected-model-floor",false
    return floor
end
local function admissible()
    local snapshot=(planner.PeekSnapshot or planner.GetSnapshot)()
    if not snapshot or not same(meta.identity,snapshot.identity) then return nil,"Terrain build or locale does not match" end
    if #(meta.blockers or {})>0 then return nil,"Terrain coverage is incomplete" end
    return true
end
local function observeLocation(position)
    local start=mesh:Project(position.mapID,position.x,position.y)
    if not start then clear(true);setState("outside-coverage","Location is outside this terrain map");return end
    local world=live and live.world
    if world then
        if world.mapID~=meta.worldMapID or math.abs(world.x-start.x)>5 or math.abs(world.z-start.z)>5 then
            clear(true);setState("unknown-location","Map and world positions disagree");return
        end
        start={x=world.x,z=world.z}
        if world.verticalStatus=="observed-altitude" then start.height=world.height end
    end
    local location,problem=mesh:LocateContinued(start,locationAge<=CONTINUITY_SECONDS and lastLocation or nil)
    if not location then clear(true);setState("unknown-location",problem);return end
    lastLocation,locationAge=location,0
    -- Search starts on this modeled surface; this does not establish native altitude.
    start.height=start.height or location.point[2]
    return location,start
end
local function requestRoute(row,location,start)
    local target=row.destination
    local goal=mesh:Project(target.mapID,target.x,target.y)
    if not goal then clear();setState("outside-coverage","Destination is outside this terrain map");return end
    refreshFloors(row,goal)
    local signature=mesh:Revision()..":"..destinationKey(row)..":"..floorIndex
    if selectedKey~=signature then clear();selectedKey=signature end
    local floor=destinationFloor()
    if floor then goal.height=floor.height end
    display=route and route.follow(location,live)
    if display then setState(display.approach and "modeled-approach" or "modeled",display.detail);return end
    if request then return end
    local attempt=signature..":"..location.id
    if lastAttempt==attempt then return end
    lastAttempt=attempt
    local speed=live and live.speed
    local begin=target.scope=="current-map-quest-poi" and mesh.BeginMarkerApproach or mesh.Begin
    -- Quest-map POIs represent a vicinity, not an exact standing/interaction position.
    local maxWork=math.max(32768,meta.counts.portals*2+1)
    local problem
    request,problem=begin(mesh,start,goal,{maxWork=maxWork,speed=speed or 7,markerRadius=8,reachableApproach=true,commonApproach=true,uncertainVicinity=true})
    if request then stats.plans=stats.plans+1 end
    setState(request and "calculating" or "unknown-target",problem or "Calculating terrain corridor")
end
local function update()
    if not mesh then return end
    live=planner.Context.Frame and planner.Context.Frame() or {position=planner.Context.Position(),
        world=planner.Context.WorldPosition and planner.Context.WorldPosition(),speed=planner.Context.RunSpeed and planner.Context.RunSpeed()}
    local ok,reason=admissible()
    if not ok then clear(true);setState("unavailable",reason);return end
    local row,position,issue=selected()
    if not position then clear(true);setState("unavailable-position",issue);return end
    local location,start=observeLocation(position)
    if not location then return end
    -- Quest selection and journal updates do not invalidate recent floor observations.
    if not row then clear();setState("ready","No active terrain destination");return end
    requestRoute(row,location,start)
end
local function loadSlice()
    local clock=type(debugprofilestop)=="function" and debugprofilestop
    local started=clock and clock()
    for _=1,clock and LOAD_BATCHES or LOAD_FALLBACK_BATCHES do
        local value,reason,done=loader:Step(64)
        if done then return value,reason,true end
        if clock and clock()-started>=LOAD_MS then return end
    end
end
local function searchSlice()
    local clock=type(debugprofilestop)=="function" and debugprofilestop
    local started=clock and clock()
    for _=1,clock and SEARCH_BATCHES or SEARCH_FALLBACK_BATCHES do
        local result=request:Step(64,true)
        if result then return result end
        if clock and clock()-started>=SEARCH_MS then return end
    end
end
function terrain.Step()
    if not planner.enabled then clear(true); setState("disabled","Quest planner is disabled"); return end
    if loader then
        local value,reason,done=loadSlice()
        if done then
            loader=nil; mesh=value;meta=value and value:Metadata()
            setState(value and "ready" or "invalid",reason or "Terrain model ready")
            if value then update() end
        end
    elseif request then
        -- Validate live destination, identity and player admission before spending a slice
        -- or publishing a result from a request started on an earlier frame.
        local pending=request
        update()
        if request~=pending then return end
        local result=searchSlice()
        if result then
            request=nil
            if result.status=="modeled" then
                if not result.prepared then
                    local row=selected()
                    result.markerProvenance=row and schema.Clone(row.destination)
                    result.destinationFloor=destinationFloor()
                    request=planner.NavFollow.Begin(mesh,result,#floorChoices)
                    return
                end
                route=result;stats.published=stats.published+1;stats.generation=stats.generation+1
                update()
            else display=nil; setState(result.status,result.detail) end
        end
    end
end
-- Internal planner bridge. A modeled position never grants NPC access or taxi unlocks.
function terrain.PlanningOrigin(identity,position)
    if not mesh or not position or not same(meta.identity,identity) then return nil end
    local point=mesh:Project(position.mapID,position.x,position.y)
    if not point then return nil end
    local located=mesh:LocateContinued(point,locationAge<=CONTINUITY_SECONDS and lastLocation or nil)
    if not located then return nil end
    local currentMesh=mesh
    local origin={id="player-origin",identity=schema.Clone(identity),
        revision=mesh:Revision()..":"..located.id..":"..string.format("%.6f:%.6f",point.x,point.z)}
    origin.valid=function()
        if mesh~=currentMesh or not planner.enabled then return false end
        local frame=planner.Context.Frame and planner.Context.Frame()
        local now
        if frame then now=frame.position else now=planner.Context.Position() end
        if not now or now.mapID~=position.mapID then return false end
        local current=mesh:Project(now.mapID,now.x,now.y)
        return current and (current.x-point.x)^2+(current.z-point.z)^2<=3^2
    end
    local start={x=located.point[1],height=located.point[2],z=located.point[3]}
    local function bridge(anchor,budget)
        if not origin.valid() or budget<1 or not anchor.terrain or anchor.terrain.revision~=mesh:Revision() then return nil end
        local goal=mesh:Project(anchor.mapID,anchor.x,anchor.y)
        if not goal then return nil end
        goal.height=anchor.terrain.height
        local endpoint=mesh:Locate(goal)
        if not endpoint or (anchor.terrain.polygon and anchor.terrain.polygon~=endpoint.id) then return nil end
        local search=mesh:Begin(start,goal,{maxWork=budget,speed=(planner.Context.RunSpeed and planner.Context.RunSpeed()) or 7})
        if not search then return nil end
        return {Step=function(_,work)
            if not origin.valid() then search:Cancel();return {status="cancelled"} end
            local result=search:Step(work,true)
            if result and result.status=="modeled" then
                local last=result.walkPoints[#result.walkPoints]
                if result.corridor[#result.corridor]~=endpoint.id or planner.NavGeometry.Distance(last,endpoint.point)>.002 then
                    return {status="invalid"} end
                result.uncertainty=.25
            end
            return result
        end}
    end
    return origin,bridge
end
function terrain.Start()
    if driver then return end
    driver=CreateFrame("Frame")
    driver:SetScript("OnUpdate",function(_,delta)
        locationAge=locationAge+delta
        terrain.Step()
        elapsed=elapsed+delta
        if route and planner.enabled then
            -- An active corridor must follow lateral movement without retaining an old ray.
            update()
        elseif elapsed>=STEERING_INTERVAL and planner.enabled then update() end
        if elapsed>=STEERING_INTERVAL then elapsed=elapsed%STEERING_INTERVAL end
    end)
end
