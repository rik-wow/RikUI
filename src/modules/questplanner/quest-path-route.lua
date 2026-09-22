-- Reconstructs a derived center-network route and validates every directed portal.
-- This does not claim native verification or a globally optimal walking route.
local planner=RikUI.QuestPlanner
local geometry=planner.NavGeometry
local route={REVISION='prepared-center-route-1'}
planner.PathRoute=route
local Job={};Job.__index=Job
local MAX_WORK=1048576
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function integer(n,minimum,maximum)return finite(n) and n%1==0 and n>=minimum and n<=maximum end
local function abort(reason,status)error({status=status or 'unavailable',reason=reason},0)end
local function checkpoint()coroutine.yield()end
local function closeCost(a,b)
 return finite(a) and finite(b) and math.abs(a-b)<=1e-9*math.max(1,math.abs(a),math.abs(b))
end
local function ownPoint(value)
 if not geometry.Point(value)then abort('invalid-route-point')end
 local point={value[1],value[2],value[3]};checkpoint();return point
end
local function ownPolygon(value,id)
 if type(value)~='table' or value.id~=id or type(value.points)~='table' then abort('polygon-unavailable')end
 if #value.points<3 or #value.points>6 then abort('invalid-polygon-size')end
 local polygon={id=id,center=ownPoint(value.center),points={}}
 for i=1,#value.points do polygon.points[i]=ownPoint(value.points[i])end
 if geometry.Convex(polygon.points)~=true then abort('invalid-polygon-shape')end
 if not geometry.Contains(polygon.points,polygon.center[1],polygon.center[3])then abort('polygon-center-outside')end
 checkpoint();return polygon
end
local function samePolygon(a,b)
 if a.id~=b.id or #a.points~=#b.points or not closeCost(geometry.Distance(a.center,b.center),0)then return false end
 for _,point in ipairs(a.points)do
  local found=false
  for _,other in ipairs(b.points)do if geometry.Distance(point,other)<=.002 then found=true;break end end
  if not found then return false end;checkpoint()
 end
 return true
end
local function ownPortal(value,to)
 if type(value)~='table' or value.to~=to then abort('directed-portal-unavailable')end
 return{to=to,left=ownPoint(value.left),right=ownPoint(value.right),midpoint=ownPoint(value.midpoint)}
end
local function portalCost(source,target,portal,maxStep)
 if not geometry.OnBoundary(source.points,portal.left) or not geometry.OnBoundary(source.points,portal.right)
  or not geometry.OnBoundary(target.points,portal.left,.01) or not geometry.OnBoundary(target.points,portal.right,.01)then
  abort('portal-boundary-mismatch')
 end
 if geometry.Distance(portal.left,portal.right)<.0001 then abort('portal-too-narrow')end
 local mid=portal.midpoint
 if not geometry.Contains(source.points,mid[1],mid[3]) or not geometry.Contains(target.points,mid[1],mid[3])then
  abort('portal-midpoint-outside')
 end
 checkpoint()
 for _,point in ipairs({portal.left,portal.right,portal.midpoint})do
  local sourceHeight=geometry.BoundaryHeight(source.points,point)
  local targetHeight=geometry.BoundaryHeight(target.points,point,.01)
  if not finite(sourceHeight) or not finite(targetHeight) or math.abs(point[2]-sourceHeight)>.002
   or math.abs(sourceHeight-targetHeight)>maxStep+.002 then abort('portal-height-mismatch')end
  checkpoint()
 end
 return geometry.Distance(source.center,mid)+geometry.Distance(mid,target.center)
end
local function appendPoint(state,point)
 local owned=ownPoint(point);local previous=state.result.points[#state.result.points]
 if previous then
  local distance=geometry.Distance(previous,owned)
  if not finite(distance) or distance<0 then abort('invalid-route-distance')end
  state.result.graphMeters=state.result.graphMeters+distance
  if not finite(state.result.graphMeters)then abort('route-distance-overflow')end
 end
 state.result.points[#state.result.points+1]=owned
end
local function firstPolygon(state,polygon)
 if state.current then
  if not samePolygon(state.current,polygon)then abort('corridor-joint-mismatch')end
  return
 end
 if polygon.id~=state.start.id then abort('prefix-start-mismatch')end
 if not geometry.Contains(polygon.points,state.start.point[1],state.start.point[3])then abort('start-point-outside')end
 state.current=polygon;state.seen[polygon.id]=true;state.result.corridor[1]=polygon.id;state.result.surfaces[1]=polygon.points
 appendPoint(state,state.start.point)
 if state.useCenters then appendPoint(state,polygon.center)end
end
local function appendEdge(state,target,portal,expectedCost)
 if state.seen[target.id] then abort('repeated-corridor-polygon')end
 state.seen[target.id]=true
 if #state.result.corridor>=state.maxPath then abort('path-limit','budget-exhausted')end
 local cost=portalCost(state.current,target,portal,state.maxStep)
 if expectedCost~=nil and not closeCost(cost,expectedCost)then abort('portal-cost-mismatch')end
 state.result.portals[#state.result.portals+1]=portal
 state.result.corridor[#state.result.corridor+1]=target.id
 state.result.surfaces[#state.result.surfaces+1]=target.points
 appendPoint(state,portal.midpoint);appendPoint(state,target.center);state.current=target
end
local function await(job,child,problem)
 if type(child)~='table' or type(child.Step)~='function'then abort(problem or 'witness-unavailable')end
 job.activeChild=child
 while true do
  local value,why,done=child:Step(1);checkpoint()
  if done then
   job.activeChild=nil
   if type(value)~='table'then abort(why or 'witness-unavailable')end
   return value
  end
 end
end
local function localLeg(_job,state,mesh,path)
 if #path<1 then abort('empty-local-witness')end
 if #path>state.maxPath then abort('path-limit','budget-exhausted')end
 for i=1,#path do
  local id=path[i]
  if not integer(id,0,2147483647)then abort('invalid-original-polygon-id')end
  local polygon=ownPolygon(mesh:PathVertex(id),id)
  if i==1 then firstPolygon(state,polygon)
  else
   local raw=mesh:PathPortal(state.current.id,id)
   if type(raw)~='table' or not finite(raw.meters) or raw.meters<0 then abort('local-portal-unavailable')end
   appendEdge(state,polygon,ownPortal(raw,id),raw.meters)
  end
  checkpoint()
 end
end
local function gatewayJoint(graph,gateway,polygonID)
 if type(graph.Original)~='function' or graph:Original(gateway)~=polygonID then abort('gateway-boundary-mismatch')end
 checkpoint()
end
local function networkLeg(job,state,graph,fromGateway,toGateway)
 gatewayJoint(graph,fromGateway,state.current.id)
 local child,why=graph:BeginWitness(fromGateway,toGateway);local edges=await(job,child,why)
 if #edges<1 and fromGateway~=toGateway then abort('empty-network-witness')end
 if #edges>=state.maxPath then abort('path-limit','budget-exhausted')end
 for i=1,#edges do
  if not integer(edges[i],1,2147483647)then abort('invalid-directed-edge-id')end
  local segment,problem=graph:Segment(edges[i])
  if type(segment)~='table' then abort(problem or 'network-segment-unavailable')end
  local from,to,origin,destination,midpoint,left,right=segment.from,segment.to,segment.origin,segment.destination,segment.midpoint,segment.left,segment.right
  if from~=state.current.id or not integer(to,0,2147483647)then abort('network-witness-disconnected')end
  local source=ownPolygon(graph:Polygon(from),from)
  if not samePolygon(source,state.current)then abort('network-source-mismatch')end
  local target=ownPolygon(graph:Polygon(to),to)
  if not geometry.Point(origin) or not geometry.Point(destination)
   or not closeCost(geometry.Distance(origin,source.center),0)
   or not closeCost(geometry.Distance(destination,target.center),0)then abort('network-center-mismatch')end
  local portal=ownPortal({to=to,midpoint=midpoint,left=left,right=right},to)
  appendEdge(state,target,portal)
  checkpoint()
 end
 gatewayJoint(graph,toGateway,state.current.id)
end
local function finishGeometry(state,coarse,speed)
 if not state.current or state.current.id~=state.goal.id then abort('suffix-goal-mismatch')end
 if not geometry.Contains(state.current.points,state.goal.point[1],state.goal.point[3])then abort('goal-point-outside')end
 appendPoint(state,state.goal.point)
 local result=state.result
 if not closeCost(result.graphMeters,coarse.cost)then abort('model-cost-mismatch')end
 local points,crossings,corners=geometry.StringPull(result,nil,nil,checkpoint)
 if type(points)~='table' then abort(crossings or 'projection-unavailable')end
 if #points<1 or #points>state.maxPath*4+2 then abort('walk-point-limit','budget-exhausted')end
 result.walkPoints=points;result.crossings=crossings;result.corners=corners;result.suffix={}
 for i=#points,1,-1 do
  if not geometry.Point(points[i])then abort('invalid-projected-point')end
  if i==#points then result.suffix[i]=0
  else result.suffix[i]=result.suffix[i+1]+geometry.Distance(points[i],points[i+1])end
  if not finite(result.suffix[i])then abort('projected-distance-overflow')end
  checkpoint()
 end
 if geometry.Distance(points[1],state.start.point)>.002 or geometry.Distance(points[#points],state.goal.point)>.002 then
  abort('projected-endpoint-mismatch')
 end
 result.meters=result.suffix[1];result.seconds=result.meters/speed
 if not finite(result.seconds)then abort('route-time-overflow')end
 return result
end
local function assemble(job,mesh,graph,attachments,coarse,options)
 if type(geometry.StringPull)~='function'then abort('projection-unavailable')end
 local meta=mesh:Metadata()
 if type(meta)~='table' or not finite(meta.modeledMaxStep) or meta.modeledMaxStep<0 then abort('step-model-unavailable')end
 if type(attachments.start)~='table' or type(attachments.goal)~='table'then abort('route-endpoints-unavailable')end
 local state={seen={},maxPath=options.maxPath,maxStep=meta.modeledMaxStep,
  start={id=attachments.start.id,point=ownPoint(attachments.start.point)},
  goal={id=attachments.goal.id,point=ownPoint(attachments.goal.point)},
  result={status='modeled',corridor={},surfaces={},portals={},points={},graphMeters=0,
   confidence='derived-model',nativeVerified=false,revision=job.revision,
   searchRepresentation='prepared-center-network',globalOptimal=false}}
 if not finite(coarse.cost) or coarse.cost<0 then abort('invalid-coarse-cost')end
 if coarse.direct==true then
  local child,why=attachments:BeginDirect();local path=await(job,child,why)
  state.useCenters=#path>1;localLeg(job,state,mesh,path)
 else
  local gateways,links=coarse.gatewayPath,coarse.links
  if type(gateways)~='table' or type(links)~='table' or #gateways<1 or #links~=#gateways-1 then abort('invalid-gateway-path')end
  if #gateways>options.maxPath then abort('path-limit','budget-exhausted')end
  for i=1,#gateways do if not integer(gateways[i],1,2147483647)then abort('invalid-gateway-id')end;checkpoint()end
  state.useCenters=true
  local prefix,why=attachments:BeginPrefix(gateways[1]);localLeg(job,state,mesh,await(job,prefix,why))
  gatewayJoint(graph,gateways[1],state.current.id)
  for i=1,#links do
   local link=links[i]
   if type(link)~='table' or link.from~=gateways[i] or link.to~=gateways[i+1]then abort('coarse-link-mismatch')end
   networkLeg(job,state,graph,link.from,link.to)
  end
  gatewayJoint(graph,gateways[#gateways],state.current.id)
  local suffix,problem=attachments:BeginSuffix(gateways[#gateways]);localLeg(job,state,mesh,await(job,suffix,problem))
 end
 return finishGeometry(state,coarse,options.speed)
end
local function terminal(job,result)
 if job.result then return job.result end
 if type(result)~='table'then result={status='unavailable',reason='invalid-assembly-result'}end
 if job.activeChild and type(job.activeChild.Cancel)=='function'then pcall(job.activeChild.Cancel,job.activeChild)end
 result.work=job.work;job.result=result;job.activeChild=nil;job.coroutine=nil;job.mesh=nil
 return result
end
function Job:Progress()return self.work end
function Job:Cancel(reason)
 return terminal(self,{status='cancelled',reason=type(reason)=='string' and reason:sub(1,96) or 'cancelled'})
end
function Job:Step(budget)
 if self.result then return self.result end
 local ok,revision=pcall(self.mesh.Revision,self.mesh)
 if not ok or revision~=self.revision then return self:Cancel('stale')end
 budget=finite(budget) and math.floor(budget) or 32;budget=math.max(1,math.min(64,budget))
 for _=1,budget do
  if self.work>=self.maxWork then return terminal(self,{status='budget-exhausted',reason='work-limit'})end
  local success,value=coroutine.resume(self.coroutine);self.work=self.work+1
  if not success then
   return terminal(self,type(value)=='table' and{status=value.status or 'unavailable',reason=value.reason or 'route-assembly-error'}
    or{status='unavailable',reason='route-assembly-error',detail=tostring(value):sub(1,256)})
  end
  if coroutine.status(self.coroutine)=='dead'then return terminal(self,value)end
 end
 return nil
end
function route.Begin(mesh,graph,attachments,coarse,options)
 local job=setmetatable({work=0},Job);if options==nil then options={}end
 if type(mesh)~='table' or type(mesh.Revision)~='function' or type(mesh.Metadata)~='function'
  or type(mesh.PathVertex)~='function' or type(mesh.PathPortal)~='function' or type(graph)~='table'
  or type(attachments)~='table' or type(coarse)~='table' or type(options)~='table'then
  terminal(job,{status='unavailable',reason='invalid-route-input'});return job
 end
 local speed=options.speed or 7;local maxPath=options.maxPath or 4096;local maxWork=options.maxWork or MAX_WORK
 if not finite(speed) or speed<=0 or not integer(maxPath,1,4096) or not integer(maxWork,1,MAX_WORK)then
  terminal(job,{status='unavailable',reason='invalid-route-limit'});return job
 end
 local ok,revision=pcall(mesh.Revision,mesh)
 if not ok or revision==nil then terminal(job,{status='unavailable',reason='revision-unavailable'});return job end
 job.mesh=mesh;job.revision=revision;job.maxWork=maxWork
 job.coroutine=coroutine.create(function()
  return assemble(job,mesh,graph,attachments,coarse,{speed=speed,maxPath=maxPath})
 end)
 return job
end
