-- A bounded session journal for explicit manual export, never a fact catalogue.
local planner, schema = RikUI.QuestPlanner, RikUI.QuestPlanner.Schema
local journal = {}
planner.Journal = journal
local LIMIT = 48
local entries, dropped, dialog = {}, 0, nil
local function append(value)
    local copy = schema.CopyLimited(value,512,8192,8)
    if not copy then dropped=dropped+1; return false end
    if #entries==LIMIT then table.remove(entries,1); dropped=dropped+1 end
    entries[#entries+1]=copy
    return true
end
local function eventValue(fn,...)
    local guard=RikUI.Secret
    if guard.IsSecret(fn) or type(fn)~="function" or type(guard.Read)~="function" then return nil end
    local ok,value=guard.Read(fn,...)
    if ok then return value end
end
local function eventContext(row,snapshot)
    row.origin,row.scope="live","current-character-event"
    if snapshot and schema.Identity(snapshot.identity) then row.identity=snapshot.identity end
    local now,level=eventValue(GetTime),eventValue(UnitLevel,"player")
    row.contextStatus={time={state="unavailable"},level={state="unavailable"}}
    if schema.Number(now,0,2147483647) then
        row.observedAt=now;row.contextStatus.time.state="observed"
    end
    if schema.Integer(level,1,1000) then
        row.levelAtEvent=level;row.contextStatus.level.state="observed"
    end
    return row
end
local function questEvent(event,snapshot,id,xp,money)
    if not schema.ID(id) then return end
    local row=eventContext({event=event,questID=id,source="client-event"},snapshot)
    if event=="QUEST_TURNED_IN" then
        row.source="QUEST_TURNED_IN"
        if schema.Number(xp,0,2147483647) then row.receivedXP=xp end
        if schema.Number(money,0,2147483647) then row.receivedMoney=money end
    else row.argument=id end
    append(row)
end
function journal.Record(event, snapshot, ...)
    if event=="QUEST_FINISHED" or event=="GOSSIP_CLOSED" then dialog=nil; return end
    if event=="GOSSIP_SHOW" then
        dialog=nil
        local observed=planner.Gossip and snapshot and planner.Gossip.Read(snapshot.identity)
        if observed then append(observed) end
        return
    end
    if event=="QUEST_DETAIL" or event=="QUEST_PROGRESS" or event=="QUEST_COMPLETE" then
        dialog=planner.Context.Dialog(event)
        if dialog then
            if snapshot and schema.Identity(snapshot.identity) then dialog.identity=snapshot.identity end
            dialog.playerInteractionPosition=dialog.position
            dialog.positionScope="player-interaction-position"
            append(dialog)
        end
        return
    end
    if event=="QUEST_TURNED_IN" or event=="QUEST_ACCEPTED" or event=="QUEST_REMOVED" then
        questEvent(event,snapshot,...)
        if event=="QUEST_TURNED_IN" then dialog=nil end
    end
end
local function recordChange(event,ids,snapshot,reason)
    if #ids==0 and event~="initial-observation" then return end
    local copied={}
    for index=1,math.min(#ids,40) do copied[index]=ids[index] end
    append({event=event,questIDs=copied,total=#ids,limited=#ids>40,reason=reason,
        observedAt=snapshot.observedAt,identity=snapshot.identity,source="client-log-snapshot"})
end

local function changedObjectives(row,old)
    if row.title~=old.title or row.level~=old.level or row.failed~=old.failed then return true,false,false end
    local difference,increased,reduced,comparable=planner.Objectives.Compare(row.objectives,old.objectives)
    if row.objectivesComplete~=old.objectivesComplete then
        difference=true
        if comparable then
            increased=increased or row.objectivesComplete==true and old.objectivesComplete==false
            reduced=reduced or row.objectivesComplete==false and old.objectivesComplete==true
        end
    end
    -- Mixed movement and changed definitions must not be summarized as one direction.
    if increased and reduced then return true,false,false end
    return difference,increased,reduced
end

local function collectChanges(snapshot,previous)
    local added,progress,reduced,changed={},{},{},{}
    for _,id in ipairs(snapshot.order) do
        local row,old=snapshot.quests[id],previous.quests[id]
        if not old then
            added[#added+1]=id
        else
            local difference,increased,decreased=changedObjectives(row,old)
            if decreased then
                reduced[#reduced+1]=id
            elseif increased then
                progress[#progress+1]=id
            elseif difference then
                changed[#changed+1]=id
            end
        end
    end

    return added,progress,reduced,changed
end

function journal.SnapshotChanged(snapshot,previous)
    local sameIdentity=previous and previous.identity and snapshot.identity
        and previous.identity.product==snapshot.identity.product and previous.identity.build==snapshot.identity.build
        and previous.identity.locale==snapshot.identity.locale
    if not sameIdentity then
        recordChange("initial-observation",snapshot.order,snapshot,previous and "identity-changed" or "first-snapshot")
        return
    end
    local added,progress,reduced,changed=collectChanges(snapshot,previous)
    local removed={}
    -- An incomplete/collapsed current log cannot establish that a quest left it.
    if snapshot.coverage=="log-complete" then
        for _,id in ipairs(previous.order) do
            if not snapshot.quests[id] then removed[#removed+1]=id end
        end
    end
    recordChange("newly-observed",added,snapshot)
    recordChange("observed-progress",progress,snapshot)
    recordChange("observed-objective-reduction",reduced,snapshot)
    recordChange("observed-change",changed,snapshot)
    recordChange("observed-quest-removed",removed,snapshot,"absent-from-complete-current-log")
end
function journal.Dialog() return schema.Clone(dialog) end
function journal.Export() return {entries=schema.Clone(entries),dropped=dropped,scope="session-only"} end
local LOG_EVENTS={["initial-observation"]="initial log",["newly-observed"]="new quest observed",
    ["observed-progress"]="objective progress",["observed-objective-reduction"]="objective counters reduced",
    ["observed-change"]="quest details changed",["observed-quest-removed"]="quest left the log"}
function journal.Status()
    local result={entries=#entries,dropped=dropped}
    for index=#entries,1,-1 do
        local row=entries[index]
        if LOG_EVENTS[row.event] then
            result.lastChange=LOG_EVENTS[row.event];result.changedQuests=row.total or #row.questIDs
            break
        end
    end
    return result
end
