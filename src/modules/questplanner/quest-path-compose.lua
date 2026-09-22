-- Bounded exact composition of already admitted physical compact graphs.
local planner=RikUI.QuestPlanner
local schema,geometry=planner.Schema,planner.NavGeometry
local compose={};planner.PathCompose=compose
local STRIDE,MAX_PACKS,SEAM_BASE=16777216,8,134217728
local function same(a,b)return a and b and a.product==b.product and a.build==b.build and a.locale==b.locale end
local function hash(v)return type(v)=='string'and#v==64 and v:match('^[a-f0-9]+$')end
local function close(a,b)return schema.Number(a,0,1e10)and schema.Number(b,0,1e10)and math.abs(a-b)<=1e-9*math.max(1,a,b)end
local function fail(why)error({reason=why},0)end
local function pause()coroutine.yield()end
local function vector(v)
 if not geometry.Point(v)then fail('invalid-seam-point')end
 return {v[1],v[2],v[3]}
end
local function polygon(graph,id)
 local p=graph:Polygon(id)
 if not p or p.id~=id or not geometry.Point(p.center)or not geometry.Convex(p.points)then fail('seam-polygon-unavailable')end
 if not geometry.Contains(p.points,p.center[1],p.center[3])then fail('seam-center-outside')end
 return p
end
local function seamGeometry(row,a,b,step)
 local left,right,mid=vector(row.left),vector(row.right),vector(row.midpoint)
 if geometry.Distance(left,right)<.0001 then fail('seam-too-narrow')end
 for axis=1,3 do if math.abs((left[axis]+right[axis])/2-mid[axis])>.000001 then fail('seam-midpoint-mismatch')end end
 if not geometry.OnBoundary(a.points,left)or not geometry.OnBoundary(a.points,right)
  or not geometry.OnBoundary(b.points,left,.01)or not geometry.OnBoundary(b.points,right,.01)
  or not geometry.Contains(a.points,mid[1],mid[3])or not geometry.Contains(b.points,mid[1],mid[3])then fail('seam-boundary-mismatch')end
 for _,point in ipairs({left,right,mid})do
  local h=geometry.BoundaryHeight(a.points,point);local other=geometry.BoundaryHeight(b.points,point,.01)
  if not schema.Number(h,-100000,100000)or not schema.Number(other,-100000,100000)
   or math.abs(point[2]-h)>.002 or math.abs(h-other)>step+.002 then fail('seam-height-mismatch')end
  pause()
 end
 local cost=geometry.Distance(a.center,mid)+geometry.Distance(mid,b.center)
 if not close(cost,row.authoredCenterCost)or not close(cost,row.meters)then fail('seam-cost-mismatch')end
 return {origin=vector(a.center),destination=vector(b.center),left=left,right=right,midpoint=mid,cost=cost}
end
local function witness(child,offset,single)
 local cancelled,done=false,false
 local worker=coroutine.create(function()
  local values=single
  if not values then
   while true do local v,why,finished=child:Step(1);pause();if finished then if not v then return nil,why end;values=v;break end end
  end
  if #values>4096 then return nil,'witness-path-limit'end
  local out={}
  for _,id in ipairs(values)do if not schema.Integer(id,1,STRIDE-1)then return nil,'witness-edge-invalid'end;out[#out+1]=offset+id;pause()end
  return out
 end)
 return {Cancel=function()cancelled=true;if child then child:Cancel()end end,Step=function(_,budget)
  if cancelled then return nil,'cancelled',true end
  if done then return nil,'witness-already-completed',true end
  if not schema.Integer(budget or 16,1,64)then return nil,'invalid-witness-budget',true end
  for _=1,budget or 16 do local ok,value,why=coroutine.resume(worker)
   if not ok then done=true;return nil,'invalid-witness',true end
   if coroutine.status(worker)=='dead'then done=true;return value,why,true end
  end
 end}
end
local function publish(packs,byName,gateways,seams,adj,edgeCount,identity,world,profile)
 local function gateway(id)
  if not schema.Integer(id,1,#gateways)then return end
  local row=gateways[id];return packs[row.pack],row.localID
 end
 local function decode(id)
  if not schema.Integer(id,1,MAX_PACKS*STRIDE-1)then return end
  local slot=math.floor(id/STRIDE)+1;local localID=id%STRIDE
  if localID==0 or not packs[slot]then return end
  return packs[slot],localID
 end
 local out={}
 function out:Encode(namespace,id)local p=byName[namespace];if p and schema.Integer(id,1,STRIDE-1)then return p.polygonOffset+id end end
 function out:Decode(id)local p,localID=decode(id);if p then return p.namespace,localID end end
 function out:Gateway(id)local p,localID=decode(id);local g=p and p.graph:Gateway(localID);if g then return p.gatewayOffset+g end end
 function out:Original(id)local p,localID=gateway(id);if p then return p.polygonOffset+p.graph:Original(localID)end end
 function out:Center(id)local p,localID=gateway(id);if p then return p.graph:Center(localID)end end
 function out:Polygon(id)local p,localID=decode(id);local value=p and p.graph:Polygon(localID);if value then value.id=id;return value end end
 function out:Edges(id)
  local p,localID=gateway(id);if not p then return function()end end
  local it=p.graph:Edges(localID);local tail,index=false,0
  return function()
   if not tail then local target,cost,proof,edge=it();if target then return p.gatewayOffset+target,cost,proof,edge and(p.polygonOffset+edge)end;tail=true end
   index=index+1;local row=adj[id]and adj[id][index];if row then return row.toGateway,row.cost,row.id,SEAM_BASE+row.index end
  end
 end
 function out:Segment(id)
  if not schema.ID(id)then return nil,'invalid-composed-edge'end
  if id>SEAM_BASE then local row=seams[id-SEAM_BASE];if row then return schema.Clone(row.segment)end;return nil,'seam-edge-unavailable'end
  local p,localID=decode(id);local value=p and p.graph:Segment(localID)
  if not value then return nil,'composed-edge-unavailable'end
  value.from=p.polygonOffset+value.from;value.to=p.polygonOffset+value.to;return value
 end
 function out:BeginWitness(from,to)
  local a,ai=gateway(from);local b,bi=gateway(to)
  if not a or not b then return nil,'invalid-composed-gateway'end
  if a==b then local child,why=a.graph:BeginWitness(ai,bi);if not child then return nil,why end;return witness(child,a.polygonOffset)end
  for _,row in ipairs(adj[from]or{})do if row.toGateway==to then return witness(nil,SEAM_BASE,{row.index})end end
  return nil,'directed-seam-absent'
 end
 function out:Stats()return {gateways=#gateways,edges=edgeCount,packs=#packs,seams=#seams}end
 function out:Catalog()return {format='rikui-composed-path-graph-v1',identity=schema.Clone(identity),worldMapID=world,sourceProfileSHA256=profile,nativeVerified=false}end
 return out
end
function compose.Begin(inputs,rawSeams,options)
 options=options or{}
 if not schema.List(inputs,MAX_PACKS)or#inputs<1 or not schema.List(rawSeams,4096)
  or not schema.Number(options.maxStep,0,2)then return nil,'invalid-composition-input'end
 local maxWork=options.maxWork or 1048576
 if not schema.Integer(maxWork,1,1048576)then return nil,'invalid-composition-budget'end
 local cancelled,done,work=false,false,0
 local worker=coroutine.create(function()
  local packs,byName,gateways={}, {},{}
  local identity,world,profile,edgeCount=nil,nil,nil,0
  for _,input in ipairs(inputs)do
   if type(input)~='table'or type(input.graph)~='table'or type(input.graph.Catalog)~='function'then fail('invalid-composition-pack')end
   local c=input.graph:Catalog();local m=planner.NavMesh.ValidateMetadata(input.meta)
   if not m or not c or c.namespace~=input.namespace or not planner.TerrainPacks.Namespace(c.namespace,c.worldMapID)
    or not same(c.identity,m.identity)or c.worldMapID~=m.worldMapID or c.sourceSHA256~=m.source.sha256
    or not hash(m.source.profileSHA256)or m.modeledMaxStep~=options.maxStep or byName[c.namespace]then fail('incompatible-composition-pack')end
   if identity and(not same(identity,c.identity)or world~=c.worldMapID or profile~=m.source.profileSHA256)then fail('incompatible-composition-world')end
   identity,world,profile=c.identity,c.worldMapID,m.source.profileSHA256
   local stats=input.graph:Stats()
   if not schema.Integer(stats.gateways,1,65536)or not schema.Integer(stats.edges,0,200000)then fail('invalid-composition-size')end
   local row={namespace=c.namespace,graph=input.graph,count=stats.gateways,edges=stats.edges}
   packs[#packs+1]=row;byName[row.namespace]=row;pause()
  end
  table.sort(packs,function(a,b)return a.namespace<b.namespace end)
  for slot,p in ipairs(packs)do
   p.polygonOffset=(slot-1)*STRIDE;p.gatewayOffset=#gateways
   if #gateways+p.count>8192 or edgeCount+p.edges>200000 then fail('composition-working-set-limit')end
   for id=1,p.count do
    if not schema.Integer(p.graph:Original(id),1,STRIDE-1)then fail('invalid-composition-original-id')end
    gateways[#gateways+1]={pack=slot,localID=id};pause()
   end
   edgeCount=edgeCount+p.edges
  end
  local best,seen={},{}
  for _,raw in ipairs(rawSeams)do
   local r=schema.Copy(raw)
   if not r or not hash(r.id)or not hash(r.proofSHA256)or seen[r.id]or r.worldMapID~=world
    or type(r.fromKey)~='string'or type(r.toKey)~='string'then fail('invalid-composition-seam')end
   seen[r.id]=true
   local a,b=byName[r.fromNamespace],byName[r.toNamespace]
   if not a or not b or a==b or not schema.Integer(r.fromID,1,STRIDE-1)or not schema.Integer(r.toID,1,STRIDE-1)then fail('unbound-composition-seam')end
   local ag,bg=a.graph:Gateway(r.fromID),b.graph:Gateway(r.toID)
   if not ag or not bg then fail('seam-endpoint-not-gateway')end
   local from,to=a.gatewayOffset+ag,b.gatewayOffset+bg
   local segment=seamGeometry(r,polygon(a.graph,r.fromID),polygon(b.graph,r.toID),options.maxStep)
   segment.from=a.polygonOffset+r.fromID;segment.to=b.polygonOffset+r.toID
   local row={id=r.id,fromGateway=from,toGateway=to,cost=segment.cost,segment=segment};segment.cost=nil
   local key=from..':'..to;local prior=best[key]
   if not prior or row.cost<prior.cost or row.cost==prior.cost and row.id<prior.id then best[key]=row end
   pause()
  end
  local seams,adj={},{}
  for _,row in pairs(best)do seams[#seams+1]=row end
  table.sort(seams,function(a,b)return a.fromGateway<b.fromGateway or a.fromGateway==b.fromGateway and a.toGateway<b.toGateway end)
  for i,row in ipairs(seams)do row.index=i;local list=adj[row.fromGateway]or{};adj[row.fromGateway]=list;list[#list+1]=row;pause()end
  if edgeCount+#seams>200000 then fail('composition-edge-limit')end
  return publish(packs,byName,gateways,seams,adj,edgeCount+#seams,identity,world,profile)
 end)
 return {Cancel=function()cancelled=true end,Progress=function()return work end,Step=function(_,budget)
  if cancelled then return nil,'cancelled',true end
  if done then return nil,'composition-already-completed',true end
  if not schema.Integer(budget or 16,1,64)then return nil,'invalid-composition-slice',true end
  for _=1,budget or 16 do
   if options.isCurrent and not options.isCurrent()then cancelled=true;return nil,'stale-composition',true end
   if work>=maxWork then done=true;return nil,'composition-work-limit',true end
   work=work+1;local ok,value=coroutine.resume(worker)
   if not ok then done=true;return nil,type(value)=='table'and value.reason or'invalid-composition',true end
   if coroutine.status(worker)=='dead'then done=true;return value,nil,true end
  end
 end}
end
