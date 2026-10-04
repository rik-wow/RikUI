-- Optional installed provider; never bundles or executes provider source strings.
-- API reviewed against QuestieDB contract 3 and its public Forever documentation.
local core,g=RikUI,RikUI.GearGoals
local provider={status="not started",count=0,scanned=0};g.Provider=provider
local ids,index,db,work,limit,requested= nil,1,nil,nil,0,false
local EQUIP={INVTYPE_HEAD={1},INVTYPE_NECK={2},INVTYPE_SHOULDER={3},INVTYPE_CLOAK={15},
    INVTYPE_CHEST={5},INVTYPE_ROBE={5},INVTYPE_WRIST={9},INVTYPE_HAND={10},INVTYPE_WAIST={6},
    INVTYPE_LEGS={7},INVTYPE_FEET={8},INVTYPE_FINGER={11,12},INVTYPE_TRINKET={13,14},
    INVTYPE_WEAPON={16,17},INVTYPE_2HWEAPON={16},INVTYPE_WEAPONMAINHAND={16},
    INVTYPE_WEAPONOFFHAND={17},INVTYPE_SHIELD={17},INVTYPE_HOLDABLE={17},INVTYPE_RANGED={18},
    INVTYPE_RANGEDRIGHT={18},INVTYPE_THROWN={18},INVTYPE_RELIC={18}}
local TYPES={INVTYPE_HEAD=1,INVTYPE_NECK=2,INVTYPE_SHOULDER=3,INVTYPE_CLOAK=16,INVTYPE_CHEST=5,
    INVTYPE_ROBE=20,INVTYPE_WRIST=9,INVTYPE_HAND=10,INVTYPE_WAIST=6,INVTYPE_LEGS=7,INVTYPE_FEET=8,
    INVTYPE_FINGER=11,INVTYPE_TRINKET=12,INVTYPE_WEAPON=13,INVTYPE_2HWEAPON=17,
    INVTYPE_WEAPONMAINHAND=21,INVTYPE_WEAPONOFFHAND=22,INVTYPE_SHIELD=14,INVTYPE_HOLDABLE=23,
    INVTYPE_RANGED=15,INVTYPE_RANGEDRIGHT=26,INVTYPE_THROWN=25,INVTYPE_RELIC=28}
-- Area identifiers are curation, not a loot table. Names come from the installed provider.
local DUNGEONS={[1581]=true,[718]=true,[2437]=true,[209]=true,[717]=true,[719]=true,[1337]=true,
    [721]=true,[491]=true,[722]=true,[796]=true,[1176]=true,[1477]=true,[2100]=true,
    [1583]=true,[1584]=true,[2057]=true,[2017]=true,[2557]=true}
local QUEST_FIELDS={"name","requiredLevel","requiredMaxLevel","requiredClasses","requiredRaces","preQuestGroup",
    "preQuestSingle","exclusiveTo","parentQuest","requiredSkill","requiredMinRep","requiredMaxRep","requiredSpell",
    "requiredSpecialization","availableUntilCompleted","availableStartingWith","disabledByQuest","requiredRanks","questFlags"}
local function read(fn,...)if type(fn)=="function" then return core.Secret.Read(fn,...)end;return false end
local function safe(v)return not core.Secret.IsSecret(v)end
local function id(v)return safe(v) and type(v)=="number" and v%1==0 and v>0 and v<2147483648 end
local function text(v)return safe(v) and type(v)=="string" and #v<=512 and not v:find("[%c]") and v:gsub("|","") or nil end
local function get(entity,entityID,field)
    local ok,value=read(entity and entity.Get,entityID,field)
    if not ok then error(text(value) or "Provider field read failed",0) end
    if safe(value)then return value end
end
local function clean(value,depth,nodes)
    depth,nodes=depth or 0,nodes or {count=0}
    if depth>5 or not safe(value)then return nil end
    if type(value)=="number" then if value==value and math.abs(value)<=2^53 then return value end
    elseif type(value)=="string" then return text(value)
    elseif type(value)=="table" and getmetatable(value)==nil then
        local out={}
        for k,v in pairs(value)do
            nodes.count=nodes.count+1
            if nodes.count>256 or not id(k) or k>64 then return nil end
            local x=clean(v,depth+1,nodes);if x==nil then return nil end;out[k]=x
        end
        return out
    end
end
local function list(value,maximum)
    if value==nil then return {} end
    if not safe(value) or type(value)~="table" or getmetatable(value)~=nil or #value>maximum then return nil end
    local out={}
    for k,v in pairs(value)do if not id(k) or k>#value or not id(v)then return nil end;out[k]=v end
    if #out~=#value then return nil end;return out
end
local function quest(qid,full)
    if not db then return end
    local row=work.quests[qid]
    if row and (not full or row.gearFull) then return row end
    if not row then
        if provider.questCount>=8192 then return end
        local name=text(get(db.Quest,qid,"name"));if not name then return end
        row={name=name};work.quests[qid]=row;provider.questCount=provider.questCount+1
        for _,field in ipairs({"requiredLevel","requiredClasses","requiredRaces","questFlags"})do row[field]=clean(get(db.Quest,qid,field))end
    end
    if full then
        local ok,values=read(db.Quest.GetAll,qid,QUEST_FIELDS)
        if not ok or not safe(values) or type(values)~="table" or getmetatable(values)~=nil or values.n~=#QUEST_FIELDS then error("Quest requirements unavailable",0)end
        for i,field in ipairs(QUEST_FIELDS)do row[field]=clean(values[i])end
        row.gearFull=true
    end
    return row
end
function provider.Quest(qid,full)
    local ok,row=pcall(quest,qid,full)
    if ok then return row end
    provider.failed=true;provider.status="Source read failed; "..(text(row) or "provider unavailable")
end
function provider.Start(force)
    requested=true
    if core.GearCatalog and not core.GearCatalog.installedProvider and g.CurrentCatalog() and not force then provider.status="compiled local catalog";return true end
    if (ids or provider.ready) and not force then return true end
    local lib=LibQuestieDB
    if type(lib)~="table" then provider.status="Install QuestieDB for source browsing, or build the local catalog.";return nil,provider.status end
    local ok,accepted,message=read(lib.RequireContract,3)
    if not ok or accepted~=true then provider.status=text(message) or "QuestieDB contract 3 required";return nil,provider.status end
    local good,state=read(lib.ModeIndicator and lib.ModeIndicator.GetStatus)
    if not good or not safe(state) or type(state)~="table" or state.expansion~="Forever" then
        provider.status="QuestieDB must be loaded with Forever data";return nil,provider.status
    end
    if type(lib.Item)~="table" or type(lib.Quest)~="table" or type(lib.Npc)~="table" then provider.status="QuestieDB entity API unavailable";return nil,provider.status end
    local valid,all=read(lib.Item.GetAllIds)
    if not valid or not safe(all) or type(all)~="table" or #all>40000 then provider.status="QuestieDB item inventory exceeds supported capacity";return nil,provider.status end
    -- Shared inventory is read-only; corrections cannot be mutated by this consumer.
    ids,index,db,limit=all,1,lib,#all
    local b,v,build=read(GetBuildInfo)
    work={version=1,installedProvider=true,identity={build=b and text(v) and text(tostring(build)) and v.."."..tostring(build) or "unknown",
        provider="Installed QuestieDB",mode=lib.readMode},items={},slots={},quests={},variants={},raceMasks=lib.Enum and lib.Enum.raceMaskById}
    provider.status,provider.count,provider.scanned,provider.questCount="Indexing installed source references",0,0,0
    provider.ready,provider.failed,provider.unknownSlots=false,false,0
    core.GearCatalog=work
    return true
end
local function process(itemID)
    if not id(itemID)then error("Invalid item inventory ID")end
    local class=get(db.Item,itemID,"class")
    if class~=2 and class~=4 then return end
    local ok,_,kind,subtype,equip,icon,classID,subclassID=read(C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant,itemID)
    if not ok or not safe(equip) or not EQUIP[equip] then provider.unknownSlots=(provider.unknownSlots or 0)+1;return end
    local quests=list(get(db.Item,itemID,"questRewards"),32)
    local sources={}
    for _,qid in ipairs(quests or {})do
        local quest=provider.Quest(qid)
        if quest then sources[#sources+1]={kind="quest",id=qid,name=quest.name,authority="reference"}end
    end
    local drops=list(get(db.Item,itemID,"npcDrops"),20)
    for _,nid in ipairs(drops or {})do
        local area=get(db.Npc,nid,"zoneID");local rank=get(db.Npc,nid,"rank")
        if safe(area) and DUNGEONS[area] and safe(rank) and type(rank)=="number" and rank>=1 then
            sources[#sources+1]={kind="dungeon",id=nid,area=area,name=text(get(db.Npc,nid,"name")) or "Unknown encounter",
                dungeon=(function()
                    local known,name=read(C_Map and C_Map.GetAreaInfo,area)
                    return known and text(name) or "Dungeon area #"..area
                end)(),authority="reference"}
        end
    end
    if #sources==0 or #sources>32 then return end
    if provider.count>=10000 then error("Gear catalog capacity reached")end
    -- Source indexing never requests full item metadata; only visible items do.
    local meta=nil
    local name=meta and meta.name or text(get(db.Item,itemID,"name"))
    if not name then return end
    local min=get(db.Item,itemID,"requiredLevel");local level=get(db.Item,itemID,"itemLevel")
    work.items[itemID]={name=name,inventoryType=TYPES[equip],icon=safe(icon) and icon or nil,
        classID=safe(classID) and classID or class,subclassID=safe(subclassID) and subclassID or 0,
        level=meta and meta.minLevel or type(min)=="number" and safe(min) and min or 0,
        itemLevel=meta and meta.level or type(level)=="number" and safe(level) and level or 0,
        metadataAuthority=meta and "client" or "reference",sources=sources}
    for _,slot in ipairs(EQUIP[equip])do work.slots[slot]=work.slots[slot] or {};work.slots[slot][#work.slots[slot]+1]=itemID end
    provider.count=provider.count+1
end
function provider.Step()
    if not ids then return false end
    local ok,start=read(debugprofilestop)
    for _=1,64 do
        if index>limit then
            ids=nil;provider.ready=true;provider.status="Installed QuestieDB · "..provider.count.." candidates · reference sources"
            work.counts={items=provider.count,quests=provider.questCount}
            return true
        end
        local good,reason=pcall(process,ids[index])
        if not good then ids=nil;provider.failed=true;provider.status="Source indexing stopped; "..(text(reason) or "provider failure");return true end
        index=index+1;provider.scanned=provider.scanned+1
        local timed,now=read(debugprofilestop)
        if ok and timed and safe(start) and safe(now) and type(start)=="number" and type(now)=="number" and now-start>=1 then break end
    end
    return false
end
function provider.Progress()return ids and provider.scanned/math.max(1,limit) end
function provider.RetryAfterLoad()if requested and not ids and not core.GearCatalog then provider.Start()end end
