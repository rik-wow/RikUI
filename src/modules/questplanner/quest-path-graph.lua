-- Sliced admission of a compact directed network with on-demand path witnesses.
local planner=RikUI.QuestPlanner
local schema,graph=planner.Schema,{}
planner.PathGraph=graph
local MAX_GATEWAYS,MAX_EDGES,MAX_VERTICES,MAX_TREES=16384,131072,65535,1048576
local ARRAY_PAGE=2048
local function hash(value) return type(value)=="string" and #value==64 and value:match("^[a-f0-9]+$") end
local function vector(reader,index,offset)
    offset=offset or 0
    local x,why=reader:Number(index,offset)
    local y,second=reader:Number(index,offset+8)
    local z,third=reader:Number(index,offset+16)
    if not schema.Number(x,-100000,100000) or not schema.Number(y,-100000,100000)
        or not schema.Number(z,-100000,100000) then return nil,why or second or third or "Invalid path coordinate" end
    return {x,y,z}
end
local function binary(values,target)
    local first,last=1,#values
    while first<=last do
        local middle=math.floor((first+last)/2)
        if values[middle]==target then return middle end
        if values[middle]<target then first=middle+1 else last=middle-1 end
    end
end
local function publish(catalog,arrays,streams,originals,centers)
    local count=catalog.counts
    local function edge(index)
        if not schema.Integer(index,1,count.geometry) then return nil,"Invalid witness edge" end
        local from,why=streams.geometry:UInt(index,0,2)
        local to,other=streams.geometry:UInt(index,2,2)
        local mid,reason=streams.geometry:UInt(index,4,2)
        if not schema.Integer(from,1,count.vertices) or not schema.Integer(to,1,count.vertices)
            or not schema.Integer(mid,1,count.midpoints) then return nil,why or other or reason or "Invalid witness geometry" end
        return from,to,mid
    end
    local function treeEdge(root,target)
        local first,last=arrays.treeOffsets[root]+1,arrays.treeOffsets[root+1]
        while first<=last do
            local middle=math.floor((first+last)/2)
            local id,problem=streams.treeEdges:UInt(middle,0,3)
            if not id then return nil,problem end
            local from,to=edge(id)
            if not from then return nil,to end
            if to==target then return id,from end
            if to<target then first=middle+1 else last=middle-1 end
        end
        return nil,"Missing local path witness"
    end
    local function polygon(original)
        if not streams.surfaceOffsets or not schema.ID(original) then return nil,"Prepared polygon geometry unavailable" end
        local first,last=1,count.vertices
        local vertex
        while first<=last do
            local middle=math.floor((first+last)/2)
            local id=streams.vids:UInt(middle,0,3)
            if not schema.ID(id) then return nil,"Invalid polygon identifier" end
            if id==original then vertex=middle;break end
            if id<original then first=middle+1 else last=middle-1 end
        end
        if not vertex then return nil,"Polygon outside prepared network" end
        local a=streams.surfaceOffsets:UInt(vertex,0,4)
        local b=streams.surfaceOffsets:UInt(vertex+1,0,4)
        if not schema.Integer(a,0,count.surfacePoints) or not schema.Integer(b,a+3,math.min(a+6,count.surfacePoints)) then
            return nil,"Invalid prepared polygon offsets"
        end
        local center,why=vector(streams.centers,vertex)
        if not center then return nil,why end
        local points={}
        for index=a+1,b do
            local point,problem=vector(streams.surfacePoints,index)
            if not point then return nil,problem end
            points[#points+1]=point
        end
        if not planner.NavGeometry or not planner.NavGeometry.Convex(points) then return nil,"Invalid prepared polygon surface" end
        return {id=original,center=center,points=points}
    end
    return {
        Catalog=function() return schema.Clone(catalog) end,
        Polygon=function(_,original) return polygon(original) end,
        Gateway=function(_,originalID) if schema.ID(originalID) then return binary(originals,originalID) end end,
        Original=function(_,index) return originals[index] end,
        Center=function(_,index) return centers[index] and schema.Clone(centers[index]) end,
        Edges=function(_,index)
            if not schema.Integer(index,1,count.gateways) then return function() end end
            local at,last=arrays.adjOffsets[index],arrays.adjOffsets[index+1]
            return function()
                at=at+1
                if at<=last then return arrays.adjTargets[at],arrays.adjCosts[at],arrays.adjWitness[at],at end
            end
        end,
        Segment=function(_,index)
            local from,to,mid=edge(index)
            if not from then return nil,to end
            local a,why=vector(streams.centers,from)
            local b,second=vector(streams.centers,to)
            local m,third=vector(streams.mids,mid)
            if not a or not b or not m then return nil,why or second or third end
            local fromID=streams.vids:UInt(from,0,3)
            local toID=streams.vids:UInt(to,0,3)
            if not schema.ID(fromID) or not schema.ID(toID) then return nil,"Invalid original path vertex" end
            local left,right
            if streams.portalEnds then
                left=vector(streams.portalEnds,index,0);right=vector(streams.portalEnds,index,24)
                if not left or not right then return nil,"Invalid prepared portal endpoints" end
                for axis=1,3 do
                    if math.abs((left[axis]+right[axis])/2-m[axis])>.000001 then return nil,"Prepared portal midpoint differs" end
                end
            end
            return {from=fromID,to=toID,origin=a,destination=b,midpoint=m,left=left,right=right}
        end,
        BeginWitness=function(_,root,target)
            if not schema.Integer(root,1,count.gateways) or not schema.Integer(target,1,count.gateways) then return nil,"Invalid gateway" end
            local descriptor
            for at=arrays.adjOffsets[root]+1,arrays.adjOffsets[root+1] do
                if arrays.adjTargets[at]==target then descriptor=arrays.adjWitness[at];break end
            end
            if descriptor==nil then return nil,"Directed connection absent" end
            local cancelled,done=false,false
            local worker=coroutine.create(function()
                if descriptor>0 then
                    local from,to=edge(descriptor)
                    if from~=arrays.boundary[root] or to~=arrays.boundary[target] then return nil,"Invalid seam witness" end
                    return {descriptor}
                end
                local node,goal=arrays.boundary[target],arrays.boundary[root]
                local reverse,seen={},{}
                local maximum=arrays.treeOffsets[root+1]-arrays.treeOffsets[root]
                while node~=goal do
                    if seen[node] or #reverse>=maximum then return nil,"Cyclic or excessive path witness" end
                    seen[node]=true
                    local id,parent=treeEdge(root,node)
                    if not id then return nil,parent end
                    reverse[#reverse+1]=id;node=parent
                    coroutine.yield()
                end
                local result={}
                for index=#reverse,1,-1 do result[#result+1]=reverse[index];coroutine.yield() end
                return result
            end)
            return {Cancel=function() cancelled=true end,Step=function(_,budget)
                if cancelled then return nil,"cancelled",true end
                if done then return nil,"witness already completed",true end
                if not schema.Integer(budget or 16,1,64) then return nil,"Invalid witness budget",true end
                for _=1,budget or 16 do
                    local ok,value,reason=coroutine.resume(worker)
                    if not ok then done=true;return nil,"Invalid witness data",true end
                    if coroutine.status(worker)=="dead" then done=true;return value,reason,true end
                end
            end}
        end,
        Stats=function()
            local bytes=0;for _,spec in pairs(catalog.streams) do bytes=bytes+spec.bytes end
            return {gateways=count.gateways,edges=count.edges,encodedRawBytes=bytes}
        end,
    }
end
function graph.Begin(raw,payload)
    local catalog=schema.CopyLimited(raw,4096,65536,12)
    if not catalog or (catalog.format~="rikui-path-backbone-v1" and catalog.format~="rikui-path-backbone-v2") or not schema.Identity(catalog.identity)
        or not hash(catalog.payloadID) or not hash(catalog.sourceManifestSHA256)
        or not hash(catalog.graphSHA256) or not hash(catalog.partitionAuditSHA256)
        or not schema.ID(catalog.uiMapID) or not schema.Integer(catalog.worldMapID,0,100000)
        or not schema.PlainTable(catalog.counts) or not schema.PlainTable(catalog.arrays)
        or not schema.PlainTable(catalog.streams) then return nil,"Invalid path catalog" end
    if not schema.PlainTable(payload) or payload.format~=catalog.format or payload.payloadID~=catalog.payloadID
        or not schema.PlainTable(payload.arrays) or not schema.PlainTable(payload.streams) then return nil,"Path payload identity mismatch" end
    local c=catalog.counts
    if not schema.Integer(c.vertices,1,MAX_VERTICES) or not schema.Integer(c.gateways,1,MAX_GATEWAYS)
        or not schema.Integer(c.edges,0,MAX_EDGES) or not schema.Integer(c.geometry,0,16777215)
        or not schema.Integer(c.midpoints,0,65535) or not schema.Integer(c.treeEntries,0,MAX_TREES) then return nil,"Path network size limit" end
    local arrayCounts={boundary=c.gateways,adjOffsets=c.gateways+1,adjTargets=c.edges,
        adjCosts=c.edges,adjWitness=c.edges,treeOffsets=c.gateways+1}
    local streamShape={vids={3,c.vertices},centers={24,c.vertices},mids={24,c.midpoints},
        edgeIds={3,c.geometry},geometry={6,c.geometry},treeEdges={3,c.treeEntries}}
    if catalog.format=="rikui-path-backbone-v2" then
        if not schema.Integer(c.surfacePoints,c.vertices*3,c.vertices*6) then return nil,"Prepared surface count limit" end
        streamShape.surfaceOffsets={4,c.vertices+1}
        streamShape.surfacePoints={24,c.surfacePoints}
        streamShape.portalEnds={48,c.geometry}
    end
    local cancelled,done,work=false,false,0
    local worker=coroutine.create(function()
        local arrays,streams,originals,centers={},{},{},{}
        local function pause() work=work+1;if work%32==0 then coroutine.yield() end end
        for name,expected in pairs(arrayCounts) do
            local spec,rawArray=catalog.arrays[name],payload.arrays[name]
            local pages=math.ceil(expected/ARRAY_PAGE)
            if not schema.PlainTable(spec) or spec.count~=expected or spec.pageSize~=ARRAY_PAGE or spec.pages~=pages
                or not schema.List(rawArray,pages) or #rawArray~=pages then return nil,"Invalid path array layout" end
            local values={};arrays[name]=values
            for page,list in ipairs(rawArray) do
                local length=math.min(ARRAY_PAGE,expected-(page-1)*ARRAY_PAGE)
                if not schema.List(list,length) or #list~=length then return nil,"Invalid path array page" end
                for _,value in ipairs(list) do
                    if name=="adjCosts" then
                        if not schema.Number(value,0,1000000000) then return nil,"Invalid path cost" end
                    elseif not schema.Integer(value,0,16777215) then return nil,"Invalid path index" end
                    values[#values+1]=value;pause()
                end
            end
        end
        for name,shape in pairs(streamShape) do
            local spec=catalog.streams[name]
            if not schema.PlainTable(spec) or spec.stride~=shape[1] or spec.count~=shape[2]
                or spec.bytes~=shape[1]*shape[2] or spec.chunkChars~=32000
                or not hash(spec.rawSHA256) or not hash(spec.encodedSHA256) then return nil,"Invalid encoded path layout" end
            local reader,reason=planner.PathCodec.Open(payload.streams[name],spec.bytes,spec.stride,spec.count)
            if not reader then return nil,reason end
            if spec.parts~=#payload.streams[name] then return nil,"Missing path stream page" end
            streams[name]=reader;pause()
        end
        if arrays.adjOffsets[1]~=0 or arrays.adjOffsets[c.gateways+1]~=c.edges
            or arrays.treeOffsets[1]~=0 or arrays.treeOffsets[c.gateways+1]~=c.treeEntries then return nil,"Invalid path offsets" end
        for index=1,c.gateways do
            local vertex=arrays.boundary[index]
            if not schema.Integer(vertex,1,c.vertices) or index>1 and vertex<=arrays.boundary[index-1]
                or arrays.adjOffsets[index]>arrays.adjOffsets[index+1] or arrays.treeOffsets[index]>arrays.treeOffsets[index+1]
                then return nil,"Unordered path gateway or offset" end
            local id=streams.vids:UInt(vertex,0,3)
            if not schema.ID(id) or index>1 and id<=originals[index-1] then return nil,"Unordered source gateway" end
            originals[index]=id
            local center,reason=vector(streams.centers,vertex)
            if not center then return nil,reason end
            centers[index]=center
            local prior=0
            for at=arrays.adjOffsets[index]+1,arrays.adjOffsets[index+1] do
                local target=arrays.adjTargets[at]
                if not schema.Integer(target,1,c.gateways) or target==index or target<=prior
                    or not schema.Integer(arrays.adjWitness[at],0,c.geometry) then return nil,"Invalid directed path edge" end
                prior=target;pause()
            end
            pause()
        end
        return publish(catalog,arrays,streams,originals,centers)
    end)
    return {Cancel=function() cancelled=true end,Progress=function() return work end,Step=function(_,budget)
        if cancelled then return nil,"cancelled",true end
        if done then return nil,"path loader already finished",true end
        if not schema.Integer(budget or 8,1,64) then return nil,"Invalid path load budget",true end
        for _=1,budget or 8 do
            local ok,value,reason=coroutine.resume(worker)
            if not ok then done=true;return nil,"Invalid path data",true end
            if coroutine.status(worker)=="dead" then done=true;return value,reason,true end
        end
    end}
end
