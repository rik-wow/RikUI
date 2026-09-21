-- Incrementally validates a bounded derived polygon/portal dataset before publication.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local geometry,mesh=planner.NavGeometry,{}
planner.NavMesh=mesh
local CELL,MAX_POLYGONS,MAX_PORTALS,MAX_CELL_POLYGONS,MAX_CELLS=64,65536,131072,1024,4096
local function same(a,b) return a.product==b.product and a.build==b.build and a.locale==b.locale end
local function key(x,z) return math.floor(x/CELL)..":"..math.floor(z/CELL) end
local function metadata(raw)
    local value=schema.CopyLimited(raw,2048,16384,12)
    if not schema.PlainTable(value) or value.format~="rikui-navmesh-v1" or not schema.Identity(value.identity)
        or not schema.Text(value.revision) or not schema.ID(value.uiMapID)
        or not schema.Integer(value.worldMapID,0,100000) then return nil,"invalid navigation manifest" end
    if not schema.PlainTable(value.source) or not schema.Text(value.source.sha256)
        or not value.source.sha256:match("^[a-f0-9]+$") or #value.source.sha256~=64
        or not schema.Text(value.source.parser) then return nil,"navigation provenance missing" end
    local projection=value.projection
    if not schema.PlainTable(projection) or not schema.Number(projection.originX,-100000,100000)
        or not schema.Number(projection.originY,-100000,100000) or not schema.Number(projection.width,1,100000)
        or not schema.Number(projection.height,1,100000) then return nil,"invalid map projection" end
    if not schema.Number(value.modeledMaxStep,0,2) then return nil,"navigation step model missing" end
    local count=value.counts
    if not schema.PlainTable(count) or not schema.Integer(count.polygons,1,MAX_POLYGONS)
        or not schema.Integer(count.portals,0,MAX_PORTALS) then return nil,"navigation size limit" end
    if not schema.List(value.bounds,4) or #value.bounds~=4 then return nil,"navigation bounds missing" end
    for _,number in ipairs(value.bounds) do if not schema.Number(number,-100000,100000) then return nil,"invalid navigation bounds" end end
    if value.bounds[1]>=value.bounds[3] or value.bounds[2]>=value.bounds[4] then return nil,"inverted navigation bounds" end
    if not schema.List(value.exclusions or {},64) or not schema.List(value.blockers or {},64) then return nil,"navigation coverage limit" end
    for _,bounds in ipairs(value.exclusions or {}) do
        if not schema.List(bounds,4) or #bounds~=4 then return nil,"invalid exclusion" end
        for _,number in ipairs(bounds) do if not schema.Number(number,-100000,100000) then return nil,"invalid exclusion bounds" end end
        if bounds[1]>bounds[3] or bounds[2]>bounds[4] then return nil,"inverted exclusion" end
    end
    return value
end
local MAX_WIRE_ID=2147483647 -- Preserve the previous generic-copy numeric ceiling.
local POLYGON_FIELDS={id=true,points=true,portals=true}
local PORTAL_FIELDS={to=true,left=true,right=true}
local function fields(raw,allowed)
    if not schema.PlainTable(raw) then return false end
    for name in pairs(raw) do
        if not schema.Text(name) or not allowed[name] then return false end
    end
    return true
end
local function copyPoint(raw)
    if not geometry.Point(raw) then return nil end
    return {raw[1],raw[2],raw[3]}
end
-- The wire shape is fixed and bounded; do not recursively copy arbitrary fields.
local function copyPolygon(raw)
    if not fields(raw,POLYGON_FIELDS) or not schema.Integer(raw.id,1,MAX_WIRE_ID)
        or not schema.List(raw.points,6) or #raw.points<3
        or not schema.List(raw.portals,32) then return nil end
    local value={id=raw.id,points={},portals={}}
    for at,point in ipairs(raw.points) do
        value.points[at]=copyPoint(point)
        if not value.points[at] then return nil end
    end
    for at,portal in ipairs(raw.portals) do
        if not fields(portal,PORTAL_FIELDS) or not schema.Integer(portal.to,1,MAX_WIRE_ID) then return nil end
        local left,right=copyPoint(portal.left),copyPoint(portal.right)
        if not left or not right then return nil end
        value.portals[at]={to=portal.to,left=left,right=right}
    end
    return value
end
local function polygon(raw)
    local value=copyPolygon(raw)
    if not value or not geometry.Convex(value.points) then return nil,"invalid polygon" end
    value.center={0,0,0}
    for _,point in ipairs(value.points) do for axis=1,3 do value.center[axis]=value.center[axis]+point[axis]/#value.points end end
    value.bounds=geometry.Bounds(value.points)
    if value.bounds[3]-value.bounds[1]>128 or value.bounds[4]-value.bounds[2]>128 then return nil,"polygon spatial limit" end
    for _,portal in ipairs(value.portals) do
        if not schema.Integer(portal.to,1,4294967295) or portal.to==value.id
            or not geometry.Point(portal.left) or not geometry.Point(portal.right)
            or geometry.Distance(portal.left,portal.right)<.0001
            or not geometry.OnBoundary(value.points,portal.left) or not geometry.OnBoundary(value.points,portal.right) then
            return nil,"invalid portal boundary"
        end
        portal.midpoint=geometry.Midpoint(portal.left,portal.right)
    end
    table.sort(value.portals,function(a,b)
        if a.to~=b.to then return a.to<b.to end
        if a.left[1]~=b.left[1] then return a.left[1]<b.left[1] end
        return a.left[3]<b.left[3]
    end)
    return value
end
local function add(data,value)
    if data.polygons[value.id] then return nil,"duplicate polygon" end
    local b=value.bounds
    local known=data.meta.bounds
    if b[1]<known[1]-.002 or b[2]<known[2]-.002 or b[3]>known[3]+.002 or b[4]>known[4]+.002 then
        return nil,"polygon leaves sourced terrain bounds"
    end
    for _,box in ipairs(data.meta.exclusions or {}) do
        if b[1]<=box[3] and b[3]>=box[1] and b[2]<=box[4] and b[4]>=box[2] then return nil,"polygon enters excluded geometry" end
    end
    for x=math.floor(b[1]/CELL),math.floor(b[3]/CELL) do
        for z=math.floor(b[2]/CELL),math.floor(b[4]/CELL) do
            local id=x..":"..z
            local cell=data.cells[id]
            if not cell then
                if data.cellCount>=MAX_CELLS then return nil,"navigation spatial index limit" end
                cell={}; data.cells[id]=cell; data.cellCount=data.cellCount+1
            end
            if #cell>=MAX_CELL_POLYGONS then return nil,"navigation cell limit" end
            cell[#cell+1]=value.id
        end
    end
    data.polygons[value.id]=value; data.order[#data.order+1]=value.id
    data.edges=data.edges+#value.portals
    if #data.order>MAX_POLYGONS or data.edges>MAX_PORTALS then return nil,"navigation capacity" end
    return true
end
local function ingest(data,shards)
    for _,shard in ipairs(shards) do
        if not schema.PlainTable(shard) or not schema.Identity(shard.identity) or not same(shard.identity,data.meta.identity)
            or not schema.List(shard.polygons,1024) then return nil,"invalid navigation shard" end
        local edges=0
        for _,raw in ipairs(shard.polygons) do
            local value,reason=polygon(raw)
            if not value then return nil,reason end
            edges=edges+#value.portals
            if edges>4096 then return nil,"shard portal limit" end
            local ok,problem=add(data,value)
            if not ok then return nil,problem end
            coroutine.yield()
        end
    end
    if #data.order~=data.meta.counts.polygons or data.edges~=data.meta.counts.portals then return nil,"partial navigation dataset" end
    table.sort(data.order)
    for _,id in ipairs(data.order) do
        local value=data.polygons[id]
        for _,portal in ipairs(value.portals) do
            local target=data.polygons[portal.to]
            -- Detour clips external links to 8-bit fractions; target endpoints may differ by <.01 yard.
            if not target or not geometry.OnBoundary(target.points,portal.left,.01)
                or not geometry.OnBoundary(target.points,portal.right,.01)
                or not geometry.Contains(value.points,portal.midpoint[1],portal.midpoint[3])
                or not geometry.Contains(target.points,portal.midpoint[1],portal.midpoint[3]) then return nil,"unmatched navigation portal" end
            for _,point in ipairs({portal.left,portal.right,portal.midpoint}) do
                local sourceHeight=geometry.BoundaryHeight(value.points,point)
                local targetHeight=geometry.BoundaryHeight(target.points,point,.01)
                if not sourceHeight or not targetHeight or math.abs(point[2]-sourceHeight)>.002
                    or math.abs(sourceHeight-targetHeight)>data.meta.modeledMaxStep+.002 then
                    return nil,"portal exceeds modeled vertical step"
                end
            end
            portal.meters=geometry.Distance(value.center,portal.midpoint)+geometry.Distance(portal.midpoint,target.center)
        end
        coroutine.yield()
    end
    return true
end
local function boundaryMatches(data,matches)
    if #matches==1 then return matches[1] end
    if #matches>8 then return nil end
    local seen={[matches[1].id]=true}
    for _=1,#matches do
        for _,a in ipairs(matches) do
            if seen[a.id] then
                for _,b in ipairs(matches) do
                    if not seen[b.id] and math.abs(a.point[2]-b.point[2])<=.002 then
                        for _,edge in ipairs(data.polygons[a.id].portals) do
                            if edge.to==b.id and geometry.OnBoundary({edge.left,edge.right},a.point,.002) then
                                seen[b.id]=true
                            end
                        end
                    end
                end
            end
        end
    end
    local best=matches[1]
    for _,match in ipairs(matches) do
        if not seen[match.id] then return nil end
        if match.id<best.id then best=match end
    end
    return best
end
local function locate(data,point)
    if not schema.PlainTable(point) or not schema.Number(point.x,-100000,100000)
        or not schema.Number(point.z,-100000,100000)
        or (point.height~=nil and not schema.Number(point.height,-100000,100000)) then return nil,"invalid point" end
    local matches={}
    for _,id in ipairs(data.cells[key(point.x,point.z)] or {}) do
        local value=data.polygons[id]
        if geometry.Contains(value.points,point.x,point.z) then
            local height=geometry.Height(value.points,point.x,point.z)
            if height and (point.height==nil or math.abs(height-point.height)<=1) then
                matches[#matches+1]={id=id,point={point.x,height,point.z}}
            end
        end
    end
    if #matches==0 then return nil,"outside known navigation polygons" end
    local match=boundaryMatches(data,matches)
    return match,match and nil or "Floor or polygon boundary is ambiguous",matches
end
local function distinctFloors(data,matches)
    local groups={}
    for _,value in ipairs(matches or {}) do
        local group
        for _,existing in ipairs(groups) do
            if math.abs(existing[1].point[2]-value.point[2])<=.002 then group=existing;break end
        end
        if not group then group={};groups[#groups+1]=group end
        group[#group+1]=value
    end
    if #groups<2 or #groups>4 then return nil end
    local result={}
    for _,group in ipairs(groups) do
        local value=boundaryMatches(data,group)
        if not value then return nil end
        result[#result+1]=value
    end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end
-- One yard is a marker-displacement bound, not an interaction or movement radius.
local APPROACH_RADIUS,APPROACH_INSET=1,.005
local MAX_MARKER_RADIUS,NEAREST_SURFACE_BAND,CONTINUITY_DISTANCE=8,.25,3
local function inside(box,x,z) return x>=box[1] and x<=box[3] and z>=box[2] and z<=box[4] end
local function approachCovered(data,goal,radius)
    if not inside(data.meta.bounds,goal.x,goal.z) then return false end
    for _,box in ipairs(data.meta.exclusions or {}) do
        -- Do not approach across an excluded footprint even when the marker is just outside it.
        if goal.x+radius>=box[1] and goal.x-radius<=box[3]
            and goal.z+radius>=box[2] and goal.z-radius<=box[4] then return false end
    end
    return true
end
local function candidate(data,id,goal,radius)
    local poly=data.polygons[id]
    local point,gap=geometry.ClosestBoundary(poly.points,goal.x,goal.z)
    if not gap or gap>radius then return nil end
    local distance=geometry.Distance(point,poly.center)
    local t=math.min(1,APPROACH_INSET/math.max(distance,APPROACH_INSET))
    local x,z=point[1]+t*(poly.center[1]-point[1]),point[3]+t*(poly.center[3]-point[3])
    local height=geometry.Height(poly.points,x,z)
    if not height then return nil end
    return {id=id,point={x,height,z},gap=math.sqrt((x-goal.x)^2+(z-goal.z)^2),height=point[2]}
end
local function approachFloor(data,best,candidates,uncertainVicinity)
    if not best then return nil,"No modeled approach within marker vicinity" end
    -- Nearby equally plausible floors remain ambiguous; distant hills do not compete.
    local low,high=best.height,best.height
    for _,value in ipairs(candidates) do
        if value.gap<=best.gap+NEAREST_SURFACE_BAND then
            low=math.min(low,value.height);high=math.max(high,value.height)
            if high-low>data.meta.modeledMaxStep then
                if not uncertainVicinity then return nil,"Marker approach floor is ambiguous" end
                best.floorUncertain=true
            end
        end
        coroutine.yield()
    end
    local resolved,reason=locate(data,{x=best.point[1],z=best.point[3]})
    if not resolved or resolved.id~=best.id then return nil,reason or "Marker approach floor is ambiguous" end
    return best
end
local function approachEndpoint(data,goal,metrics,radius,uncertainVicinity)
    local best,seen,candidates=nil,{},{}
    for x=math.floor((goal.x-radius)/CELL),math.floor((goal.x+radius)/CELL) do
        for z=math.floor((goal.z-radius)/CELL),math.floor((goal.z+radius)/CELL) do
            for _,id in ipairs(data.cells[x..":"..z] or {}) do
                if not seen[id] then
                    seen[id]=true; metrics.endpointChecks=metrics.endpointChecks+1
                    local value=candidate(data,id,goal,radius)
                    if value then
                        candidates[#candidates+1]=value
                        if value.gap<=radius and (not best or value.gap<best.gap
                            or (value.gap==best.gap and value.id<best.id)) then best=value end
                    end
                end
                coroutine.yield()
            end
        end
    end
    return approachFloor(data,best,candidates,uncertainVicinity)
end
local function approachResult(data,status,detail,metrics)
    return {status=status,detail=detail,metrics=metrics,nativeVerified=false,revision=data.meta.revision}
end
local function reachableCandidates(data,goal,last,options,metrics)
    local radius=options.markerRadius or APPROACH_RADIUS
    local result,seen={},{}
    if not options.reachableApproach or goal.height~=nil or not approachCovered(data,goal,radius) then return result end
    for x=math.floor((goal.x-radius)/CELL),math.floor((goal.x+radius)/CELL) do
        for z=math.floor((goal.z-radius)/CELL),math.floor((goal.z+radius)/CELL) do
            for _,id in ipairs(data.cells[x..":"..z] or {}) do
                if not seen[id] then
                    seen[id]=true;metrics.endpointChecks=metrics.endpointChecks+1
                    local value=candidate(data,id,goal,radius)
                    if value and value.gap<=radius
                        and math.abs(value.point[2]-last.point[2])<=data.meta.modeledMaxStep then
                        local unique=locate(data,{x=value.point[1],z=value.point[3]})
                        if unique and unique.id==id then result[#result+1]=value end
                    end
                end
                coroutine.yield()
            end
        end
    end
    return result
end
local function exactApproachWorker(data,start,goal,last,options,metrics)
    local candidates=reachableCandidates(data,goal,last,options,metrics)
    local job,issue=planner.NavSearch.Begin(data,start,goal,options,locate,candidates)
    if not job then return approachResult(data,"unknown-target",issue,metrics) end
    while true do
        local result=job:Step(1)
        if result then result.metrics.endpointChecks=metrics.endpointChecks;return result end
        coroutine.yield()
    end
end
local function approachWorker(data,start,goal,options,metrics)
    local endpoint,reason=approachEndpoint(data,goal,metrics,options.markerRadius or APPROACH_RADIUS,options.uncertainVicinity)
    if not endpoint then return approachResult(data,"unknown-target",reason,metrics) end
    local job,issue=planner.NavSearch.Begin(data,start,{x=endpoint.point[1],z=endpoint.point[3]},options,locate)
    if not job then return approachResult(data,"unknown-target",issue,metrics) end
    while true do
        local result=job:Step(1)
        if result then
            result.metrics.endpointChecks=metrics.endpointChecks
            if result.status=="modeled" then
                result.approach={kind="observed-marker-vicinity",marker=schema.Clone(goal),gap=endpoint.gap,
                    radius=options.markerRadius or APPROACH_RADIUS,finalLegVerified=false,interactionVerified=false}
                if endpoint.floorUncertain then
                    result.approach.kind="observed-marker-uncertain-vicinity"
                    result.approach.reason="nearby-marker-floors-ambiguous"
                end
                result.detail="Modeled approach; final gap and interaction unverified"
            end
            return result
        end
        coroutine.yield()
    end
end
local function beginApproach(data,start,goal,options)
    local first,issue=locate(data,start)
    if not first then return nil,issue end
    local last,reason,matches=locate(data,goal)
    local settings=schema.Copy(options or {})
    if not schema.PlainTable(settings) or not schema.Integer(settings.maxWork or 16384,1,262145)
        or not schema.Number(settings.speed or 7,.1,100)
        or not schema.Number(settings.markerRadius or APPROACH_RADIUS,1,MAX_MARKER_RADIUS) then return nil,"invalid navigation limits" end
    for _,name in ipairs({"commonApproach","uncertainVicinity","reachableApproach"}) do
        if settings[name]~=nil and type(settings[name])~="boolean" then return nil,"invalid navigation limits" end
    end
    if not last and reason~="outside known navigation polygons" then
        local floors=reason=="Floor or polygon boundary is ambiguous" and settings.commonApproach
            and goal.height==nil and distinctFloors(data,matches)
        if floors and approachCovered(data,goal,settings.markerRadius or APPROACH_RADIUS) then
            return planner.NavSearch.Begin(data,start,goal,settings,locate,nil,floors)
        end
        return nil,reason
    end
    if last and not settings.reachableApproach then return planner.NavSearch.Begin(data,start,goal,settings,locate) end
    if not last and (goal.height~=nil or not approachCovered(data,goal,settings.markerRadius or APPROACH_RADIUS)) then
        return nil,"Marker approach outside sourced coverage"
    end
    start,goal=schema.Clone(start),schema.Clone(goal)
    local metrics={endpointChecks=0}
    local worker=coroutine.create(function()
        if last then return exactApproachWorker(data,schema.Clone(start),schema.Clone(goal),last,settings,metrics) end
        return approachWorker(data,schema.Clone(start),schema.Clone(goal),settings,metrics)
    end)
    local cancelled,output=false,nil
    return {
        Cancel=function() cancelled=true end,
        Step=function(_,budget)
            if cancelled then return approachResult(data,"cancelled","navigation request changed",metrics) end
            if output then return schema.Clone(output) end
            if not schema.Integer(budget or 32,1,128) then return nil,"invalid navigation slice" end
            for _=1,budget or 32 do
                local ok,result=coroutine.resume(worker)
                if not ok then output=approachResult(data,"invalid","marker approach failed",metrics)
                elseif coroutine.status(worker)=="dead" then output=result end
                if output then return schema.Clone(output) end
            end
        end,
    }
end
local function publish(data)
    return {
        Revision=function() return data.meta.revision end,
        Metadata=function() return schema.Clone(data.meta) end,
        Locate=function(_,point) return locate(data,point) end,
        LocateContinued=function(_,point,previous)
            local result,reason=locate(data,point)
            if not schema.PlainTable(point) or point.height~=nil or not schema.PlainTable(previous)
                or not geometry.Point(previous.point) or not schema.Number(point.x,-100000,100000)
                or not schema.Number(point.z,-100000,100000) then return result,reason end
            if (point.x-previous.point[1])^2+(point.z-previous.point[3])^2>CONTINUITY_DISTANCE^2 then return result,reason end
            local matches=geometry.FollowSurface(data,previous,point,CONTINUITY_DISTANCE)
            if result and matches and #matches==0 then matches=geometry.FollowLocalSurface(data,previous,point,CONTINUITY_DISTANCE) end
            if matches and #matches>0 then
                local continued=boundaryMatches(data,matches)
                if continued then return continued end
            end
            -- A disconnected floor cannot replace established continuity at an overlap.
            return nil,reason or "Movement left the connected walking surface"
        end,
        Project=function(_,mapID,x,y)
            if mapID~=data.meta.uiMapID or not schema.Number(x,0,1) or not schema.Number(y,0,1) then return nil end
            local p=data.meta.projection
            return {x=p.originY-x*p.width,z=p.originX-y*p.height}
        end,
        Unproject=function(_,point)
            if not geometry.Point(point) then return nil end
            local p=data.meta.projection
            return {mapID=data.meta.uiMapID,x=(p.originY-point[1])/p.width,y=(p.originX-point[3])/p.height}
        end,
        BeginMarkerApproach=function(_,start,goal,options)
            return beginApproach(data,schema.Clone(start),schema.Clone(goal),options)
        end,
        Begin=function(_,start,goal,options)
            return planner.NavSearch.Begin(data,start,goal,options,locate)
        end,
    }
end
function mesh.Begin(rawMeta,shards)
    local meta,reason=metadata(rawMeta)
    if not meta then return nil,reason end
    if not schema.List(shards,512) then return nil,"navigation shard limit" end
    local data={meta=meta,polygons={},order={},cells={},cellCount=0,edges=0}
    local worker=coroutine.create(function() return ingest(data,shards) end)
    local cancelled,done=false,false
    return {
        Cancel=function() cancelled=true end,
        Step=function(_,budget)
            if cancelled then return nil,"cancelled",true end
            if done then return nil,"loader already finished",true end
            if not schema.Integer(budget or 8,1,64) then return nil,"invalid load budget",true end
            for _=1,budget or 8 do
                local ok,value,problem=coroutine.resume(worker)
                if not ok then done=true; return nil,"invalid navigation input",true end
                if coroutine.status(worker)=="dead" then
                    done=true
                    if not value then return nil,problem,true end
                    return publish(data),nil,true
                end
            end
        end,
    }
end
