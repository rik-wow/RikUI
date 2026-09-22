-- Bounded local following over immutable, fully pulled route geometry.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
planner.NavFollow={}
local LOCAL_PORTALS=24
function planner.NavFollow.Begin(mesh,route,floorCount)
    local cancelled=false
    local worker=coroutine.create(function()
        if planner.Hunts and route.huntHint then
            local ok,reason=planner.Hunts.Trim(route,route.huntHint)
            if not ok then return {status="invalid",detail=reason} end
        end
        local corridorLookup,projected,suffix={},{},route.suffix or {}
        local display,lastTrim,lastAim,localRoute
        for at,id in ipairs(route.corridor) do corridorLookup[id]=at;coroutine.yield() end
        for at,point in ipairs(route.walkPoints) do projected[at]=mesh:Unproject(point);coroutine.yield() end
        local function localCorridor(location,index)
            if localRoute and localRoute.index==index then return localRoute end
            local last=math.min(#route.corridor,index+LOCAL_PORTALS)
            local tail=last==#route.corridor and #route.walkPoints or route.crossings[last-1]
            local value={index=index,tail=tail,corridor={},portals={},surfaces={},points={location.point}}
            for at=index,last do
                value.corridor[#value.corridor+1]=route.corridor[at]
                value.surfaces[#value.surfaces+1]=route.surfaces[at]
                value.points[#value.points+1]=route.points[at*2] or route.points[#route.points]
                if at<last then
                    value.portals[#value.portals+1]=route.portals[at]
                    value.points[#value.points+1]=route.portals[at].midpoint
                end
            end
            value.points[#value.points+1]=route.walkPoints[tail]
            if lastAim and localRoute then
                lastAim.index=lastAim.index+localRoute.index-index
                if lastAim.index<1 or lastAim.index>#value.corridor then lastAim=nil end
            end
            localRoute=value
            return value
        end
        local function remainingPoints(location,index)
            local localPath=localCorridor(location,index)
            local aim,crossed,last=planner.NavGeometry.CorridorAim(localPath,location.point,1,lastAim)
            lastAim={point=aim,index=last,origin=location.point}
            local remaining,reason=planner.NavGeometry.StringPull(localPath,aim,last)
            if not remaining then return nil,reason end
            local points={location.point}
            for _,point in ipairs(crossed) do points[#points+1]=point end
            points[#points+1]=aim
            for at=2,#remaining do points[#points+1]=remaining[at] end
            return points,aim,localPath.tail
        end
        local function trim(location,live)
            if not route or not route.walkPoints then return nil end
            if display and lastTrim and lastTrim.id==location.id and display.speed==(live and live.speed)
                and planner.NavGeometry.Distance(lastTrim.point,location.point)<.000001 then return display end
            local hunting=planner.Hunts and planner.Hunts.Display(mesh,route,location)
            if hunting then lastTrim=location;hunting.speed=live and live.speed;return hunting end
            local index=corridorLookup[location.id]
            if not index then return nil end
            if display and lastTrim and display.speed==(live and live.speed) and lastTrim.id==location.id
                and planner.NavGeometry.Distance(lastTrim.point,location.point)<.000001 then return display end
            local points,aim,tail=remainingPoints(location,index)
            if not points then return nil end
            local result={path={prefix={},tail=projected,first=tail+1},meters=suffix[tail] or 0,status="modeled",nativeVerified=false,
                revision=route.revision,detail="Terrain estimate; traversal unverified"}
            result.destinationFloor=route.destinationFloor
            result.hunt=route.hunt and route.hunt.hint
            result.huntEndpoint=route.hunt and projected[#projected]
            result.floorChoiceAvailable=floorCount>1
            if route.approach then
                result.approach=schema.Clone(route.approach)
                result.approach.marker=mesh:Unproject({route.approach.marker.x,0,route.approach.marker.z})
                result.approach.provenance=route.markerProvenance
                local uncertain=route.approach.kind=="observed-marker-common-approach"
                    or route.approach.kind=="observed-marker-uncertain-vicinity"
                result.detail=uncertain and "Approach; quest floor is uncertain"
                    or string.format("Modeled approach; %.2f yd gap and interaction unverified",route.approach.gap)
            end
            for at,point in ipairs(points) do
                result.path.prefix[#result.path.prefix+1]=mesh:Unproject(point)
                if at>1 then result.meters=result.meters+planner.NavGeometry.Distance(points[at-1],point) end
            end
            local speed=live and live.speed
            result.speed=live and live.speed
            result.speedSource=speed and "current-run-speed" or "default-run-speed"
            result.seconds=result.meters/(speed or 7)
            result.next=mesh:Unproject(aim)
            lastTrim=location
            return result
        end

        route.follow=function(location,live) display=trim(location,live);return display end
        route.prepared=true
        return route
    end)
    return {Cancel=function() cancelled=true end,Step=function(_,budget)
        if cancelled then return {status="cancelled",detail="navigation request changed"} end
        for _=1,budget do
            local ok,result=coroutine.resume(worker)
            if not ok then return {status="invalid",detail="Route projection failed"} end
            if coroutine.status(worker)=="dead" then return result end
        end
    end}
end
