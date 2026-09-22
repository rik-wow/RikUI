-- Portal funnel over a validated corridor. Heights are sampled at every crossing.
local geometry=RikUI.QuestPlanner.NavGeometry
local EPS=1e-5
local function copy(p) return {p[1],p[2],p[3]} end
local function cross(a,b,c) return (b[1]-a[1])*(c[3]-a[3])-(b[3]-a[3])*(c[1]-a[1]) end
local function same(a,b) return (a[1]-b[1])^2+(a[3]-b[3])^2<=EPS*EPS end
local function tolerance(a,b,c)
    return EPS*(math.abs(b[1]-a[1])+math.abs(b[3]-a[3])+math.abs(c[1]-a[1])+math.abs(c[3]-a[3])+EPS)
end
local function pause(yieldFn) if yieldFn then yieldFn() end end
local function height(surface,p)
    return geometry.Height(surface,p[1],p[3]) or geometry.BoundaryHeight(surface,p,EPS*8)
end
local function oriented(route,first,start,target,yieldFn)
    local gates={{left=copy(start),right=copy(start),index=first-1}}
    for j=first,#route.corridor-1 do
        pause(yieldFn)
        local source=route.portals and route.portals[j]
        if not source or not source.left or not source.right then return nil,"missing corridor portal" end
        local left,right=copy(source.left),copy(source.right)
        local side=0
        for _,point in ipairs(route.surfaces[j]) do
            local value=cross(left,right,point)
            if math.abs(value)>math.abs(side) then side=value end
        end
        -- Normalize against the FROM polygon, independent of goal bearing.
        if side>0 then left,right=right,left end
        if side==0 and not same(left,right) then return nil,"ambiguous portal orientation" end
        gates[#gates+1]={left=left,right=right,index=j}
    end
    gates[#gates+1]={left=copy(target),right=copy(target),index=#route.corridor}
    return gates
end
local function corners(gates,yieldFn)
    local result={{point=gates[1].left,index=gates[1].index}}
    local apex,left,right=gates[1].left,gates[1].left,gates[1].right
    local ai,li,ri,i,work=1,1,1,2,0
    while i<=#gates do
        pause(yieldFn);work=work+1
        if work>#gates*#gates*4+8 then return nil,"nonprogressing funnel" end
        local nl,nr,restart=gates[i].left,gates[i].right,false
        -- Conventional cross; Mononen's triarea2 has the opposite sign.
        if cross(apex,right,nr)>=-tolerance(apex,right,nr) then
            if same(apex,right) or cross(apex,left,nr)<-tolerance(apex,left,nr) then right,ri=nr,i
            else
                if li<=ai then return nil,"nonprogressing left funnel" end
                result[#result+1]={point=copy(left),index=gates[li].index}
                apex,ai=left,li;left,right,li,ri=apex,apex,ai,ai;i,restart=ai+1,true
            end
        end
        if not restart and cross(apex,left,nl)<=tolerance(apex,left,nl) then
            if same(apex,left) or cross(apex,right,nl)>tolerance(apex,right,nl) then left,li=nl,i
            else
                if ri<=ai then return nil,"nonprogressing right funnel" end
                result[#result+1]={point=copy(right),index=gates[ri].index}
                apex,ai=right,ri;left,right,li,ri=apex,apex,ai,ai;i,restart=ai+1,true
            end
        end
        if not restart then i=i+1 end
    end
    if result[#result].index~=gates[#gates].index then
        result[#result+1]={point=copy(gates[#gates].left),index=gates[#gates].index}
    end
    return result
end
local function intersection(a,b,l,r,previous)
    local dx,dz,ex,ez=b[1]-a[1],b[3]-a[3],r[1]-l[1],r[3]-l[3]
    local ox,oz=l[1]-a[1],l[3]-a[3]
    local denom,length=dx*ez-dz*ex,dx*dx+dz*dz
    local scale=EPS*(math.abs(dx)+math.abs(dz)+math.abs(ex)+math.abs(ez)+EPS)
    if math.abs(denom)>scale then
        local t,u=(ox*ez-oz*ex)/denom,(ox*dz-oz*dx)/denom
        if t<previous-EPS or t>1+EPS or u< -EPS or u>1+EPS then return end
        return math.max(previous,math.min(1,math.max(0,t)))
    end
    if length<=EPS*EPS then
        local size=ex*ex+ez*ez
        local u=size>EPS*EPS and ((a[1]-l[1])*ex+(a[3]-l[3])*ez)/size or 0
        u=math.max(0,math.min(1,u))
        if (a[1]-l[1]-u*ex)^2+(a[3]-l[3]-u*ez)^2>EPS*EPS*4 then return end
        return previous
    end
    if math.abs(ox*dz-oz*dx)>scale then return end
    local t0,t1=(ox*dx+oz*dz)/length,((r[1]-a[1])*dx+(r[3]-a[3])*dz)/length
    local low,high=math.max(0,math.min(t0,t1),previous),math.min(1,math.max(t0,t1))
    if low>high+EPS then return end
    return math.max(previous,math.min(1,low))
end
local function append(points,p)
    local prior=points[#points]
    if not prior or not same(prior,p) or math.abs(prior[2]-p[2])>EPS then points[#points+1]=p end
    return #points
end
local function crossing(route,points,a,b,j,previous)
    local gate=route.portals[j]
    local t=intersection(a,b,gate.left,gate.right,previous)
    if not t then return nil,"funnel crosses portals out of order" end
    local p={a[1]+t*(b[1]-a[1]),0,a[3]+t*(b[3]-a[3])}
    local from,to=route.surfaces[j],route.surfaces[j+1]
    if not geometry.Contains(from,p[1],p[3]) or not geometry.Contains(to,p[1],p[3]) then
        return nil,"funnel left corridor surface"
    end
    local before,after=height(from,p),height(to,p)
    if not before or not after then return nil,"missing portal surface height" end
    append(points,{p[1],before,p[3]})
    return t,append(points,{p[1],after,p[3]})
end
local function sample(route,turns,start,first,yieldFn)
    local points,crossings,indices={},{},{}
    local startY=height(route.surfaces[first],start)
    if not startY then return nil,"missing start surface height" end
    append(points,{start[1],startY,start[3]})
    local nextPortal=first
    for k=2,#turns do
        pause(yieldFn)
        local a,b,previous=turns[k-1].point,turns[k].point,0
        for j=nextPortal,math.min(#route.corridor-1,turns[k].index) do
            pause(yieldFn)
            local t,index=crossing(route,points,a,b,j,previous)
            if not t then return nil,index end
            crossings[j],previous,nextPortal=index,t,j+1
        end
        local surface=route.surfaces[nextPortal]
        if not geometry.Contains(surface,b[1],b[3]) then return nil,"funnel corner outside surface" end
        local y=height(surface,b)
        if not y then return nil,"missing corner surface height" end
        indices[#indices+1]=append(points,{b[1],y,b[3]})
    end
    if nextPortal~=#route.corridor then return nil,"incomplete funnel corridor" end
    return points,crossings,indices
end
function geometry.StringPull(route,startPoint,firstIndex,yieldFn)
    local first,count=firstIndex or 1,#(route.corridor or {})
    local original=route.points or {}
    local start,target=startPoint or original[1],original[#original]
    if count==0 or first<1 or first>count or not start or not target or not route.surfaces then
        return nil,"invalid funnel endpoints"
    end
    if not geometry.Contains(route.surfaces[first],start[1],start[3])
        or not geometry.Contains(route.surfaces[count],target[1],target[3]) then
        return nil,"funnel endpoint outside connected surface"
    end
    local gates,reason=oriented(route,first,start,target,yieldFn)
    if not gates then return nil,reason end
    local turns,issue=corners(gates,yieldFn)
    if not turns then return nil,issue end
    return sample(route,turns,start,first,yieldFn)
end
