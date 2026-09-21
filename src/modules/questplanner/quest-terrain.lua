-- One active regional mesh and a sliced path request. No quest/world facts are inferred here.
local core,planner=RikUI,RikUI.QuestPlanner
local schema,terrain=planner.Schema,{}
planner.Terrain=terrain
local mesh,loader,request,route,driver=nil,nil,nil,nil,nil
local selectedKey,lastAttempt,elapsed=nil,nil,0
local lastLocation,locationAge=nil,0
local floorKey,floorChoices,floorIndex=nil,{},0
local floorSuggestion
local CONTINUITY_SECONDS=.5
local STEERING_INTERVAL = .05
local LOAD_MS, LOAD_BATCHES, LOAD_FALLBACK_BATCHES = 4, 32, 4
local SEARCH_MS, SEARCH_BATCHES, SEARCH_FALLBACK_BATCHES = 2, 16, 4
local state={status="unavailable",detail="Terrain datasource is not installed"}
local display,lastAim
local function setState(status,detail)
    if state.status==status and state.detail==detail then return end
    state={status=status,detail=detail}
    if planner.View and planner.View.Refresh then planner.View.Refresh() end
end
local function same(a,b) return a.product==b.product and a.build==b.build and a.locale==b.locale end
local function clear(forgetLocation)
    if request then request:Cancel(); request=nil end
    route,display,selectedKey,lastAttempt,lastAim=nil,nil,nil,nil,nil
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
function terrain.Guidance() return schema.Clone(display) end
function terrain.PeekGuidance() return display end
local function selected()
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    local row=model.selected
    local position=planner.Context.Position()
    if not position then return nil,nil,"Player position is unavailable" end
    if not row or not row.destination or model.status=="paused" or model.status=="updating" then return nil,position end
    return row,position
end
local function destinationKey(row)
    local target=row.destination
    return string.format("%d:%d:%.17g:%.17g:%s:%s:%s:%s",row.questID,target.mapID,target.x,target.y,
        target.scope or "",target.api or "",row.kind or "",(row.stepID or "")..":"..(row.targetHint and row.targetHint.id or ""))
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
    if not snapshot or not same(mesh:Metadata().identity,snapshot.identity) then return {choices={},selected=0} end
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
local function remainingPoints(location,index)
    local aim,crossed,last=planner.NavGeometry.CorridorAim(route,location.point,index,lastAim)
    lastAim={point=aim,index=last,origin=schema.Clone(location.point)}
    local points={location.point}
    for _,point in ipairs(crossed) do points[#points+1]=point end
    points[#points+1]=aim
    if last<#route.corridor then
        for at=last*2+1,#route.points do points[#points+1]=route.points[at] end
    elseif aim~=route.points[#route.points] then points[#points+1]=route.points[#route.points] end
    return points,aim
end
local function trim(location)
    if not route then return nil end
    local index
    for at,id in ipairs(route.corridor) do if id==location.id then index=at; break end end
    if not index then return nil end
    local points,aim=remainingPoints(location,index)
    local result={points={},meters=0,status="modeled",nativeVerified=false,revision=route.revision,detail="Terrain estimate; traversal unverified"}
    if route.destinationFloor then result.destinationFloor=schema.Clone(route.destinationFloor) end
    result.floorChoiceAvailable=#floorChoices>1
    if route.approach then
        result.approach=schema.Clone(route.approach)
        result.approach.marker=mesh:Unproject({route.approach.marker.x,0,route.approach.marker.z})
        result.approach.provenance=schema.Clone(route.markerProvenance)
        local uncertain=route.approach.kind=="observed-marker-common-approach"
            or route.approach.kind=="observed-marker-uncertain-vicinity"
        result.detail=uncertain and "Approach; quest floor is uncertain"
            or string.format("Modeled approach; %.2f yd gap and interaction unverified",route.approach.gap)
    end
    for at,point in ipairs(points) do
        result.points[#result.points+1]=mesh:Unproject(point)
        if at>1 then result.meters=result.meters+planner.NavGeometry.Distance(points[at-1],point) end
    end
    local speed=planner.Context.RunSpeed and planner.Context.RunSpeed()
    result.speedSource=speed and "current-run-speed" or "default-run-speed"
    result.seconds=result.meters/(speed or 7)
    result.next=mesh:Unproject(aim)
    return result
end
local function admissible()
    local snapshot=(planner.PeekSnapshot or planner.GetSnapshot)()
    local meta=mesh:Metadata()
    if not snapshot or not same(meta.identity,snapshot.identity) then return nil,"Terrain build or locale does not match" end
    if #(meta.blockers or {})>0 then return nil,"Terrain coverage is incomplete" end
    return true
end
local function observeLocation(position)
    local start=mesh:Project(position.mapID,position.x,position.y)
    if not start then clear(true);setState("outside-coverage","Location is outside this terrain map");return end
    local world=planner.Context.WorldPosition and planner.Context.WorldPosition()
    if world then
        if world.mapID~=mesh:Metadata().worldMapID or math.abs(world.x-start.x)>5 or math.abs(world.z-start.z)>5 then
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
    display=trim(location)
    if display then setState(display.approach and "modeled-approach" or "modeled",display.detail);return end
    if request then return end
    local attempt=signature..":"..location.id
    if lastAttempt==attempt then return end
    lastAttempt=attempt
    local speed=planner.Context.RunSpeed and planner.Context.RunSpeed()
    local begin=target.scope=="current-map-quest-poi" and mesh.BeginMarkerApproach or mesh.Begin
    -- Quest-map POIs represent a vicinity, not an exact standing/interaction position.
    local maxWork=math.max(32768,mesh:Metadata().counts.portals*2+1)
    local problem
    request,problem=begin(mesh,start,goal,{maxWork=maxWork,speed=speed or 7,markerRadius=8,reachableApproach=true,commonApproach=true,uncertainVicinity=true})
    setState(request and "calculating" or "unknown-target",problem or "Calculating terrain corridor")
end
local function update()
    if not mesh then return end
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
        local result=request:Step(64)
        if result then return result end
        if clock and clock()-started>=SEARCH_MS then return end
    end
end
function terrain.Step()
    if not planner.enabled then clear(true); setState("disabled","Quest planner is disabled"); return end
    if loader then
        local value,reason,done=loadSlice()
        if done then
            loader=nil; mesh=value
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
                route=result;lastAim=nil
                local row=selected()
                route.markerProvenance=row and schema.Clone(row.destination)
                route.destinationFloor=destinationFloor()
                update()
            else display=nil; setState(result.status,result.detail) end
        end
    end
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
