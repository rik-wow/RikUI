return function(check)
 local saved={}
 for _,name in ipairs({'RikUI','C_AddOns','InCombatLockdown','debugprofilestop','GetTime','RikUIQuestPathsCatalog','RikUIQuestPathsPayloads'})do saved[name]={rawget(_G,name)}end
 local ok,why=pcall(function()
  RikUI={};RikUI['Secret']={IsSecret=function()return false end}
  for _,name in ipairs({'schema','nav-geometry','nav-funnel','nav-follow','nav-search','region-codec','terrain-packs','regions','navmesh','paths','terrain'})do
   dofile('src/modules/questplanner/quest-'..name..'.lua')
  end
  local p=RikUI.QuestPlanner
  local identity={product='forever',build='1.60.1.69913',locale='enUS'}
  local clone=p.Schema.Clone
  local function hash(c)return string.rep(c,64)end
  local names={a='W0_Xp0_Zp0',b='W1_Xp0_Zp0'}
  local calls,combat={},false
  local function line(id)return table.concat({id,4,0,0,0,0,10,0,0,10,0,10,0,0,10},',')..'\n'end
  local function view(id,map,world,scale)
   return {assignmentID=id,uiMapID=map,worldMapID=world,projection={originX=scale,originY=scale,width=scale,height=scale},
    projectionSHA256=hash(id%2==0 and'd'or'e'),projectionSourceSHA256=hash('f'),
    validUIRectangle={0,0,1,1},validWorldRectangle={0,0,scale,scale},elevationBounds={-1000000,1000000}}
  end
  local views={[101]=view(101,1427,0,100),[102]=view(102,1430,1,100),[103]=view(103,1431,0,200),
   [104]=view(104,947,0,100),[105]=view(105,947,1,100)}
  local function catalog(namespace,world,map,revision,graph,source,ids)
   local out={format='rikui-region-catalog-v1',namespace=namespace,sourceSHA256=hash(source),ownedBounds={0,0,10,10},views={},
    revision=hash(revision),graphSHA256=hash(graph),sourceBytes=#line(1),
    meta={format='rikui-navmesh-v1',identity=identity,revision=hash(revision),uiMapID=map,worldMapID=world,
     source={sha256=hash(source),parser='fixture'},modeledMaxStep=.3,projection={originX=100,originY=100,width=100,height=100},
     bounds={0,0,10,10},counts={polygons=1,portals=0},exclusions={},blockers={}},
    regions={{id=1,addon='RikUIQuestTerrain_'..namespace..'_R001',polygons=1,portals=0,pages=1,bytes=#line(1),
     bounds={0,0,10,10},neighbors={},edgeCounts={}}}}
   for _,id in ipairs(ids)do out.views[id]=clone(views[id])end
   return out
  end
  local catalogs={
   [names.a]=catalog(names.a,0,1427,'a','b','c',{101,103,104}),
   [names.b]=catalog(names.b,1,1430,'d','e','f',{102,105})}
  local function reference(c)return {namespace=c.namespace,catalogAddon='RikUIQuestTerrain_'..c.namespace,
   catalogRevision=c.revision,graphSHA256=c.graphSHA256,sourceSHA256=c.sourceSHA256,ownedBounds=clone(c.ownedBounds)}end
  local function index(map,ids)
   local out={format='rikui-region-map-index-v1',revision=hash('a'),identity=identity,uiMapID=map,bindings={}}
   for _,id in ipairs(ids)do local v=clone(views[id]);v.packs={reference(catalogs[v.worldMapID==0 and names.a or names.b])};out.bindings[#out.bindings+1]=v end
   return out
  end
  local indexes={[1427]=index(1427,{101}),[1430]=index(1430,{102}),[1431]=index(1431,{103}),[947]=index(947,{104,105})}
  local function pathCatalog(c)return {format='rikui-path-backbone-v2',namespace=c.namespace,sourceSHA256=c.sourceSHA256,
   identity=identity,uiMapID=c.meta.uiMapID,worldMapID=c.meta.worldMapID,graphSHA256=c.graphSHA256,payloadID=c.revision,
   addonName='RikUIQuestPaths_'..c.namespace}
  end
  InCombatLockdown=function()return combat end;debugprofilestop=nil;GetTime=function()return 1 end
  RikUIQuestPathsCatalog=nil;RikUIQuestPathsPayloads={}
  C_AddOns={LoadAddOn=function(name)
   calls[name]=(calls[name]or 0)+1
   local map=tonumber(name:match('^RikUIQuestTerrainMap_M(%d+)$'))
   if map then if indexes[map]then assert(p.Regions.InstallIndex(indexes[map]));return true end return nil,'MISSING'end
   for namespace,c in pairs(catalogs)do
    if name=='RikUIQuestTerrain_'..namespace then
     assert(p.Regions.Install(c));assert(p.Paths.Install(pathCatalog(c)));return true
    elseif name==c.regions[1].addon then
     assert(p.Regions.RegisterPage(c.revision,1,1,line(1),namespace));return true
    elseif name=='RikUIQuestPaths_'..namespace then
     RikUIQuestPathsPayloads[c.revision]={format='rikui-path-backbone-v2'};return true
    end
   end
   return nil,'MISSING'
  end}
  local function position(map,x)return {mapID=map,x=x or.95,y=x or.95}end
  local function admit(map,world,x)
   local point=position(map,x);local why
   for _=1,16 do local ready,reason=p.Regions.Admit(identity,point,point,world);if ready then return p.Regions.Binding()end;why=reason end
   error('Admission failed: '..tostring(why))
  end
  local function packet(map,x)
   local point=position(map,x)
   for _=1,16 do local result=p.Regions.Prepare(identity,point,point);if result then return result end end
   error('Regional packet did not become ready')
  end
  check('multimap startup loads no geometry or catalogs',next(calls)==nil and p.TerrainPacks.Stats().catalogs==0)
  combat=true
  check('multimap index loading waits outside combat',select(2,p.Regions.Admit(identity,position(1427),position(1427),0))=='combat-loading-deferred'and next(calls)==nil)
  combat=false
  check('multimap first call loads only requested lightweight index',select(2,p.Regions.Admit(identity,position(1427),position(1427),0))=='loading'
   and calls.RikUIQuestTerrainMap_M1427==1 and not calls['RikUIQuestTerrain_'..names.a])
  local binding=admit(1427,0)
  check('multimap catalog admission preserves exact physical identity',binding.namespace==names.a and binding.worldMapID==0
   and binding.graphSHA256==catalogs[names.a].graphSHA256 and binding.sourceSHA256==catalogs[names.a].sourceSHA256)
  check('multimap catalog load does not load region pages',not calls[catalogs[names.a].regions[1].addon])
  local old=packet(1427)
  check('multimap regional packet binds projection and namespace',old.meta.uiMapID==1427 and old.meta.assignmentID==101 and old.meta.packNamespace==names.a)
  admit(1430,1)
  check('multimap switch invalidates old validation receipt',not p.Regions.Current(old.token)and not p.Regions.Accept(old.token))
  local second=packet(1430);assert(p.Regions.Accept(second.token))
  local bytes=p.Regions.Stats().sourceBytes
  admit(1427,0);local again=packet(1427);assert(p.Regions.Accept(again.token))
  check('multimap return reuses retained source pages without reexecuting addon',calls[catalogs[names.a].regions[1].addon]==1
   and p.Regions.Stats().sourceBytes==bytes and bytes==2*#line(1))
  local alias=admit(1431,0,.975);local aliasPacket=packet(1431,.975)
  check('multimap second UI view shares physical pages with exact projection',alias.namespace==names.a and alias.assignmentID==103
   and aliasPacket.meta.uiMapID==1431 and aliasPacket.meta.projection.width==200 and calls[catalogs[names.a].regions[1].addon]==1)
  assert(p.Regions.Accept(aliasPacket.token))
  for _=1,2 do p.Regions.Admit(identity,position(947),position(947))end
  check('multimap overlapping projection without world observation stays ambiguous',select(2,p.Regions.Admit(identity,position(947),position(947)))=='ambiguous-terrain-projection')
  check('multimap observed world chooses correct shared UI assignment',admit(947,1).namespace==names.b and p.Regions.Binding().assignmentID==105)
  check('multimap cross UI destination never creates a teleport edge',select(2,p.Regions.Admit(identity,position(1427),position(1430),0))=='cross-map-coverage-frontier')
  for _=1,8 do p.Regions.Admit(identity,position(9999),position(9999),0)end
  check('multimap missing catalog retries are bounded',calls.RikUIQuestTerrainMap_M9999==1)
  local bad=clone(indexes[1427]);bad.uiMapID=1500;bad.bindings[1].uiMapID=1500;bad.bindings[1].projectionSHA256=hash('0')
  assert(p.Regions.InstallIndex(bad))
  check('multimap index cannot substitute a different catalog projection',select(2,p.Regions.Admit(identity,position(1500),position(1500),0))=='incompatible-terrain-pack-source')
  bad=clone(indexes[1427]);bad.uiMapID=1501;bad.bindings[1].uiMapID=1501;bad.bindings[1].packs[1].catalogAddon='UnrelatedAddon'
  check('multimap rejects unrelated addon names',not p.Regions.InstallIndex(bad))
  bad=clone(indexes[1427]);bad.uiMapID=1502;bad.bindings[1].uiMapID=1502;bad.bindings[1].assignmentID=106
  local nextPack=clone(bad.bindings[1].packs[1]);nextPack.namespace='W0_Xp1_Zp0';nextPack.catalogAddon='RikUIQuestTerrain_'..nextPack.namespace;nextPack.ownedBounds={10,0,20,10}
  bad.bindings[1].packs[2]=nextPack;assert(p.Regions.InstallIndex(bad))
  check('multimap endpoints in separate packs expose a coverage frontier',select(2,p.Regions.Admit(identity,position(1502,.95),{mapID=1502,x=.85,y=.95},0))=='cross-pack-coverage-frontier'
   and not calls[nextPack.catalogAddon])

  local malformed=clone(catalogs[names.a]);malformed.namespace='W0_G0123456789abcdef';malformed.regions[1].addon='RikUIQuestTerrain_R001'
  check('multimap region namespace cannot collide with legacy page names',not p.Regions.Install(malformed))
  check('multimap pages reject a correct revision under another namespace',not p.Regions.RegisterPage(catalogs[names.a].revision,1,1,line(1),names.b))
  local cancelled,steps=0,0
  p.PathGraph={Begin=function(c)
   local n=0;return {Cancel=function()cancelled=cancelled+1 end,Step=function()n=n+1;steps=steps+1;if n==6 then return {namespace=c.namespace},nil,true end end}
  end}
  binding=admit(1427,0);p.Paths.Prepare(identity,1427,binding)
  p.Paths.Prepare(identity,1427,binding)
  local b=admit(1430,1);p.Paths.Prepare(identity,1430,b)
  check('multimap path graph admission cancels stale map work',cancelled==1)
  local result
  for _=1,8 do result=p.Paths.Prepare(identity,1430,b);if result then break end end
  check('multimap path publication uses the selected physical graph',result and result.namespace==names.b)
  b=clone(b);b.sourceSHA256=hash('0')
  check('multimap path binding rejects a different source even with matching graph',select(2,p.Paths.Prepare(identity,1430,b))=='incompatible-path-source')
  local samePhysical=admit(1431,0,.975)
  for _=1,8 do result=p.Paths.Prepare(identity,1431,samePhysical);if result then break end end
  check('multimap compact graph can attach through a second validated UI view',result and result.namespace==names.a)
  -- Real NavMesh/Terrain integration: display is dropped before spending an old-map slice.
  p.enabled=true
  local currentMap,currentWorld,currentX=1427,0,.95
  p.Context={Frame=function()local pos=position(currentMap,currentX);local scale=currentMap==1431 and 200 or 100
   return {position=pos,world={mapID=currentWorld,x=scale-pos.x*scale,z=scale-pos.y*scale,height=0,verticalStatus='observed-altitude'},speed=7}
  end}
  p.Controller={Get=function()return {status='observed',selected={questID=7,kind='objective',destination=position(currentMap,currentX)}}end}
  p.GetSnapshot=function()return {identity=identity}end
  for _=1,32 do p.Terrain.Step()end
  check('multimap terrain admits actual regional mesh',p.Terrain.Status().status=='modeled'or p.Terrain.Status().status=='ready')
  currentMap,currentWorld=9998,0;p.Terrain.Step()
  check('multimap terrain clears old guidance on missing new map',p.Terrain.Guidance()==nil and p.Terrain.Status().status=='coverage-frontier')
  currentMap,currentWorld=1427,0
  for _=1,32 do p.Terrain.Step()end
  check('multimap terrain recovers same physical map after an unavailable excursion',p.Terrain.Status().status=='modeled'or p.Terrain.Status().status=='ready')
  currentMap,currentWorld=1430,1
  for _=1,32 do p.Terrain.Step()end
  check('multimap terrain can recover on another installed map',p.Terrain.Status().status=='modeled'or p.Terrain.Status().status=='ready')
  check('multimap traversal does not reload already loaded map pages',calls[catalogs[names.a].regions[1].addon]==1 and calls[catalogs[names.b].regions[1].addon]==1)
 end)
 for name,row in pairs(saved)do rawset(_G,name,row[1])end
 check('multi-map physical pack admission suite completes',ok,why)
end
