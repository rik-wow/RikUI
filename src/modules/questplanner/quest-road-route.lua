-- Sliced A* over a compiled road walk network.
-- Endpoints attach to nodes of their own and neighbouring cells by an explicit
-- open-ground leg; the returned route labels that leg. Road preference comes
-- only from the network's precomputed costs. Output is modeled, not verified.
local planner=RikUI.QuestPlanner
local schema,route=planner.Schema,{}
planner.RoadRoute=route

local ATTACH_RINGS=2        -- search 3x3 cells, then 5x5, for attachment nodes
local ATTACH_LIMIT=8        -- nearest candidates kept per endpoint
local MAX_EXPANSIONS=400000
local DEFAULT_SPEED=7

local function dist(ax,az,bx,bz) return math.sqrt((ax-bx)^2+(az-bz)^2) end

local function attach(graph,point)
    local cell=graph.cellYards
    local cx,cz=math.floor(point.x/cell),math.floor(point.z/cell)
    for ring=1,ATTACH_RINGS do
        local found={}
        for dx=-ring,ring do for dz=-ring,ring do
            for _,n in ipairs(graph:CellNodes(cx+dx,cz+dz)) do
                local x,z=graph:Node(n)
                found[#found+1]={node=n,cost=dist(point.x,point.z,x,z)}
            end
        end end
        if #found>0 then
            table.sort(found,function(a,b) return a.cost<b.cost or a.cost==b.cost and a.node<b.node end)
            for i=#found,ATTACH_LIMIT+1,-1 do found[i]=nil end
            return found
        end
    end
end

-- Nearest network nodes around a point, for open-ground legs and gateway choice.
route.Attach=attach

local Heap={}
Heap.__index=Heap
local function heap() return setmetatable({n=0},Heap) end
function Heap:push(cost,node)
    local n=self.n+1;self.n=n;self[n]={cost,node}
    while n>1 do
        local p=math.floor(n/2)
        if self[p][1]<=self[n][1] then break end
        self[p],self[n]=self[n],self[p];n=p
    end
end
function Heap:pop()
    if self.n==0 then return nil end
    local top=self[1];self[1]=self[self.n];self[self.n]=nil;self.n=self.n-1
    local i=1
    while true do
        local l,r,s=i*2,i*2+1,i
        if l<=self.n and self[l][1]<self[s][1] then s=l end
        if r<=self.n and self[r][1]<self[s][1] then s=r end
        if s==i then break end
        self[i],self[s]=self[s],self[i];i=s
    end
    return top[1],top[2]
end

-- Polyline of one edge from its source node, as {x,y,z} points excluding the source.
local function edgePoints(graph,from,e,out)
    local target,_,_,count,first=graph:Edge(e)
    local fx,fz,fy=graph:Node(from)
    local tx,tz,ty=graph:Node(target)
    local total=dist(fx,fz,tx,tz)
    for k=first,first+count-1 do
        local dx,dz=graph:Point(k)
        local x,z=fx+dx,fz+dz
        local q=total>0 and math.min(1,dist(fx,fz,x,z)/total) or 0
        out[#out+1]={x,fy+(ty-fy)*q,z}
    end
    out[#out+1]={tx,ty,tz}
end

-- Joins of mesh legs and network edges can leave a spur: the line reaches a
-- node center and immediately doubles back. A vertex where the path reverses
-- by at least 150 degrees is dropped; the shortcut runs back along the same line.
local SPUR_COS=-0.866
local function trimSpurs(points)
    local changed=true
    while changed do
        changed=false
        for i=#points-1,2,-1 do
            local a,b,c=points[i-1],points[i],points[i+1]
            local ux,uz,vx,vz=b[1]-a[1],b[3]-a[3],c[1]-b[1],c[3]-b[3]
            local lu,lv=math.sqrt(ux*ux+uz*uz),math.sqrt(vx*vx+vz*vz)
            if lu==0 or lv==0 or (ux*vx+uz*vz)/(lu*lv)<=SPUR_COS then
                table.remove(points,i);changed=true
            end
        end
    end
end
route.TrimSpurs=trimSpurs

local function append(points,leg)
    for i=2,#leg do points[#points+1]={leg[i][1],leg[i][2],leg[i][3]} end
end

local function assemble(graph,start,goal,parents,last,legs,speed)
    local nodes={}
    local n=last
    while n do nodes[#nodes+1]=n;n=parents[n] and parents[n].node end
    local first=nodes[#nodes]
    local fx,fz,fy=graph:Node(first)
    local points
    if legs.source[first] then
        points={};local leg=legs.source[first]
        points[1]={leg[1][1],leg[1][2],leg[1][3]};append(points,leg)
    else
        points={{start.x,start.height or fy,start.z},{fx,fy,fz}}
    end
    for i=#nodes-1,1,-1 do edgePoints(graph,nodes[i+1],parents[nodes[i]].edge,points) end
    if legs.target[last] then append(points,legs.target[last])
    else points[#points+1]={goal.x,goal.height or points[#points][2],goal.z} end
    trimSpurs(points)
    local meters,suffix=0,{}
    for i=#points,1,-1 do
        if i<#points then meters=meters+dist(points[i][1],points[i][3],points[i+1][1],points[i+1][3]) end
        suffix[i]=meters
    end
    local lx,lz=graph:Node(last)
    return {status="modeled",points=points,suffix=suffix,meters=meters,seconds=meters/speed,nodes=#nodes,
        startLeg=not legs.source[first] and dist(start.x,start.z,fx,fz) or 0,
        goalLeg=not legs.target[last] and dist(goal.x,goal.z,lx,lz) or 0,
        meshStart=legs.source[first]~=nil,meshGoal=legs.target[last]~=nil,firstNode=first,lastNode=last,
        revision=graph.revision,road=true,nativeVerified=false,
        detail=(legs.source[first] and legs.target[last]) and "Road network and quest mesh estimate; traversal unverified"
            or "Road network estimate; open-ground legs and traversal unverified"}
end

-- start/goal: {x=,z=,height=?}. Returns a job whose Step(budget) yields a result table.
function route.Begin(graph,start,goal,options)
    options=options or {}
    local speed=options.speed or DEFAULT_SPEED
    if not graph or not schema.PlainTable(start) or not schema.PlainTable(goal)
        or not schema.Number(start.x,-100000,100000) or not schema.Number(goal.x,-100000,100000)
        or not schema.Number(speed,.1,100) then return nil,"invalid road request" end
    -- options.sources/targets: {node=,cost=,points=} legs already walked on quest mesh.
    local sources,targets=options.sources or attach(graph,start),options.targets or attach(graph,goal)
    if not sources or #sources==0 then return nil,"start-outside-road-network" end
    if not targets or #targets==0 then return nil,"goal-outside-road-network" end
    local legs={source={},target={}}
    for _,s in ipairs(sources) do if s.points then legs.source[s.node]=s.points end end
    local finish={}
    for _,t in ipairs(targets) do finish[t.node]=t.cost;if t.points then legs.target[t.node]=t.points end end
    local factor=1-graph.roadBonus
    local function h(n) local x,z=graph:Node(n);return factor*dist(x,z,goal.x,goal.z) end
    local best,parents,open,closed={}, {}, heap(), {}
    for _,s in ipairs(sources) do best[s.node]=s.cost;open:push(s.cost+h(s.node),s.node) end
    local work,cancelled,result=0,false,nil
    local bestTotal,bestNode=math.huge,nil
    local function step()
        local f,n=open:pop()
        if not n then return true end
        if f>=bestTotal then return true end
        if closed[n] then return false end
        closed[n]=true;work=work+1
        if finish[n] and best[n]+finish[n]<bestTotal then bestTotal,bestNode=best[n]+finish[n],n end
        local first,last=graph:EdgeRange(n)
        for e=first,last do
            local target,cost=graph:Edge(e)
            local g=best[n]+cost
            if not closed[target] and g<(best[target] or math.huge) then
                best[target]=g;parents[target]={node=n,edge=e};open:push(g+h(target),target)
            end
        end
        return false
    end
    return {Cancel=function() cancelled=true end,Progress=function() return work end,Step=function(_,budget)
        if result then return result end
        if cancelled then return {status="cancelled",detail="Road request changed"} end
        for _=1,budget or 64 do
            if work>=MAX_EXPANSIONS then result={status="budget-exhausted",detail="Road search limit"};return result end
            if step() then
                result=bestNode and assemble(graph,start,goal,parents,bestNode,legs,speed)
                    or {status="no-known-path",detail="No connected road network route"}
                result.cost=bestNode and bestTotal or nil
                result.metrics={work=work}
                return result
            end
        end
    end}
end
