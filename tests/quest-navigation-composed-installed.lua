-- Exercises ordinary Terrain.Start/Step through the forced-split production export.
-- Usage: lua MODULE_DIR ADDON_PACK_DIR [normal|disconnected|budget|cancel|reentrant]
local root=assert(arg[1],'module directory required');local pack=assert(arg[2],'pack directory required')
RikUI={};RikUI['Secret']={IsSecret=function()return false end}
for _,name in ipairs({'schema','nav-geometry','nav-funnel','nav-follow','nav-search','region-codec','terrain-packs','regions','navmesh','nav-attach','path-codec','path-graph','path-search','path-route','path-navigate','paths','path-compose','terrain'})do dofile(root..'/quest-'..name..'.lua')end
local p=RikUI.QuestPlanner;local calls,loaded={},{}
local mode=arg[3]or'normal'
local composeJob,composeCancelled
local composeBegin=p.PathCompose.Begin
p.PathCompose.Begin=function(inputs,seams,options)
 if mode=='budget'then options.maxWork=1 end
 local job,why=composeBegin(inputs,seams,options);if job then
  composeJob=job;local cancel=job.Cancel;job.Cancel=function(self)composeCancelled=true;return cancel(self)end
 end;return job,why
end
local projection={originX=1085.4166259766,originY=1781.2498779297,width=4237.4998779297,height=2824.9998779297002}
local function ui(point,map)return {mapID=map or 1459,x=(projection.originY-point[1])/projection.width,y=(projection.originX-point[3])/projection.height}end
local start={-14.583333333333334,-4,35.625};local goal={.083333333333333329,20.300000000000001,496.25}
local current={start[1],start[2],start[3]};local map,world=1459,30
local target=ui(goal);target.terrainHeight=goal[2];target.scope='fixture-exact-source-center'
local capturedIndex
local installIndex=p.Regions.InstallIndex;p.Regions.InstallIndex=function(value)capturedIndex=value;target.corpusRevision=value.revision;if mode=='disconnected'then value.bindings[1].connections={}end;return installIndex(value)end
C_AddOns={LoadAddOn=function(name)
 calls[name]=(calls[name]or 0)+1;if loaded[name]then return true end
 assert(name:match('^RikUIQuest%w+_[%w_]+$'))
 local dir=pack..'/'..name..'/';local handle=io.open(dir..name..'.toc','r');if not handle then return nil,'MISSING'end
 for line in handle:lines()do line=line:gsub('\r','');if line:sub(1,1)~='#'and line~=''then assert(line:match('^[%w_%-]+%.lua$'));dofile(dir..line)end end
 handle:close();loaded[name]=true;if mode=='reentrant'then p.Terrain.Step()end;return true
end}
local tick,time=0,0
GetTime=function()return time end;debugprofilestop=function()return os.clock()*1000 end;InCombatLockdown=function()return false end
CreateFrame=function()return {SetScript=function(_,event,fn)assert(event=='OnUpdate');tick=fn end}end
p.enabled=true;p.GetSnapshot=function()return {identity={product='forever',build='1.60.1.69913',locale='enUS'}}end
p.Context={Frame=function()return {position=ui(current,map),world={mapID=world,x=current[1],height=current[2],z=current[3],verticalStatus='observed-altitude'},speed=7}end}
p.Controller={Get=function()return {status='observed',selected={questID=7,kind='objective',destination=target}}end}
local builtPoints
local followBegin=p.NavFollow.Begin;p.NavFollow.Begin=function(mesh,route,floors)builtPoints=p.Schema.Clone(route.walkPoints);return followBegin(mesh,route,floors)end
p.Terrain.Start();assert(next(calls)==nil)
local function frame()time=time+1/60;tick(nil,1/60)end
if mode=='disconnected'or mode=='budget'then
 for _=1,4000 do frame()end
 local status=p.Terrain.Status()
 assert(not p.Terrain.Guidance()and status.status=='coverage-frontier',status.status..': '..tostring(status.detail))
 if mode=='budget'then assert(status.detail=='composition-work-limit',status.detail)end
 for name in pairs(loaded)do assert(not name:match('_R%d+$'),'unavailable composition loaded geometry')end
 print('TERRAIN_NEGATIVE_OK mode='..mode..' detail='..tostring(status.detail)..' noGuidance=true noLocalGeometry=true');os.exit(0)
end
if mode=='cancel'then
 for _=1,4000 do frame();if composeJob then break end end
 assert(composeJob,'composition was never started')
 local old=composeJob;map,world=9999,0;frame();assert(composeCancelled and not p.Terrain.Guidance())
 local value,why,done=old:Step(64);assert(not value and why=='cancelled'and done)
 map,world=1459,30
end
local ready
for i=1,20000 do frame();local display=p.Terrain.Guidance();if display then ready=i;break end end
local state=p.Terrain.Status();assert(ready,state.status..': '..tostring(state.detail))
assert(state.status=='modeled',state.status..': '..tostring(state.detail))
local display=p.Terrain.Guidance();assert(display.nativeVerified==false)
local binding=p.Regions.Binding();assert(binding.packs and#binding.packs==2)
local function countNames(pattern)local n=0;for name in pairs(loaded)do if name:match(pattern)then n=n+1 end end;return n end
assert(countNames('_R%d+$')<16,'loaded all physical regions')
local plans=p.Terrain.Stats().plans;local initialMeters=display.meters
-- Drive along the actual pulled route in <=1yard steps, including omitted middle regions.
local points=builtPoints
if not points then for k,v in pairs(display)do print('DISPLAYKEY',k,type(v))end;error('need display route points')end
local moved,crossed=0,0;local priorX=current[1]
for i=2,#points do
 local value=points[i];local endpoint
 if value.mapID then endpoint={projection.originY-value.x*projection.width,value.height or current[2],projection.originX-value.y*projection.height}
 else endpoint=value end
 local distance=p.NavGeometry.Distance(current,endpoint);local steps=math.max(1,math.ceil(distance));local origin={current[1],current[2],current[3]}
 for at=1,steps do
  local t=at/steps;for axis=1,3 do current[axis]=origin[axis]+(endpoint[axis]-origin[axis])*t end
  if priorX<0 and current[1]>=0 or priorX>=0 and current[1]<0 then crossed=crossed+1 end;priorX=current[1]
  frame();moved=moved+1
  assert(p.Terrain.Guidance(),p.Terrain.Status().status..': '..tostring(p.Terrain.Status().detail))
 end
end
assert(crossed>=1 and p.Terrain.Stats().plans==plans,'walking across physical packs replaced route')
local walkingPlans=p.Terrain.Stats().plans-plans
map,world=9999,0;frame();assert(not p.Terrain.Guidance())
map,world=1459,30;current={start[1],start[2],start[3]}
for _=1,20000 do frame();if p.Terrain.Guidance()then break end end
assert(p.Terrain.Guidance(),'failed to recover original composed corridor')
for name,n in pairs(calls)do assert(n==1,'addon reexecuted: '..name)end
print(string.format('TERRAIN_COMPOSED_OK readyFrame=%d initialMeters=%.9f walkingSteps=%d packCrossings=%d newPlansDuringWalk=%d regionAddons=%d graphAddons=%d seamAddons=%d missingMapClears=true sameMapRecovers=true',ready,initialMeters,moved,crossed,walkingPlans,countNames('_R%d+$'),countNames('^RikUIQuestPaths'),countNames('^RikUIQuestSeams')))
