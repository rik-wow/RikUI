-- Exact source locations shared by direct guidance and the action planner.
local planner = RikUI.QuestPlanner
local schema, waypoints = planner.Schema, {}
planner.Waypoints = waypoints

function waypoints.Count(area)
    return area.spawns and #area.spawns > 0 and #area.spawns or 1
end

function waypoints.At(area, index)
    local spawn = area.spawns and area.spawns[index]
    if area.spawns and #area.spawns > 0 and not spawn then return end
    local x, y = spawn and spawn[1] or area.x, spawn and spawn[2] or area.y
    if not schema.Number(x, 0, 1) or not schema.Number(y, 0, 1) then return end
    local point = {}
    for key, value in pairs(area) do if key ~= "spawns" then point[key] = value end end
    point.x, point.y = x, y
    point.clusterID, point.spawnIndex = area.id, index
    point.id = spawn and (area.id .. ":spawn:" .. index) or area.id
    point.precision = spawn and "spawn" or area.precision
    -- Recenter the search bounds around the chosen actual spawn.
    if spawn and area.bounds then
        local b = area.bounds
        point.radiusNormalized = math.sqrt(math.max((x-b.minX)^2,(x-b.maxX)^2)
            + math.max((y-b.minY)^2,(y-b.maxY)^2))
    end
    return point
end

function waypoints.Nearest(area, origin, frame, requested)
    if not area.spawns or #area.spawns==0 then return waypoints.At(area,1) end
    local best,score
    local width,height=frame and frame.width or 1,frame and frame.height or 1
    local requestedIndex=requested and tonumber(requested:match(":spawn:(%d+)$"))
    if requestedIndex then
        local id=area.id..":spawn:"..requestedIndex
        if requested==id or requested:sub(-#id-1)==":"..id then
            local point=waypoints.At(area,requestedIndex)
            if point then return point end
        end
    end
    for index,spawn in ipairs(area.spawns) do
        local x,y=spawn[1],spawn[2]
        if schema.Number(x,0,1) and schema.Number(y,0,1) then
            local distance=origin and origin.mapID==area.mapID
                and ((x-origin.x)*width)^2+((y-origin.y)*height)^2 or 0
            if not best or distance<score then best,score=index,distance end
        end
    end
    return best and waypoints.At(area,best)
end

function waypoints.Destination(area)
    return {mapID=area.mapID,x=area.x,y=area.y,floor=area.floor,areaID=area.id,
        clusterID=area.clusterID,precision=area.precision,scope="semantic-objective-area",
        api=area.source or "QuestieDB"}
end
