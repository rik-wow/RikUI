-- Actual mesh stair/floor replay. Arguments: companion, archive, optional quest ID.
-- Enumerated target heights are model test cases, never observed quest/player altitude.
local questID=tonumber(arg[3]) or 310
arg[3],arg[4]=nil,nil
local h=dofile("tests/quest-marker-replay.lua")
local p,mesh=RikUI.QuestPlanner,h.mesh
local world=assert(h.snapshot.context.worldPosition)
local start={x=world.x,z=world.z}
local initial=assert(mesh:Locate(start),"archived start needs a unique floor")
local poi=assert(h.snapshot.context.destinations[questID])
local marker=assert(mesh:Project(poi.mapID,poi.x,poi.y))
local floors={}
for id,poly in pairs(h.raw) do
    if p.NavGeometry.Contains(poly.points,marker.x,marker.z) then
        floors[#floors+1]={id=id,height=assert(p.NavGeometry.Height(poly.points,marker.x,marker.z))}
    end
end
table.sort(floors,function(a,b) return a.height<b.height end)
assert(#floors>=2,"scenario no longer covers multiple floors")
local function path(from,to)
    local job=assert(mesh:Begin(from,to,{maxWork=mesh:Metadata().counts.portals*2+1}))
    local result
    repeat result=job:Step(64) until result
    assert(result.status=="modeled",result.detail)
    return result
end
local function walk(route,prior)
    local samples=0
    for at=2,#route.points do
        local origin=prior.point
        local target=route.points[at]
        local distance=math.sqrt((target[1]-origin[1])^2+(target[3]-origin[3])^2)
        local steps=math.max(1,math.ceil(distance/.2))
        for step=1,steps do
            local point={x=origin[1]+(target[1]-origin[1])*step/steps,
                z=origin[3]+(target[3]-origin[3])*step/steps}
            local found,issue=mesh:LocateContinued(point,prior)
            assert(found,string.format("stair continuity %s at segment %d/%d from %d (%.8f,%.8f,%.8f) to (%.8f,%.8f)",
                issue or "",at,#route.points,prior.id,prior.point[1],prior.point[2],prior.point[3],point.x,point.z))
            prior=found
            samples=samples+1
        end
    end
    return prior,samples
end
for _,floor in ipairs(floors) do
    local to={x=marker.x,z=marker.z,height=floor.height}
    local outward=path(start,to)
    local arrived,samples=walk(outward,initial)
    assert(math.abs(arrived.point[2]-floor.height)<.002,"jumped to a different target floor")
    local returning=path(to,{x=start.x,z=start.z,height=initial.point[2]})
    local returned,back=walk(returning,arrived)
    assert(math.abs(returned.point[2]-initial.point[2])<.002,"return staircase changed floor")
    print(string.format("STAIRS floor=%.4f outward=%d return=%d corridor=%d/%d nativeVerified=false",
        floor.height,samples,back,#outward.corridor,#returning.corridor))
end
print("All modeled marker floors reached and returned through explicit portals without native altitude.")
