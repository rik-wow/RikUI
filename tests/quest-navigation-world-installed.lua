-- Host-only source-pack acceptance. Never records native traversal evidence.
-- Usage: lua quest-navigation-world-installed.lua MODULE_DIR ADDON_PACK_DIR [REPORT_JSON]
local moduleRoot,packRoot=assert(arg[1],'module directory required'),assert(arg[2],'pack directory required')
local modules={'schema','nav-geometry','nav-funnel','nav-follow','nav-search','region-codec','terrain-packs','regions','navmesh','nav-attach','path-codec','path-graph','path-search','path-route','path-navigate','paths','path-compose','terrain'}
local identity={product='forever',build='1.60.1.69913',locale='enUS'}
local function bootstrap()
 RikUI={};RikUI['Secret']={IsSecret=function()return false end}
 RikUIQuestPathsCatalog=nil;RikUIQuestPathsPayloads=nil
 for _,name in ipairs(modules)do dofile(moduleRoot..'/quest-'..name..'.lua')end
 local p=RikUI.QuestPlanner;local state={calls={},loaded={},indexes={},catalogs={}}
 local index=p.Regions.InstallIndex;p.Regions.InstallIndex=function(v)state.indexes[v.uiMapID]=v;return index(v)end
 local install=p.Regions.Install;p.Regions.Install=function(v)state.catalogs[v.namespace]=v;return install(v)end
 C_AddOns={LoadAddOn=function(name)
  assert(name:match('^RikUIQuest%w+_[%w_]+$'),'unsafe addon name')
  state.calls[name]=(state.calls[name]or 0)+1
  if state.loaded[name]then return true end
  local dir=packRoot..'/'..name..'/';local toc=io.open(dir..name..'.toc','r')
  if not toc then return nil,'MISSING'end
  for line in toc:lines()do
   line=line:gsub('\r','')
   if line:sub(1,1)~='#'and line~=''then assert(line:match('^[%w_%-]+%.lua$'),'unsafe toc entry');dofile(dir..line)end
  end
  toc:close();state.loaded[name]=true;return true
 end}
 InCombatLockdown=function()return false end;debugprofilestop=function()return os.clock()*1000 end
 return p,state
end
local function ui(case,point)
 local v=case.projection
 return {mapID=case.mapID,x=(v.originY-point[1])/v.width,y=(v.originX-point[3])/v.height}
end
local function inside(v,x,z)return x>=v[1]and x<=v[3]and z>=v[2]and z<=v[4]end
local function casesFromSource()
 -- This separate bootstrap reads actual compact source centers. It is discarded before cold runtime checks.
 local p,state=bootstrap();local cases={}
 for _,mapID in ipairs({1459,1460,1461})do
  assert(C_AddOns.LoadAddOn('RikUIQuestTerrainMap_M'..mapID),'missing expected index')
  local index=state.indexes[mapID];assert(#index.bindings==1,'fixture needs an unambiguous source assignment')
  local view=index.bindings[1];local ref=view.packs[1];assert(#view.packs==1,'whole-world fixture requires one physical pack per world')
  local box=ref.ownedBounds;local valid=view.validWorldRectangle
  local x=(math.max(box[1],valid[1])+math.min(box[3],valid[3]))/2
  local z=(math.max(box[2],valid[2])+math.min(box[4],valid[4]))/2
  local case={mapID=mapID,worldMapID=view.worldMapID,projection=view.projection,indexRevision=index.revision,namespace=ref.namespace}
  local point=ui(case,{x,0,z})
  for _=1,32 do if p.Regions.Admit(identity,point,point,view.worldMapID)then break end end
  local binding=assert(p.Regions.Binding());assert(binding.namespace==ref.namespace)
  local graph,reason
  for _=1,100000 do graph,reason=p.Paths.Prepare(identity,mapID,binding);if graph then break end;assert(reason=='loading',reason)end
  assert(graph,reason)
  local count=graph:Stats().gateways;local first,last,start,distance
  for candidate=1,count do
   local center=graph:Center(candidate);local pos=ui(case,center)
   if inside(view.validUIRectangle,pos.x,pos.y)and inside(valid,center[1],center[3])then
    local seen,queue,at={[candidate]=true},{candidate},1
    while at<=#queue do local node=queue[at];at=at+1;for target in graph:Edges(node)do if not seen[target]then seen[target]=true;queue[#queue+1]=target end end end
    local best,target=0,nil
    for id in pairs(seen)do local goal=graph:Center(id);local goalPos=ui(case,goal)
     local d=(goal[1]-center[1])^2+(goal[3]-center[3])^2
     if (d>best or d==best and target and id<target)and d<=500*500 and inside(view.validUIRectangle,goalPos.x,goalPos.y)and inside(valid,goal[1],goal[3])then target,best=id,d end
    end
    if target and best>100*100 then first,last,start,distance=candidate,target,center,best;break end
   end
  end
  assert(first and last,'source selection has no declared 100-500yd reachable pair')
  case.start=start;case.goal=graph:Center(last);case.sourceStartID=graph:Original(first);case.sourceGoalID=graph:Original(last)
  case.graph=graph:Stats();case.catalogRevision=state.catalogs[ref.namespace].revision;case.sourceSHA256=ref.sourceSHA256
  case.availableRegions=#state.catalogs[ref.namespace].regions;case.selectionRule='first source gateway in assignment with a directed-reachable target100-500 planar yards away; furthest such target'
  cases[#cases+1]=case
 end
 return cases
end
local cases=casesFromSource()
local p,state=bootstrap();collectgarbage('collect')
local active=cases[1];local point={unpack(active.start)};local time,tick=0,nil
local target=ui(active,active.goal);target.scope='fixture-exact-source-center';target.corpusRevision=active.catalogRevision;target.terrainHeight=active.goal[2]
GetTime=function()return time end
CreateFrame=function()return {SetScript=function(_,name,fn)assert(name=='OnUpdate');tick=fn end}end
p.enabled=true;p.GetSnapshot=function()return {identity=identity}end
p.Context={Frame=function()return {position=ui(active,point),world={mapID=active.worldMapID,x=point[1],height=point[2],z=point[3],verticalStatus='observed-altitude'},speed=7}end}
p.Controller={Get=function()return {status='observed',selected={questID=7,kind='objective',destination=target}}end}
local routePoints
local follow=p.NavFollow.Begin;p.NavFollow.Begin=function(mesh,route,floors)routePoints=p.Schema.Clone(route.walkPoints);return follow(mesh,route,floors)end
local pending,cancellations
cancellations=0
local beginGraph=p.PathGraph.Begin
p.PathGraph.Begin=function(c,payload)
 local job,why=beginGraph(c,payload)
 if job then
  pending=job;local cancel,step=job.Cancel,job.Step
  job.Cancel=function(self)cancellations=cancellations+1;if pending==self then pending=nil end;return cancel(self)end
  job.Step=function(self,budget)local value,reason,done=step(self,budget);if done and pending==self then pending=nil end;return value,reason,done end
 end
 return job,why
end
p.Terrain.Start();assert(next(state.calls)==nil,'cold runtime loaded source at startup')
local peakMS=0
local function frame()
 time=time+1/60;local before=os.clock();tick(nil,1/60);peakMS=math.max(peakMS,(os.clock()-before)*1000)
end
local function selectCase(case)
 active=case;point={unpack(case.start)};target=ui(case,case.goal)
 target.scope='fixture-exact-source-center';target.corpusRevision=case.catalogRevision;target.terrainHeight=case.goal[2];routePoints=nil
end
-- Interrupt an actual cold graph validator and prove it cannot publish on the new map.
for _=1,20000 do frame();if pending then break end end
assert(pending,'cold graph admission never began')
local stale=pending;local cancelledBefore=cancellations;selectCase(cases[2]);frame()
assert(cancellations>cancelledBefore and not p.Terrain.Guidance(),'map change retained an earlier graph job')
local oldValue,oldReason,oldDone=stale:Step(64);assert(not oldValue and oldDone and oldReason=='cancelled','old graph job remained live')
stale=nil
local results={};local visits={1,2,3,1,2,3,1,2,3,1,2,3}
for visit,index in ipairs(visits)do
 local case=cases[index];selectCase(case);frame();assert(not p.Terrain.Guidance(),'old-map display survived transition')
 local ready
 for i=1,30000 do frame();if p.Terrain.Guidance()then ready=i;break end end
 local status=p.Terrain.Status();assert(ready,status.status..': '..tostring(status.detail))
 local display=p.Terrain.Guidance();assert(display.nativeVerified==false and display.status=='modeled')
 local initialMeters=display.meters;local plans=p.Terrain.Stats().plans;local steps=0
 if visit<=3 then
  local points=assert(routePoints);for i=2,#points do
   local goal=points[i];local origin={unpack(point)};local distance=p.NavGeometry.Distance(origin,goal);local n=math.max(1,math.ceil(distance))
   for at=1,n do for axis=1,3 do point[axis]=origin[axis]+(goal[axis]-origin[axis])*at/n end;frame();steps=steps+1
    assert(p.Terrain.Guidance(),p.Terrain.Status().status..': '..tostring(p.Terrain.Status().detail))
   end
  end
  assert(p.Terrain.Stats().plans==plans,'ordinary movement replaced the admitted corridor')
 end
 routePoints=nil;collectgarbage('collect')
 results[#results+1]={visit=visit,mapID=case.mapID,worldMapID=case.worldMapID,readyFrame=ready,modeledYards=initialMeters,walkingSteps=steps,
  newPlansDuringWalk=p.Terrain.Stats().plans-plans,retainedLuaKiB=collectgarbage('count'),regionalSourceBytes=p.Regions.Stats().sourceBytes,
  pathSourceBudgetBytes=p.Paths.Stats().retainedSourceBudgetBytes}
 if visit>6 then assert(results[visit].retainedLuaKiB<=results[visit-3].retainedLuaKiB+128,'same-world retained memory did not stabilize')end
 print(string.format('WORLD_VISIT %d map=%d frames=%d modeledYards=%.9f walkSteps=%d retainedKiB=%.1f',visit,case.mapID,ready,initialMeters,steps,results[#results].retainedLuaKiB))
end
for name,n in pairs(state.calls)do assert(n==1,'source addon reexecuted: '..name)end
assert(p.TerrainPacks.Stats().indexes==3 and p.TerrainPacks.Stats().catalogs==3)
assert(p.Regions.Stats().sourceBytes<=134217728 and p.Paths.Stats().retainedSourceBudgetBytes<=134217728)
local regionLoads,totalLoads=0,0
for name in pairs(state.loaded)do totalLoads=totalLoads+1;if name:match('_R%d+$')then regionLoads=regionLoads+1 end end
local report={format='rikui-world-runtime-host-check-v1',nativeVerified=false,moduleRoot=moduleRoot,packRoot=packRoot,
 sourceSelection='deterministic actual compact source centers, chosen in a discarded bootstrap before cold runtime',cases=cases,visits=results,
 cancelledGraphJobs=cancellations,staleGraphRejected=true,sourceAddonsReexecuted=false,loadedAddons=totalLoads,localRegionAddons=regionLoads,
 peakHostCallbackMS=peakMS,regions=p.Regions.Stats(),paths=p.Paths.Stats()}
local function json(value)
 local kind=type(value)
 if kind=='string'then return string.format('%q',value):gsub('\\\n','\\n')end
 if kind=='number'then assert(value==value and math.abs(value)<math.huge);return string.format('%.17g',value)end
 if kind=='boolean'then return value and'true'or'false'end
 if kind=='nil'then return'null'end
 assert(kind=='table');local out={};if#value>0 then for _,v in ipairs(value)do out[#out+1]=json(v)end;return'['..table.concat(out,',')..']'end
 local keys={};for key in pairs(value)do keys[#keys+1]=key end;table.sort(keys)
 for _,key in ipairs(keys)do out[#out+1]=json(key)..':'..json(value[key])end;return'{'..table.concat(out,',')..'}'
end
if arg[3]then local file=assert(io.open(arg[3],'wb'));file:write(json(report),'\n');file:close()end
print(string.format('THREE_WORLD_OK sourceAddons=%d localRegions=%d cancellations=%d peakHostMS=%.3f nativeVerified=false',totalLoads,regionLoads,cancellations,peakMS))
