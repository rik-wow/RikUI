-- Lazy physical-pack metadata. Loaded addon source is retained, never claimed evicted.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local packs={};planner.TerrainPacks=packs
local indexes,catalogs,failures={},{},{}
local busy=false
local seamPages,seamBytes,routeCache,routeExpansion={ },0,nil,1
local MAX_ROUTE_PACKS=8
local stats={indexes=0,catalogs=0,loads=0,metadataNodes=0,metadataBytes=0}
local MAX_INDEXES,MAX_CATALOGS,MAX_NODES,MAX_BYTES=32,64,131072,4194304
local function same(a,b)return a and b and a.product==b.product and a.build==b.build and a.locale==b.locale end
local function hash(v)return type(v)=='string'and#v==64 and v:match('^[a-f0-9]+$')end
local function number(v,a,b)return schema.Number(v,a,b)end
local function rect(v,minimum,maximum)
 if not schema.List(v,4)or#v~=4 then return false end
 for _,n in ipairs(v)do if not number(n,minimum,maximum)then return false end end
 return v[1]<v[3]and v[2]<v[4]
end
local function inside(v,x,z)return x>=v[1]and x<=v[3]and z>=v[2]and z<=v[4]end
local function equalProjection(a,b)
 if not a or not b then return false end
 for _,key in ipairs({'originX','originY','width','height'})do if a[key]~=b[key]then return false end end
 return true
end
local function equalRect(a,b)
 if not a or not b then return false end
 for i=1,4 do if a[i]~=b[i]then return false end end
 return true
end
local function projection(p)
 return schema.PlainTable(p)and number(p.originX,-100000,100000)and number(p.originY,-100000,100000)
  and number(p.width,1,100000)and number(p.height,1,100000)
end
function packs.Namespace(value,world)
 if type(value)~='string'or#value>64 then return false end
 local w,x,z=value:match('^W(%d+)_X([np]%d+)_Z([np]%d+)$')
 if not w then w=value:match('^W(%d+)_G%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$')end
 return w and schema.Integer(tonumber(w),0,100000)and(world==nil or tonumber(w)==world)or false
end
local function view(v,mapID)
 return schema.PlainTable(v)and schema.ID(v.assignmentID)and schema.Integer(v.worldMapID,0,100000)
  and(v.uiMapID==nil or v.uiMapID==mapID)and projection(v.projection)and hash(v.projectionSHA256)
  and hash(v.projectionSourceSHA256)and rect(v.validUIRectangle,0,1)and rect(v.validWorldRectangle,-100000,100000)
  and schema.List(v.elevationBounds,2)and#v.elevationBounds==2
  and number(v.elevationBounds[1],-1000000,1000000)and number(v.elevationBounds[2],-1000000,1000000)
  and v.elevationBounds[1]<=v.elevationBounds[2]
end
local function measure(value)
 local nodes,bytes=0,0
 local function walk(v)
  nodes=nodes+1
  if type(v)=='string'then bytes=bytes+#v
  elseif type(v)=='table'then for k,item in pairs(v)do walk(k);walk(item)end
  else bytes=bytes+8 end
 end
 walk(value);return nodes,bytes
end
local function reserve(value)
 local nodes,bytes=measure(value)
 if stats.metadataNodes+nodes>MAX_NODES or stats.metadataBytes+bytes>MAX_BYTES then return nil,'terrain-metadata-cache-limit'end
 stats.metadataNodes=stats.metadataNodes+nodes;stats.metadataBytes=stats.metadataBytes+bytes;return true
end
function packs.InstallIndex(raw)
 local value=schema.CopyLimited(raw,32768,1048576,12)
 if not value or value.format~='rikui-region-map-index-v1'or not schema.Identity(value.identity)
  or not schema.ID(value.uiMapID)or not hash(value.revision)or not schema.List(value.bindings,64)or#value.bindings==0 then return nil,'invalid-terrain-map-index'end
 local seen={}
 for _,binding in ipairs(value.bindings)do
  if not view(binding,value.uiMapID)or seen[binding.assignmentID]or not schema.List(binding.packs,512)then return nil,'invalid-terrain-projection-binding'end
  seen[binding.assignmentID]=true;local names={}
  for _,pack in ipairs(binding.packs)do
   if not schema.PlainTable(pack)or not packs.Namespace(pack.namespace,binding.worldMapID)or names[pack.namespace]
    or pack.catalogAddon~='RikUIQuestTerrain_'..pack.namespace or not hash(pack.catalogRevision)
    or not hash(pack.graphSHA256)or not hash(pack.sourceSHA256)or not rect(pack.ownedBounds,-100000,100000)then return nil,'invalid-terrain-pack-reference'end
   names[pack.namespace]=true
  end
  table.sort(binding.packs,function(a,b)return a.namespace<b.namespace end)
  if binding.connections~=nil then
   if not schema.List(binding.connections,1024)then return nil,'invalid-terrain-connections'end
   local seenConnections={}
   for _,c in ipairs(binding.connections)do
    if not schema.PlainTable(c)or not names[c.fromNamespace]or not names[c.toNamespace]
     or c.fromNamespace==c.toNamespace or c.worldMapID~=binding.worldMapID or not hash(c.seamRevision)
     or c.seamAddon~='RikUIQuestSeams_S'..c.seamRevision:sub(1,16)
     or not schema.Integer(c.rows,1,128)or not schema.Integer(c.bytes,1,32768)
     or seenConnections[c.seamRevision]then return nil,'invalid-terrain-connection'end
    seenConnections[c.seamRevision]=true
   end
   table.sort(binding.connections,function(a,b)return a.seamRevision<b.seamRevision end)
  end
 end
 local prior=indexes[value.uiMapID]
 if prior then return prior.revision==value.revision and same(prior.identity,value.identity)or nil,'terrain-map-index-already-loaded'end
 if stats.indexes>=MAX_INDEXES then return nil,'terrain-index-cache-limit'end
 local ok,why=reserve(value);if not ok then return nil,why end
 indexes[value.uiMapID]=value;stats.indexes=stats.indexes+1;return true
end
function packs.ValidateCatalog(value)
 if not packs.Namespace(value.namespace,value.meta.worldMapID)or not hash(value.sourceSHA256)
  or not rect(value.ownedBounds,-100000,100000)or not schema.PlainTable(value.views)then return nil,'invalid-terrain-pack-identity'end
 local count=0
 for id,v in pairs(value.views)do
  count=count+1
  if count>64 or not schema.ID(id)or not schema.PlainTable(v)or not schema.ID(v.uiMapID)or not view(v,v.uiMapID)
   or id~=v.assignmentID or v.worldMapID~=value.meta.worldMapID then return nil,'invalid-terrain-pack-projection'end
 end
 if count==0 then return nil,'terrain-pack-projection-missing'end
 return true
end
function packs.Register(value)
 local old=catalogs[value.namespace]
 if old then
  if old.revision==value.revision and old.graphSHA256==value.graphSHA256 and old.sourceSHA256==value.sourceSHA256
   and same(old.meta.identity,value.meta.identity)then return true end
  return nil,'terrain-pack-already-loaded'
 end
 if stats.catalogs>=MAX_CATALOGS then return nil,'terrain-catalog-cache-limit'end
 local ok,why=reserve(value);if not ok then return nil,why end
 catalogs[value.namespace]=value;stats.catalogs=stats.catalogs+1;return true
end
function packs.IsLoading()return busy end
function packs.BeginLoad()if busy then return false end;busy=true;return true end
function packs.EndLoad()busy=false end
function packs.HasIndex(mapID)return indexes[mapID]~=nil end
function packs.Stats()return schema.Clone(stats)end
local function load(name,check)
 if busy then return nil,'loading'end
 if failures[name]then return nil,failures[name]end
 if type(InCombatLockdown)=='function'and InCombatLockdown()then return nil,'combat-loading-deferred'end
 local fn=type(C_AddOns)=='table'and C_AddOns.LoadAddOn
 if type(fn)~='function'then return nil,'terrain-loader-unavailable'end
 busy=true;local ok,loaded=pcall(fn,name);busy=false;stats.loads=stats.loads+1
 if not ok or not loaded or not check()then failures[name]='terrain-pack-unavailable';return nil,failures[name]end
 return nil,'loading'
end
local function matching(index,position,worldMapID)
 local found
 for _,v in ipairs(index.bindings)do
  if(worldMapID==nil or v.worldMapID==worldMapID)and inside(v.validUIRectangle,position.x,position.y)then
   local p=v.projection;local x,z=p.originY-position.x*p.width,p.originX-position.y*p.height
   if inside(v.validWorldRectangle,x,z)then
    if found then return nil,'ambiguous-terrain-projection'end
    found=v
   end
  end
 end
 return found,found and nil or'outside-projection-coverage'
end
local function agrees(value,index,binding,reference)
 local v=value.views[binding.assignmentID]
 return same(value.meta.identity,index.identity)and value.meta.worldMapID==binding.worldMapID
  and value.revision==reference.catalogRevision and value.graphSHA256==reference.graphSHA256
  and value.sourceSHA256==reference.sourceSHA256 and equalRect(value.ownedBounds,reference.ownedBounds)
  and v and v.uiMapID==index.uiMapID and v.worldMapID==binding.worldMapID
  and v.projectionSHA256==binding.projectionSHA256 and v.projectionSourceSHA256==binding.projectionSourceSHA256
  and equalProjection(v.projection,binding.projection)and equalRect(v.validUIRectangle,binding.validUIRectangle)
  and equalRect(v.validWorldRectangle,binding.validWorldRectangle)
  and v.elevationBounds[1]==binding.elevationBounds[1]and v.elevationBounds[2]==binding.elevationBounds[2]
end
function packs.Select(identity,position,destination,worldMapID)
 if busy then return nil,'loading'end
 if not schema.Identity(identity)or not position or not schema.ID(position.mapID)
  or not number(position.x,0,1)or not number(position.y,0,1)then return nil,'unavailable-position'end
 if not destination or destination.mapID~=position.mapID or not number(destination.x,0,1)or not number(destination.y,0,1)then return nil,'cross-map-coverage-frontier'end
 local index=indexes[position.mapID]
 if not index then return load('RikUIQuestTerrainMap_M'..position.mapID,function()return indexes[position.mapID]~=nil end)end
 if not same(index.identity,identity)then return nil,'incompatible-region-identity'end
 local binding,why=matching(index,position,worldMapID);if not binding then return nil,why end
 local goal,problem=matching(index,destination,worldMapID)
 if not goal then return nil,problem end
 if goal.assignmentID~=binding.assignmentID then return nil,'cross-assignment-coverage-frontier'end
 local p=binding.projection;local sx,sz=p.originY-position.x*p.width,p.originX-position.y*p.height
 local gx,gz=p.originY-destination.x*p.width,p.originX-destination.y*p.height
 local reference;local startCovered,goalCovered=false,false
 for _,pack in ipairs(binding.packs)do
  local a,b=inside(pack.ownedBounds,sx,sz),inside(pack.ownedBounds,gx,gz)
  startCovered=startCovered or a;goalCovered=goalCovered or b
  if a and b and not reference then reference=pack end
 end
 if not reference then return nil,startCovered and goalCovered and'cross-pack-coverage-frontier'or'outside-pack-coverage'end
 local value=catalogs[reference.namespace]
 if not value then return load(reference.catalogAddon,function()return catalogs[reference.namespace]~=nil end)end
 if not agrees(value,index,binding,reference)then return nil,'incompatible-terrain-pack-source'end
 return {catalog=value,namespace=value.namespace,binding=binding,indexRevision=index.revision,
  key=value.namespace..':'..value.revision..':'..binding.assignmentID..':'..binding.projectionSHA256},'ready'
end

-- Exact directed seam metadata is loaded only for the selected physical corridor.
function packs.RegisterSeams(revision,raw)
 if not hash(revision)or not schema.List(raw,128)or#raw<1 then return nil,'invalid-seam-page'end
 local value=schema.CopyLimited(raw,32768,32768,12)
 if not value then return nil,'invalid-seam-page'end
 if seamPages[revision]then return nil,'duplicate-seam-page'end
 local _,bytes=measure(value)
 if seamBytes+bytes>4194304 then return nil,'seam-cache-limit'end
 local seen={}
 for _,r in ipairs(value)do
  if not schema.PlainTable(r)or not hash(r.id)or not hash(r.proofSHA256)or seen[r.id]
   or not schema.Integer(r.worldMapID,0,100000)or not packs.Namespace(r.fromNamespace,r.worldMapID)
   or not packs.Namespace(r.toNamespace,r.worldMapID)or r.fromNamespace==r.toNamespace
   or not schema.ID(r.fromID)or not schema.ID(r.toID)or not schema.Text(r.fromKey)or not schema.Text(r.toKey)
   or not schema.Number(r.meters,0,1000000)or not schema.Number(r.authoredCenterCost,0,1000000)then return nil,'invalid-seam-record'end
  seen[r.id]=true
  for _,key in ipairs({'left','right','midpoint'})do
   local point=r[key]
   if not schema.List(point,3)or#point~=3 then return nil,'invalid-seam-point'end
   for _,v in ipairs(point)do if not number(v,-100000,100000)then return nil,'invalid-seam-point'end end
  end
 end
 seamPages[revision]=value;seamBytes=seamBytes+bytes;return true
end
function packs.PrepareSeams(connections)
 if not schema.List(connections,1024)then return nil,'invalid-seam-connections'end
 local total=0
 for _,ref in ipairs(connections)do total=total+ref.rows;if total>4096 then return nil,'seam-working-set-limit'end end
 for _,ref in ipairs(connections)do
  if not seamPages[ref.seamRevision]then
   return load(ref.seamAddon,function()return seamPages[ref.seamRevision]~=nil end)
  end
 end
 local rows,seen={},{}
 for _,ref in ipairs(connections)do
  local page=seamPages[ref.seamRevision]
  if #page~=ref.rows then return nil,'seam-page-count-mismatch'end
  for _,row in ipairs(page)do
   if row.worldMapID~=ref.worldMapID or row.fromNamespace~=ref.fromNamespace or row.toNamespace~=ref.toNamespace
    or seen[row.id]then return nil,'seam-page-source-mismatch'end
   seen[row.id]=true;rows[#rows+1]=row
  end
 end
 return rows,'ready'
end
local function projectionPoint(binding,position)
 local p=binding.projection;return p.originY-position.x*p.width,p.originX-position.y*p.height
end
local function traverse(seeds,adj)
 local distance,parent,queue={}, {},{}
 for _,id in ipairs(seeds)do distance[id]=0;parent[id]=false;queue[#queue+1]=id end
 local at=1
 while at<=#queue do
  local id=queue[at];at=at+1
  for _,to in ipairs(adj[id]or{})do
   if distance[to]==nil then distance[to]=distance[id]+1;parent[to]=id;queue[#queue+1]=to end
  end
 end
 return distance,parent
end
local function corridor(binding,sx,sz,gx,gz)
 local references,starts,goals,outgoing,incoming={}, {},{},{},{}
 for _,p in ipairs(binding.packs)do
  references[p.namespace]=p
  if inside(p.ownedBounds,sx,sz)then starts[#starts+1]=p.namespace end
  if inside(p.ownedBounds,gx,gz)then goals[#goals+1]=p.namespace end
 end
 if#starts==0 or#goals==0 then return nil,'outside-pack-coverage'end
 for _,c in ipairs(binding.connections or{})do
  local a=outgoing[c.fromNamespace]or{};outgoing[c.fromNamespace]=a;a[#a+1]=c.toNamespace
  local b=incoming[c.toNamespace]or{};incoming[c.toNamespace]=b;b[#b+1]=c.fromNamespace
 end
 for _,map in ipairs({outgoing,incoming})do for _,list in pairs(map)do table.sort(list)end end
 local forward,parent=traverse(starts,outgoing);local backward=traverse(goals,incoming)
 local last
 for _,id in ipairs(goals)do if forward[id]and(not last or forward[id]<forward[last])then last=id end end
 if not last then return nil,'cross-pack-coverage-frontier'end
 local selected,names={},{}
 while last do selected[last]=true;names[#names+1]=last;last=parent[last]end
 if#names>MAX_ROUTE_PACKS then return nil,'pack-corridor-limit'end
 local extras={}
 for id in pairs(references)do
  if not selected[id]and forward[id]and backward[id]then extras[#extras+1]={id=id,cost=forward[id]+backward[id]}end
 end
 table.sort(extras,function(a,b)return a.cost<b.cost or a.cost==b.cost and a.id<b.id end)
 local available=#names+#extras;local capacity=math.max(#names,math.min(MAX_ROUTE_PACKS,2+routeExpansion*2))
 for _,row in ipairs(extras)do if#names>=capacity then break end;selected[row.id]=true;names[#names+1]=row.id end
 table.sort(names)
 local refs,connections={},{}
 for _,id in ipairs(names)do refs[#refs+1]=references[id]end
 for _,c in ipairs(binding.connections or{})do if selected[c.fromNamespace]and selected[c.toNamespace]then connections[#connections+1]=c end end
 return {references=refs,connections=connections,set=selected,canExpand=available>#names and capacity<MAX_ROUTE_PACKS}
end
function packs.ExpandRoute()
 if not routeCache or not routeCache.selection.canExpand or routeExpansion>=3 then return false end
 routeExpansion=routeExpansion+1;routeCache=nil;return true
end
function packs.RetryRoute()routeCache=nil;routeExpansion=1 end
function packs.SelectRoute(identity,position,destination,worldMapID)
 -- Existing single-pack admission preserves the legacy path and returns explicit failures.
 local one,why=packs.Select(identity,position,destination,worldMapID)
 if one then
  if not routeCache or routeCache.single or routeCache.mapID~=position.mapID then return one,why end
 elseif why~='cross-pack-coverage-frontier'then return nil,why end
 local index=indexes[position.mapID]
 local binding,problem=matching(index,position,worldMapID);if not binding then return nil,problem end
 local goal=matching(index,destination,worldMapID)
 if not goal or binding.assignmentID~=goal.assignmentID then return nil,'cross-assignment-coverage-frontier'end
 local sx,sz=projectionPoint(binding,position);local gx,gz=projectionPoint(binding,destination)
 local key=index.revision..':'..binding.assignmentID..':'..string.format('%.17g:%.17g',destination.x,destination.y)
 local selection
 if routeCache and routeCache.key==key then
  for _,ref in ipairs(routeCache.selection.references)do if inside(ref.ownedBounds,sx,sz)then selection=routeCache.selection;break end end
 end
 if not selection then
  selection,problem=corridor(binding,sx,sz,gx,gz);if not selection then return nil,problem end
  routeCache={key=key,mapID=position.mapID,selection=selection}
 end
 local admitted={};local names={}
 for _,ref in ipairs(selection.references)do
  local value=catalogs[ref.namespace]
  if not value then return load(ref.catalogAddon,function()return catalogs[ref.namespace]~=nil end)end
  if not agrees(value,index,binding,ref)then return nil,'incompatible-terrain-pack-source'end
  admitted[#admitted+1]={catalog=value,namespace=ref.namespace};names[#names+1]=ref.namespace..':'..value.revision
 end
 if#admitted==1 then return {catalog=admitted[1].catalog,namespace=admitted[1].namespace,binding=binding,indexRevision=index.revision,
  key=admitted[1].namespace..':'..admitted[1].catalog.revision..':'..binding.assignmentID..':'..binding.projectionSHA256},'ready'end
 return {packs=admitted,connections=selection.connections,binding=binding,indexRevision=index.revision,
  key=key..':'..table.concat(names,':')},'ready'
end
