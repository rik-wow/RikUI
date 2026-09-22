-- One walking request on the road network: quest-mesh legs at either end when
-- a patch covers that end, straight open-ground legs otherwise, and road A*
-- in between. Short trips inside one patch use the mesh directly.
local planner=RikUI.QuestPlanner
local navigate={}
planner.RoadNavigate=navigate

local GATEWAYS=3            -- nearest gateway nodes tried per end
local DIRECT_YARDS=240      -- try a mesh-only route when both ends are this close
local END_FRAME="end-frame" -- yielded after a synchronous addon load
local STEP_MS=4              -- per-frame time budget for one request
local MESH_OPTIONS={maxWork=262144,markerRadius=8,reachableApproach=true,commonApproach=true,uncertainVicinity=true}

-- Mesh searches return their result table from Step once finished.
local function meshLeg(mesh,from,to,marker)
    local begin=marker and mesh.BeginMarkerApproach or mesh.Begin
    local job=begin(mesh,from,to,MESH_OPTIONS)
    if not job then return nil end
    local result
    while true do
        result=job:Step(64,true)
        if result then break end
        coroutine.yield()
    end
    if result.status=="modeled" and result.walkPoints then return result end
end

-- Gateway nodes near point whose representative polygon is in the patch mesh.
local function gateways(graph,mesh,point)
    local out={}
    for _,row in ipairs(planner.RoadRoute.Attach(graph,point) or {}) do
        local polygon=graph:NodePolygon(row.node)
        if polygon and mesh:PathVertex(polygon) then out[#out+1]=row end
        if #out>=GATEWAYS then break end
    end
    return out
end

local function nodePoint(graph,n)
    local x,z,y=graph:Node(n)
    return {x=x,z=z,height=y}
end

local function legs(graph,mesh,point,toGoal,marker)
    if not mesh or not mesh:Locate(point) and not marker then return nil end
    local out={}
    for _,row in ipairs(gateways(graph,mesh,point)) do
        local node=nodePoint(graph,row.node)
        local result
        if toGoal then result=meshLeg(mesh,node,point,marker) else result=meshLeg(mesh,point,node,false) end
        if result then out[#out+1]={node=row.node,cost=result.meters,points=result.walkPoints,approach=result.approach} end
        coroutine.yield()
    end
    return #out>0 and out or nil
end

local function direct(mesh,start,goal,marker,speed)
    if not mesh or (start.x-goal.x)^2+(start.z-goal.z)^2>DIRECT_YARDS^2 or not mesh:Locate(start) then return nil end
    local result=meshLeg(mesh,start,goal,marker)
    if not result then return nil end
    local points,suffix,meters={}, {},0
    for i,p in ipairs(result.walkPoints) do points[i]={p[1],p[2],p[3]} end
    for i=#points,1,-1 do
        if i<#points then meters=meters+math.sqrt((points[i][1]-points[i+1][1])^2+(points[i][3]-points[i+1][3])^2) end
        suffix[i]=meters
    end
    return {status="modeled",points=points,suffix=suffix,meters=meters,seconds=meters/speed,road=true,meshOnly=true,
        approach=result.approach,revision=mesh:Revision(),nativeVerified=false,startLeg=0,goalLeg=0,
        detail="Quest mesh estimate; traversal unverified"}
end

-- start/goal: {x=,z=,height=?}. options.marker: goal is a quest marker vicinity.
function navigate.Begin(graph,view,start,goal,options)
    options=options or {}
    local speed=options.speed or 7
    if not graph or not view then return nil,"road network unavailable" end
    local cancelled,output=false,nil
    local worker=coroutine.create(function()
        local mesh
        local loader,why=planner.RoadPatches.Begin(graph,view,{start,goal})
        while not loader and why=="loading" do
            coroutine.yield(END_FRAME)  -- a patch addon was loaded; nothing more this frame
            loader,why=planner.RoadPatches.Begin(graph,view,{start,goal})
        end
        if loader then
            local value,reason
            while true do
                local v,r,done=loader:Step(16)
                if done then value,reason=v,r;break end
                coroutine.yield()
            end
            mesh=value
            if not mesh then return {status="invalid",detail=reason or "Quest mesh patch failed validation"} end
        elseif why~="no-patch" then
            return {status=why=="combat-loading-deferred" and "loading" or "unavailable",detail=why}
        end
        local shortcut=direct(mesh,start,goal,options.marker,speed)
        local sources=legs(graph,mesh,start,false,false)
        local targets=legs(graph,mesh,goal,true,options.marker)
        local job,problem=planner.RoadRoute.Begin(graph,start,goal,{speed=speed,sources=sources,targets=targets})
        if not job then return shortcut or {status="outside-coverage",detail=problem} end
        local networked
        while true do networked=job:Step(64);if networked then break end;coroutine.yield() end
        if shortcut and (networked.status~="modeled" or shortcut.meters<=networked.meters) then return shortcut end
        for _,row in ipairs(networked.meshGoal and targets or {}) do
            if row.node==networked.lastNode then networked.approach=row.approach end
        end
        return networked
    end)
    return {Cancel=function() cancelled=true end,Step=function(_,budget)
        if output then return output end
        if cancelled then return {status="cancelled",detail="Road request changed"} end
        -- Stop at a time budget as well as a step count: steps cost several
        -- times more in the client's Lua 5.1 than in LuaJIT.
        local clock=type(debugprofilestop)=="function" and debugprofilestop
        local started=clock and clock()
        for _=1,budget or 16 do
            if clock and clock()-started>=STEP_MS then return nil end
            local ok,value=coroutine.resume(worker)
            if not ok then output={status="invalid",detail="Road navigation failed: "..tostring(value)};return output end
            if coroutine.status(worker)=="dead" then output=value;return output end
            if value==END_FRAME then return nil,END_FRAME end
        end
    end}
end
