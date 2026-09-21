-- Geometry predicates for a derived navigation mesh; coordinates are [worldY,height,worldX].
local planner, schema = RikUI.QuestPlanner, RikUI.QuestPlanner.Schema
local geometry = {}
planner.NavGeometry = geometry
local EPSILON, EDGE_TOLERANCE = .00001, .002
local LOOKAHEAD_PORTALS, PORTAL_MARGIN, CONTINUATION = 64, .0001, .25
local LOOKAHEAD_YARDS = 24
local MAX_CONTINUITY_POLYGONS = 64
local ANTICIPATION, CONTINUATION_TRIES = 6, 6
function geometry.Point(value)
    return schema.List(value,3) and #value==3 and schema.Number(value[1],-100000,100000)
        and schema.Number(value[2],-100000,100000) and schema.Number(value[3],-100000,100000)
end
function geometry.Distance(a,b)
    return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2+(a[3]-b[3])^2)
end
function geometry.Midpoint(a,b) return {(a[1]+b[1])/2,(a[2]+b[2])/2,(a[3]+b[3])/2} end
local function cross(a,b,c) return (b[1]-a[1])*(c[3]-a[3])-(b[3]-a[3])*(c[1]-a[1]) end
function geometry.Convex(points)
    if not schema.List(points,6) or #points<3 then return false end
    local sign,area=0,0
    for _,point in ipairs(points) do if not geometry.Point(point) then return false end end
    for index,a in ipairs(points) do
        local b,c=points[index%#points+1],points[(index+1)%#points+1]
        local turn=cross(a,b,c)
        if math.abs(turn)>EPSILON then
            if sign~=0 and sign*turn<0 then return false end
            sign=turn
        end
        area=area+a[1]*b[3]-b[1]*a[3]
    end
    if sign==0 or math.abs(area)<=EPSILON then return false end
    for index,a in ipairs(points) do
        local b=points[index%#points+1]
        for _,point in ipairs(points) do
            if cross(a,b,point)*sign < -EPSILON then return false end
        end
    end
    return true
end
function geometry.Contains(points,x,z)
    local sign=0
    for index,a in ipairs(points) do
        local b=points[index%#points+1]
        local value=(b[1]-a[1])*(z-a[3])-(b[3]-a[3])*(x-a[1])
        if math.abs(value)>EPSILON then
            if sign~=0 and value*sign<0 then return false end
            sign=value
        end
    end
    return true
end
function geometry.Height(points,x,z)
    local a=points[1]
    for index=2,#points-1 do
        local b,c=points[index],points[index+1]
        local denominator=cross(a,b,c)
        if math.abs(denominator)>EPSILON then
            local u=((x-a[1])*(c[3]-a[3])-(z-a[3])*(c[1]-a[1]))/denominator
            local v=((b[1]-a[1])*(z-a[3])-(b[3]-a[3])*(x-a[1]))/denominator
            if u>=-EPSILON and v>=-EPSILON and u+v<=1+EPSILON then return a[2]+u*(b[2]-a[2])+v*(c[2]-a[2]) end
        end
    end
end
function geometry.BoundaryHeight(points,point,tolerance)
    local closest,height
    for index,a in ipairs(points) do
        local b=points[index%#points+1]
        local dx,dz=b[1]-a[1],b[3]-a[3]
        local length=dx*dx+dz*dz
        if length>EPSILON then
            local t=((point[1]-a[1])*dx+(point[3]-a[3])*dz)/length
            t=math.max(0,math.min(1,t))
            local errorX,errorZ=point[1]-a[1]-t*dx,point[3]-a[3]-t*dz
            local distance=errorX*errorX+errorZ*errorZ
            if distance<=(tolerance or EDGE_TOLERANCE)^2 and (not closest or distance<closest) then
                closest,height=distance,a[2]+t*(b[2]-a[2])
            end
        end
    end
    return height
end
function geometry.OnBoundary(points,point,tolerance)
    return geometry.BoundaryHeight(points,point,tolerance)~=nil
end
-- Closest horizontal boundary point; this is geometry, never a traversable link.
function geometry.ClosestBoundary(points,x,z)
    local closest,distance
    for index,a in ipairs(points) do
        local b=points[index%#points+1]
        local dx,dz=b[1]-a[1],b[3]-a[3]
        local length=dx*dx+dz*dz
        if length>EPSILON then
            local t=math.max(0,math.min(1,((x-a[1])*dx+(z-a[3])*dz)/length))
            local point={a[1]+t*dx,a[2]+t*(b[2]-a[2]),a[3]+t*dz}
            local squared=(x-point[1])^2+(z-point[3])^2
            if not distance or squared<distance then closest,distance=point,squared end
        end
    end
    return closest,distance and math.sqrt(distance)
end
-- Follow a short observed displacement through explicit portals from the previous
-- modeled floor. This is continuity evidence, never a new native altitude reading.
local function motionCrossing(origin,target,gate,after)
    local rx,rz=target.x-origin[1],target.z-origin[3]
    local a,b=gate.left,gate.right
    local sx,sz=b[1]-a[1],b[3]-a[3]
    local denominator=rx*sz-rz*sx
    if math.abs(denominator)<EPSILON then return end
    local qx,qz=a[1]-origin[1],a[3]-origin[3]
    local t,u=(qx*sz-qz*sx)/denominator,(qx*rz-qz*rx)/denominator
    if t<after-EPSILON or t<0 or t>1 or u<0 or u>1 then return end
    return t,origin[1]+t*rx,origin[3]+t*rz
end
local function motionNeighbors(data,origin,target,node,queue,seen)
    for _,gate in ipairs(data.polygons[node.id].portals) do
        if not seen[gate.to] then
            local t,x,z=motionCrossing(origin,target,gate,node.t)
            if t and geometry.Contains(data.polygons[node.id].points,x,z)
                and geometry.Contains(data.polygons[gate.to].points,x,z) then
                seen[gate.to]=true
                queue[#queue+1]={id=gate.to,t=t}
            end
        end
    end
end
function geometry.FollowSurface(data,previous,target,limit)
    if not previous or not data.polygons[previous.id] or not geometry.Point(previous.point) then return end
    local surface=data.polygons[previous.id].points
    local origin=previous.point
    local height=geometry.Height(surface,origin[1],origin[3])
    if not height or math.abs(height-origin[2])>EDGE_TOLERANCE then return end
    if (target.x-origin[1])^2+(target.z-origin[3])^2>limit^2 then return end
    local queue,seen,matches={{id=previous.id,t=0}},{[previous.id]=true},{}
    for at=1,MAX_CONTINUITY_POLYGONS do
        local node=queue[at]
        if not node then return matches end
        local points=data.polygons[node.id].points
        if geometry.Contains(points,target.x,target.z) then
            local y=geometry.Height(points,target.x,target.z)
            if y then matches[#matches+1]={id=node.id,point={target.x,y,target.z},floorSource="modeled-continuity"} end
        else motionNeighbors(data,origin,target,node,queue,seen) end
    end
    -- Too many crossed surfaces is a new location problem, not permission to snap.
end
-- A shortcut must cross every directed corridor portal, in order, on both modeled
-- surfaces. Convexity then keeps each intervening segment inside its polygon.
local function crossings(route,origin,target,first,last)
    local rx,rz=target[1]-origin[1],target[3]-origin[3]
    local previous,result=0,{}
    for index=first,last-1 do
        local gate=route.portals[index]
        local a,b=gate.left,gate.right
        local sx,sz=b[1]-a[1],b[3]-a[3]
        local denominator=rx*sz-rz*sx
        if math.abs(denominator)<EPSILON then return nil end
        local qx,qz=a[1]-origin[1],a[3]-origin[3]
        local t,u=(qx*sz-qz*sx)/denominator,(qx*rz-qz*rx)/denominator
        if t<previous or t>1 or u<=PORTAL_MARGIN or u>=1-PORTAL_MARGIN then return nil end
        local x,z=origin[1]+t*rx,origin[3]+t*rz
        local from,to=route.surfaces[index],route.surfaces[index+1]
        if not geometry.Contains(from,x,z) or not geometry.Contains(to,x,z) then return nil end
        result[#result+1]={x,geometry.Height(from,x,z),z}
        previous=t
    end
    return result
end
-- Clip a future portal to the angular window of every earlier portal.
-- This only proposes a target: crossings still proves order and surface membership.
local function clipHalfPlane(lo,hi,a,b)
    if a<0 and b<0 then return nil end
    if a>=0 and b>=0 then return lo,hi end
    local cut=a/(a-b)
    if a<0 then lo=math.max(lo,cut) else hi=math.min(hi,cut) end
    if lo>=hi then return nil end
    return lo,hi
end
local function rayPortalFraction(origin,goal,a,b)
    local rx,rz=goal[1]-origin[1],goal[3]-origin[3]
    local sx,sz=b[1]-a[1],b[3]-a[3]
    local denominator=rx*sz-rz*sx
    if math.abs(denominator)<EPSILON then return end
    local qx,qz=a[1]-origin[1],a[3]-origin[3]
    if (qx*sz-qz*sx)/denominator<=0 then return end
    return (qx*rz-qz*rx)/denominator
end
local function visiblePortal(route,origin,first,last,preferred)
    local target=route.portals[last-1]
    local a,b=target.left,target.right
    local lo,hi=PORTAL_MARGIN*2,1-PORTAL_MARGIN*2
    for at=first,last-2 do
        local gate=route.portals[at]
        local sign=cross(origin,gate.left,gate.right)
        if math.abs(sign)>EPSILON then
            sign=sign>0 and 1 or -1
            lo,hi=clipHalfPlane(lo,hi,sign*cross(origin,gate.left,a),sign*cross(origin,gate.left,b))
            if not lo then return end
            lo,hi=clipHalfPlane(lo,hi,-sign*cross(origin,gate.right,a),-sign*cross(origin,gate.right,b))
            if not lo then return end
        end
    end
    -- When the destination lies behind this portal (a cave bend/U-turn), use
    -- the local corridor direction instead of dragging the aim to its midpoint.
    local goal=preferred or route.points[#route.points]
    local t=rayPortalFraction(origin,goal,a,b)
        or rayPortalFraction(origin,route.points[last*2] or goal,a,b) or (lo+hi)/2
    -- Keep an interior angular margin without pulling every aim to a polygon center.
    local inset=(hi-lo)*.02
    t=math.max(lo+inset,math.min(hi-inset,t))
    return {a[1]+t*(b[1]-a[1]),a[2]+t*(b[2]-a[2]),a[3]+t*(b[3]-a[3])}
end
local function rayContinuation(route,origin,gate,first,last)
    local dx,dz=gate[1]-origin[1],gate[3]-origin[3]
    local length=math.sqrt(dx*dx+dz*dz)
    if length<EPSILON then return end
    dx,dz=dx/length,dz/length
    local surface=route.surfaces[last]
    local low,high=0,ANTICIPATION
    -- Convex containment bounds a forward ray inside the entered polygon.
    for _=1,10 do
        local distance=(low+high)/2
        if geometry.Contains(surface,gate[1]+dx*distance,gate[3]+dz*distance) then low=distance else high=distance end
    end
    if low<.01 then return end
    local x,z=gate[1]+dx*low*.8,gate[3]+dz*low*.8
    local height=geometry.Height(surface,x,z)
    if not height then return end
    local target={x,height,z}
    local proof=crossings(route,origin,target,first,last)
    if proof then return target,proof,last end
end
local function finalPortalAim(route,origin,gate,first,last)
    if last~=#route.corridor then return end
    local endpoint=route.points[#route.points]
    local ratio=1
    for _=1,CONTINUATION_TRIES do
        local target={}
        for at=1,3 do target[at]=gate[at]+ratio*(endpoint[at]-gate[at]) end
        local proof=crossings(route,origin,target,first,last)
        if proof then return target,proof,last end
        ratio=ratio/2
    end
end
local function portalAim(route,origin,first,last,preferred)
    local gate=visiblePortal(route,origin,first,last,preferred)
    if not gate then return end
    -- Turn into the final approach instead of overshooting its entrance ray.
    local final,finalProof=finalPortalAim(route,origin,gate,first,last)
    if final then return final,finalProof,last end
    local ray,proof=rayContinuation(route,origin,gate,first,last)
    if ray then return ray,proof,last end
    local center=route.points[last*2]
    local distance=geometry.Distance(gate,center)
    local ratio=distance>0 and math.min(1,ANTICIPATION/distance) or 1
    -- Try progressively shorter interior continuations, always with corridor proof.
    for _=1,CONTINUATION_TRIES do
        local target={}
        for at=1,3 do target[at]=gate[at]+ratio*(center[at]-gate[at]) end
        local crossed=crossings(route,origin,target,first,last)
        if crossed then return target,crossed,last end
        ratio=ratio/2
    end
end
local function lookaheadEnd(route,origin,index)
    local last=index
    local previous,distance=origin,0
    for at=index,math.min(#route.corridor-1,index+LOOKAHEAD_PORTALS-1) do
        local point=route.portals[at].midpoint
        distance=distance+geometry.Distance(previous,point)
        previous,last=point,at+1
        -- Spatial horizon adapts to tessellation; the hard cap bounds proof work.
        if distance>=LOOKAHEAD_YARDS and at-index+1>=12 then break end
    end
    return last
end
local function corridorAim(route,origin,index)
    if index==#route.corridor then return route.points[#route.points],{},index end
    if not route.portals or not route.surfaces then
        return route.points[index*2+1],{},index
    end
    -- Aim through the visible corridor, not at the next breadcrumb to be collected.
    for last=lookaheadEnd(route,origin,index),index+1,-1 do
        local target=last==#route.corridor and route.points[#route.points] or route.points[last*2]
        local crossed=last==#route.corridor and crossings(route,origin,target,index,last)
        if crossed then return target,crossed,last end
        local visible,proof=portalAim(route,origin,index,last)
        if visible then return visible,proof,last end
        crossed=crossings(route,origin,target,index,last)
        if crossed then return target,crossed,last end
    end
    -- A short continuation beyond the first portal avoids stopping on its boundary.
    local gate=route.portals[index].midpoint
    local center=route.points[(index+1)*2]
    local distance=geometry.Distance(gate,center)
    local ratio=distance>0 and math.min(1,CONTINUATION/distance) or 1
    local target={}
    for at=1,3 do target[at]=gate[at]+ratio*(center[at]-gate[at]) end
    local crossed=crossings(route,origin,target,index,index+1)
    if crossed then return target,crossed,index+1 end
    return gate,{},index
end
function geometry.CorridorAim(route,origin,index,previous)
    local target,proof,last=corridorAim(route,origin,index)
    if not previous or previous.index<index or previous.index-index>LOOKAHEAD_PORTALS
        or not route.surfaces or not route.portals then return target,proof,last end
    local old=previous.point
    local dx,dz=old[1]-origin[1],old[3]-origin[3]
    if dx*(target[1]-origin[1])+dz*(target[3]-origin[3])>=0
        or dx*dx+dz*dz<=1 then return target,proof,last end
    local surface=route.surfaces[previous.index]
    if not surface or not geometry.Contains(surface,old[1],old[3]) then return target,proof,last end
    local retained=crossings(route,origin,old,index,previous.index)
    -- Retain a still-visible aim only to suppress opposite-direction oscillation.
    -- Crossing a wall, a passed polygon or a necessary corner invalidates it.
    if retained then return old,retained,previous.index end
    for at=lookaheadEnd(route,origin,index),index+1,-1 do
        local adjusted,crossed=portalAim(route,origin,index,at,old)
        if adjusted and dx*(adjusted[1]-origin[1])+dz*(adjusted[3]-origin[3])>0 then
            return adjusted,crossed,at
        end
    end
    return target,proof,last
end
-- Screen-space sampling keeps animation work bounded even for mostly off-screen routes.
local function clipAxis(a,d,low,high,first,last)
    if math.abs(d)<.000001 then if a<low or a>high then return nil end;return first,last end
    local enter,leave=(low-a)/d,(high-a)/d
    if enter>leave then enter,leave=leave,enter end
    first,last=math.max(first,enter),math.min(last,leave)
    if first>last then return nil end
    return first,last
end
function geometry.ScreenAnts(points,width,height,phase,limit,round)
    local result,total,attempts={},0,0
    local gap,margin=14,3
    for at=2,math.min(#points,2049) do
        local a,b=points[at-1],points[at]
        local dx,dy=b[1]-a[1],b[2]-a[2]
        local length=math.sqrt(dx*dx+dy*dy)
        local first,last=clipAxis(a[1],dx,margin,width-margin,0,1)
        if first then first,last=clipAxis(a[2],dy,margin,height-margin,first,last) end
        if first and length>.000001 then
            local nextDistance=math.ceil((total+first*length-phase)/gap)*gap+phase
            while nextDistance<=total+last*length and #result<limit and attempts<1024 do
                attempts=attempts+1
                local t=(nextDistance-total)/length
                local x,y=a[1]+dx*t,a[2]+dy*t
                if not round or ((x-width/2)/(width/2-margin))^2+((y-height/2)/(height/2-margin))^2<=1 then
                    result[#result+1]={x,y}
                end
                nextDistance=nextDistance+gap
            end
        end
        total=total+length
        if #result>=limit or attempts>=1024 then break end
    end
    return result
end
function geometry.MinimapPoint(point,position,mapWidth,mapHeight,width,height,radius,rotation)
    local x,y=(point.x-position.x)*mapWidth,(point.y-position.y)*mapHeight
    local c,s=math.cos(rotation),math.sin(rotation)
    return {width/2+(x*c-y*s)*width/(2*radius),height/2+(x*s+y*c)*height/(2*radius)}
end
function geometry.Bounds(points)
    local bounds={points[1][1],points[1][3],points[1][1],points[1][3]}
    for _,point in ipairs(points) do
        bounds[1],bounds[2]=math.min(bounds[1],point[1]),math.min(bounds[2],point[3])
        bounds[3],bounds[4]=math.max(bounds[3],point[1]),math.max(bounds[4],point[3])
    end
    return bounds
end
