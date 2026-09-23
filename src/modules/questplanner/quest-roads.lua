-- Road walk-network registry, lazy loader and read-only graph accessors.
-- Networks are compiled offline (tools/terrain/road_network.py); nothing here
-- adds walkable connections. Positions are navigation coordinates:
-- x = game world Y, z = game world X, in yards.
local planner=RikUI.QuestPlanner
local schema,roads=planner.Schema,{}
planner.Roads=roads

local FORMAT,INDEX_FORMAT="rikui-road-network-v1","rikui-road-index-v1"
local STREAMS={nodes=13,offsets=4,edges=8,points=4,cells=8,reps=4,patches=10}
local MAX_NODES,MAX_EDGES,MAX_POINTS=4194304,16777215,16777215
local CELL_BIAS,CELL_SPAN=2048,4096
local LOAD_SLICE=128
local LOAD_MS=3  -- per-frame time budget for network validation

local index={byMap={},worlds={}}
local catalogs,pages,graphs,loading={}, {}, {}, {}
local partsLoaded={}  -- revision -> part addons loaded so far
local stats={loads=0,maxLoadMS=0}

local function hash(v) return type(v)=="string" and #v==64 and v:match("^[a-f0-9]+$") end
local function same(a,b) return a and b and a.product==b.product and a.build==b.build and a.locale==b.locale end

local function validView(view)
    local p=schema.PlainTable(view) and view.projection
    return schema.ID(view.uiMapID) and schema.PlainTable(p) and schema.Number(p.originX,-100000,100000)
        and schema.Number(p.originY,-100000,100000) and schema.Number(p.width,1,200000)
        and schema.Number(p.height,1,200000) and schema.List(view.validUIRectangle,4)
end

-- Index and catalogs carry travel stops, links and stop-to-stop walks.
local COPY_NODES,COPY_BYTES,COPY_DEPTH=32768,1048576,8

function roads.InstallIndex(raw)
    local value=schema.CopyLimited(raw,COPY_NODES,COPY_BYTES,COPY_DEPTH)
    if not value or value.format~=INDEX_FORMAT or not schema.Identity(value.identity)
        or not schema.List(value.worlds,64) then return nil,"invalid road index" end
    local nextIndex={byMap={},worlds={}}
    for _,world in ipairs(value.worlds) do
        if not schema.Integer(world.worldMapID,0,100000) or not hash(world.revision)
            or type(world.addon)~="string" or not schema.List(world.views,256) then return nil,"invalid road index world" end
        world.identity=value.identity
        nextIndex.worlds[world.worldMapID]=world
        for _,view in ipairs(world.views) do
            if not validView(view) then return nil,"invalid road view" end
            local list=nextIndex.byMap[view.uiMapID] or {};nextIndex.byMap[view.uiMapID]=list
            list[#list+1]={world=world.worldMapID,view=view}
        end
    end
    if planner.RoadTravel then
        local ok,why=planner.RoadTravel.Install(value.travel or {stops={},links={}})
        if not ok then return nil,why end
    end
    index=nextIndex
    return true
end

-- Read-only source handle: replacement changes identity, catalog/page loads do not.
function roads.EstimateIndex() return index end

function roads.Install(raw)
    local value=schema.CopyLimited(raw,COPY_NODES,COPY_BYTES,COPY_DEPTH)
    if not value or value.format~=FORMAT or not schema.Identity(value.identity) or not hash(value.revision)
        or not schema.Integer(value.worldMapID,0,100000) or not schema.PlainTable(value.streams)
        or not schema.PlainTable(value.counts) then return nil,"invalid road catalog" end
    catalogs[value.revision]=value;pages[value.revision]=pages[value.revision] or {}
    return true
end

function roads.Page(revision,name,part,text)
    if not hash(revision) or not STREAMS[name] or not schema.Integer(part,1,4096) or type(text)~="string" then return nil,"invalid road page" end
    local byName=pages[revision] or {};pages[revision]=byName
    local list=byName[name] or {};byName[name]=list
    list[part]=text
    return true
end

-- Map position -> world and navigation point. Views covering the same map
-- (continent maps) are disambiguated by their valid UI rectangle.
function roads.Locate(mapID,x,y,source)
    if not schema.ID(mapID) or not schema.Number(x,0,1) or not schema.Number(y,0,1) then return nil end
    for _,row in ipairs((source or index).byMap[mapID] or {}) do
        local r,p=row.view.validUIRectangle,row.view.projection
        if x>=r[1] and x<=r[3] and y>=r[2] and y<=r[4] then
            return row.world,{x=p.originY-x*p.width,z=p.originX-y*p.height},row.view
        end
    end
end

-- Borrowed validated projection; rendering never loads network geometry.
function roads.View(world,mapID)
    for _,row in ipairs(index.byMap[mapID] or {}) do
        if row.world==world then return row.view end
    end
end

function roads.Unproject(view,point)
    local p=view and view.projection
    if not p or not schema.PlainTable(point) then return nil end
    local px,pz=point.x or point[1],point.z or point[3]
    return {mapID=view.uiMapID,x=(p.originY-px)/p.width,y=(p.originX-pz)/p.height}
end

function roads.HasWorld(world) return index.worlds[world]~=nil end
function roads.Stats() return schema.Clone(stats) end

local function publish(catalog,streams,pointOffsets)
    local units=catalog.unitsPerYard
    local counts=catalog.counts
    local graph={catalog=catalog,revision=catalog.revision,world=catalog.worldMapID,cellYards=catalog.cellYards,roadBonus=catalog.roadBonus}
    local function signed(value,bits) if value>=2^(bits-1) then return value-2^bits end return value end
    function graph:Nodes() return counts.nodes end
    function graph:Node(i)
        if not schema.Integer(i,1,counts.nodes) then return nil end
        local x=signed(streams.nodes:UInt(i,0,4),32)/units
        local z=signed(streams.nodes:UInt(i,4,4),32)/units
        local y=signed(streams.nodes:UInt(i,8,4),32)/units
        return x,z,y,streams.nodes:UInt(i,12,1)/255
    end
    function graph:EdgeRange(i)
        return streams.offsets:UInt(i,0,4)+1,streams.offsets:UInt(i+1,0,4)
    end
    function graph:Edge(e)
        local target=streams.edges:UInt(e,0,3)
        return target,streams.edges:UInt(e,3,2)/units,streams.edges:UInt(e,5,2)/units,streams.edges:UInt(e,7,1),pointOffsets[e]
    end
    function graph:Point(k)
        return signed(streams.points:UInt(k,0,2),16)/units,signed(streams.points:UInt(k,2,2),16)/units
    end
    local function lowest(stream,key)
        local first,last,found=1,stream.count,nil
        while first<=last do
            local mid=math.floor((first+last)/2);local k=stream:UInt(mid,0,4)
            if k<key then first=mid+1 else last=mid-1;if k==key then found=mid end end
        end
        return found
    end
    function graph:CellKey(cx,cz) return (cx+CELL_BIAS)*CELL_SPAN+(cz+CELL_BIAS) end
    function graph:CellNodes(cx,cz)
        local key=graph:CellKey(cx,cz)
        local found,out=lowest(streams.cells,key),{}
        while found and found<=streams.cells.count and streams.cells:UInt(found,0,4)==key do
            out[#out+1]=streams.cells:UInt(found,4,4);found=found+1
        end
        return out
    end
    -- Polygon ID (in patch data) of each node's representative polygon, and back.
    local polygonNode
    function graph:NodePolygon(n) return streams.reps.count>0 and streams.reps:UInt(n,0,4) or nil end
    function graph:PolygonNode(id)
        if not polygonNode then
            polygonNode={}
            for n=1,counts.nodes do local p=graph:NodePolygon(n);if p then polygonNode[p]=n end end
        end
        return polygonNode[id]
    end
    -- Patch addon index for a cell key, or nil when the cell has no quest patch.
    function graph:PatchAddon(key)
        if streams.patches.count==0 then return nil end
        local at=lowest(streams.patches,key)
        return at and streams.patches:UInt(at,4,2)
    end
    return graph
end

-- Sliced validation and point-offset prefix sums; publishes a graph object.
local function beginGraph(catalog)
    local c=catalog.counts
    if not schema.Integer(c.nodes,1,MAX_NODES) or not schema.Integer(c.edges,0,MAX_EDGES)
        or not schema.Integer(c.points,0,MAX_POINTS) or not schema.Number(catalog.unitsPerYard,1,64)
        or not schema.Number(catalog.cellYards,16,1024) or not schema.Number(catalog.roadBonus,0,.9) then
        return nil,"road network size limit"
    end
    local expected={nodes=c.nodes,offsets=c.nodes+1,edges=c.edges,points=c.points,cells=c.nodes,reps=c.nodes,
        patches=c.patchCells or 0}
    local streams={}
    for name,stride in pairs(STREAMS) do
        local spec=catalog.streams[name]
        if not schema.PlainTable(spec) or spec.stride~=stride or spec.count~=expected[name] then return nil,"invalid road stream layout" end
        if spec.bytes==0 then
            streams[name]={count=0,UInt=function() return nil end}
        else
            local list=pages[catalog.revision] and pages[catalog.revision][name]
            if not list or #list~=spec.parts then return nil,"missing road stream page" end
            local reader,why=planner.PathCodec.Open(list,spec.bytes,spec.stride,spec.count)
            if not reader then return nil,why end
            reader.count=spec.count;streams[name]=reader
        end
    end
    local offsets,edgeAt,pointTotal,node={},1,0,1
    local worker=coroutine.create(function()
        if streams.offsets:UInt(1,0,4)~=0 or streams.offsets:UInt(c.nodes+1,0,4)~=c.edges then return nil,"invalid road offsets" end
        while edgeAt<=c.edges do
            local target=streams.edges:UInt(edgeAt,0,3);local count=streams.edges:UInt(edgeAt,7,1)
            if not schema.Integer(target,1,c.nodes) or not count then return nil,"invalid road edge" end
            offsets[edgeAt]=pointTotal+1;pointTotal=pointTotal+count;edgeAt=edgeAt+1
            if edgeAt%LOAD_SLICE==0 then coroutine.yield() end
        end
        if pointTotal~=c.points then return nil,"road point count mismatch" end
        return publish(catalog,streams,offsets)
    end)
    local done,cancelled=false,false
    return {Cancel=function() cancelled=true end,Step=function(_,budget)
        if cancelled then return nil,"cancelled",true end
        if done then return nil,"road loader finished",true end
        local clock=type(debugprofilestop)=="function" and debugprofilestop
        local started=clock and clock()
        for _=1,budget or 8 do
            if clock and clock()-started>=LOAD_MS then return nil,nil,false end
            local ok,value,reason=coroutine.resume(worker)
            if not ok then done=true;return nil,"invalid road data",true end
            if coroutine.status(worker)=="dead" then done=true;return value,reason,true end
        end
    end}
end

local function loadAddon(name)
    if type(InCombatLockdown)=="function" and InCombatLockdown() then return nil,"combat-loading-deferred" end
    local load=type(C_AddOns)=="table" and C_AddOns.LoadAddOn
    if type(load)~="function" then return nil,"road-loader-unavailable" end
    local clock=type(debugprofilestop)=="function" and debugprofilestop
    local before=clock and clock()
    local ok,loaded,reason=pcall(load,name)
    if before then local ms=clock()-before;if ms>stats.maxLoadMS then stats.maxLoadMS=ms end end
    stats.loads=stats.loads+1
    -- The client lists addon folders only at startup; one added by an install
    -- since then reads as MISSING until the game restarts.
    if ok and not loaded and reason=="MISSING" then return nil,"road-addon-missing" end
    if not ok or not loaded then return nil,"road-addon-unavailable" end
    return true
end

-- Returns graph, or nil plus "loading"/reason. Call once per frame until ready.
function roads.Prepare(identity,world)
    local entry=index.worlds[world]
    if not entry then return nil,"no-road-network" end
    if not same(entry.identity,identity) then return nil,"road-network-identity" end
    local ready=graphs[entry.revision]
    if ready then return ready end
    local job=loading[entry.revision]
    if not job then
        if not catalogs[entry.revision] then
            local ok,why=loadAddon(entry.addon)
            if not ok then return nil,why end
            if not catalogs[entry.revision] then return nil,"road-catalog-revision" end
            return nil,"loading"
        end
        -- Stream pages ship in part addons; one synchronous load per call.
        local done=partsLoaded[entry.revision] or 0
        if schema.List(entry.parts,64) and done<#entry.parts then
            local ok,why=loadAddon(entry.parts[done+1])
            if not ok then return nil,why end
            partsLoaded[entry.revision]=done+1
            return nil,"loading"
        end
        local problem
        job,problem=beginGraph(catalogs[entry.revision])
        if not job then return nil,problem end
        loading[entry.revision]=job
    end
    local value,reason,done=job:Step(16)
    if not done then return nil,"loading" end
    loading[entry.revision]=nil
    if not value then return nil,reason end
    graphs[entry.revision]=value
    return value
end

function roads.Reset()
    for key,job in pairs(loading) do job:Cancel();loading[key]=nil end
end
