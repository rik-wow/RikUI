-- One active regional mesh and a sliced path request. No quest/world facts are inferred here.
local core,planner=RikUI,RikUI.QuestPlanner
local schema,terrain=planner.Schema,{}
planner.Terrain=terrain
local mesh,loader,request,route,driver=nil,nil,nil,nil,nil
local selectedKey,lastAttempt,elapsed=nil,nil,0
local state={status="unavailable",detail="Terrain datasource is not installed"}
local display
local function setState(status,detail)
    if state.status==status and state.detail==detail then return end
    state={status=status,detail=detail}
    if planner.View and planner.View.Refresh then planner.View.Refresh() end
end
local function same(a,b) return a.product==b.product and a.build==b.build and a.locale==b.locale end
local function clear()
    if request then request:Cancel(); request=nil end
    route,display,selectedKey,lastAttempt=nil,nil,nil,nil
end
function terrain.Invalidate()
    clear()
    if loader then setState("loading","Preparing terrain guidance")
    elseif mesh then setState("updating","Updating walking route") end
end
function terrain.Install(meta,shards)
    local value,reason=planner.NavMesh.Begin(meta,shards)
    if not value then return nil,reason end
    if loader then loader:Cancel() end
    clear(); mesh=nil; loader=value
    setState("loading","Preparing terrain guidance")
    return true
end
function terrain.Status() return schema.Clone(state) end
function terrain.Guidance() return schema.Clone(display) end
local function selected()
    local model=planner.Controller.Get()
    local row=model.selected
    if not row or model.status=="paused" or model.status=="updating" then return nil end
    local position=planner.Context.Position()
    if not row.destination then return nil end
    if not position then return nil,nil,"Player position is unavailable" end
    return row,position
end
local function trim(location)
    if not route then return nil end
    local index
    for at,id in ipairs(route.corridor) do if id==location.id then index=at; break end end
    if not index then return nil end
    local points={location.point}
    if index<#route.corridor then
        for at=index*2+1,#route.points do points[#points+1]=route.points[at] end
    else points[#points+1]=route.points[#route.points] end
    local result={points={},meters=0,status="modeled",nativeVerified=false,detail="Terrain estimate; traversal unverified"}
    for at,point in ipairs(points) do
        result.points[#result.points+1]=mesh:Unproject(point)
        if at>1 then result.meters=result.meters+planner.NavGeometry.Distance(points[at-1],point) end
    end
    local speed=planner.Context.RunSpeed and planner.Context.RunSpeed()
    result.speedSource=speed and "current-run-speed" or "default-run-speed"
    result.seconds=result.meters/(speed or 7)
    result.next=result.points[2]
    return result
end
local function admissible()
    local snapshot=planner.GetSnapshot()
    local meta=mesh:Metadata()
    if not snapshot or not same(meta.identity,snapshot.identity) then return nil,"Terrain build or locale does not match" end
    if #(meta.blockers or {})>0 then return nil,"Terrain coverage is incomplete" end
    return true
end
local function update()
    if not mesh then return end
    local ok,reason=admissible()
    if not ok then clear(); setState("unavailable",reason); return end
    local row,position,issue=selected()
    if not row then clear(); setState(issue and "unavailable-position" or "ready",issue or "No active terrain destination"); return end
    local target=row.destination
    local signature=string.format("%d:%d:%.6f:%.6f",row.questID,target.mapID,target.x,target.y)
    if selectedKey~=signature then clear(); selectedKey=signature end
    local start,goal=mesh:Project(position.mapID,position.x,position.y),mesh:Project(target.mapID,target.x,target.y)
    if not start or not goal then clear(); setState("outside-coverage","Location or destination is outside this terrain map"); return end
    local world=planner.Context.WorldPosition and planner.Context.WorldPosition()
    if world then
        if world.mapID~=mesh:Metadata().worldMapID or math.abs(world.x-start.x)>5 or math.abs(world.z-start.z)>5 then
            clear(); setState("unknown-location","Map and world positions disagree"); return
        end
        start={x=world.x,z=world.z}
        if world.verticalStatus=="observed-altitude" then start.height=world.height end
    end
    local location,problem=mesh:Locate(start)
    if not location then clear(); setState("unknown-location",problem); return end
    display=trim(location)
    if display then setState("modeled",display.detail); return end
    if request then return end
    local attempt=signature..":"..location.id
    if lastAttempt==attempt then return end
    lastAttempt=attempt
    local speed=planner.Context.RunSpeed and planner.Context.RunSpeed()
    request,problem=mesh:Begin(start,goal,{maxWork=32768,speed=speed or 7})
    setState(request and "calculating" or "unknown-target",problem or "Calculating terrain corridor")
end
function terrain.Step()
    if not planner.enabled then clear(); setState("disabled","Quest planner is disabled"); return end
    if loader then
        local value,reason,done=loader:Step(32)
        if done then
            loader=nil; mesh=value
            setState(value and "ready" or "invalid",reason or "Terrain model ready")
            if value then update() end
        end
    elseif request then
        local result=request:Step(64)
        if result then
            request=nil
            if result.status=="modeled" then route=result; update()
            else display=nil; setState(result.status,result.detail) end
        end
    end
end
function terrain.Start()
    if driver then return end
    driver=CreateFrame("Frame")
    driver:SetScript("OnUpdate",function(_,delta)
        terrain.Step()
        elapsed=elapsed+delta
        if elapsed>=.2 then elapsed=0; if planner.enabled then update() end end
    end)
end
