-- Generated corpus pages ship inside RikUI (generated/corpus) as deferred
-- functions; only requested partitions are materialized, one page per frame.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local data,pages,queued,queue={}, {}, {}, {}
planner.SemanticData=data
local wanted,persona,catalog,problem,loading,catalogRevision
local revision,loaded,head,sliceAt=0,0,1,1
local MAX_PARTITIONS,MAX_QUESTS,MAX_SLICES=512,40,512
local shards={}  -- page key -> deferred page function, freed once run
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
-- Called by generated/corpus page files at addon load; the body runs on demand.
function data.Page(key,fn)
    if type(key)~="string" or not key:match("^P%d+_S%d+$") or type(fn)~="function" then return nil,"invalid corpus page" end
    if shards[key] then return nil,"duplicate corpus page" end
    shards[key]=fn
    return true
end
local function runPage(key)
    local fn=shards[key]
    if not fn then return nil,"corpus page missing: "..tostring(key) end
    shards[key]=nil
    local ok,reason=pcall(fn)
    if not ok then return nil,tostring(reason) end
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
        catalog=acceptCatalog()
        catalogRevision=catalog and catalog.revision
        if not catalog then problem="corpus data not installed" end
        notify()
        return
    end
    if not same(wanted,catalog.identity) or head>#queue then return end
    if loaded>=MAX_PARTITIONS then problem="partition memory limit";return end
    local bucket=queue[head]
    local entry=catalog.partitions[bucket]
    local slices=type(entry)=="table" and entry.pages
    local key=type(slices)=="table" and slices[sliceAt]
    if not schema.List(slices,MAX_SLICES) or not schema.Text(key) then
        problem="invalid partition pages";head=head+1;sliceAt=1;return
    end
    loading=true
    local ok,reason=runPage(key)
    loading=false
    if not ok or (sliceAt==#slices and not pages[bucket]) then
        problem=reason or "partition did not register"
        RikUIQuestCorpusPagePool=nil;head=head+1;sliceAt=1;notify()
    elseif sliceAt==#slices then head=head+1;sliceAt=1
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
local frontierKey,history={},{}
local historyQueue,historyPending,historyHead={}, {},1
function data.ResetHistory()
    history,historyQueue,historyPending,historyHead={},{},{},1
end
function data.StepHistory()
    if historyHead>#historyQueue or not planner.Context or not planner.Context.History then return end
    local ids={}
    for _=1,16 do
        local id=historyQueue[historyHead];if not id then break end
        ids[#ids+1]=id;historyHead=historyHead+1
    end
    local values=planner.Context.History(ids) or {}
    local changed=false
    for _,id in ipairs(ids) do
        if type(values[id])=="boolean" and not RikUI.Secret.IsSecret(values[id]) then
            changed=changed or history[id]~=values[id];history[id]=values[id]
        end
    end
    if changed then notify() end
end
function data.Frontier(snapshot,ctx,policy)
    policy=policy or {}
    local identity=snapshot.identity
    local key=table.concat({identity.product,identity.build,identity.locale,ctx.characterKey or "session",catalogRevision or "?"},":")
    if key~=frontierKey then frontierKey=key;data.ResetHistory() end
    local ids,seen,seeds={}, {},{}
    local function add(id,force)
        if schema.ID(id) and not seen[id] and #ids<MAX_FRONTIER and (force or history[id]~=true) then
            seen[id]=true;ids[#ids+1]=id;return true
        end
    end
    local function keys(map)
        local result={};for id,value in pairs(map or {}) do if value==true and schema.ID(id) then result[#result+1]=id end end
        table.sort(result);return result
    end
    for _,id in ipairs(snapshot.order or {}) do add(id,true);seeds[#seeds+1]=id end
    for _,map in ipairs({policy.pins or {},policy.questGoals or {}}) do
        for _,id in ipairs(keys(map)) do add(id,true);seeds[#seeds+1]=id end
    end
    local index=catalog and catalog.planning
    if not index or index.version~=1 or not same(wanted,snapshot.identity) then return ids end
    local chain,chainSeen={},{}
    for _,id in ipairs(seeds) do if not chainSeen[id] then chainSeen[id]=true;chain[#chain+1]=id end end
    local at=1
    while at<=#chain and #chain<192 do
        for n,id in ipairs(index.links[chain[at]] or {}) do
            if n>MAX_LINKS or #chain>=192 then break end
            if schema.ID(id) and not chainSeen[id] then chainSeen[id]=true;chain[#chain+1]=id end
        end
        at=at+1
    end
    local level=ctx.attributes and ctx.attributes.level
    local maps=keys(policy.zoneGoals);local current=ctx.position and ctx.position.mapID
    if current then table.insert(maps,1,current) end
    local localIDs,localSeen={},{}
    for mapIndex,mapID in ipairs(maps) do
        if mapIndex>5 then break end
        for n,id in ipairs(index.maps[mapID] or {}) do
            if n>2048 then break end
            local metadata=index.quests[id]
            if metadata and metadata.semantic and not localSeen[id]
                and (not level or (metadata.minLevel or 0)<=level+3) and history[id]~=true then
                localSeen[id]=true
                localIDs[#localIDs+1]={id=id,rank=level and metadata.minLevel and math.abs(level-metadata.minLevel) or 1000,
                    tier=level and metadata.minLevel and (metadata.minLevel<=level and 0 or 2) or 1}
            end
        end
    end
    table.sort(localIDs,function(a,b)
        if a.tier~=b.tier then return a.tier<b.tier end
        if a.rank~=b.rank then return a.rank<b.rank end
        return a.id<b.id
    end)
    local function query(id)
        if history[id]==nil and not historyPending[id] and #historyQueue<1024 then
            historyPending[id]=true;historyQueue[#historyQueue+1]=id
        end
    end
    for _,id in ipairs(chain) do query(id) end
    for n,row in ipairs(localIDs) do if n>384 then break end;query(row.id) end
    local limit=#ids+math.floor((MAX_FRONTIER-#ids)*.4)
    for _,id in ipairs(chain) do if #ids>=limit then break end;add(id) end
    for _,row in ipairs(localIDs) do if #ids>=MAX_FRONTIER then break end;add(row.id) end
    for _,id in ipairs(chain) do if #ids>=MAX_FRONTIER then break end;add(id) end
    ctx.frontierHistory=history
    for _,id in ipairs(ids) do data.Request(id) end
    return ids
end
function data.Records(snapshot,ctx,policy)
    local records,ids={},data.Frontier(snapshot,ctx,policy)
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

