-- Strategic time estimates from the always-loaded road index. These are costs,
-- not verified walking routes; the road follower remains responsible for guidance.
local planner=RikUI.QuestPlanner
local schema,estimate=planner.Schema,{}
planner.TravelEstimate=estimate
local DEFAULT_RATE,CELL,NEAREST=1.3/7,8,6
local emptyIndex,emptyStops,emptyLinks={byMap={},worlds={}},{},{}
local sourceCache,graphCache

-- Stable source fingerprint, independent of Lua table order and reloads.
local function digest(value)
    local a,b=1,0
    local function feed(s)
        for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end
    end
    local function visit(v)
        local kind=type(v);feed(kind..":")
        if kind=="table" then
            local keys={};for k in pairs(v) do keys[#keys+1]=k end
            table.sort(keys,function(x,y) return type(x)==type(y) and x<y or type(x)<type(y) end)
            for _,k in ipairs(keys) do visit(k);visit(v[k]) end
            feed(";")
        else local s=kind=="number" and string.format("%.17g",v) or tostring(v);feed(#s..":"..s) end
    end
    visit(value);return string.format("%04x%04x",b,a)
end
local function source()
    local index=planner.Roads and planner.Roads.EstimateIndex() or emptyIndex
    local stops,links=emptyStops,emptyLinks
    if planner.RoadTravel then stops,links=planner.RoadTravel.EstimateSource() end
    if not sourceCache or sourceCache.index~=index or sourceCache.stops~=stops or sourceCache.links~=links then
        sourceCache={index=index,stops=stops,links=links,revision=digest({index=index,stops=stops,links=links})}
        graphCache=nil
    end
    return sourceCache
end
function estimate.Capture(state,mapSizes)
    local rates={}
    local prefix=tostring(state.identity and state.identity.build)..":"
    for _,model in pairs(planner.PlanLearning and planner.PlanLearning.Export().models or {}) do
        if model.kind=="travel" and model.context:sub(1,#prefix)==prefix then
            local map=tonumber(model.context:sub(#prefix+1):match("^(%d+):foot$"))
            if map and schema.Number(model.mean,.01,5) then rates[map]=model.mean end
        end
    end
    local flights=planner.RoadTravel and planner.RoadTravel.Discovered() or {}
    return {version=1,indexRevision=source().revision,faction=string.lower(state.faction or ""),
        flights=flights,flightDigest=digest(flights),rates=rates,defaultRate=DEFAULT_RATE,mapSizes=schema.Clone(mapSizes or {})}
end
local function valid(model)
    if not schema.PlainTable(model) or model.version~=1 or not schema.Text(model.indexRevision)
        or not schema.Text(model.faction) or not schema.PlainTable(model.flights) or not schema.PlainTable(model.rates)
        or not schema.Number(model.defaultRate,.01,5) or not schema.PlainTable(model.mapSizes) then return false end
    for id,value in pairs(model.flights) do if not schema.ID(id) or value~=true then return false end end
    for id,rate in pairs(model.rates) do if not schema.ID(id) or not schema.Number(rate,.01,5) then return false end end
    for id,size in pairs(model.mapSizes) do
        if not schema.ID(id) or not schema.List(size,2) or #size~=2
            or not schema.Number(size[1],1,200000) or not schema.Number(size[2],1,200000) then return false end
    end
    return model.flightDigest==digest(model.flights)
end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2) end
local function buildGraph(src,model)
    local key=digest({model.faction,model.flights,model.rates,model.defaultRate})
    if graphCache and graphCache.source==src and graphCache.key==key then return graphCache end
    local graph={source=src,key=key,stops={},byID={},byWorld={},links={},distances={},order={},runs=0}
    local ids={};for id in pairs(src.stops) do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids) do
        local s=src.stops[id];local n=#graph.stops+1
        graph.stops[n]={id=id,world=s.world,x=s.point[1],z=s.point[3]}
        graph.byID[id]=n;graph.links[n]={}
        local list=graph.byWorld[s.world] or {};graph.byWorld[s.world]=list;list[#list+1]=n
    end
    graph.rates={}
    local maps={};for map in pairs(model.rates) do maps[#maps+1]=map end;table.sort(maps)
    local sums,counts={},{}
    for _,map in ipairs(maps) do
        local seen={}
        for _,view in ipairs(src.index.byMap[map] or {}) do
            if not seen[view.world] then
                local w=view.world;seen[w]=true;sums[w]=(sums[w] or 0)+model.rates[map];counts[w]=(counts[w] or 0)+1
            end
        end
    end
    for w,sum in pairs(sums) do graph.rates[w]=sum/counts[w] end
    for _,link in ipairs(src.links) do
        if planner.RoadTravel.Usable(link,model.faction,model.flights) then
            local a,b=graph.byID[link.from],graph.byID[link.to]
            graph.links[a][#graph.links[a]+1]={to=b,seconds=link.seconds+link.wait}
        end
    end
    graphCache=graph;return graph
end
local function distances(graph,start,defaultRate)
    if graph.distances[start] then return graph.distances[start] end
    local dist,done={[start]=0},{}
    for _=1,#graph.stops do
        local at,best=nil,math.huge
        for n=1,#graph.stops do if not done[n] and (dist[n] or math.huge)<best then at,best=n,dist[n] end end
        if not at then break end
        done[at]=true
        local s=graph.stops[at];local rate=graph.rates[s.world] or defaultRate
        for _,n in ipairs(graph.byWorld[s.world]) do
            if not done[n] then
                local cost=best+distance(s,graph.stops[n])*rate
                if cost<(dist[n] or math.huge) then dist[n]=cost end
            end
        end
        for _,link in ipairs(graph.links[at]) do
            local cost=best+link.seconds
            if cost<(dist[link.to] or math.huge) then dist[link.to]=cost end
        end
    end
    if #graph.order>=64 then graph.distances[table.remove(graph.order,1)]=nil end
    graph.order[#graph.order+1]=start;graph.distances[start]=dist;graph.runs=graph.runs+1
    return dist
end
local function nearest(graph,world,point)
    local rows={}
    for _,n in ipairs(graph.byWorld[world] or {}) do rows[#rows+1]={n=n,yards=distance(point,graph.stops[n])} end
    table.sort(rows,function(a,b) return a.yards==b.yards and a.n<b.n or a.yards<b.yards end)
    for i=#rows,NEAREST+1,-1 do rows[i]=nil end
    return rows
end
local function locate(src,p)
    if not p or not planner.Roads then return end
    local world,point=planner.Roads.Locate(p.mapID,p.x,p.y,src.index)
    if world then
        -- Cell centers make the result independent of which point first queried a cell.
        point.x=(math.floor(point.x/CELL)+.5)*CELL;point.z=(math.floor(point.z/CELL)+.5)*CELL
        return world,point,world..":"..point.x..":"..point.z
    end
end
local function fallback(from,to,model)
    local size=from and to and from.mapID==to.mapID and model.mapSizes[to.mapID]
    if size and schema.Number(from.x,0,1) and schema.Number(from.y,0,1)
        and schema.Number(to.x,0,1) and schema.Number(to.y,0,1) then
        return math.sqrt(((from.x-to.x)*size[1])^2+((from.y-to.y)*size[2])^2)*(model.rates[to.mapID] or model.defaultRate)
    end
    -- Uncovered maps retain a continent-scale planning allowance, never a route refusal.
    return from and to and from.mapID==to.mapID and 300 or 1800
end
function estimate.Open(raw)
    local model=schema.CopyLimited(raw,16384,131072,8)
    if not valid(model) then return nil,"invalid_travel_model" end
    local src=source()
    if model.indexRevision~=src.revision then return nil,"source_mismatch" end
    local graph=buildGraph(src,model)
    local memo,count={},0
    local function query(from,to)
        if from and to and schema.ID(from.mapID) and schema.Number(from.x,0,1) and schema.Number(from.y,0,1)
            and from.mapID==to.mapID and from.x==to.x and from.y==to.y and from.floor==to.floor then
            return {seconds=0,lower=0,upper=0,status="unverified"}
        end
        local a,pa,ka=locate(src,from);local b,pb,kb=locate(src,to)
        local rateA=model.rates[from and from.mapID] or graph.rates[a] or model.defaultRate
        local rateB=model.rates[to and to.mapID] or graph.rates[b] or model.defaultRate
        local key=ka and kb and table.concat({ka,kb,rateA,rateB},"|")
        if key and memo[key] then return schema.Clone(memo[key]) end
        local seconds,reason=math.huge,"road-index estimate"
        if a and b then
            if a==b then seconds=distance(pa,pb)*(rateA+rateB)/2 end
            local starts,goals=nearest(graph,a,pa),nearest(graph,b,pb)
            for _,s in ipairs(starts) do
                local costs=distances(graph,s.n,model.defaultRate)
                for _,g in ipairs(goals) do
                    local cost=s.yards*rateA+(costs[g.n] or math.huge)+g.yards*rateB
                    if cost<seconds then seconds=cost end
                end
            end
        end
        if seconds==math.huge then seconds=fallback(from,to,model);reason="uncovered travel estimate" end
        seconds=math.min(86400,math.max(.1,seconds))
        local result={seconds=seconds,lower=0,upper=math.min(86400,math.max(120,seconds*2)),
            status="unverified",reason=reason}
        if key then
            if count>=4096 then memo,count={},0 end
            memo[key]=result;count=count+1
        end
        return schema.Clone(result)
    end
    return query,nil,function() return {memo=count,dijkstra=graph.runs,stops=#graph.stops} end
end
