-- One active regional mesh and a sliced path request. No quest/world facts are inferred here.
local core,planner=RikUI,RikUI.QuestPlanner
local schema,terrain=planner.Schema,{}
planner.Terrain=terrain
local mesh,loader,request,route,driver=nil,nil,nil,nil,nil
local meta,live,regionalToken
local packKey
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
function terrain.Stats()
    local result=schema.Clone(stats);result.roads=planner.RoadGuidance and planner.RoadGuidance.Stats();return result
end
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
local function roadMode() return planner.RoadGuidance and planner.RoadGuidance.Active() end
function terrain.Invalidate()
    if planner.RoadGuidance then planner.RoadGuidance.Invalidate() end
    clear()
    if loader then setState("loading","Preparing terrain guidance")
    elseif mesh then setState("updating","Updating walking route") end
end
function terrain.Retry()
    if not planner.enabled then return nil,"Quest planner is disabled" end
    if roadMode() then planner.RoadGuidance.Invalidate();return true end
    local regional=planner.Regions and planner.Regions.Enabled()
    if not mesh and not loader and not regional then return nil,state.detail end
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    if model.status=="paused" then return nil,"Resume quest guidance before retrying" end
    if not model.selected or not model.selected.destination then return nil,"Choose a quest with a map location" end
    if regional then planner.Regions.Retry() end
    terrain.Invalidate()
    return true
end
function terrain.Install(meta,shards)
    local value,reason=planner.NavMesh.Begin(meta,shards)
    if not value then return nil,reason end
    if loader then loader:Cancel() end
    clear(true)
    if not meta.regionalCandidate then mesh=nil end
    loader=value
    floorKey,floorChoices,floorIndex,floorSuggestion=nil,{},0,nil
    setState("loading","Preparing terrain guidance")
    return true
end
function terrain.Status()
    if roadMode() then return planner.RoadGuidance.Status() end
    return schema.Clone(state)
end
local function current() if roadMode() then return planner.RoadGuidance.PeekGuidance() end return display end
function terrain.Guidance()
    local display=current()
    if not display or not display.path then return end
    local result={}
    for key,value in pairs(display) do if key~="path" then result[key]=schema.Clone(value) end end
    result.points={}
    for _,point in ipairs(display.path.prefix) do result.points[#result.points+1]=schema.Clone(point) end
    for at=display.path.first,#display.path.tail do result.points[#result.points+1]=schema.Clone(display.path.tail[at]) end
    return result
end
function terrain.PeekGuidance() return current() end
local function selected()
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    local row=model.selected
    local position
    if live then position=live.position else position=planner.Context.Position() end
    if not position then return nil,nil,"Player position is unavailable" end
    if not row or not row.destination or row.suppressSteering or model.status=="paused" or model.status=="updating" then return nil,position end
    return row,position
end
local function destinationKey(row)
    local target=row.destination
    return string.format("%d:%d:%.17g:%.17g:%s:%s:%s:%s",row.questID,target.mapID,target.x,target.y,
        target.scope or "",target.api or "",row.kind or "",(row.stepIdentity~="snapshot-slot" and row.stepIdentity~="quest-marker" and row.stepID or "")..":"..(row.targetHint and row.targetHint.id or "")..":"..(row.hunt and (row.hunt.objectiveID..":"..row.hunt.radius) or "")..":"..(target.terrainHeight or ""))
end
local function refreshFloors(row,goal)
    local key=mesh:Revision()..":"..destinationKey(row)..":"..(row.destinationSignature or "")
    if floorKey~=key then
        floorKey,floorIndex=key,0
        floorChoices=(row.destination.scope=="current-map-quest-poi" or row.destination.scope=="semantic-objective-area") and mesh:MarkerFloors(goal) or {}
        floorSuggestion=planner.Targets and planner.Targets.Floor(row.targetHint,meta.corpusRevision or mesh:Revision(),floorChoices,row.destination)
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
function terrain.ContinuedLocation(point,previous)
    local continued=route and route.locate and route.locate(point,previous)
    if continued then return continued end
    if mesh then return mesh:LocateContinued(point,previous) end
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
    local location,problem=terrain.ContinuedLocation(start,locationAge<=CONTINUITY_SECONDS and lastLocation or nil)
    if not location then
        clear(true)
        if meta.regionalCandidate and planner.Regions.Expand() then setState("loading","Expanding terrain coverage")
        else setState("unknown-location",problem) end
        return
    end
    lastLocation,locationAge=location,0
    -- Search starts on this modeled surface; this does not establish native altitude.
    start.height=start.height or location.point[2]
    return location,start
end
local function requestRoute(row,location,start)
    local target=row.destination
    local goal=mesh:Project(target.mapID,target.x,target.y)
    if not goal then clear();setState("outside-coverage","Destination is outside this terrain map");return end
    if target.scope=="observed-hunt-area" and target.corpusRevision~=(meta.corpusRevision or mesh:Revision()) then
        clear();setState("unknown-target","Observed hunting terrain changed; refresh quest guidance");return
    end
    refreshFloors(row,goal)
    local signature=mesh:Revision()..":"..destinationKey(row)..":"..floorIndex
    if selectedKey~=signature then clear();selectedKey=signature end
    local floor=destinationFloor()
    if floor then goal.height=floor.height
    elseif target.corpusRevision==(meta.corpusRevision or mesh:Revision()) and schema.Number(target.terrainHeight,-100000,100000) then goal.height=target.terrainHeight end
    display=route and route.follow(location,live)
    if display then setState(display.searching and "hunting" or display.approach and "modeled-approach" or "modeled",display.detail);return end
    if request then return end
    local attempt=signature..":"..location.id
    if lastAttempt==attempt then return end
    lastAttempt=attempt
    local speed=live and live.speed
    local begin=(target.scope=="current-map-quest-poi" or target.scope=="semantic-objective-area") and mesh.BeginMarkerApproach or mesh.Begin
    -- Quest-map POIs represent a vicinity, not an exact standing/interaction position.
    local maxWork=math.max(32768,meta.counts.portals*2+1)
    local problem
    request,problem=begin(mesh,start,goal,{maxWork=maxWork,speed=speed or 7,markerRadius=8,reachableApproach=true,commonApproach=true,uncertainVicinity=true})
    if request then stats.plans=stats.plans+1 end
    setState(request and "calculating" or "unknown-target",problem or "Calculating terrain corridor")
end
local function update()
    if not mesh or loader then return end
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
local function prepareRegions()
    if planner.TerrainPacks and planner.TerrainPacks.IsLoading()then return false end
    local manager=planner.Regions
    if not manager then return true end
    if not manager.Admit and not manager.Enabled()then return true end
    live=planner.Context.Frame and planner.Context.Frame() or {position=planner.Context.Position()}
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    local snapshot=(planner.PeekSnapshot or planner.GetSnapshot)()
    if not live.position or not snapshot or model.status=="paused" then
        manager.Suspend()
        if regionalToken and loader then loader:Cancel();loader=nil;regionalToken=nil end
        clear(true)
        setState(model.status=="paused" and "paused" or "unavailable-position","Waiting for an active position and destination")
        return false
    end
    local row=model.selected
    local destination=row and row.destination or live.position
    if manager.Admit then
        local admitted,why=manager.Admit(snapshot.identity,live.position,destination,live.world and live.world.mapID)
        if not admitted then
            -- A directly installed legacy mesh can remain useful without regional packs.
            if mesh and meta and not meta.regionalCandidate and same(meta.identity,snapshot.identity)
                and live.position.mapID==meta.uiMapID then return true end
            if loader then loader:Cancel();loader=nil end
            regionalToken,mesh,meta,packKey=nil,nil,nil,nil
            clear(true)
            setState(why=="loading"and"loading"or"coverage-frontier",
                why=="loading"and"Loading this map's terrain catalog"or why or"Terrain pack is unavailable")
            return false
        end
        local binding=(manager.PeekBinding or manager.Binding)();local key=binding and binding.packKey
        if key~=packKey then
            if loader then loader:Cancel();loader=nil end
            regionalToken,mesh,meta=nil,nil,nil
            clear(true);packKey=key
        end
    end
    -- Physical world packs were composed by the compact-path runtime, now
    -- replaced by the road network; only single regional packs load here.
    local regionBinding=(manager.PeekBinding or manager.Binding)()
    if regionBinding and regionBinding.packs then
        clear(true);setState("coverage-frontier","This map is served by the road network");return false
    end
    local packet,reason=manager.Prepare(snapshot.identity,live.position,destination,false)
    if regionalToken and not manager.Current(regionalToken) then
        if loader then loader:Cancel();loader=nil end
        regionalToken=nil;clear(true)
    end
    if packet then
        local ok,problem=terrain.Install(packet.meta,packet.stream)
        if not ok then manager.Accept(packet.token,problem);setState("invalid",problem);return false end
        regionalToken=packet.token
        return true
    end
    if reason=="ready" or reason=="validating" then return true end
    clear()
    setState(reason=="loading" and "loading" or "coverage-frontier",
        reason=="loading" and "Loading nearby terrain regions" or reason)
    return false
end
function terrain.Step()
    if not planner.enabled then
        clear(true)
        if planner.Regions then planner.Regions.Suspend() end
        if regionalToken and loader then loader:Cancel();loader=nil;regionalToken=nil end
        setState("disabled","Quest planner is disabled");return
    end
    -- Where a road network covers the player's map it owns walking guidance.
    if planner.RoadGuidance and planner.RoadGuidance.Step() then return end
    if not prepareRegions() then return end
    if loader then
        local value,reason,done=loadSlice()
        if done then
            loader=nil
            if regionalToken then
                local accepted=planner.Regions.Accept(regionalToken,not value and reason or nil)
                regionalToken=nil
                if not accepted then return end
            end
            if value then mesh=value;meta=value:Metadata() end
            setState(value and "ready" or "invalid",reason or "Terrain model ready")
            if value then
                update()
                if planner.SemanticData and planner.Request then planner.Request() end
            end
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
                    result.huntHint=row and not row.journey and floorIndex==0 and schema.Clone(row.hunt)
                    result.markerProvenance=row and schema.Clone(row.destination)
                    result.destinationFloor=destinationFloor()
                    result.destinationKey=row and destinationKey(row)
                    request=planner.NavFollow.Begin(mesh,result,#floorChoices)
                    return
                end
                route=result;stats.published=stats.published+1;stats.generation=stats.generation+1
                update()
            else
                display=nil
                if meta.composedCandidate then
                    if planner.Regions.Expand()then clear(true);setState("loading","Expanding connected terrain packs")
                    else clear(true);setState("coverage-frontier","No modeled route in the bounded connected pack corridor")end
                elseif meta.regionalCandidate then
                    if planner.Regions.Expand() then setState("loading","Expanding terrain coverage")
                    else setState("coverage-frontier","No complete route in the bounded terrain window; retry or choose a nearer waypoint") end
                else setState(result.status,result.detail) end
            end
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
        if not origin.valid() or budget<1 or not anchor.terrain or anchor.terrain.revision~=(meta.corpusRevision or mesh:Revision()) then return nil end
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
                result.uncertainty=.25;result.revision=meta.corpusRevision or result.revision
            end
            return result
        end}
    end
    return origin,bridge
end
-- Area probes are isolated and cannot publish routes or infer quest floors.
function terrain.AreaRevision() return mesh and mesh:Revision() end
function terrain.BeginAreaEstimate(identity,position,area,budget)
    if roadMode() then return planner.RoadGuidance.BeginAreaEstimate(identity,position,area,budget) end
    if not mesh or loader or not position or not same(meta.identity,identity) then return end
    local point=mesh:Project(position.mapID,position.x,position.y)
    local goal=mesh:Project(area.mapID,area.x,area.y)
    if not point or not goal then return end
    local located=mesh:LocateContinued(point,locationAge<=CONTINUITY_SECONDS and lastLocation or nil)
    if not located then return end
    local currentMesh=mesh
    local start={x=located.point[1],height=located.point[2],z=located.point[3]}
    local query=mesh:BeginMarkerApproach(start,goal,{maxWork=budget,speed=7,markerRadius=8,
        reachableApproach=true,commonApproach=true,uncertainVicinity=true})
    if not query then return end
    return {Step=function(_,work)
        local frame=planner.Context.Frame()
        if mesh~=currentMesh or not frame or not frame.position or frame.position.mapID~=position.mapID then
            query:Cancel();return {status="cancelled"}
        end
        local now=mesh:Project(frame.position.mapID,frame.position.x,frame.position.y)
        if not now or (now.x-point.x)^2+(now.z-point.z)^2>3^2 then query:Cancel();return {status="cancelled"} end
        return query:Step(work,true)
    end}
end
function terrain.ProgressConnected(a,b)
    if not mesh or not a or not b or a.corpusRevision~=b.corpusRevision
        or a.corpusRevision~=(meta.corpusRevision or mesh:Revision()) or a.instanceID~=b.instanceID then return false end
    local x,y=mesh:Project(a.mapID,a.x,a.y),mesh:Project(b.mapID,b.x,b.y)
    return x and y and mesh:ConnectedNearby({id=a.polygon,point={x.x,a.terrainHeight,x.z}},
        {id=b.polygon,point={y.x,b.terrainHeight,y.z}},35)
end
-- A progress sample is bound to this modeled surface, never promoted to a mob spawn.
function terrain.ProgressAnchor(frame)
    if not mesh or loader or not frame.position or not frame.world or frame.world.mapID~=meta.worldMapID then return end
    local point=mesh:Project(frame.position.mapID,frame.position.x,frame.position.y)
    if not point or math.abs(frame.world.x-point.x)>5 or math.abs(frame.world.z-point.z)>5 then return end
    local located=mesh:LocateContinued(point,locationAge<=CONTINUITY_SECONDS and lastLocation or nil)
    if not located then return end
    local unique=mesh:Locate({x=point.x,z=point.z,height=located.point[2]})
    if not unique or unique.id~=located.id then return end
    local anchor=mesh:Unproject(located.point)
    anchor.scope,anchor.api="observed-hunt-area","quest-objective-progress"
    anchor.terrainHeight,anchor.corpusRevision=located.point[2],meta.corpusRevision or mesh:Revision()
    anchor.instanceID,anchor.polygon=meta.worldMapID,located.id
    return anchor
end
-- Arrival receipts certify the selected connected modeled anchor, never a quest interaction.
function terrain.Arrival(node,frame,sequence)
    local anchor=node and node.terrain
    if not mesh or loader or not anchor or anchor.revision~=(meta.corpusRevision or mesh:Revision())
        or not frame or not frame.position or frame.position.mapID~=node.mapID then return nil end
    if node.instanceID~=nil and (not frame.world or frame.world.mapID~=node.instanceID) then return nil end
    local point=mesh:Project(node.mapID,node.x,node.y)
    if not point then return nil end
    point.height=anchor.height
    local endpoint=mesh:Locate(point)
    if not endpoint or (anchor.polygon and endpoint.id~=anchor.polygon) then return nil end
    local current=mesh:Project(frame.position.mapID,frame.position.x,frame.position.y)
    local located=current and mesh:LocateContinued(current,locationAge<=CONTINUITY_SECONDS and lastLocation or nil)
    if not located or math.abs(located.point[2]-endpoint.point[2])>1 then return nil end
    local distance=planner.NavGeometry.Distance(located.point,endpoint.point)
    if distance>4 then return nil end
    local connected=located.id==endpoint.id or (route and not route.hunt and display and not display.approach
        and route.corridor[#route.corridor]==endpoint.id and display.meters<=4)
    if not connected then return nil end
    return {sequence=sequence,anchorVerified=true,connected=true,partial=false,distance=distance,
        mapID=node.mapID,instanceID=node.instanceID,floor=node.floor,anchorRevision=anchor.revision}
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
