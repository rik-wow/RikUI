-- Deterministic bounded A* over explicit portals, with an admissible center-distance bound.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local geometry,search=planner.NavGeometry,{}
planner.NavSearch=search
local MAX_WORK,MAX_PATH=65536,1024
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
local function run(job)
    while #job.heap>0 do
        if job.work>=job.maxWork then return response(job,"budget-exhausted","navigation work limit") end
        local current=pop(job.heap)
        job.work=job.work+1
        if current.cost==job.distance[current.id] and not job.closed[current.id] then
            job.closed[current.id]=true; job.visited=job.visited+1
            if current.id==job.goal.id then return finish(job) end
            for _,portal in ipairs(job.data.polygons[current.id].portals) do
                if job.work>=job.maxWork then return response(job,"budget-exhausted","navigation work limit") end
                job.work=job.work+1
                local cost=current.cost+portal.meters
                if not job.closed[portal.to] and (job.distance[portal.to]==nil or cost<job.distance[portal.to]) then
                    job.distance[portal.to]=cost
                    job.previous[portal.to]={from=current.id,portal=portal}
                    push(job.heap,{id=portal.to,cost=cost,priority=cost+geometry.Distance(job.data.polygons[portal.to].center,job.data.polygons[job.goal.id].center)})
                end
                coroutine.yield()
            end
        end
        coroutine.yield()
    end
    return response(job,"no-known-path","No connected corridor in this datasource")
end
function search.Begin(data,start,goal,options,locate)
    local settings=schema.Copy(options or {})
    if not schema.PlainTable(settings) then return nil,"invalid navigation policy" end
    local maxWork,speed=settings.maxWork or 16384,settings.speed or 7
    if not schema.Integer(maxWork,1,MAX_WORK) or not schema.Number(speed,.1,100) then return nil,"invalid navigation limits" end
    local first,problem=locate(data,start)
    if not first then return nil,problem end
    local last,failure=locate(data,goal)
    if not last then return nil,failure end
    local job={data=data,start=first,goal=last,maxWork=maxWork,speed=speed,work=0,visited=0,
        heap={},distance={},previous={},closed={}}
    job.distance[first.id]=geometry.Distance(first.point,data.polygons[first.id].center)
    push(job.heap,{id=first.id,cost=job.distance[first.id],priority=job.distance[first.id]+geometry.Distance(data.polygons[first.id].center,data.polygons[last.id].center)})
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
