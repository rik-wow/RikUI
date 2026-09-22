-- Real production geometry and NavFollow continuity integration.
-- Extends the real-geometry fixture; root may extract this added continuity block.
-- Loaded by the standard test harness from repository root. No native gameplay claim.
return function(check)
 local oldRikUI,oldGetTime,oldProfiler=RikUI,GetTime,debugprofilestop
 RikUI={};RikUI['Secret']={IsSecret=function()return false end,Read=pcall}
 GetTime=function()return 1 end;debugprofilestop=function()return 0 end
 local function module(name)dofile('src/modules/questplanner/quest-'..name..'.lua')end
 local function clonePoint(p)return{p[1],p[2],p[3]}end
 local function clonePolygon(p)
  local out={id=p.id,center=clonePoint(p.center),points={}}
  for i,point in ipairs(p.points)do out.points[i]=clonePoint(point)end;return out
 end
 local function near(a,b)return type(a)=='number' and math.abs(a-b)<=1e-7*math.max(1,math.abs(b))end
 local function square(id,x,z,height)
  height=height or 0
  return{id=id,center={x+5,height,z+5},points={{x,height,z},{x+10,height,z},{x+10,height,z+10},{x,height,z+10}},portals={}}
 end
 local function finishMesh(job,why)
  assert(job,'NavMesh.Begin did not return a job: '..tostring(why))
  for _=1,10000 do local mesh,problem,done=job:Step(64)
   if done then assert(mesh,'Validated local mesh rejected: '..tostring(problem));return mesh end
  end
  error('NavMesh build did not finish')
 end
 local function finish(job,budget)
  assert(job,'PathNavigate.Begin did not return a job')
  for _=1,100000 do local result=job:Step(budget or 64);if result then return result end end
  error('PathNavigate did not finish')
 end
 local function metadata(identity,polygons,portals)
  return{format='rikui-navmesh-v1',identity=identity,revision='real-path-integration-1',uiMapID=1426,worldMapID=0,
   source={sha256=string.rep('a',64),parser='fixture'},
   projection={originX=100,originY=100,width=100,height=100},modeledMaxStep=.3,
   counts={polygons=polygons,portals=portals},bounds={0,0,30,20},exclusions={},blockers={}}
 end
 local function setup(planner,options)
  options=options or {};local G=planner.NavGeometry
  local identity={product='forever',build='1.60.1.69913',locale='enUS'}
  local polygons={[1]=square(1,0,0),[2]=square(2,10,0,options.middleHeight),[3]=square(3,20,0),
   [4]=square(4,0,10),[5]=square(5,10,10),[6]=square(6,20,10)}
  local function portal(from,to)
   local a,b=polygons[from].center,polygons[to].center
   local dx,dz=(b[1]-a[1])/10,(b[3]-a[3])/10
   assert(math.abs(dx)+math.abs(dz)==1,'Fixture edges must share square boundaries')
   local mid={(a[1]+b[1])/2,a[2],(a[3]+b[3])/2}
   local p={to=to,left={mid[1]-dz*5,a[2],mid[3]+dx*5},right={mid[1]+dz*5,a[2],mid[3]-dx*5},midpoint=mid}
   p.meters=G.Distance(a,mid)+G.Distance(mid,b);return p
  end
  local localRows={};local localPortalCount=0
  for _,id in ipairs(options.localDirect and{1,2,3}or{1,3})do
   local p=clonePolygon(polygons[id]);p.center=nil;p.portals={}
   if options.localDirect and id<3 then
    local raw=portal(id,id+1);p.portals[1]={to=raw.to,left=raw.left,right=raw.right}
    localPortalCount=localPortalCount+1
   end
   localRows[#localRows+1]=p
  end
  local meta=metadata(identity,#localRows,localPortalCount)
  local mesh=finishMesh(planner.NavMesh.Begin(meta,{{identity=identity,polygons=localRows}}))
  local routeIDs=options.detour and{1,4,5,6,3}or{1,2,3}
  if options.reverseOnly then routeIDs={3,2,1}end
  if options.repeated then routeIDs={1,2,1,2,3}end
  local segments,total={},0
  for i=1,#routeIDs-1 do
   local from,to=routeIDs[i],routeIDs[i+1];local p=portal(from,to)
   segments[i]={from=from,to=to,origin=polygons[from].center,destination=polygons[to].center,
    midpoint=p.midpoint,left=p.left,right=p.right};total=total+p.meters
  end
  if options.badCost then total=total+1 end
  local stats={witnesses=0,segments=0,edges=0,childSteps=0,childCancels=0}
  local graph={}
  function graph:Stats()return{gateways=2,edges=1,revision='fixture-compact-v2'}end
  function graph:Original(gateway)return gateway==2 and 1 or gateway==1 and 3 or nil end
  function graph:Gateway(original)return original==1 and 2 or original==3 and 1 or nil end
  function graph:Polygon(original)local p=polygons[original];if p then return clonePolygon(p)end end
  function graph:Edges(gateway)
   local yielded=false
   return function()
    stats.edges=stats.edges+1;if yielded then return end;yielded=true
    if options.reverseOnly and gateway==1 then return 2,total,1,1 end
    if not options.reverseOnly and gateway==2 then return 1,total,1,1 end
   end
  end
  function graph:Segment(id)
   stats.segments=stats.segments+1
   if options.missingSegment and id==2 then return nil,'missing-global-portal'end
   local segment=segments[id];if not segment then return nil,'missing-edge'end
   return{from=segment.from,to=segment.to,origin=clonePoint(segment.origin),destination=clonePoint(segment.destination),
    midpoint=clonePoint(segment.midpoint),left=clonePoint(segment.left),right=clonePoint(segment.right)}
  end
  function graph:BeginWitness(from,to)
   stats.witnesses=stats.witnesses+1
   if options.reverseOnly and(from~=1 or to~=2)or not options.reverseOnly and(from~=2 or to~=1)then return nil,'no-directed-witness'end
   local job={at=0,ids={}}
   function job:Step(budget)
    assert(budget>=1 and budget<=64);stats.childSteps=stats.childSteps+1
    if self.cancelled then return nil,'cancelled',true end
    if options.staleDuringWitness and not self.changed then
     self.changed=true;local revision=mesh:Revision();mesh.Revision=function()return tostring(revision)..':stale'end
    end
    self.at=self.at+1
    if self.at<=#segments then self.ids[#self.ids+1]=self.at;return nil,nil,false end
    return self.ids,nil,true
   end
   function job:Cancel()self.cancelled=true;stats.childCancels=stats.childCancels+1 end
   return job
  end
  return mesh,graph,stats
 end
 local function query(planner,mesh,graph,budget)
  local job,problem=planner.PathNavigate.Begin(mesh,graph,{x=2,z=2,height=0},{x=28,z=8,height=0},{speed=7})
  assert(job,'PathNavigate rejected fixture: '..tostring(problem));return finish(job,budget),job
 end
 local function reject(check,name,result)
  check(name,result and type(result.status)=='string' and result.status~='modeled',result and result.reason)
  check(name..' does not publish partial geometry',result and result.corridor==nil and result.walkPoints==nil)
 end
 local function run()
  for _,name in ipairs({'schema','nav-geometry','nav-funnel','navmesh','nav-attach','path-search','path-route','path-navigate','nav-follow'})do module(name)end
  local p=assert(RikUI.QuestPlanner)
  local mesh,graph,stats=setup(p)
  check('real path fixture omits middle polygon from local NavMesh',mesh:PathVertex(2)==nil and graph:Polygon(2)~=nil)
  local result=query(p,mesh,graph,1)
  check('real compact corridor publishes a hybrid modeled route',result.status=='modeled' and result.hybrid==true,result.reason)
  if result.status=='modeled'then
   check('real compact corridor reconstructs original polygons',table.concat(result.corridor,',')=='1,2,3')
   check('real compact corridor owns every intermediate surface and forward portal',#result.surfaces==3 and #result.portals==2 and result.portals[1].to==2 and result.portals[2].to==3)
   check('real NavFunnel shortens the center route',type(result.walkPoints)=='table' and #result.walkPoints<#result.points and result.meters<result.graphMeters)
   check('real NavFunnel flat shortest path has expected length',near(result.meters,math.sqrt(26*26+6*6)))
   check('real center graph cost includes endpoint attachments',near(result.graphMeters,20+2*math.sqrt(18)))
   check('real route has matching seconds and suffix',near(result.seconds,result.meters/7) and near(result.suffix[1],result.meters) and result.suffix[#result.suffix]==0)
   check('real route retains derived-only evidence labels',result.confidence=='derived-model' and result.nativeVerified==false and result.globalOptimal==false)
   local metrics=result.metrics or {}
   check('real pipeline exposes attachment/network/assembly work',type(metrics.attachmentWork)=='number' and metrics.attachmentWork>0 and type(metrics.networkWork)=='number' and metrics.networkWork>0 and type(metrics.pipelineWork)=='number' and metrics.pipelineWork>0)
  end
  check('real hybrid used directed compact witnesses',stats.witnesses==1 and stats.segments==2)
  if result.status=='modeled'then
   local followJob=assert(p.NavFollow.Begin(mesh,result,1),'NavFollow.Begin rejected the real route')
   local retained=finish(followJob,1)
   check('hybrid retained route installs actual NavFollow callbacks',type(retained.locate)=='function' and type(retained.follow)=='function')
   if type(retained.locate)=='function' and type(retained.follow)=='function'then
    local previous={id=1,point={9.5,0,5}}
    local sourcePolygon=assert(mesh:PathVertex(1))
    check('continuity prior is inside validated endpoint polygon',p.NavGeometry.Point(previous.point)
     and p.NavGeometry.Contains(sourcePolygon.points,previous.point[1],previous.point[3])
     and near(previous.point[2],sourcePolygon.points[1][2]))
    check('continuity rejects missing prior location',retained.locate({x=10.5,z=5,height=0},nil)==nil)
    check('continuity rejects unknown prior polygon',retained.locate({x=10.5,z=5,height=0},{id=999,point={9.5,0,5}})==nil)
    local stationary=retained.locate({x=9.5,z=5,height=0},previous)
    check('continuity accepts a stationary known location',stationary and stationary.id==1)
    local boundary=retained.locate({x=6.5,z=5,height=0},previous)
    check('continuity accepts exactly three yards within the known polygon',boundary and boundary.id==1)
    check('continuity rejects a teleport within the same polygon',retained.locate({x=6.49,z=5,height=0},previous)==nil,
     'Distance must be measured from previous.point, not merely from the containing polygon')
    check('continuity rejects a long forward jump across the route',retained.locate({x=20.5,z=5,height=0},previous)==nil)
    check('continuity rejects a known incompatible floor height',retained.locate({x=10.5,z=5,height=5},previous)==nil)
    check('continuity rejects height beyond its stated one-yard tolerance',retained.locate({x=10.5,z=5,height=1.001},previous)==nil)
    check('continuity rejects invalid height values',retained.locate({x=10.5,z=5,height=math.huge},previous)==nil
     and retained.locate({x=10.5,z=5,height='unknown'},previous)==nil)
    local middle=retained.locate({x=10.5,z=5,height=0},previous)
    check('continuity crosses into an unloaded middle polygon',middle and middle.id==2 and mesh:PathVertex(2)==nil)
    check('continuity does not mutate its prior live location',previous.id==1 and previous.point[1]==9.5 and previous.point[2]==0 and previous.point[3]==5)
    if middle then
     check('continuity does not invent a reverse portal',retained.locate({x=9.5,z=5,height=0},middle)==nil)
     local missingHeight=retained.locate({x=11.5,z=5},middle)
     check('continuity can retain a unique surface when height is unavailable',missingHeight and missingHeight.id==2)
     local firstDisplay=retained.follow(middle,{speed=7})
     check('actual NavFollow provides guidance in unloaded middle polygon',firstDisplay and type(firstDisplay.meters)=='number'
      and firstDisplay.meters>0 and type(firstDisplay.seconds)=='number' and firstDisplay.next~=nil)
     if firstDisplay then check('retained follow cost uses observed walking speed',near(firstDisplay.seconds,firstDisplay.meters/7))end
     local current=middle;local lastMeters=firstDisplay and firstDisplay.meters
     for _,x in ipairs({12.5,14.5,16.5,18.5,20.5})do
      local nextLocation=retained.locate({x=x,z=5,height=0},current)
      check('continuity advances by bounded movement at '..x,nextLocation and nextLocation.id==(x<20 and 2 or 3))
      if not nextLocation then break end
      local display=retained.follow(nextLocation,{speed=7})
      check('actual NavFollow remains available at '..x,display and type(display.meters)=='number' and type(display.seconds)=='number' and display.next~=nil)
      if display and lastMeters then check('retained remaining distance decreases at '..x,display.meters<lastMeters)end
      if display then lastMeters=display.meters end
      current=nextLocation
     end
     check('continuity reaches loaded goal region without loading the middle',current.id==3 and mesh:PathVertex(2)==nil)
     check('goal region does not gain an invented reverse crossing',retained.locate({x=19.5,z=5,height=0},current)==nil)
    end
   end
  end

  local repeated=query(p,mesh,graph,64)
  check('real pipeline budgets preserve corridor and cost',repeated.status=='modeled' and result.status=='modeled'
   and table.concat(repeated.corridor,',')==table.concat(result.corridor,',') and near(repeated.meters,result.meters))

  mesh,graph=setup(p,{middleHeight=1});reject(check,'real compact wrong-floor step is rejected',query(p,mesh,graph))
  mesh,graph=setup(p,{missingSegment=true});reject(check,'real compact missing forward portal is rejected',query(p,mesh,graph))
  mesh,graph=setup(p,{reverseOnly=true});reject(check,'real compact reverse-only edge cannot route forward',query(p,mesh,graph))
  mesh,graph=setup(p,{repeated=true});local loop=query(p,mesh,graph)
  reject(check,'real compact repeated polygon rejected before following',loop)
  check('repeated polygon retains explicit diagnostic',loop.reason=='repeated-corridor-polygon')
  mesh,graph=setup(p,{badCost=true});local mismatched=query(p,mesh,graph)
  reject(check,'real compact cost mismatch is rejected',mismatched)
  check('real compact cost mismatch retains explicit reason',mismatched.reason=='model-cost-mismatch')
  mesh,graph=setup(p,{staleDuringWitness=true});local stale=query(p,mesh,graph,1)
  reject(check,'real pipeline cancels stale mesh revision',stale)
  check('real stale route is cancelled explicitly',stale.status=='cancelled' and stale.reason=='stale')

  mesh,graph,stats=setup(p)
  local job=assert(p.PathNavigate.Begin(mesh,graph,{x=2,z=2,height=0},{x=28,z=8,height=0},{speed=7}))
  job:Step(1);job:Cancel();local calls=stats.edges+stats.segments+stats.childSteps
  local cancelled=finish(job,64)
  reject(check,'real pipeline cancellation discards pending route',cancelled)
  job:Step(64)
  check('real cancelled pipeline does not query the compact graph again',stats.edges+stats.segments+stats.childSteps==calls)

  mesh,graph,stats=setup(p,{localDirect=true,detour=true})
  local localResult=query(p,mesh,graph,1)
  check('real local direct path competes with valid global detour',localResult.status=='modeled' and table.concat(localResult.corridor,',')=='1,2,3',localResult.reason)
  check('real direct winner avoids reconstructing the unused global detour',stats.witnesses==0 and stats.segments==0)
  check('real local direct winner uses the actual funnel',localResult.status=='modeled' and near(localResult.meters,math.sqrt(26*26+6*6)))
 end
 local ok,problem=xpcall(run,function(err)return debug and debug.traceback and debug.traceback(err,2) or tostring(err)end)
 RikUI=oldRikUI;GetTime=oldGetTime;debugprofilestop=oldProfiler
 if not ok then error(problem,0)end
end
