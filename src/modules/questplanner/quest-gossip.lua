-- Observes an already open gossip dialog. It never selects or accepts a quest.
local planner,guard=RikUI.QuestPlanner,RikUI.Secret
local schema,gossip=planner.Schema,{}
planner.Gossip=gossip
local MAX_ROWS,MAX_TITLE,MAX_ID=32,256,2147483647

local function status(state,reason)
    return {state=state,reason=reason}
end

local function read(fn,...)
    if guard.IsSecret(fn) then return status("rejected","secret-function") end
    if type(fn)~="function" then return status("unavailable","api-missing") end
    local ok,a,b,c,d=guard.Read(fn,...)
    if not ok then return status("unavailable","read-failed") end
    if guard.IsSecret(a) or guard.IsSecret(b) or guard.IsSecret(c) or guard.IsSecret(d) then
        return status("rejected","secret-result")
    end
    return status("observed"),a,b,c,d
end

local function api(namespace,name)
    if schema.PlainTable(namespace) then return namespace[name] end
end

local function boolean(value)
    return not guard.IsSecret(value) and type(value)=="boolean"
end

local function text(value,maximum)
    return schema.Text(value) and #value>0 and #value<=maximum
end

local function currentIdentity(expected)
    if not schema.Identity(expected) then return nil,"expected identity unavailable" end
    local observed,version,build,_,interface=read(GetBuildInfo)
    if observed.state~="observed" or not text(version,128) or not text(build,128)
        or not schema.Integer(interface,1,MAX_ID) then return nil,"build identity unavailable" end
    if interface~=16001 or not version:match("^1%.60%.%d+$") or not build:match("^%d+$") then
        return nil,"unsupported gossip client identity"
    end
    local localeStatus,locale=read(GetLocale)
    if localeStatus.state~="observed" or not text(locale,4) or not locale:match("^[a-z][a-z][A-Z][A-Z]$") then
        return nil,"locale unavailable"
    end
    local identity={product="forever",build=version.."."..build,locale=locale}
    if expected.product~=identity.product or expected.build~=identity.build or expected.locale~=identity.locale then
        return nil,"gossip identity mismatch"
    end
    return identity
end

local function npcGUID()
    local observed,guid=read(UnitGUID,"npc")
    if observed.state~="observed" then return nil,observed end
    if guid==nil then return nil,status("no-result","npc-guid-unavailable") end
    if not text(guid,128) or not guid:match("^[%w%-]+$") then
        return nil,status("rejected","invalid-npc-guid")
    end
    return guid,observed
end

local function questRow(value)
    if not schema.PlainTable(value) or not schema.ID(value.questID) or not text(value.title,MAX_TITLE)
        or not schema.Integer(value.questLevel,-1,1000) then return nil end
    local result={questID=value.questID,title=value.title,questLevel=value.questLevel}
    -- These optional values are omitted when unknown, never changed to false.
    for _,name in ipairs({"isComplete","repeatable"}) do
        local child=value[name]
        if guard.IsSecret(child) or (child~=nil and not boolean(child)) then return nil end
        result[name]=child
    end
    local frequency=value.frequency
    if guard.IsSecret(frequency) or (frequency~=nil and not schema.Integer(frequency,0,256)) then return nil end
    result.frequency=frequency
    return result
end

local function copyRows(rows,count,observed)
    local copied,seen={},{}
    for index=1,count do
        local value=questRow(rows[index])
        if not value then
            observed.state,observed.reason="rejected","invalid-or-oversized-row"
            return nil,observed
        end
        if seen[value.questID] then
            observed.state,observed.reason="ambiguous","duplicate-quest-id"
            return nil,observed
        end
        seen[value.questID]=true
        copied[index]=value
    end
    observed.rows=count
    if count==0 then observed.state,observed.reason="no-result","empty-dialog-list" end
    return copied,observed
end

local function questList(name)
    local observed,rows=read(api(C_GossipInfo,name))
    observed.api="C_GossipInfo."..name
    if observed.state~="observed" then return nil,observed end
    if rows==nil then
        observed.state,observed.reason="no-result","no-list-returned"
        return nil,observed
    end
    local valid,count=schema.List(rows,MAX_ROWS)
    if not valid then
        observed.state,observed.reason="rejected","invalid-or-oversized-list"
        return nil,observed
    end
    return copyRows(rows,count,observed)
end

local function sessionContext(result)
    local timed,now=read(GetTime)
    if timed.state=="observed" and schema.Number(now,0,MAX_ID) then
        result.observedAt=now
    elseif timed.state=="observed" then timed=status(now==nil and "no-result" or "rejected","invalid-or-unavailable-time") end
    result.contextStatus.time=timed
    local leveled,level=read(UnitLevel,"player")
    if leveled.state=="observed" and schema.Integer(level,1,1000) then
        result.level=level
    elseif leveled.state=="observed" then leveled=status(level==nil and "no-result" or "rejected","invalid-or-unavailable-level") end
    result.contextStatus.level=leveled
    local located,position=read(api(planner.Context,"Position"))
    if located.state=="observed" and schema.PlainTable(position) and schema.ID(position.mapID)
        and schema.Number(position.x,0,1) and schema.Number(position.y,0,1) then
        result.playerInteractionPosition={mapID=position.mapID,x=position.x,y=position.y}
    elseif located.state=="observed" then
        located=status(position==nil and "no-result" or "rejected","invalid-or-unavailable-player-position")
    end
    result.contextStatus.playerPosition=located
end

local function dialogLists(result,before)
    local offered,offeredStatus=questList("GetAvailableQuests")
    local active,activeStatus=questList("GetActiveQuests")
    local after,afterStatus=npcGUID()
    if not after or before~=after then
        result.status=status("rejected","npc-changed-or-unavailable-during-read")
        result.npcStatus=afterStatus
        return
    end
    result.unitGUID=before
    local entry=tonumber(before:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if schema.ID(entry) then result.npcID=entry end
    result.offered,result.active=offered,active
    result.offeredStatus,result.activeStatus=offeredStatus,activeStatus
    result.status=status("observed")
    if offeredStatus.state~="observed" and offeredStatus.state~="no-result"
        or activeStatus.state~="observed" and activeStatus.state~="no-result" then
        result.status=status("partial","one-or-more-dialog-lists-unavailable")
    end
end

function gossip.Read(expectedIdentity)
    local identity,reason=currentIdentity(expectedIdentity)
    if not identity then return nil,reason end
    local result={identity=identity,event="GOSSIP_SHOW",source="client-gossip-dialog-v1",origin="live",
        scope="current-character-dialog",positionScope="player-interaction-position",contextStatus={}}
    sessionContext(result)
    local before,beforeStatus=npcGUID()
    if not before then result.status=beforeStatus;return result end
    dialogLists(result,before)
    local bounded=schema.CopyLimited(result,512,8192,8)
    if not bounded then
        result.offered,result.active=nil,nil
        result.status=status("query-limited","journal-entry-budget")
        result.offeredStatus=status("query-limited","journal-entry-budget")
        result.activeStatus=status("query-limited","journal-entry-budget")
    end
    -- A current-character offer never establishes universal availability.
    return bounded or result
end
