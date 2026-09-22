-- Local generated companions are references; only requested partitions enter memory.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local data,pages,queued,queue={}, {}, {}, {}
planner.SemanticData=data
local wanted,persona,catalog,problem,loading,catalogRevision
local revision,loaded,head,sliceAt=0,0,1,1
local MAX_PARTITIONS,MAX_QUESTS=512,40
local CLASSES={[1]="WARRIOR",[2]="PALADIN",[3]="HUNTER",[4]="ROGUE",[5]="PRIEST",[7]="SHAMAN",[8]="MAGE",[9]="WARLOCK",[11]="DRUID"}
local function same(a,b)
    return a and b and a.product==b.product and a.build==b.build and a.locale==b.locale
end
local function notify()
    revision=revision+1
    if planner.Request then planner.Request() end
end
local function acceptCatalog()
    local raw=RikUIQuestCorpusCatalog
    if not schema.PlainTable(raw) or raw.version~=1 or not schema.Identity(raw.identity)
        or not schema.Text(raw.revision) or not schema.Integer(raw.partitionSize,1,256)
        or not schema.PlainTable(raw.partitions) then return nil end
    return raw
end
local function loadAddon(name)
    local api=type(C_AddOns)=="table" and C_AddOns.LoadAddOn or LoadAddOn
    if type(api)~="function" then return nil,"addon loading API unavailable" end
    local ok,value,reason=pcall(api,name)
    if not ok or not value then return nil,tostring(reason or value or "load failed") end
    return true
end
function data.Ensure(snapshot,ctx)
    wanted=snapshot and snapshot.identity
    if not snapshot or snapshot.origin=="imported-untrusted" or not ctx or ctx.origin~="live" then wanted=nil;return end
    local attributes=ctx and ctx.attributes or {}
    local nextPersona=(attributes.faction=="Alliance" or attributes.faction=="Horde") and CLASSES[attributes.class]
        and attributes.faction..":"..CLASSES[attributes.class]
    if persona~=nextPersona then persona=nextPersona;notify() end
    local available=acceptCatalog()
    if catalog and available and catalogRevision~=available.revision then
        wanted=nil
        if problem~="corpus revision changed; restart required" then problem="corpus revision changed; restart required";notify() end
        return
    end
    catalog=catalog or available
    if catalog and not catalogRevision then catalogRevision=catalog.revision end
    if not catalog or not same(wanted,catalog.identity) then return end
    for index,id in ipairs(snapshot.order or {}) do
        if index>MAX_QUESTS then break end
        local bucket=math.floor(id/catalog.partitionSize)
        if catalog.partitions[bucket] and not pages[bucket] and not queued[bucket] then
            queued[bucket]=true;queue[#queue+1]=bucket
        end
    end
end
function data.Register(bucket,version,records)
    local current=acceptCatalog()
    if not current or version~=current.revision or not schema.Integer(bucket,0,1000000)
        or not current.partitions[bucket] or not schema.PlainTable(records) then return nil,"partition identity mismatch" end
    if loaded>=MAX_PARTITIONS and not pages[bucket] then return nil,"partition memory limit" end
    local count=0
    for id,record in pairs(records) do
        count=count+1
        if count>current.partitionSize or not schema.ID(id) or math.floor(id/current.partitionSize)~=bucket
            or not schema.PlainTable(record) or not schema.PlainTable(record.base)
            or record.base.id~=id or not schema.Text(record.base.title)
            or not schema.PlainTable(record.variants) then return nil,"invalid quest partition" end
    end
    if pages[bucket] then return nil,"partition already registered" end
    catalog=current;catalogRevision=current.revision;pages[bucket]=records;loaded=loaded+1;notify()
    return true
end
function data.Step()
    if not wanted or loading or (catalog and head>#queue) then return end
    if type(InCombatLockdown)=="function" then
        local ok,busy=pcall(InCombatLockdown)
        if not ok or RikUI.Secret.IsSecret(busy) or busy then return end
    end
    if not catalog then
        if problem then return end
        loading=true
        local ok,reason=loadAddon("RikUIQuestCorpus")
        loading=false;catalog=acceptCatalog()
        catalogRevision=catalog and catalog.revision
        if not ok or not catalog then problem=reason or "invalid corpus catalog";notify() end
        if catalog then notify() end
        return
    end
    if not same(wanted,catalog.identity) or head>#queue then return end
    if loaded>=MAX_PARTITIONS then problem="partition memory limit";return end
    local bucket=queue[head]
    local entry=catalog.partitions[bucket]
    local addons=type(entry)=="table" and entry.addons or {entry}
    local name=type(addons)=="table" and addons[sliceAt]
    if not schema.List(addons,512) or not schema.Text(name)
        or not (name:match("^RikUIQuestCorpus_P%d+$") or name:match("^RikUIQuestCorpus_P%d+_S%d+$")) then
        problem="invalid partition addon";head=head+1;sliceAt=1;return
    end
    loading=true
    local ok,reason=loadAddon(name)
    loading=false
    if not ok or (sliceAt==#addons and not pages[bucket]) then
        problem=reason or "partition did not register"
        RikUIQuestCorpusPagePool=nil;head=head+1;sliceAt=1;notify()
    elseif sliceAt==#addons then head=head+1;sliceAt=1
    else sliceAt=sliceAt+1 end
end
-- Borrowed immutable records: no copying the world graph on planner refresh.
function data.Quest(identity,id)
    if not catalog or not same(identity,catalog.identity) or not same(wanted,catalog.identity) or not persona then return end
    local page=pages[math.floor(id/catalog.partitionSize)]
    local record=page and page[id]
    if not record then return end
    if catalog.selectors then
        local found=false
        for _,selector in ipairs(catalog.selectors) do if selector==persona then found=true;break end end
        if not found then return end
    end
    local value=record.variants[persona]
    if value==false then return end
    return value or record.base
end

-- Stable bounded frontier: active quests first, then connected chains and local opportunities.
local MAX_FRONTIER,MAX_LINKS=96,24
function data.Request(id)
    if not catalog or not schema.ID(id) then return false end
    local bucket=math.floor(id/catalog.partitionSize)
    if not catalog.partitions[bucket] then return false end
    if not pages[bucket] and not queued[bucket] and #queue<MAX_PARTITIONS then
        queued[bucket]=true;queue[#queue+1]=bucket
    end
    return pages[bucket]~=nil
end
function data.Frontier(snapshot,ctx)
    local ids,seen={},{}
    local function add(id)
        if schema.ID(id) and not seen[id] and #ids<MAX_FRONTIER then seen[id]=true;ids[#ids+1]=id end
    end
    for _,id in ipairs(snapshot.order or {}) do add(id) end
    local index=catalog and catalog.planning
    if not index or index.version~=1 or not same(wanted,snapshot.identity) then return ids end
    local at=1
    while at<=#ids and at<=MAX_FRONTIER do
        for n,id in ipairs(index.links[ids[at]] or {}) do if n>MAX_LINKS then break end;add(id) end
        at=at+1
    end
    local mapID=ctx.position and ctx.position.mapID
    local level=ctx.attributes and ctx.attributes.level
    for _,id in ipairs(index.maps[mapID] or {}) do
        local metadata=index.quests[id]
        if metadata and metadata.semantic and (not level or (metadata.minLevel or 0)<=level+3) then add(id) end
    end
    for _,id in ipairs(ids) do data.Request(id) end
    return ids
end
function data.Records(snapshot,ctx)
    local records,ids={},data.Frontier(snapshot,ctx)
    for _,id in ipairs(ids) do
        local record=data.Quest(snapshot.identity,id)
        if record then records[id]=record end
    end
    return records,ids
end

function data.Revision() return revision end
function data.Status()
    return {revision=catalog and catalog.revision,loadedPartitions=loaded,queuedPartitions=math.max(0,#queue-head+1),
        state=problem and "unavailable" or not catalog and "loading" or not same(wanted,catalog.identity) and "identity-mismatch" or "ready",
        reason=problem,counts=catalog and schema.Clone(catalog.counts)}
end

