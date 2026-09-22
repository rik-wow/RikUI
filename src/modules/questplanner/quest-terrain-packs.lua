-- Lazy physical-pack metadata. Loaded addon source is retained, never claimed evicted.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local packs={};planner.TerrainPacks=packs
local indexes,catalogs,failures={},{},{}
local busy=false
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
