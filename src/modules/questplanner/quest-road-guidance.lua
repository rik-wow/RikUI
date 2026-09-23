-- Road-mode walking guidance: owns the request, follower and published display
-- whenever the player's map has a compiled road network. The terrain module
-- delegates to it; nothing here completes quests or infers world facts.
local planner=RikUI.QuestPlanner
local schema,guidance=planner.Schema,{}
planner.RoadGuidance=guidance

local SEARCH_MS,SEARCH_SLICES=4,16
local REPLAN_SECONDS=1.5
local state={status="unavailable",detail="Road network is not installed"}
local active,request,follower,requestKey,routeKey,display,lastReplan=false,nil,nil,nil,nil,nil,0
local lastTarget -- {key,row}: kept while the planner briefly has no selection
local failure    -- last failed plan: {key,status,detail,x,z,retryAt}; not retried until something changes
local RETRY_YARDS=40       -- moving this far retries a failed destination
local RETRY_TRANSIENT=2    -- seconds before retrying a deferred (combat/loading) plan
local trip={}         -- travel plan for the current destination: legs, index, job
local legDetail      -- leg text shown while walking to a stop
local stats={plans=0,published=0,replans=0}

local function setState(status,detail)
    if state.status==status and state.detail==detail then return end
    state={status=status,detail=detail}
    if planner.View and planner.View.Refresh then planner.View.Refresh() end
end

local function clear()
    if request then request:Cancel() end
    request,follower,requestKey,routeKey,display,lastTarget=nil,nil,nil,nil,nil,nil
end
local function now() return GetTime and GetTime() or 0 end

function guidance.Active() return active end
function guidance.Status() return schema.Clone(state) end
function guidance.PeekGuidance() return display end
function guidance.Stats() return schema.Clone(stats) end
-- Quest-state events invalidate the planner often, sometimes several times a
-- second. A road plan takes about a second, so the request and route are kept
-- and only replaced when the destination itself changes (see Step).
function guidance.Invalidate() end
-- Explicit retry: drop everything and plan again.
function guidance.Reset() clear();failure=nil;trip={} end

local function isMarker(target)
    return target.scope=="current-map-quest-poi" or target.scope=="semantic-objective-area"
end

local function destinationKey(row,revision)
    local t=row.destination
    return string.format("%s:%d:%d:%.6f:%.6f:%s",revision,row.questID or 0,t.mapID,t.x,t.y,t.scope or "")
end

local function playerPoint(live,world,point)
    local w=live and live.world
    if w and w.mapID==world and math.abs(w.x-point.x)<=5 and math.abs(w.z-point.z)<=5 then
        return {x=w.x,z=w.z,height=w.verticalStatus=="observed-altitude" and w.height or nil}
    end
    return {x=point.x,z=point.z}
end

local function searchSlice()
    local clock=type(debugprofilestop)=="function" and debugprofilestop
    local started=clock and clock()
    for _=1,SEARCH_SLICES do
        local result,signal=request:Step(16)
        if result then return result end
        if signal=="end-frame" then return end
        if clock and clock()-started>=SEARCH_MS then return end
    end
end

local function follow(start,live)
    display=follower.follow(start,live)
    if display and display.offRoute and (GetTime and GetTime() or 0)-lastReplan>REPLAN_SECONDS then
        stats.replans=stats.replans+1;lastReplan=GetTime and GetTime() or 0
        follower,display=nil,nil
        return false
    end
    if display and legDetail then display.detail=legDetail end
    if display then setState(display.meshOnly and "modeled" or "modeled-road",display.detail) end
    return true
end

local function begin(graph,view,start,goal,row,live,key,toStop)
    local job,why=planner.RoadNavigate.Begin(graph,view,start,goal,{speed=live and live.speed or 7,
        marker=not toStop and isMarker(row.destination)})
    if not job then setState("unknown-target",why);return end
    request,requestKey=job,key;stats.plans=stats.plans+1
    setState("calculating","Calculating road route")
end

local function publish(result,view,key,start)
    if result.status~="modeled" then
        local detail=result.detail
        -- A walking path exists in the world; this is a gap in the baked model.
        if result.status=="no-known-path" then
            detail="The terrain model has a gap between here and the destination; retrying after you move"
        end
        local transient=result.status=="loading" or result.status=="cancelled"
        failure={key=key,status=result.status,detail=detail,x=start.x,z=start.z,retryAt=transient and now()+RETRY_TRANSIENT or nil}
        setState(result.status,detail);return
    end
    failure=nil
    local handle,why=planner.RoadFollow.Begin(result,function(point) return planner.Roads.Unproject(view,point) end)
    if not handle then setState("invalid",why);return end
    handle.route.meshOnly=result.meshOnly
    follower,routeKey=handle,key;stats.published=stats.published+1
end

-- Travel plan for the current destination: which leg comes next.
local ARRIVE_YARDS=15     -- this close to a stop, the next leg is the link from it
local JUMP_YARDS=150      -- moving this far between frames means a flight, ride or teleport
local TRAVEL_MS=2         -- per-frame budget for travel planning; it runs beside the walking route

local function planWorlds(identity,world,goalWorld)
    local travel=planner.RoadTravel
    local worlds=travel and travel.Count()>0 and travel.Worlds(world,goalWorld) or {world}
    local graphs={}
    for _,w in ipairs(worlds) do
        if planner.Roads.HasWorld(w) then
            local g,why=planner.Roads.Prepare(identity,w)
            if not g then
                if why=="loading" then return nil,"loading" end
            else graphs[w]=g end
        end
    end
    return graphs
end

local function walkOnly(goalWorld)
    return {mode="walk",to="goal",text="Walk to the destination",worldOnly=goalWorld}
end

local function detailFor(legs,index)
    local leg,nextLeg=legs[index],legs[index+1]
    if leg.mode=="walk" and nextLeg then return leg.text..", then "..nextLeg.text:gsub("^%u",string.lower) end
    return leg.text
end

local function planTrip(identity,world,start,goalWorld,goalPoint,key)
    local travel=planner.RoadTravel
    if not travel or travel.Count()==0 then
        if goalWorld~=world then setState("outside-coverage","Destination is on another continent or map");return end
        trip={key=key,world=world,legs={walkOnly(goalWorld)},index=1,at=start};return
    end
    if not trip.job then
        local graphs,why=planWorlds(identity,world,goalWorld)
        if not graphs then setState("loading","Loading travel networks");return end
        local job,problem=travel.Begin(graphs,{world=world,x=start.x,z=start.z},{world=goalWorld,x=goalPoint.x,z=goalPoint.z})
        if not job then setState("no-known-path",problem);trip={key=key,world=world,failed=true,at=start};return end
        trip={key=key,world=world,job=job,at=start}
    end
    local clock=type(debugprofilestop)=="function" and debugprofilestop
    local began=clock and clock()
    local result
    repeat result=trip.job:Step() until result or not clock or clock()-began>=TRAVEL_MS
    if not result then
        -- Walking needs no plan within one world: guide on foot meanwhile.
        if goalWorld==world then trip.pending={walkOnly(goalWorld)} else setState("calculating","Planning travel") end
        return
    end
    trip.pending=nil
    trip.job=nil
    if result.status~="planned" then
        trip.failed=true
        setState(result.status,"The terrain model has a gap between here and the destination; retrying after you move")
        return
    end
    trip.legs,trip.index,trip.seconds=result.legs,1,result.seconds
end

local function tripLeg(identity,world,start,goalWorld,goalPoint,key)
    local jumped=trip.last and (trip.world~=world or (start.x-trip.last.x)^2+(start.z-trip.last.z)^2>JUMP_YARDS^2)
    local moved=trip.failed and trip.at and (start.x-trip.at.x)^2+(start.z-trip.at.z)^2>=RETRY_YARDS^2
    if trip.key~=key or jumped or moved then
        if trip.job and trip.job.Cancel then trip.job:Cancel() end
        trip={key=key,world=world}
    end
    trip.last={x=start.x,z=start.z}
    if trip.failed then return end
    if not trip.legs then planTrip(identity,world,start,goalWorld,goalPoint,key) end
    if not trip.legs then
        if trip.pending then trip.detail=nil;return trip.pending[1] end
        return
    end
    local leg=trip.legs[trip.index]
    -- Reaching the stop at the end of a walking leg moves on to the link.
    if leg.mode=="walk" and leg.to~="goal" then
        local p=leg.stop.point
        if (start.x-p[1])^2+(start.z-p[3])^2<=ARRIVE_YARDS^2 and trip.legs[trip.index+1] then
            trip.index=trip.index+1;leg=trip.legs[trip.index]
        end
    end
    trip.detail=detailFor(trip.legs,trip.index)
    return leg
end

-- Returns true when road mode handled this frame (the terrain mesh path is skipped).
function guidance.Step()
    local roads=planner.Roads
    local live=planner.Context.Frame and planner.Context.Frame()
    local position=live and live.position or planner.Context.Position()
    if not roads or not position then
        if active then clear();active=false end
        return false
    end
    local world,point,view=roads.Locate(position.mapID,position.x,position.y)
    if not world or not roads.HasWorld(world) then
        if active then clear();active=false end
        return false
    end
    active=true
    local snapshot=(planner.PeekSnapshot or planner.GetSnapshot)()
    if not snapshot then setState("unavailable-position","Waiting for quest observations");return true end
    local graph,why=roads.Prepare(snapshot.identity,world)
    if not graph then
        if why=="road-addon-missing" then clear();setState("restart-required","Restart the game to load the new road data");return true end
        clear();setState(why=="loading" and "loading" or "unavailable",why=="loading" and "Loading the road network" or why)
        return true
    end
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    local row=model.selected
    if model.status=="paused" then clear();setState("paused","Quest guidance is paused");return true end
    if row and row.suppressSteering then clear();setState("ready","No active walking destination");return true end
    if not row or not row.destination then
        -- The planner is between results: keep working toward the last destination.
        if not (model.status=="updating" and lastTarget) then clear();setState("ready","No active walking destination");return true end
        row=lastTarget
    end
    lastTarget=row
    local goalWorld,goalPoint=roads.Locate(row.destination.mapID,row.destination.x,row.destination.y)
    if not goalWorld or not roads.HasWorld(goalWorld) then
        clear();setState("outside-coverage","Destination is outside the road networks");return true
    end
    local destinationKey_=destinationKey(row,graph.revision)
    local start=playerPoint(live,world,point)
    local leg=tripLeg(snapshot.identity,world,start,goalWorld,goalPoint,destinationKey_)
    if not leg then return true end
    if leg.mode~="walk" then
        follower,display=nil,nil
        if request then request:Cancel();request=nil end
        setState("travel",leg.text);return true
    end
    -- Walk the current leg: to the goal, or to the stop where the next link starts.
    local key=destinationKey_..(leg.to=="goal" and "" or ":"..leg.to)
    if leg.to~="goal" then
        local p=leg.stop.point
        goalPoint={x=p[1],z=p[3]}
    end
    legDetail=leg.to~="goal" and trip.detail or nil
    if follower and routeKey==key and follow(start,live) then return true end
    if request and requestKey~=key then request:Cancel();request=nil end
    if not request then
        follower,display=nil,nil
        if failure and failure.key==key and (failure.retryAt and now()<failure.retryAt
            or not failure.retryAt and (start.x-failure.x)^2+(start.z-failure.z)^2<RETRY_YARDS^2) then
            setState(failure.status,failure.detail);return true
        end
        begin(graph,view,start,{x=goalPoint.x,z=goalPoint.z,height=leg.to=="goal" and row.destination.terrainHeight or nil},
            row,live,key,leg.to~="goal")
        return true
    end
    local result=searchSlice()
    if result then request=nil;publish(result,view,key,{x=start.x,z=start.z}) end
    return true
end

-- Walking estimate between the player and a quest area, for the optimizer.
function guidance.BeginAreaEstimate(identity,position,area,budget)
    local roads=planner.Roads
    local world,point,view=roads.Locate(position.mapID,position.x,position.y)
    if not world then return end
    local graph=roads.Prepare(identity,world)
    local goalWorld,goal=roads.Locate(area.mapID,area.x,area.y)
    if not graph or goalWorld~=world then return end
    local job=planner.RoadNavigate.Begin(graph,view,{x=point.x,z=point.z},{x=goal.x,z=goal.z},{speed=7,marker=true})
    if not job then return end
    return {Step=function(_,work) return job:Step(math.max(1,math.min(64,math.floor((work or 64)/16)))) end}
end
