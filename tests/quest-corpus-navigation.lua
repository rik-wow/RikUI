-- Installed corpus + installed terrain + archived native progress; automated host evidence only.
-- Arguments match quest-region-replay.lua. No imported snapshot gains trust in the addon.
local h=dofile("tests/quest-region-replay.lua")
local p,mesh=RikUI.QuestPlanner,h.mesh
local root=arg[1]:gsub("\\","/"):gsub("/$","")
local questID=assert(tonumber(arg[8]))
for _,name in ipairs({"optimizer","area-optimizer","semantic-data","semantic-guidance"}) do
    dofile("src/modules/questplanner/quest-"..name..".lua")
end
local regionalLoad=C_AddOns.LoadAddOn
local loads,peak,total=0,0,0
C_AddOns.LoadAddOn=function(name)
    if name:match("^RikUIQuestTerrain_") then return regionalLoad(name) end
    assert(name=="RikUIQuestCorpus" or name:match("^RikUIQuestCorpus_P%d+_S%d+$"))
    local begin=os.clock()
    local toc=assert(io.open(root.."/"..name.."/"..name..".toc"))
    for line in toc:lines() do
        line=line:gsub("\r",""):match("^%s*(.-)%s*$")
        if line~="" and line:sub(1,1)~="#" then
            assert(line:match("^[%w_-]+%.lua$"))
            assert(loadfile(root.."/"..name.."/"..line))()
        end
    end
    toc:close()
    local elapsed=(os.clock()-begin)*1000
    loads,total,peak=loads+1,total+elapsed,math.max(peak,elapsed)
    return true
end
local snapshot,ctx=h.snapshot,h.snapshot.context
snapshot.origin=nil;ctx.origin="live"
local requested=false
p.Request=function() requested=true end
p.Context.Call=function(fn,...) if type(fn)=="function" then return pcall(fn,...) end return false end
local policy={pins={},skips={},avoids={}}
collectgarbage("collect");local before=collectgarbage("count")
for _=1,2048 do
    p.SemanticData.Ensure(snapshot,ctx);p.SemanticData.Step();p.SemanticData.Ensure(snapshot,ctx)
    local status=p.SemanticData.Status()
    if status.state=="ready" and status.queuedPartitions==0 then break end
end
assert(p.SemanticData.Status().state=="ready" and p.SemanticData.Status().queuedPartitions==0)
collectgarbage("collect");local retained=collectgarbage("count")-before
local function refresh()
    requested=false;ctx.position=p.Context.Frame().position
    p.SemanticGuidance.Observe(snapshot,ctx,policy,questID)
    if p.Hunts then p.Hunts.Observe(snapshot,ctx) end
    for _,row in ipairs(p.Guidance.Observed(snapshot,ctx,policy,questID)) do
        if row.questID==questID then
            for key in pairs(h.selected) do h.selected[key]=nil end
            for key,value in pairs(row) do h.selected[key]=value end
            return
        end
    end
    error("selected quest disappeared")
end
refresh()
assert(h.selected.semantic or questID==310 and h.selected.targetHint,"expected generic or preserved reviewed target")
assert(not h.selected.step.objectiveBinding.semantic,"view copied the corpus")
p.Terrain.Invalidate()
local start=assert(mesh:Project(p.Context.Frame().position.mapID,p.Context.Frame().position.x,p.Context.Frame().position.y))
local located=assert(mesh:Locate(start))
local quiet=0
for _=1,30000 do
    h.tick(located.point,.02);p.SemanticGuidance.Step()
    if requested then refresh();quiet=0 else quiet=quiet+1 end
    if p.Terrain.Guidance() and quiet>2100 then break end
end
print("SELECTED",h.selected.semantic and h.selected.semantic.method,h.selected.destination.x,h.selected.destination.y,h.selected.semantic and h.selected.semantic.costBasis)
local route=assert(p.Terrain.Guidance(),p.Terrain.Status().detail)
local length=route.meters
local Q=dofile("tests/quest-route-quality.lua")
local quality,callbacks=Q.New(),{}
local stats=p.Terrain.Stats()
local done=false
for tick=1,15000 do
    local begin=os.clock()
    h.tick(located.point,.02);p.SemanticGuidance.Step()
    if requested then refresh() end
    route=assert(p.Terrain.Guidance(),p.Terrain.Status().detail)
    callbacks[#callbacks+1]=(os.clock()-begin)*1000
    if route.searching or route.meters<=1 then quality:Observe(located.point,nil,tick*.02);done=true;break end
    local aim=assert(mesh:Project(route.next.mapID,route.next.x,route.next.y))
    quality:Observe(located.point,aim,tick*.02)
    local dx,dz=aim.x-located.point[1],aim.z-located.point[3]
    local distance=math.sqrt(dx*dx+dz*dz)
    assert(distance>0,"stationary aim")
    local step=math.min(.15,distance)
    located=assert(mesh:LocateContinued({x=located.point[1]+dx/distance*step,z=located.point[3]+dz/distance*step},located),"left replay mesh")
end
assert(done,"walk exceeded bound")
assert(h.selected.step.state~="completed","proximity completed an observed quest")
local after=p.Terrain.Stats()
assert(after.plans==stats.plans and after.published==stats.published,"source area changed while walking")
local allocation=Q.Allocations(function() h.tick(located.point,.02);p.SemanticGuidance.Step() end,100)
local viewAllocation=Q.Allocations(function() p.Schema.Clone(h.selected) end,30)
local timing=Q.Timing(callbacks)
print(string.format("CORPUS NAV quest%d: method %s; modeled %.3f yd; walked %.3f; oscillations %d; moving plans/changes %d/%d; callback p99/max %.3f/%.3f ms; stationary %.1f bytes/frame; selected-view %.1f bytes/copy; %d partitions %.1f KiB; %d corpus loads total/max %.3f/%.3f ms",
    questID,h.selected.semantic and h.selected.semantic.method or "reviewed",length,quality.spatial,quality.aim.oscillations,
    after.plans-stats.plans,after.published-stats.published,timing.p99,timing.maximum,allocation.bytesPerCallback,
    viewAllocation.bytesPerCallback,p.SemanticData.Status().loadedPartitions,retained,loads,total,peak))

