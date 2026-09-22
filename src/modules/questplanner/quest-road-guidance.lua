-- Road-mode walking guidance: owns the request, follower and published display
-- whenever the player's map has a compiled road network. The terrain module
-- delegates to it; nothing here completes quests or infers world facts.
local planner=RikUI.QuestPlanner
local schema,guidance=planner.Schema,{}
planner.RoadGuidance=guidance

local SEARCH_MS,SEARCH_SLICES=2,16
local REPLAN_SECONDS=1.5
local state={status="unavailable",detail="Road network is not installed"}
local active,request,follower,requestKey,routeKey,display,lastReplan=false,nil,nil,nil,nil,nil,0
local stats={plans=0,published=0,replans=0}

local function setState(status,detail)
    if state.status==status and state.detail==detail then return end
    state={status=status,detail=detail}
    if planner.View and planner.View.Refresh then planner.View.Refresh() end
end

local function clear()
    if request then request:Cancel() end
    request,follower,requestKey,routeKey,display=nil,nil,nil,nil,nil
end

function guidance.Active() return active end
function guidance.Status() return schema.Clone(state) end
function guidance.PeekGuidance() return display end
function guidance.Stats() return schema.Clone(stats) end
function guidance.Invalidate() clear() end

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
    if display then setState(display.meshOnly and "modeled" or "modeled-road",display.detail) end
    return true
end

local function begin(graph,view,start,goal,row,live,key)
    local job,why=planner.RoadNavigate.Begin(graph,view,start,goal,{speed=live and live.speed or 7,marker=isMarker(row.destination)})
    if not job then setState("unknown-target",why);return end
    request,requestKey=job,key;stats.plans=stats.plans+1
    setState("calculating","Calculating road route")
end

local function publish(result,view,key)
    if result.status~="modeled" then setState(result.status,result.detail);return end
    local handle,why=planner.RoadFollow.Begin(result,function(point) return planner.Roads.Unproject(view,point) end)
    if not handle then setState("invalid",why);return end
    handle.route.meshOnly=result.meshOnly
    follower,routeKey=handle,key;stats.published=stats.published+1
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
        clear();setState(why=="loading" and "loading" or "unavailable",why=="loading" and "Loading the road network" or why)
        return true
    end
    local model=(planner.Controller.Peek or planner.Controller.Get)()
    local row=model.selected
    if model.status=="paused" then clear();setState("paused","Quest guidance is paused");return true end
    if not row or not row.destination or row.suppressSteering then clear();setState("ready","No active walking destination");return true end
    local goalWorld,goalPoint=roads.Locate(row.destination.mapID,row.destination.x,row.destination.y)
    if goalWorld~=world then clear();setState("outside-coverage","Destination is on another continent or map");return true end
    local key=destinationKey(row,graph.revision)
    local start=playerPoint(live,world,point)
    if follower and routeKey==key and follow(start,live) then return true end
    if request and requestKey~=key then request:Cancel();request=nil end
    if not request then
        follower,display=nil,nil
        begin(graph,view,start,{x=goalPoint.x,z=goalPoint.z,height=row.destination.terrainHeight},row,live,key)
        return true
    end
    local result=searchSlice()
    if result then request=nil;publish(result,view,key) end
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
