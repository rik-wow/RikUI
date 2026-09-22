-- Lazy source pages and a bounded window of exact directed regional topology.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local regions={}
planner.Regions=regions
local catalog,pages,registeredBytes,job,activeKey,activeSet,failed=nil,{},0,nil,nil,nil,nil
local serial,expansion=0,1
local stats={loads=0,maxLoadMS=0,sourceBytes=0,windows=0}
local function same(a,b) return a and b and a.product==b.product and a.build==b.build and a.locale==b.locale end
local function hash(v) return type(v)=="string" and #v==64 and v:match("^[a-f0-9]+$") end
local function rectangle(v)
    if not schema.List(v,4) or #v~=4 then return false end
    for _,n in ipairs(v) do if not schema.Number(n,-100000,100000) then return false end end
    return v[1]<=v[3] and v[2]<=v[4]
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
    local total=0
    for i,r in ipairs(value.regions) do
        if r.id~=i or r.addon~=string.format("RikUIQuestTerrain_R%03d",i)
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
    catalog,pages,registeredBytes,job,activeKey,activeSet,failed=value,{},0,nil,nil,nil,nil
    serial=serial+1;expansion=1
    return true
end
function regions.RegisterPage(revision,id,index,payload)
    local r=catalog and catalog.regions[id]
    if not r or revision~=catalog.revision or not schema.Integer(index,1,r.pages)
        or type(payload)~="string" or #payload<1 or #payload>32768
        or payload:sub(-1)~="\n" or payload:find("[^%d%,%.%-%+eE\n]") then return nil,"invalid regional source page" end
    local list=pages[id] or {bytes=0,count=0}
    if list[index] then return nil,"duplicate regional page" end
    if list.bytes+#payload>r.bytes or registeredBytes+#payload>catalog.sourceBytes then return nil,"regional source cache limit" end
    pages[id]=list;list[index]=payload;list.bytes=list.bytes+#payload;list.count=list.count+1
    registeredBytes=registeredBytes+#payload;stats.sourceBytes=registeredBytes
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
function regions.Select(start,goal)
    if not catalog then return nil,"unavailable" end
    local starts,goals,goalSet={},{},{}
    for _,r in ipairs(catalog.regions) do
        if contains(r,start) then starts[#starts+1]=r.id end
        if contains(r,goal) then goals[#goals+1]=r.id;goalSet[r.id]=true end
    end
    if #starts==0 or #goals==0 then return nil,"outside-coverage" end
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
    local path={}
    while found do table.insert(path,1,found);found=parent[found] end
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
    for _=1,expansion do
        local seeds={};for i,id in ipairs(ids) do seeds[i]=id end
        for _,id in ipairs(seeds) do for _,nextID in ipairs(catalog.regions[id].neighbors) do add(nextID) end end
    end
    table.sort(ids)
    local edges=0
    for _,id in ipairs(ids) do for target,n in pairs(catalog.regions[id].edgeCounts) do if set[target] then edges=edges+n end end end
    return {ids=ids,set=set,polygons=pc,portals=edges,topologyOnly=true,optimal=false}
end
function regions.Retry()
    job,activeKey,activeSet,failed=nil,nil,nil,nil;serial=serial+1;expansion=1
end
function regions.Suspend() job=nil;serial=serial+1 end
function regions.Current(token) return job and job.token==token end
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
    expansion=expansion+1;job,activeKey,activeSet=nil,nil,nil;serial=serial+1
    return true
end
function regions.Enabled() return catalog~=nil end
function regions.Stats() return schema.Clone(stats) end
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
function regions.Prepare(identity,position,destination)
    if not catalog then return end
    if not same(identity,catalog.meta.identity) then regions.Suspend();return nil,"incompatible-region-identity" end
    local start,goal=project(position),project(destination)
    if not start or not goal then regions.Suspend();return nil,"unavailable-position" end
    local key=catalog.revision..":"..string.format("%d:%.17g:%.17g",destination.mapID,destination.x,destination.y)
    if activeKey==key then
        for id in pairs(activeSet) do if contains(catalog.regions[id],start) then return nil,"ready" end end
    end
    if activeSet and not job and covered(start) and covered(goal) then
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
        local selection,reason=regions.Select(start,goal)
        if not selection then failed={key=key,reason=reason,origin=originKey};return nil,reason end
        serial=serial+1;job={key=key,selection=selection,index=1,token=serial}
    end
    local current=job
    if current.loading then return nil,"loading" end
    if current.validating then return nil,"validating" end
    local id=current.selection.ids[current.index]
    if id then
        local r=catalog.regions[id];local list=pages[id]
        if not list or list.count~=r.pages or list.bytes~=r.bytes then
            if type(InCombatLockdown)=="function" and InCombatLockdown() then return nil,"combat-loading-deferred" end
            local load=type(C_AddOns)=="table" and C_AddOns.LoadAddOn
            if type(load)~="function" then failed={key=key,reason="regional-loader-unavailable",permanent=true};return nil,failed.reason end
            local before=type(debugprofilestop)=="function" and debugprofilestop()
            current.loading=true
            local ok,loaded,reason=pcall(load,r.addon)
            current.loading=nil
            if job~=current then return nil,"loading" end
            if before then stats.maxLoadMS=math.max(stats.maxLoadMS,debugprofilestop()-before) end
            stats.loads=stats.loads+1
            list=pages[id]
            if not ok or not loaded or not list or list.count~=r.pages or list.bytes~=r.bytes then
                failed={key=key,reason="regional-addon-unavailable: "..tostring(reason or loaded or "registration missing"),permanent=true}
                return nil,failed.reason
            end
        end
        current.index=current.index+1;return nil,"loading"
    end
    local selection=current.selection;local meta=schema.Clone(catalog.meta)
    meta.corpusRevision=catalog.revision
    meta.revision=catalog.revision..":"..table.concat(selection.ids,",")
    meta.counts={polygons=selection.polygons,portals=selection.portals};meta.regionalCandidate=true
    local stream=planner.RegionCodec.Stream(selection.ids,pages,selection.set,meta.identity,#catalog.regions)
    current.validating=true;stats.windows=stats.windows+1
    return {meta=meta,stream=stream,selection=selection,token=current.token},"prepared"
end
