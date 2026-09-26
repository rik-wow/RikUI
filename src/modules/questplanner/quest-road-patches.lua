-- Quest-spot mesh patches: registration, decoding and a bounded NavMesh
-- built from the patch cells around given points. Patches are detailed mesh
-- kept only near corpus quest areas; everything else routes on the network.
local planner=RikUI.QuestPlanner
local schema,patches=planner.Schema,{}
planner.RoadPatches=patches

local REACH=48              -- yards around each end whose patch cells are loaded
local SHORT_TRIP=240        -- trips this short also load the cells between the ends
local MESH_CACHE=3          -- validated meshes kept for plans over the same cells
local meshes={}
local DECODE_SLICE=64       -- polygons decoded between yields
local CACHE_CELLS=48        -- decoded cells kept for later plans
local decoded,decodedOrder={},{}
local MAX_MESH_POLYGONS=60000
local registered={}
local stats={loads=0,cells=0}

local function hash(v) return type(v)=="string" and #v==64 and v:match("^[a-f0-9]+$") end

-- Called from patch addon files.
function planner.Roads.Patch(revision,key,vertexCount,polygons,portals,recordBytes,vertexText,recordText)
    if not hash(revision) or not schema.Integer(key,0,16777215) or not schema.Integer(vertexCount,1,65535)
        or not schema.Integer(polygons,1,65535) or not schema.Integer(portals,0,1048575)
        or not schema.Integer(recordBytes,1,16777215) or type(vertexText)~="string" or type(recordText)~="string" then
        return nil,"invalid road patch"
    end
    local byKey=registered[revision] or {};registered[revision]=byKey
    byKey[key]={vertexCount=vertexCount,polygons=polygons,portals=portals,recordBytes=recordBytes,
        vertexText=vertexText,recordText=recordText}
    return true
end

local function signed(value) if value>=2147483648 then return value-4294967296 end return value end

-- The stream reader takes pages of at most 32000 characters.
local PAGE=32000
local function pages(text)
    local out={}
    for at=1,#text,PAGE do out[#out+1]=text:sub(at,at+PAGE-1) end
    return out
end

-- Decode one cell into {id=,points=,portals=} rows; portals keep target IDs.
local function decode(graph,key,row)
    local units=graph.catalog.patchUnitsPerYard or 1024
    local vertices,why=planner.PathCodec.Open(pages(row.vertexText),row.vertexCount*12,12,row.vertexCount)
    if not vertices then return nil,why end
    local records,problem=planner.PathCodec.Open(pages(row.recordText),row.recordBytes,1,row.recordBytes)
    if not records then return nil,problem end
    local cell=graph.cellYards
    local cx=math.floor(key/4096)-2048
    local cz=key%4096-2048
    local ox,oz=cx*cell,cz*cell
    local cache={}
    local function vertex(i)
        local v=cache[i]
        if v then return {v[1],v[2],v[3]} end
        local x=signed(vertices:UInt(i+1,0,4))/units+ox
        local z=signed(vertices:UInt(i+1,4,4))/units+oz
        local y=signed(vertices:UInt(i+1,8,4))/units
        cache[i]={x,y,z}
        return {x,y,z}
    end
    local at=1
    local function u(width)
        local value,mult=0,1
        for k=0,width-1 do value=value+records:UInt(at+k,0,1)*mult;mult=mult*256 end
        at=at+width
        return value
    end
    local rows={}
    for index=1,row.polygons do
        if index%DECODE_SLICE==0 then coroutine.yield() end
        local id=u(4);local count=u(1)
        local points={}
        for k=1,count do points[k]=vertex(u(2)) end
        local portals={}
        for k=1,u(1) do
            local to=u(4);local left=vertex(u(2));local right=vertex(u(2))
            portals[k]={to=to,left=left,right=right}
        end
        rows[#rows+1]={id=id,points=points,portals=portals}
    end
    if at~=row.recordBytes+1 then return nil,"road patch length mismatch" end
    return rows
end

local function cellsAround(graph,points)
    local keys,seen,size={}, {},graph.cellYards
    local function box(x0,z0,x1,z1)
        for cx=math.floor(x0/size),math.floor(x1/size) do
            for cz=math.floor(z0/size),math.floor(z1/size) do
                local key=graph:CellKey(cx,cz)
                if not seen[key] and graph:PatchAddon(key) then seen[key]=true;keys[#keys+1]=key end
            end
        end
    end
    for _,p in ipairs(points) do box(p.x-REACH,p.z-REACH,p.x+REACH,p.z+REACH) end
    -- Short trips also load the cells between the ends so a direct mesh route
    -- is possible instead of a detour through 128-yard network nodes.
    local a,b=points[1],points[2]
    if a and b and (a.x-b.x)^2+(a.z-b.z)^2<=SHORT_TRIP^2 then
        box(math.min(a.x,b.x)-REACH,math.min(a.z,b.z)-REACH,math.max(a.x,b.x)+REACH,math.max(a.z,b.z)+REACH)
    end
    table.sort(keys)
    return keys
end

-- Loads at most one patch addon per call. Patches are the only LoadOnDemand
-- data left: each pack holds up to 16 MiB of cells (quest_pockets.py), so a
-- load is one synchronous stall per region, not per frame of walking.
-- Returns nil,"loading" until every needed cell is registered.
local function ensureLoaded(graph,keys)
    local have,loadedThisCall=registered[graph.revision] or {},false
    for _,key in ipairs(keys) do
        if not have[key] then
            if loadedThisCall then return nil,"loading" end
            if type(InCombatLockdown)=="function" and InCombatLockdown() then return nil,"combat-loading-deferred" end
            local load=type(C_AddOns)=="table" and C_AddOns.LoadAddOn
            if type(load)~="function" then return nil,"road-loader-unavailable" end
            local name=string.format("RikUIQuestRoads_W%d_P%03d",graph.world,graph:PatchAddon(key))
            local ok,loaded=pcall(load,name)
            stats.loads=stats.loads+1
            if not ok or not loaded then return nil,"road-patch-unavailable" end
            have=registered[graph.revision] or {}
            if not have[key] then return nil,"road-patch-revision" end
            loadedThisCall=true
        end
    end
    return have
end

local function meshFor(graph,view,keys,polygons,byID)
    local portals,minX,minZ,maxX,maxZ=0,math.huge,math.huge,-math.huge,-math.huge
    for _,row in ipairs(polygons) do
        local kept={}
        for _,portal in ipairs(row.portals) do if byID[portal.to] then kept[#kept+1]=portal end end
        row.portals=kept;portals=portals+#kept
        for _,p in ipairs(row.points) do
            minX,maxX=math.min(minX,p[1]),math.max(maxX,p[1]);minZ,maxZ=math.min(minZ,p[3]),math.max(maxZ,p[3])
        end
    end
    local shards={}
    for at=1,#polygons,1024 do
        local shard={identity=graph.catalog.identity,polygons={}}
        for k=at,math.min(#polygons,at+1023) do shard.polygons[#shard.polygons+1]=polygons[k] end
        shards[#shards+1]=shard
    end
    local meta={format="rikui-navmesh-v1",identity=graph.catalog.identity,revision=graph.revision..":"..table.concat(keys,","),
        uiMapID=view.uiMapID,worldMapID=graph.world,source={sha256=graph.revision,parser="rikui-road-patch-v1"},
        projection=view.projection,modeledMaxStep=1,counts={polygons=#polygons,portals=portals},
        bounds={minX-1,minZ-1,maxX+1,maxZ+1},exclusions={},blockers={},coverageScope="quest-patches",
        nativeVerified=false}
    return planner.NavMesh.Begin(meta,shards)
end

-- Decoded cell rows, cached by revision and key. Must run inside a coroutine.
local function cellRows(graph,key,row)
    local id=graph.revision..":"..key
    if decoded[id] then return decoded[id] end
    local rows,problem=decode(graph,key,row)
    if not rows then return nil,problem end
    decoded[id]=rows;decodedOrder[#decodedOrder+1]=id
    if #decodedOrder>CACHE_CELLS then decoded[table.remove(decodedOrder,1)]=nil end
    return rows
end

local function copyRow(row)
    local points,portals={}, {}
    for i,point in ipairs(row.points) do points[i]={point[1],point[2],point[3]} end
    for i,portal in ipairs(row.portals) do
        portals[i]={to=portal.to,left={portal.left[1],portal.left[2],portal.left[3]},right={portal.right[1],portal.right[2],portal.right[3]}}
    end
    return {id=row.id,points=points,portals=portals}
end

-- Returns a sliced job for the patch cells around points: each step decodes at
-- most one cell, then the NavMesh loader validates incrementally. Step returns
-- value,reason,done like other loaders. "no-patch": none of the cells has mesh.
function patches.Begin(graph,view,points)
    local keys=cellsAround(graph,points)
    if #keys==0 then return nil,"no-patch" end
    local cacheKey=graph.revision..":"..table.concat(keys,",")
    for _,row in ipairs(meshes) do
        if row.key==cacheKey then
            return {Cancel=function() end,Step=function() return row.mesh,nil,true end}
        end
    end
    local have,why=ensureLoaded(graph,keys)
    if not have then return nil,why end
    local polygons,byID,loader,cancelled={}, {},nil,false
    -- Decoding yields every DECODE_SLICE polygons; the mesh loader is sliced too.
    local collector=coroutine.create(function()
        for _,key in ipairs(keys) do
            local rows,problem=cellRows(graph,key,have[key])
            if not rows then return nil,problem end
            for index,row in ipairs(rows) do
                polygons[#polygons+1]=copyRow(row);byID[row.id]=true
                if index%DECODE_SLICE==0 then coroutine.yield() end
            end
            stats.cells=stats.cells+1
            if #polygons>MAX_MESH_POLYGONS then return nil,"road patch mesh limit" end
        end
        return true
    end)
    return {Cancel=function() cancelled=true;if loader then loader:Cancel() end end,Step=function(_,budget)
        if cancelled then return nil,"cancelled",true end
        if coroutine.status(collector)~="dead" then
            local ok,value,problem=coroutine.resume(collector)
            if not ok then return nil,"invalid road patch",true end
            if coroutine.status(collector)~="dead" then return nil,nil,false end
            if not value then return nil,problem,true end
        end
        if not loader then
            local problem
            loader,problem=meshFor(graph,view,keys,polygons,byID)
            if not loader then return nil,problem,true end
        end
        local value,reason,done=loader:Step(budget)
        if done and value then
            table.insert(meshes,1,{key=cacheKey,mesh=value})
            meshes[MESH_CACHE+1]=nil
        end
        return value,reason,done
    end}
end

function patches.Stats() return schema.Clone(stats) end
