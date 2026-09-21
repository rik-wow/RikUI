-- Geometry predicates for a derived navigation mesh; coordinates are [worldY,height,worldX].
local planner, schema = RikUI.QuestPlanner, RikUI.QuestPlanner.Schema
local geometry = {}
planner.NavGeometry = geometry
local EPSILON, EDGE_TOLERANCE = .00001, .002
local LOOKAHEAD_PORTALS, PORTAL_MARGIN, CONTINUATION = 12, .0001, .25
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
function geometry.CorridorAim(route,origin,index)
    if index==#route.corridor then return route.points[#route.points],{},index end
    if not route.portals or not route.surfaces then
        return route.points[index*2+1],{},index
    end
    -- At most 12 portals ahead: 78 candidate intersection tests plus one fallback.
    for last=math.min(#route.corridor,index+LOOKAHEAD_PORTALS),index+1,-1 do
        local target=last==#route.corridor and route.points[#route.points] or route.points[last*2]
        local crossed=crossings(route,origin,target,index,last)
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
function geometry.Bounds(points)
    local bounds={points[1][1],points[1][3],points[1][1],points[1][3]}
    for _,point in ipairs(points) do
        bounds[1],bounds[2]=math.min(bounds[1],point[1]),math.min(bounds[2],point[3])
        bounds[3],bounds[4]=math.max(bounds[3],point[1]),math.max(bounds[4],point[3])
    end
    return bounds
end
