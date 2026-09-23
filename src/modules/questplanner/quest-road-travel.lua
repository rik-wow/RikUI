-- Travel planning across road networks: walking plus flights, boats, zeppelins
-- and the Deeprun Tram. Stops and links are compiled offline
-- (tools/terrain/travel_links.py) and attached to each world's network. A plan
-- walks the network to a stop, takes links, and walks from the last stop to
-- the goal. Flights need both flight points discovered and a shared faction.
-- Times are estimates; nothing here claims a transport is running.
local planner=RikUI.QuestPlanner
local schema,travel=planner.Schema,{}
planner.RoadTravel=travel

local RUN_SPEED=7              -- yd/s; road costs are road-weighted yards
local MAX_STOPS,MAX_LINKS=1024,4096
local ATTACH_RADIUS=192        -- yards searched for network nodes around an end
local ATTACH_NODES=6           -- nearest nodes an end may start from
local DIJKSTRA_SLICE=96        -- heap pops per step at most
local SLICE_MS=2               -- and at most this long, when the client clock is available
local KNOWN_REFRESH=30         -- seconds between discovered-flight reads
local CONTINENT_MAPS={1415,1414}  -- Eastern Kingdoms, Kalimdor
local MODES={flight=true,transport=true}
local KINDS={flight=true,dock=true,tram=true,elevator=true,portal=true}

local stops,links,byWorld={}, {}, {}
local known,knownAt={},nil

local function token(v) return schema.Text(v) and #v>0 and #v<=64 and v:match("^[%w_:%-]+$")~=nil end
local function point(p) return schema.List(p,3) and #p==3 and schema.Number(p[1],-100000,100000)
    and schema.Number(p[2],-100000,100000) and schema.Number(p[3],-100000,100000) end

-- Called by Roads.InstallIndex with the index's travel section.
function travel.Install(raw)
    if not schema.PlainTable(raw) or not schema.List(raw.stops,MAX_STOPS) or not schema.List(raw.links,MAX_LINKS) then
        return nil,"invalid travel section"
    end
    local nextStops,nextLinks,nextWorld={}, {}, {}
    for _,s in ipairs(raw.stops) do
        if not token(s.id) or not KINDS[s.kind] or not schema.Text(s.name) or not schema.Integer(s.world,0,100000)
            or not point(s.point) or nextStops[s.id] then return nil,"invalid travel stop" end
        nextStops[s.id]=s
        local list=nextWorld[s.world] or {};nextWorld[s.world]=list;list[#list+1]=s
    end
    for _,l in ipairs(raw.links) do
        if not token(l.id) or not MODES[l.mode] or not nextStops[l.from] or not nextStops[l.to]
            or not schema.Number(l.seconds,0,86400) or not schema.Number(l.wait,0,86400) then return nil,"invalid travel link" end
        nextLinks[#nextLinks+1]=l
    end
    stops,links,byWorld=nextStops,nextLinks,nextWorld
    return true
end

function travel.Stop(id) return stops[id] end
function travel.OnEvent(event)
    if event=="TAXIMAP_OPENED" or event=="TAXIMAP_CLOSED" or event=="PLAYER_ENTERING_WORLD" then knownAt=nil end
end

local function now() return type(GetTime)=="function" and GetTime() or 0 end

-- Discovered flight points (TaxiNodes IDs), read from the client's taxi map API.
local function discovered()
    if knownAt and now()-knownAt<KNOWN_REFRESH then return known end
    local read=type(C_TaxiMap)=="table" and C_TaxiMap.GetTaxiNodesForMap
    local found={}
    if type(read)=="function" then
        for _,mapID in ipairs(CONTINENT_MAPS) do
            local ok,rows=pcall(read,mapID)
            if ok and type(rows)=="table" then
                for _,row in ipairs(rows) do
                    local undiscovered=type(row)=="table" and row.isUndiscovered
                    if not RikUI.Secret.IsSecret(undiscovered) and undiscovered==false and schema.ID(row.nodeID) then
                        found[row.nodeID]=true
                    end
                end
            end
        end
    end
    known,knownAt=found,now()
    return known
end
function travel.Discovered() return schema.Clone(discovered()) end

local function playerFaction()
    local ok,group=pcall(UnitFactionGroup or function() end,"player")
    return ok and (group=="Alliance" and "alliance" or group=="Horde" and "horde") or nil
end

local function usable(link,faction,flights)
    if link.mode~="flight" then return true end
    local a,b=stops[link.from],stops[link.to]
    if not (a.taxiNode and b.taxiNode and flights[a.taxiNode] and flights[b.taxiNode]) then return false end
    for _,side in ipairs(link.factions or {}) do if side==faction then return true end end
    return false
end

-- Min-heap of {cost,key}.
local function push(heap,cost,key)
    local i=#heap+1;heap[i]={cost,key}
    while i>1 do
        local p=math.floor(i/2)
        if heap[p][1]<=heap[i][1] then break end
        heap[p],heap[i]=heap[i],heap[p];i=p
    end
end
local function pop(heap)
    local top,last=heap[1],table.remove(heap)
    if #heap==0 then return top end
    heap[1]=last
    local i=1
    while true do
        local l,r,s=i*2,i*2+1,i
        if heap[l] and heap[l][1]<heap[s][1] then s=l end
        if heap[r] and heap[r][1]<heap[s][1] then s=r end
        if s==i then break end
        heap[s],heap[i]=heap[i],heap[s];i=s
    end
    return top
end

-- Nearest network nodes to a point, with straight-line yards.
local function endNodes(graph,p)
    local size=graph.cellYards
    local cx,cz=math.floor(p.x/size),math.floor(p.z/size)
    local rows={}
    local reach=math.ceil(ATTACH_RADIUS/size)
    for dx=-reach,reach do for dz=-reach,reach do
        for _,n in ipairs(graph:CellNodes(cx+dx,cz+dz)) do
            local x,z=graph:Node(n)
            local d=math.sqrt((x-p.x)^2+(z-p.z)^2)
            if d<=ATTACH_RADIUS then rows[#rows+1]={n,d} end
        end
    end end
    table.sort(rows,function(a,b) return a[2]<b[2] end)
    for i=#rows,ATTACH_NODES+1,-1 do rows[i]=nil end
    return rows
end

-- Sliced multi-source Dijkstra; Step returns the node->cost table when done.
-- Road edges are near-symmetric, so a search from the goal stands in for the
-- reverse search.
local function spread(graph,sources,wanted)
    local dist,heap,remaining={}, {},0
    for n in pairs(wanted) do remaining=remaining+1 end
    for _,row in ipairs(sources) do
        local cost=row[2]
        if not dist[row[1]] or cost<dist[row[1]] then dist[row[1]]=cost;push(heap,cost,row[1]) end
    end
    local settled={}
    return {Step=function()
        local clock=type(debugprofilestop)=="function" and debugprofilestop
        local began=clock and clock()
        for _=1,DIJKSTRA_SLICE do
            if clock and clock()-began>=SLICE_MS then return end
            local top=#heap>0 and pop(heap)
            if not top or remaining==0 then return dist end
            local d,n=top[1],top[2]
            if not settled[n] and d<=dist[n] then
                settled[n]=true
                if wanted[n] then remaining=remaining-1 end
                local first,last=graph:EdgeRange(n)
                for e=first,last do
                    local m,cost=graph:Edge(e)
                    local nd=d+cost
                    if not dist[m] or nd<dist[m] then dist[m]=nd;push(heap,nd,m) end
                end
            end
        end
    end}
end

local function stopNodes(graph)
    local section=graph.catalog.travel
    local rows={}
    for index,row in ipairs(section and section.stops or {}) do
        if stops[row.id] then rows[#rows+1]={index=index,id=row.id,node=row.node,yards=row.yards} end
    end
    return rows
end

-- Walking seconds between two stops in the same world, from the catalog.
local function walkTable(graph,rows)
    local byIndex={}
    for _,row in ipairs(rows) do byIndex[row.index]=row end
    local out={}
    for _,w in ipairs(graph.catalog.travel and graph.catalog.travel.walks or {}) do
        local a,b=byIndex[w[1]],byIndex[w[2]]
        if a and b then
            local list=out[a.id] or {};out[a.id]=list
            list[#list+1]={to=b.id,seconds=(w[3]+a.yards+b.yards)/RUN_SPEED}
        end
    end
    return out
end

-- Stop-level search over start, goal and stops. Returns legs.
local function stopSearch(fromStart,toGoal,direct,walks,faction,flights)
    local adj={}
    local function add(from,edge) local list=adj[from] or {};adj[from]=list;list[#list+1]=edge end
    for id,seconds in pairs(fromStart) do add("start",{to=id,seconds=seconds,mode="walk"}) end
    for id,seconds in pairs(toGoal) do add(id,{to="goal",seconds=seconds,mode="walk"}) end
    if direct then add("start",{to="goal",seconds=direct,mode="walk"}) end
    for _,table_ in pairs(walks) do
        for from,list in pairs(table_) do for _,w in ipairs(list) do add(from,{to=w.to,seconds=w.seconds,mode="walk"}) end end
    end
    for _,l in ipairs(links) do
        if usable(l,faction,flights) then add(l.from,{to=l.to,seconds=l.seconds+l.wait,wait=l.wait,mode=l.mode,link=l}) end
    end
    local dist,prev,heap,done={start=0},{}, {},{}
    push(heap,0,"start")
    while #heap>0 do
        local top=pop(heap);local d,key=top[1],top[2]
        if not done[key] then
            done[key]=true
            if key=="goal" then break end
            for _,e in ipairs(adj[key] or {}) do
                local nd=d+e.seconds
                if not dist[e.to] or nd<dist[e.to] then dist[e.to]=nd;prev[e.to]={from=key,edge=e};push(heap,nd,e.to) end
            end
        end
    end
    if not dist.goal then return nil end
    local legs,key={},"goal"
    while prev[key] do
        local p=prev[key]
        table.insert(legs,1,{mode=p.edge.mode,from=p.from,to=key,seconds=p.edge.seconds,wait=p.edge.wait,link=p.edge.link})
        key=p.from
    end
    -- Consecutive walks (start -> stop -> stop on foot) collapse to one walk leg.
    local merged={}
    for _,leg in ipairs(legs) do
        local last=merged[#merged]
        if last and last.mode=="walk" and leg.mode=="walk" then last.to=leg.to;last.seconds=last.seconds+leg.seconds
        else merged[#merged+1]=leg end
    end
    return merged,dist.goal
end

local function describe(leg)
    local to=stops[leg.to]
    if leg.mode=="flight" then return "Fly to "..to.name:gsub(",.*$","") end
    if leg.mode=="transport" then
        if leg.link.vehicle=="tram" then return "Ride the Deeprun Tram to "..to.name end
        if leg.link.vehicle=="lift" then
            return "Take the "..to.name:gsub(" %(%a+%)$","").." "..(leg.link.direction or "up")
        end
        if leg.link.vehicle=="portal" then return "Step through "..stops[leg.from].name end
        return "Take the "..(leg.link.vehicle=="zeppelin" and "zeppelin" or "boat").." to "..to.name
    end
    if leg.to=="goal" then return "Walk to the destination" end
    if to.kind=="flight" then return "Walk to the flight master at "..to.name:gsub(",.*$","") end
    if to.kind=="tram" then return "Walk to the Deeprun Tram in "..to.name:gsub(",.*$","") end
    if to.kind=="elevator" then return "Walk to the "..to.name:gsub(" %(%a+%)$","") end
    return "Walk to "..to.name
end

--[[ Begin(graphs, start, goal): graphs = {[world]=graph}, start/goal = {world,x,z}.
Step(budget) returns nil while working, then {status, legs, seconds}. ]]
function travel.Begin(graphs,start,goal)
    local sg,gg=graphs[start.world],graphs[goal.world]
    if not sg or not gg then return nil,"travel graph missing" end
    local faction,flights=playerFaction(),discovered()
    local startStops,goalStops=stopNodes(sg),stopNodes(gg)
    local function wantedFor(rows,extra)
        local set={};for _,r in ipairs(rows) do set[r.node]=true end
        for _,r in ipairs(extra or {}) do set[r[1]]=true end
        return set
    end
    local startEnds,goalEnds=endNodes(sg,start),endNodes(gg,goal)
    -- After a lift or portal the player is at that link's destination stop: start
    -- there, on the right level, instead of at whichever stacked floor is nearest.
    if start.stop then
        for _,row in ipairs(startStops) do if row.id==start.stop then startEnds={{row.node,row.yards}} end end
    end
    if #startEnds==0 then return nil,"start is off the road network" end
    if #goalEnds==0 then return nil,"destination is off the road network" end
    local sameWorld=start.world==goal.world
    local forward=spread(sg,startEnds,wantedFor(startStops,sameWorld and goalEnds))
    local backward=spread(gg,goalEnds,wantedFor(goalStops))
    local fromDist,toDist,result
    return {Step=function()
        if result then return result end
        if not fromDist then fromDist=forward:Step();return end
        if not toDist then toDist=backward:Step();return end
        local fromStart,toGoal={},{}
        for _,r in ipairs(startStops) do
            if fromDist[r.node] then fromStart[r.id]=(fromDist[r.node]+r.yards)/RUN_SPEED end
        end
        for _,r in ipairs(goalStops) do
            if toDist[r.node] then toGoal[r.id]=(toDist[r.node]+r.yards)/RUN_SPEED end
        end
        local direct
        if sameWorld then
            for _,row in ipairs(goalEnds) do
                local d=fromDist[row[1]]
                if d then d=(d+row[2])/RUN_SPEED;if not direct or d<direct then direct=d end end
            end
        end
        local walks={}
        for world,graph in pairs(graphs) do walks[world]=walkTable(graph,stopNodes(graph)) end
        local legs,seconds=stopSearch(fromStart,toGoal,direct,walks,faction,flights)
        if not legs then
            result={status="no-known-path",detail="No walking or travel connection is known to this destination"}
        else
            for _,leg in ipairs(legs) do leg.text=describe(leg);leg.stop=stops[leg.to] end
            result={status="planned",legs=legs,seconds=seconds,walkOnly=#legs==1 and legs[1].mode=="walk"}
        end
        return result
    end}
end

-- Worlds a plan between two worlds may pass through: both ends plus any world
-- with a stop linked from either end's world.
function travel.Worlds(startWorld,goalWorld)
    -- A trip within one world uses its own stops, flights and ferries only.
    if startWorld==goalWorld then return {startWorld} end
    local set={[startWorld]=true,[goalWorld]=true}
    for _,l in ipairs(links) do
        local a,b=stops[l.from],stops[l.to]
        if set[a.world] or set[b.world] then set[a.world]=true;set[b.world]=true end
    end
    local out={}
    for world in pairs(set) do out[#out+1]=world end
    table.sort(out)
    return out
end

function travel.Count() local n=0;for _ in pairs(stops) do n=n+1 end;return n,#links end
