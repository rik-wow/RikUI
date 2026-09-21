-- Deterministic bounded A* over explicit portals, with an admissible center-distance bound.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local geometry,search=planner.NavGeometry,{}
planner.NavSearch=search
-- Each directed edge can insert at most one heap entry and is expanded once.
-- Two operations per edge plus the initial pop bound complete finite-graph work.
local MAX_WORK,MAX_PATH=262145,1024
local function less(a,b) return a.priority<b.priority or (a.priority==b.priority and a.id<b.id) end
local function push(heap,value)
    local index=#heap+1
    while index>1 do
        local parent=math.floor(index/2)
        if not less(value,heap[parent]) then break end
        heap[index],index=heap[parent],parent
    end
    heap[index]=value
end
local function pop(heap)
    local result,last=heap[1],table.remove(heap)
    if #heap==0 then return result end
    local index=1
    while index*2<=#heap do
        local child=index*2
        if child<#heap and less(heap[child+1],heap[child]) then child=child+1 end
        if not less(heap[child],last) then break end
        heap[index],index=heap[child],child
    end
    heap[index]=last
    return result
end
local function response(job,status,detail)
    return {status=status,detail=detail,metrics={work=job.work,visited=job.visited},
        confidence="derived-model",nativeVerified=false,revision=job.data.meta.revision}
end
local function attachCorridor(job,order,result)
    result.corridor,result.portals,result.surfaces={},{},{}
    for index=#order,1,-1 do
        local id=order[index]
        result.corridor[#result.corridor+1]=id
        result.surfaces[#result.surfaces+1]=schema.Clone(job.data.polygons[id].points)
        if index<#order then result.portals[#result.portals+1]=schema.Clone(job.previous[id].portal) end
    end
end
local function finish(job)
    local order,id={},job.goal.id
    while id do
        if #order>=MAX_PATH then return response(job,"budget-exhausted","path output limit") end
        order[#order+1]=id
        id=job.previous[id] and job.previous[id].from
    end
    local points={schema.Clone(job.start.point)}
    if #order>1 then
        points[#points+1]=schema.Clone(job.data.polygons[job.start.id].center)
        for index=#order-1,1,-1 do
            points[#points+1]=schema.Clone(job.previous[order[index]].portal.midpoint)
            points[#points+1]=schema.Clone(job.data.polygons[order[index]].center)
        end
    end
    points[#points+1]=schema.Clone(job.goal.point)
    local meters=0
    for index=2,#points do meters=meters+geometry.Distance(points[index-1],points[index]) end
    local result=response(job,"modeled","Terrain corridor estimate; game traversal is unverified")
    result.points,result.meters,result.seconds=points,meters,meters/job.speed
    attachCorridor(job,order,result)
    result.shortestWithinCenterGraph=true
    result.globalOptimal=false
    return result
end
local function reachableApproach(job)
    local best
    for _,value in ipairs(job.alternatives or {}) do
        if job.closed[value.id] and (not best or value.gap<best.gap
            or (value.gap==best.gap and value.id<best.id)) then best=value end
        coroutine.yield()
    end
    if not best then return response(job,"no-known-path","No connected corridor in this datasource") end
    job.goal=best
    local result=finish(job)
    if result.status=="modeled" then
        result.approach={kind="observed-marker-reachable-vicinity",marker=schema.Clone(job.marker),
            gap=best.gap,radius=job.radius,finalLegVerified=false,interactionVerified=false,
            reason="exact-marker-disconnected"}
        result.detail="Reachable approach; final gap is outside the connected walking model"
    end
    return result
end
-- Ambiguous map markers may share an approach, but never select one floor by cost.
local COMMON_APPROACH_RADIUS=64
local function ancestors(job,id)
    local result,count={},0
    while id do
        count=count+1
        if count>MAX_PATH then return nil end
        result[id]=true;id=job.previous[id] and job.previous[id].from
        coroutine.yield()
    end
    return result
end
local function commonEndpoint(job)
    local shared=ancestors(job,job.goals[1].id)
    if not shared then return nil,"path output limit" end
    for index=2,#job.goals do
        local other=ancestors(job,job.goals[index].id)
        if not other then return nil,"path output limit" end
        for id in pairs(shared) do
            if not other[id] then shared[id]=nil end
            coroutine.yield()
        end
    end
    local id=job.goals[1].id
    while id and id~=job.start.id do
        local center=job.data.polygons[id].center
        local gap=math.sqrt((center[1]-job.marker.x)^2+(center[3]-job.marker.z)^2)
        if shared[id] and gap<=COMMON_APPROACH_RADIUS then
            local unique=job.locate(job.data,{x=center[1],z=center[3]})
            if unique and unique.id==id then return {id=id,point=schema.Clone(center),gap=gap} end
        end
        id=job.previous[id] and job.previous[id].from
        coroutine.yield()
    end
    return nil,"No shared approach to the uncertain marker floors"
end
local function commonApproach(job)
    local endpoint,reason=commonEndpoint(job)
    if not endpoint then return response(job,"unknown-target",reason) end
    job.goal=endpoint
    local result=finish(job)
    if result.status=="modeled" then
        result.approach={kind="observed-marker-common-approach",marker=schema.Clone(job.marker),
            gap=endpoint.gap,radius=COMMON_APPROACH_RADIUS,floorCount=#job.goals,
            finalLegVerified=false,interactionVerified=false,reason="marker-floor-ambiguous"}
        result.detail="Shared approach to marker floors; choose the quest floor nearby"
    end
    return result
end
local function reached(job,id)
    if not job.goals then return id==job.goal.id and finish(job) or nil end
    if job.pendingGoals[id] then job.pendingGoals[id]=nil;job.remaining=job.remaining-1 end
    if job.remaining==0 then return commonApproach(job) end
end
local function heuristic(job,id)
    if job.goals then return 0 end -- One Dijkstra tree gives consistent shared prefixes.
    return geometry.Distance(job.data.polygons[id].center,job.data.polygons[job.goal.id].center)
end
local function run(job)
    while #job.heap>0 do
        if job.work>=job.maxWork then return response(job,"budget-exhausted","navigation work limit") end
        local current=pop(job.heap)
        job.work=job.work+1
        if current.cost==job.distance[current.id] and not job.closed[current.id] then
            job.closed[current.id]=true; job.visited=job.visited+1
            local result=reached(job,current.id)
            if result then return result end
            for _,portal in ipairs(job.data.polygons[current.id].portals) do
                if job.work>=job.maxWork then return response(job,"budget-exhausted","navigation work limit") end
                job.work=job.work+1
                local cost=current.cost+portal.meters
                if not job.closed[portal.to] and (job.distance[portal.to]==nil or cost<job.distance[portal.to]) then
                    job.distance[portal.to]=cost
                    job.previous[portal.to]={from=current.id,portal=portal}
                    push(job.heap,{id=portal.to,cost=cost,priority=cost+heuristic(job,portal.to)})
                end
                coroutine.yield()
            end
        end
        coroutine.yield()
    end
    if job.goals then return response(job,"unknown-target","Not all marker floors have a connected approach") end
    return reachableApproach(job)
end
local function copyGoals(data,goals)
    if not schema.List(goals,4) or #goals<2 then return nil end
    local result,seen={},{}
    for _,value in ipairs(goals) do
        if not schema.PlainTable(value) or not data.polygons[value.id]
            or seen[value.id] or not geometry.Point(value.point) then return nil end
        seen[value.id]=true;result[#result+1]={id=value.id,point=schema.Clone(value.point)}
    end
    return result
end
local function handle(job)
    local worker=coroutine.create(function() return run(job) end)
    local cancelled,output=false,nil
    return {
        Cancel=function() cancelled=true end,
        Step=function(_,budget)
            if cancelled then return response(job,"cancelled","navigation request changed") end
            if output then return schema.Clone(output) end
            if not schema.Integer(budget or 32,1,128) then return nil,"invalid navigation slice" end
            for _=1,budget or 32 do
                local ok,result=coroutine.resume(worker)
                if not ok then output=response(job,"invalid","navigation search failed"); return schema.Clone(output) end
                if coroutine.status(worker)=="dead" then output=result; return schema.Clone(output) end
            end
        end,
    }
end
local function seed(job)
    if job.goals then
        job.pendingGoals={};job.remaining=#job.goals
        for _,value in ipairs(job.goals) do job.pendingGoals[value.id]=true end
    end
    local first=job.start
    job.distance[first.id]=geometry.Distance(first.point,job.data.polygons[first.id].center)
    push(job.heap,{id=first.id,cost=job.distance[first.id],priority=job.distance[first.id]+heuristic(job,first.id)})
    return handle(job)
end
function search.Begin(data,start,goal,options,locate,alternatives,commonGoals)
    local settings=schema.Copy(options or {})
    if not schema.PlainTable(settings) then return nil,"invalid navigation policy" end
    local maxWork,speed=settings.maxWork or 16384,settings.speed or 7
    if not schema.Integer(maxWork,1,MAX_WORK) or not schema.Number(speed,.1,100) then return nil,"invalid navigation limits" end
    local first,problem=locate(data,start)
    if not first then return nil,problem end
    local last,failure=locate(data,goal)
    if commonGoals then
        commonGoals=copyGoals(data,commonGoals)
        if not commonGoals then return nil,"invalid marker floors" end
        last=commonGoals[1]
    end
    if not last then return nil,failure end
    local job={data=data,start=first,goal=last,maxWork=maxWork,speed=speed,work=0,visited=0,
        heap={},distance={},previous={},closed={},alternatives=alternatives,
        marker=(alternatives or commonGoals) and schema.Clone(goal),radius=settings.markerRadius or 1,
        goals=commonGoals,locate=locate}
    return seed(job)
end
