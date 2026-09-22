-- Actual regional movement history replay; arguments match quest-nav-visual.
local h=dofile("tests/quest-region-replay.lua")
local p,mesh=RikUI.QuestPlanner,h.mesh
local start=assert(mesh:Project(h.meta.uiMapID,tonumber(arg[3]),tonumber(arg[4])))
local location=assert(mesh:Locate(start))
local history={location.point}
local initial=p.Terrain.Stats()
for _=1,300 do
    h.tick(location.point,.02)
    local guidance=assert(p.Terrain.Guidance())
    local target=assert(mesh:Project(guidance.next.mapID,guidance.next.x,guidance.next.y))
    local dx,dz=target.x-location.point[1],target.z-location.point[3]
    local length=math.sqrt(dx*dx+dz*dz)
    assert(length>.15)
    location=assert(mesh:LocateContinued({x=location.point[1]+dx*.15/length,z=location.point[3]+dz*.15/length},location))
    history[#history+1]=location.point
end
h.tick(location.point,.02)
local forward=assert(p.Terrain.Guidance()).meters
for at=#history-1,#history-120,-1 do
    h.tick(history[at],.02)
    assert(p.Terrain.Guidance(),"backtracking lost the connected route")
end
local backward=assert(p.Terrain.Guidance()).meters
assert(backward>forward+10,"backtracking did not restore remaining distance")
assert(p.Terrain.Stats().plans==initial.plans,"local backtracking unnecessarily replanned")
for at=#history-119,#history do
    h.tick(history[at],.02);assert(p.Terrain.Guidance(),"returning along history lost route")
end
h.tick(history[1],.1)
for _=1,2000 do if p.Terrain.Guidance()then break end;h.tick(history[1],.02)end
local recovered=assert(p.Terrain.Guidance(),"large displacement did not recover")
assert(recovered.meters>forward+30,"large displacement did not restore route distance")
-- A perpendicular displacement is admitted only by a connected movement query.
location=assert(mesh:Locate({x=history[1][1],z=history[1][3],height=history[1][2]}))
local target=assert(mesh:Project(recovered.next.mapID,recovered.next.x,recovered.next.y))
local dx,dz=target.x-location.point[1],target.z-location.point[3]
local length=math.sqrt(dx*dx+dz*dz)
local deviated=mesh:LocateContinued({x=location.point[1]-dz*6/length,z=location.point[3]+dx*6/length},location)
assert(deviated,"fixture has no connected six-yard deviation")
h.tick(deviated.point,.1)
for _=1,2000 do if p.Terrain.Guidance()then break end;h.tick(deviated.point,.02)end
local after=assert(p.Terrain.Guidance(),"connected deviation did not recover")
assert(after.status=="modeled" and after.next,"deviation published an incomplete route")
print(string.format("Regional recovery passed:18yd backtracking,45yd displacement,6yd connected deviation; plans %d",
    p.Terrain.Stats().plans-initial.plans))
