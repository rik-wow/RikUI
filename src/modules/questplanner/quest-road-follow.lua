-- Follow a road-network polyline and publish the NavFollow display contract.
-- Progress is the nearest segment within a bounded forward/backward window;
-- the arrow aims a fixed distance ahead along the polyline.
local planner=RikUI.QuestPlanner
local schema,follow=planner.Schema,{}
planner.RoadFollow=follow

local LOOKAHEAD=18          -- yards ahead along the line for the arrow aim
local WINDOW_BACK,WINDOW_AHEAD=2,12
local OFF_ROUTE=35          -- yards from the line before a replan is requested

local function project(ax,az,bx,bz,px,pz)
    local dx,dz=bx-ax,bz-az
    local n=dx*dx+dz*dz
    local t=n>0 and math.max(0,math.min(1,((px-ax)*dx+(pz-az)*dz)/n)) or 0
    local x,z=ax+dx*t,az+dz*t
    return x,z,math.sqrt((px-x)^2+(pz-z)^2),t
end

-- route: RoadRoute result. unproject(point{x,y,z}) -> map point.
function follow.Begin(route,unproject,mapView,worldMapID)
    if not route or not schema.List(route.points,1048576) or #route.points<2 or type(unproject)~="function" then
        return nil,"invalid road route"
    end
    local points,suffix=route.points,route.suffix
    local tail={}
    for i,p in ipairs(points) do
        tail[i]=unproject({x=p[1],z=p[3]})
        if not tail[i] then return nil,"road route outside map projection" end
    end
    local segment=1
    local function locate(px,pz)
        local best,bestGap,bx,bz=segment,math.huge,nil,nil
        for i=math.max(1,segment-WINDOW_BACK),math.min(#points-1,segment+WINDOW_AHEAD) do
            local a,b=points[i],points[i+1]
            local x,z,gap=project(a[1],a[3],b[1],b[3],px,pz)
            if gap<bestGap-.01 or (math.abs(gap-bestGap)<=.01 and i>best) then best,bestGap,bx,bz=i,gap,x,z end
        end
        return best,bestGap,bx,bz
    end
    local function ahead(index,x,z,distance)
        local left=distance
        local cx,cz=x,z
        for i=index+1,#points do
            local p=points[i]
            local d=math.sqrt((p[1]-cx)^2+(p[3]-cz)^2)
            if d>=left then local q=left/d;return cx+(p[1]-cx)*q,cz+(p[3]-cz)*q,i end
            left=left-d;cx,cz=p[1],p[3]
        end
        return points[#points][1],points[#points][3],#points
    end
    local handle={route=route}
    function handle.follow(position,live)
        if not schema.PlainTable(position) or not schema.Number(position.x,-100000,100000) then return nil end
        local index,gap,x,z=locate(position.x,position.z)
        if gap>OFF_ROUTE then return {status="off-route",detail="Left the road route; recalculating",offRoute=true} end
        segment=index
        local nextPoint=points[index+1]
        local meters=math.sqrt((nextPoint[1]-x)^2+(nextPoint[3]-z)^2)+(suffix[index+1] or 0)+gap
        local ax,az=ahead(index,x,z,LOOKAHEAD)
        local speed=live and live.speed
        local first=index+1
        return {status="modeled",nativeVerified=false,revision=route.revision,road=true,
            mapView=mapView,worldMapID=worldMapID,
            detail=route.detail,meters=meters,speed=speed,
            speedSource=speed and "current-run-speed" or "default-run-speed",seconds=meters/(speed or 7),
            next=unproject({x=ax,z=az}),
            path={prefix={unproject({x=position.x,z=position.z})},tail=tail,first=first}}
    end
    return handle
end
