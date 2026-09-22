-- Lazy source pages and a bounded window of exact directed regional topology.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local regions={}
planner.Regions=regions
local catalog,pages,registeredBytes,job,activeKey,activeSet,failed=nil,{},0,nil,nil,nil,nil
local serial,expansion=0,1
local stores,currentStore,admissionKey,activeView={},nil,nil,nil
local retainedBytes=0
local composedBinding,peekBinding
local MAX_RETAINED_SOURCE=134217728
local stats={loads=0,maxLoadMS=0,sourceBytes=0,windows=0}
local function same(a,b) return a and b and a.product==b.product and a.build==b.build and a.locale==b.locale end
local function hash(v) return type(v)=="string" and #v==64 and v:match("^[a-f0-9]+$") end
local function rectangle(v)
    if not schema.List(v,4) or #v~=4 then return false end
    for _,n in ipairs(v) do if not schema.Number(n,-100000,100000) then return false end end
    return v[1]<=v[3] and v[2]<=v[4]
end
local function activate(store,key,binding)
    if currentStore==store and admissionKey==key then return true end
    local value={};for k,v in pairs(store.catalog)do value[k]=v end
    value.meta=schema.Clone(store.catalog.meta)
    if binding then
        value.meta.uiMapID=binding.uiMapID or store.mapID
        value.meta.projection=schema.Clone(binding.projection)
        value.meta.projectionSHA256=binding.projectionSHA256
        value.meta.projectionSourceSHA256=binding.projectionSourceSHA256
        value.meta.assignmentID=binding.assignmentID
    end
    catalog,pages,registeredBytes=value,store.pages,store.registeredBytes
    currentStore,admissionKey,activeView=store,key,binding
    composedBinding,peekBinding=nil,nil
    job,activeKey,activeSet,failed=nil,nil,nil,nil;serial=serial+1;expansion=1
    return true
end
function regions.InstallIndex(raw)
    if not planner.TerrainPacks then return nil,"terrain pack manager unavailable"end
    return planner.TerrainPacks.InstallIndex(raw)
end
local function activateComposition(selected,position)
    if admissionKey==selected.key and currentStore then return true end
    local first=selected.packs[1].catalog
    local meta=schema.Clone(first.meta);local rows,offsets={},{}
    meta.uiMapID=position.mapID;meta.projection=schema.Clone(selected.binding.projection)
    meta.projectionSHA256=selected.binding.projectionSHA256;meta.assignmentID=selected.binding.assignmentID
    meta.source={sha256=selected.indexRevision,parser="rikui-composed-region-index-v1",profileSHA256=first.meta.source.profileSHA256}
    meta.composedCandidate=true;meta.sources={};meta.exclusions={};meta.blockers={};meta.bounds={100000,100000,-100000,-100000}
    local binding={identity=schema.Clone(meta.identity),mapID=position.mapID,worldMapID=meta.worldMapID,
        packKey=selected.key,projectionSHA256=selected.binding.projectionSHA256,assignmentID=selected.binding.assignmentID,
        maxStep=meta.modeledMaxStep,packs={},connections=schema.Clone(selected.connections)}
    local total=0
    for slot,pack in ipairs(selected.packs)do
        local c=pack.catalog
        if not same(c.meta.identity,meta.identity)or c.meta.worldMapID~=meta.worldMapID
            or c.meta.modeledMaxStep~=meta.modeledMaxStep or c.meta.source.profileSHA256~=meta.source.profileSHA256 then return nil,"composed-model-mismatch"end
        offsets[pack.namespace]=#rows;total=total+c.sourceBytes
        meta.sources[#meta.sources+1]={namespace=pack.namespace,sourceSHA256=c.sourceSHA256,catalogRevision=c.revision,graphSHA256=c.graphSHA256}
        for _,key in ipairs({"exclusions","blockers"})do
            for _,value in ipairs(c.meta[key]or{})do if#meta[key]>=64 then return nil,"composed-coverage-limit"end;meta[key][#meta[key]+1]=schema.Clone(value)end
        end
        local box=c.ownedBounds
        meta.bounds[1]=math.min(meta.bounds[1],box[1]);meta.bounds[2]=math.min(meta.bounds[2],box[2])
        meta.bounds[3]=math.max(meta.bounds[3],box[3]);meta.bounds[4]=math.max(meta.bounds[4],box[4])
        binding.packs[#binding.packs+1]={identity=schema.Clone(c.meta.identity),mapID=position.mapID,worldMapID=c.meta.worldMapID,
            graphSHA256=c.graphSHA256,namespace=c.namespace,sourceSHA256=c.sourceSHA256,meta=schema.Clone(c.meta),
            projectionSHA256=selected.binding.projectionSHA256,packKey=c.namespace..":"..c.revision..":"..selected.binding.projectionSHA256}
        for _,r in ipairs(c.regions)do
            local row=schema.Clone(r);row.id=#rows+1;row.physicalID=r.id;row.namespace=pack.namespace;row.slot=slot
            for i,id in ipairs(row.neighbors)do row.neighbors[i]=offsets[pack.namespace]+id end
            local counts={};for id,n in pairs(row.edgeCounts)do counts[offsets[pack.namespace]+id]=n end;row.edgeCounts=counts
            rows[#rows+1]=row
        end
    end
    local value={composed=true,format="rikui-region-catalog-v1",revision=selected.indexRevision,meta=meta,regions=rows,sourceBytes=total}
    local store={catalog=value,pages={},registeredBytes=0}
    activate(store,selected.key);composedBinding=binding;return true
end
local function regionPages(row)
    if row.namespace then local store=stores[row.namespace];return store and store.pages[row.physicalID]end
    return pages[row.id]
end
local function regionStream(selection,meta)
    if not catalog.composed then return planner.RegionCodec.Stream(selection.ids,pages,selection.set,meta.identity,#catalog.regions)end
    local streams={}
    for slot,pack in ipairs(composedBinding.packs)do
        local store=stores[pack.namespace];local ids,set={},{}
        for _,id in ipairs(selection.ids)do local row=catalog.regions[id];if row.namespace==pack.namespace then ids[#ids+1]=row.physicalID;set[row.physicalID]=true end end
        if#ids>0 then streams[#streams+1]={offset=(slot-1)*16777216,next=planner.RegionCodec.Stream(ids,store.pages,set,meta.identity,#store.catalog.regions)}end
    end
    local at=1
    return function()
        while streams[at]do
            local entry=streams[at];local shard,why=entry.next()
            if shard then
                for _,polygon in ipairs(shard.polygons)do
                    polygon.id=polygon.id+entry.offset
                    for _,portal in ipairs(polygon.portals)do portal.to=portal.to+entry.offset end
                end
                return shard
            end
            if why then return nil,why end
            at=at+1
        end
    end
end
function regions.Admit(identity,position,destination,worldMapID)
    local manager=planner.TerrainPacks
    if manager and manager.IsLoading()then return nil,"loading"end
    if not manager then return catalog~=nil,catalog and "ready"or"unavailable"end
    local legacy=stores.legacy
    if legacy and position and position.mapID==legacy.catalog.meta.uiMapID
        and same(identity,legacy.catalog.meta.identity)and not manager.HasIndex(position.mapID)then
        return activate(legacy,"legacy:"..legacy.catalog.revision),"ready"
    end
    local selected,why=(manager.SelectRoute or manager.Select)(identity,position,destination,worldMapID)
    if not selected then regions.Suspend();activeKey,activeSet,admissionKey=nil,nil,nil;return nil,why end
    if selected.packs then return activateComposition(selected,position)end
    local store=stores[selected.namespace]
    if not store then return nil,"terrain pack registration missing"end
    local binding=schema.Clone(selected.binding);binding.packs=nil;binding.uiMapID=position.mapID
    store.mapID=position.mapID
    return activate(store,selected.key,binding),"ready"
end
function regions.Install(raw)
    local value=schema.CopyLimited(raw,32768,1048576,12)
    if not value or value.format~="rikui-region-catalog-v1" or not hash(value.revision)
        or not hash(value.graphSHA256) or not schema.PlainTable(value.meta) or not schema.Identity(value.meta.identity)
        or not schema.List(value.regions,256) or #value.regions==0
        or not schema.Integer(value.sourceBytes,1,134217728) then return nil,"invalid region catalog" end
    local checked,problem=planner.NavMesh.ValidateMetadata(value.meta)
    if not checked then return nil,problem end
    value.meta=checked
    local namespace=value.namespace
    if namespace~=nil then
        if not planner.TerrainPacks then return nil,"terrain pack manager unavailable"end
        local valid,why=planner.TerrainPacks.ValidateCatalog(value);if not valid then return nil,why end
    end
    local prefix=namespace and("RikUIQuestTerrain_"..namespace)or"RikUIQuestTerrain"
    local total=0
    for i,r in ipairs(value.regions) do
        if r.id~=i or r.addon~=prefix..string.format("_R%03d",i)
            or not rectangle(r.bounds) or not schema.Integer(r.polygons,1,8192)
            or not schema.Integer(r.portals,0,32768) or not schema.Integer(r.pages,1,128)
            or not schema.Integer(r.bytes,1,4194304) or not schema.List(r.neighbors,32)
            or not schema.PlainTable(r.edgeCounts) then return nil,"invalid region descriptor" end
        local count,seen=0,{}
        for target,n in pairs(r.edgeCounts) do
            if not schema.Integer(target,1,#value.regions) or not schema.Integer(n,1,32768) then return nil,"invalid region edge count" end
            count=count+n
        end
        for _,id in ipairs(r.neighbors) do
            if not schema.Integer(id,1,#value.regions) or id==i or seen[id] or not r.edgeCounts[id] then return nil,"invalid region neighbor" end
            seen[id]=true
        end
        for target in pairs(r.edgeCounts) do if target~=i and not seen[target] then return nil,"missing directed region neighbor" end end
        if count~=r.portals then return nil,"region portal count mismatch" end
        table.sort(r.neighbors)
        total=total+r.bytes
    end
    if total~=value.sourceBytes then return nil,"regional source byte count" end
    local key=namespace or"legacy";local store=stores[key]
    if store then
        if store.catalog.revision~=value.revision or store.catalog.graphSHA256~=value.graphSHA256
            or not same(store.catalog.meta.identity,value.meta.identity)then return nil,"region namespace already loaded"end
        if not namespace then activate(store,"legacy:"..value.revision)end
        return true
    end
    if namespace then
        local ok,why=planner.TerrainPacks.Register(value);if not ok then return nil,why end
    end
    store={catalog=value,pages={},registeredBytes=0};stores[key]=store
    if not namespace then activate(store,"legacy:"..value.revision)end
    return true
end
function regions.RegisterPage(revision,id,index,payload,namespace)
    local store=stores[namespace or"legacy"]
    local owner=store and store.catalog
    local r=owner and owner.regions[id]
    if not r or revision~=owner.revision or not schema.Integer(index,1,r.pages)
        or type(payload)~="string" or #payload<1 or #payload>32768
        or payload:sub(-1)~="\n" or payload:find("[^%d%,%.%-%+eE\n]") then return nil,"invalid regional source page" end
    local list=store.pages[id] or {bytes=0,count=0}
    if list[index] then return nil,"duplicate regional page" end
    if list.bytes+#payload>r.bytes or store.registeredBytes+#payload>owner.sourceBytes
        or retainedBytes+#payload>MAX_RETAINED_SOURCE then return nil,"regional source cache limit"end
    store.pages[id]=list;list[index]=payload;list.bytes=list.bytes+#payload;list.count=list.count+1
    store.registeredBytes=store.registeredBytes+#payload;retainedBytes=retainedBytes+#payload
    if store==currentStore then registeredBytes=store.registeredBytes end
    stats.sourceBytes=retainedBytes
    return true
end
local function project(position)
    local m=catalog.meta;local p=m.projection
    if not position or position.mapID~=m.uiMapID or not schema.Number(position.x,0,1) or not schema.Number(position.y,0,1) then return nil end
    return {x=p.originY-position.x*p.width,z=p.originX-position.y*p.height}
end
local function contains(r,p)
    return p and p.x>=r.bounds[1]-.002 and p.x<=r.bounds[3]+.002 and p.z>=r.bounds[2]-.002 and p.z<=r.bounds[4]+.002
end
function regions.Select(start,goal,localOnly)
    if not catalog then return nil,"unavailable" end
    local starts,goals,goalSet={},{},{}
    for _,r in ipairs(catalog.regions) do
        if contains(r,start) then starts[#starts+1]=r.id end
        if contains(r,goal) then goals[#goals+1]=r.id;goalSet[r.id]=true end
    end
    if #starts==0 or #goals==0 then return nil,"outside-coverage" end
    local path={}
    if not localOnly then
    local queue,parent,head={},{},1
    for _,id in ipairs(starts) do queue[#queue+1]=id;parent[id]=false end
    local found
    while head<=#queue do
        local id=queue[head];head=head+1
        if goalSet[id] then found=id;break end
        for _,target in ipairs(catalog.regions[id].neighbors) do
            if parent[target]==nil then parent[target]=id;queue[#queue+1]=target end
        end
    end
    if not found then return nil,"no-catalog-path" end
    while found do table.insert(path,1,found);found=parent[found] end
    end
    local ids,set,pc,ec={},{},0,0
    local function add(id)
        if set[id] then return true end
        local r=catalog.regions[id]
        if #ids>=32 or pc+r.polygons>65536 or ec+r.portals>131072 then return false end
        ids[#ids+1]=id;set[id]=true;pc=pc+r.polygons;ec=ec+r.portals;return true
    end
    for _,list in ipairs({starts,goals,path}) do
        for _,id in ipairs(list) do if not add(id) then return nil,"region-working-set-limit" end end
    end
    -- Include a bounded alternative neighborhood; no SCC or region is a zero-cost shortcut.
    for _=1,localOnly and 0 or expansion do
        local seeds={};for i,id in ipairs(ids) do seeds[i]=id end
        for _,id in ipairs(seeds) do for _,nextID in ipairs(catalog.regions[id].neighbors) do add(nextID) end end
    end
    table.sort(ids)
    local edges=0
    for _,id in ipairs(ids) do for target,n in pairs(catalog.regions[id].edgeCounts) do if set[target] then edges=edges+n end end end
    return {ids=ids,set=set,polygons=pc,portals=edges,topologyOnly=true,optimal=false,localOnly=localOnly==true}
end
function regions.Retry()
    job,activeKey,activeSet,failed=nil,nil,nil,nil;serial=serial+1;expansion=1
end
function regions.Suspend() job=nil;serial=serial+1 end
function regions.Current(token) return job and job["token"]==token end
function regions.Accept(token,problem)
    if not regions.Current(token) then return false end
    if problem then
        failed={key=job.key,reason="invalid-regional-data: "..tostring(problem),permanent=true}
    else activeKey,activeSet=job.key,job.selection.set end
    job=nil
    return true
end
function regions.Expand()
    if not catalog or expansion>=3 then return false end
    if catalog.composed then
        if not planner.TerrainPacks.ExpandRoute()then return false end
        admissionKey=nil
    end
    expansion=expansion+1;job,activeKey,activeSet=nil,nil,nil;serial=serial+1
    return true
end
function regions.Enabled() return catalog~=nil end
function regions.PeekBinding()
    if composedBinding then return composedBinding end
    if not peekBinding and catalog then peekBinding={identity=schema.Clone(catalog.meta.identity),mapID=catalog.meta.uiMapID,worldMapID=catalog.meta.worldMapID,
        graphSHA256=catalog.graphSHA256,namespace=catalog.namespace,sourceSHA256=catalog.sourceSHA256,
        ownedBounds=schema.Clone(catalog.ownedBounds),projectionSHA256=activeView and activeView.projectionSHA256,
        assignmentID=activeView and activeView.assignmentID,packKey=admissionKey}end
    return peekBinding
end
function regions.Binding()return schema.Clone(regions.PeekBinding())end
function regions.Stats()
    local value=schema.Clone(stats);value.packs=planner.TerrainPacks and planner.TerrainPacks.Stats()
    value.activePack=currentStore and(currentStore.catalog.namespace or"legacy");return value
end
local function covered(point)
    local found=false
    for _,region in ipairs(catalog.regions) do
        if contains(region,point) then
            found=true
            if not activeSet[region.id] then return false end
        end
    end
    return found
end
-- Called with the shared player snapshot; one synchronous addon load at most per call.
function regions.Prepare(identity,position,destination,localOnly)
    if not catalog then return end
    if not same(identity,catalog.meta.identity) then regions.Suspend();return nil,"incompatible-region-identity" end
    local start,goal=project(position),project(destination)
    if not start or not goal then regions.Suspend();return nil,"unavailable-position" end
    local key=(admissionKey or catalog.revision)..":"..(localOnly and "local:" or "regional:")..string.format("%d:%.17g:%.17g",destination.mapID,destination.x,destination.y)
    if activeKey==key then
        for id in pairs(activeSet) do if contains(catalog.regions[id],start) then return nil,"ready" end end
    end
    if activeSet and not job and activeKey and activeKey:find(localOnly and ':local:' or ':regional:',1,true) and covered(start) and covered(goal) then
        activeKey=key;return nil,"ready"
    end
    local origin={}
    for _,r in ipairs(catalog.regions) do if contains(r,start) then origin[#origin+1]=r.id end end
    local originKey=table.concat(origin,",")
    if failed and failed.key==key and (failed.permanent or failed.origin==originKey) then return nil,failed.reason end
    if job and job.key==key then
        local covered=false
        for _,id in ipairs(origin) do if job.selection.set[id] then covered=true end end
        if not covered then job=nil end
    end
    if not job or job.key~=key then
        local selection,reason=regions.Select(start,goal,localOnly)
        if not selection then failed={key=key,reason=reason,origin=originKey};return nil,reason end
        serial=serial+1;job={key=key,selection=selection,index=1,["token"]=serial}
    end
    local current=job
    if planner.TerrainPacks and planner.TerrainPacks.IsLoading()then return nil,"loading"end
    if current.loading then return nil,"loading" end
    if current.validating then return nil,"validating" end
    local id=current.selection.ids[current.index]
    if id then
        local r=catalog.regions[id];local list=regionPages(r)
        if not list or list.count~=r.pages or list.bytes~=r.bytes then
            if type(InCombatLockdown)=="function" and InCombatLockdown() then return nil,"combat-loading-deferred" end
            local load=type(C_AddOns)=="table" and C_AddOns.LoadAddOn
            if type(load)~="function" then failed={key=key,reason="regional-loader-unavailable",permanent=true};return nil,failed.reason end
            if retainedBytes+r.bytes-(list and list.bytes or 0)>MAX_RETAINED_SOURCE then
                failed={key=key,reason="regional source cache limit",permanent=true};return nil,failed.reason
            end
            local before=type(debugprofilestop)=="function" and debugprofilestop()
            if planner.TerrainPacks and not planner.TerrainPacks.BeginLoad()then return nil,"loading"end
            current.loading=true
            local ok,loaded,reason=pcall(load,r.addon)
            current.loading=nil
            if planner.TerrainPacks then planner.TerrainPacks.EndLoad()end
            if job~=current then return nil,"loading" end
            if before then stats.maxLoadMS=math.max(stats.maxLoadMS,debugprofilestop()-before) end
            stats.loads=stats.loads+1
            list=regionPages(r)
            if not ok or not loaded or not list or list.count~=r.pages or list.bytes~=r.bytes then
                failed={key=key,reason="regional-addon-unavailable: "..tostring(reason or loaded or "registration missing"),permanent=true}
                return nil,failed.reason
            end
        end
        current.index=current.index+1;return nil,"loading"
    end
    local selection=current.selection;local meta=schema.Clone(catalog.meta)
    meta.corpusRevision=catalog.revision
    meta.packNamespace=catalog.namespace;meta.packSourceSHA256=catalog.sourceSHA256;meta.packOwnedBounds=schema.Clone(catalog.ownedBounds)
    meta.revision=(admissionKey or catalog.revision)..":"..table.concat(selection.ids,",")
    meta.counts={polygons=selection.polygons,portals=selection.portals};meta.regionalCandidate=true;meta.localAttachment=selection.localOnly
    local stream=regionStream(selection,meta)
    current.validating=true;stats.windows=stats.windows+1
    return {meta=meta,stream=stream,selection=selection,["token"]=current.token},"prepared"
end
