return function(check)
 local saved=RikUI
 local ok,why=pcall(function()
  RikUI={};RikUI['Secret']={IsSecret=function()return false end}
  for _,name in ipairs({'schema','nav-geometry','nav-funnel','nav-follow','nav-search','navmesh','nav-attach','path-search','path-route','path-navigate','terrain-packs','path-compose'})do dofile('src/modules/questplanner/quest-'..name..'.lua')end
  local p=RikUI.QuestPlanner;local identity={product='forever',build='1.60.1.69913',locale='enUS'}
  local function hash(c)return string.rep(c,64)end
  local function square(id,x)return {id=id,center={x+5,0,5},points={{x,0,0},{x+10,0,0},{x+10,0,10},{x,0,10}}}end
  local function pack(namespace,base)
   local values={square(1,base),square(2,base+10)}
   local meta={format='rikui-navmesh-v1',identity=identity,revision='fixture',uiMapID=1426,worldMapID=0,
    source={sha256=hash('a'),parser='fixture',profileSHA256=hash('b')},projection={originX=100,originY=100,width=100,height=100},
    counts={polygons=2,portals=1},bounds={base,0,base+20,10},modeledMaxStep=.3,exclusions={},blockers={}}
   local graph={}
   function graph:Catalog()return {namespace=namespace,identity=identity,worldMapID=0,sourceSHA256=hash('a')}end
   function graph:Stats()return {gateways=2,edges=1}end
   function graph:Original(id)if values[id]then return id end end
   function graph:Gateway(id)if values[id]then return id end end
   function graph:Center(id)return p.Schema.Clone(values[id].center)end
   function graph:Polygon(id)return p.Schema.Clone(values[id])end
   function graph:Edges(id)local used=false;return function()if id==1 and not used then used=true;return 2,10,1,1 end end end
   function graph:Segment(id)if id==1 then return {from=1,to=2,origin=values[1].center,destination=values[2].center,
    midpoint={base+10,0,5},left={base+10,0,10},right={base+10,0,0}}end end
   function graph:BeginWitness(from,to)if from~=1 or to~=2 then return nil,'absent'end
    local cancelled=false;return {Cancel=function()cancelled=true end,Step=function()if cancelled then return nil,'cancelled',true end;return {1},nil,true end}
   end
   return {namespace=namespace,graph=graph,meta=meta}
  end
  local inputs={pack('W0_Xp0_Zp0',0),pack('W0_Xp1_Zp0',20)}
  local seam={id=hash('c'),proofSHA256=hash('d'),worldMapID=0,fromNamespace=inputs[1].namespace,toNamespace=inputs[2].namespace,
   fromID=2,toID=1,fromKey='w0:r0:0:0:p2',toKey='w0:r1:0:0:p1',left={20,0,10},right={20,0,0},midpoint={20,0,5},meters=10,authoredCenterCost=10}
  for _,key in ipairs({'left','right','midpoint'})do
   local missing=p.Schema.Clone(seam);missing[key]=nil
   local accepted,reason=p.TerrainPacks.RegisterSeams(hash('f'),{missing})
   check('seam registration rejects missing '..key,not accepted and reason=='invalid-seam-point',reason)
  end
  local function finish(job,reason)
   assert(job,reason);for _=1,10000 do local value,why,done=job:Step(1);if done then return value,why end end;error('test slice limit')
  end
  local function composed(rows,settings)return finish(p.PathCompose.Begin(inputs,rows or{seam},settings or{maxStep=.3}))end
  local graph=assert(composed());local a,b=graph:Encode(inputs[1].namespace,1),graph:Encode(inputs[2].namespace,2)
  check('composition preserves pack-local duplicate original IDs',a~=graph:Encode(inputs[2].namespace,1)and graph:Decode(a)==inputs[1].namespace)
  check('composition publishes exact bounded graph counts',graph:Stats().gateways==4 and graph:Stats().edges==3 and graph:Stats().seams==1)
  local job=assert(p.PathSearch.Begin(graph,{[graph:Gateway(a)]=0},{[graph:Gateway(b)]=0}));local coarse
  for _=1,100 do coarse=job:Step(1);if coarse then break end end
  check('composition Dijkstra uses exact directed seam',coarse and coarse.status=='modeled'and coarse.cost==30 and#coarse.gatewayPath==4)
  job=assert(p.PathSearch.Begin(graph,{[graph:Gateway(b)]=0},{[graph:Gateway(a)]=0}));local reverse
  for _=1,100 do reverse=job:Step(1);if reverse then break end end
  check('composition does not invent a reverse seam',reverse and reverse.status=='no-model-path')
  local meta=p.Schema.Clone(inputs[1].meta);meta.bounds={0,0,40,10};meta.counts={polygons=2,portals=0}
  local first,last=graph:Polygon(a),graph:Polygon(b)
  local mesh=assert(finish(p.NavMesh.Begin(meta,{{identity=identity,polygons={{id=a,points=first.points,portals={}},{id=b,points=last.points,portals={}}}}})))
  local navigate=assert(p.PathNavigate.Begin(mesh,graph,{x=5,z=5,height=0},{x=35,z=5,height=0}));local route
  for _=1,10000 do route=navigate:Step(1);if route then break end end
  check('composition real funnel reconstructs omitted pack surfaces',route and route.status=='modeled'and#route.corridor==4 and route.meters==30 and route.nativeVerified==false)
  local reversed=assert(finish(p.PathCompose.Begin({inputs[2],inputs[1]},{seam},{maxStep=.3})))
  check('composition IDs are stable under input ordering',reversed:Encode(inputs[1].namespace,1)==a and reversed:Encode(inputs[2].namespace,2)==b)
  local function rejected(name,mutate,expected)
   local row=p.Schema.Clone(seam);mutate(row);local value,problem=composed({row});check(name,not value and problem==expected,problem)
  end
  rejected('composition rejects invented seam cost',function(r)r.authoredCenterCost=11 end,'seam-cost-mismatch')
  rejected('composition rejects a different physical world',function(r)r.worldMapID=1 end,'invalid-composition-seam')
  rejected('composition rejects unadmitted pack namespace',function(r)r.toNamespace='W0_Xp2_Zp0'end,'unbound-composition-seam')
  rejected('composition rejects unavailable gateway endpoint',function(r)r.toID=99 end,'seam-endpoint-not-gateway')
  rejected('composition rejects shifted portal floor',function(r)r.left[2]=5;r.right[2]=5;r.midpoint[2]=5 end,'seam-height-mismatch')
  rejected('composition rejects outside portal geometry',function(r)r.left[1]=21;r.right[1]=21;r.midpoint[1]=21 end,'seam-boundary-mismatch')
  local duplicate=p.Schema.Clone(seam);local value,problem=composed({seam,duplicate})
  check('composition rejects duplicate exact seam proof',not value and problem=='invalid-composition-seam')
  value,problem=composed({},{maxStep=.3,maxWork=1});check('composition enforces total work budget',not value and problem=='composition-work-limit')
  job=assert(p.PathCompose.Begin(inputs,{seam},{maxStep=.3}));job:Step(1);local before=job:Progress();job:Cancel()
  value,problem=job:Step(64);check('composition cancellation stops all future work',not value and problem=='cancelled'and job:Progress()==before)
  job=assert(p.PathCompose.Begin(inputs,{seam},{maxStep=.3,isCurrent=function()return false end}));value,problem=job:Step(1)
  check('composition rejects stale map jobs before work',not value and problem=='stale-composition'and job:Progress()==0)
  local profile=inputs[2].meta.source.profileSHA256;inputs[2].meta.source.profileSHA256=hash('e');value,problem=composed()
  check('composition rejects incompatible source profiles',not value and problem=='incompatible-composition-world');inputs[2].meta.source.profileSHA256=profile
 end)
 RikUI=saved;check('physical path composition suite completes',ok,why)
end
