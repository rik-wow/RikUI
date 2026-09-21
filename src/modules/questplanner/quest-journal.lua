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
function journal.Record(event, snapshot, ...)
    if event=="QUEST_FINISHED" or event=="GOSSIP_CLOSED" then dialog=nil; return end
    if event=="QUEST_DETAIL" or event=="QUEST_PROGRESS" or event=="QUEST_COMPLETE" then
        dialog=planner.Context.Dialog(event)
        if dialog then append(dialog) end
        return
    end
    if event=="QUEST_TURNED_IN" then
        local id,xp,money=...
        if schema.ID(id) then
            local row={event=event,questID=id,source="QUEST_TURNED_IN"}
            if schema.Number(xp,0,2147483647) then row.receivedXP=xp end
            if schema.Number(money,0,2147483647) then row.receivedMoney=money end
            append(row)
        end
        dialog=nil
    elseif event=="QUEST_ACCEPTED" or event=="QUEST_REMOVED" then
        local value=...
        if schema.ID(value) then append({event=event,argument=value,source="client-event"}) end
    end
end
function journal.SnapshotChanged(snapshot, previous)
    local changed={}
    for _,id in ipairs(snapshot.order) do
        local row,old=snapshot.quests[id],previous and previous.quests[id]
        local difference=not old or row.objectivesComplete~=old.objectivesComplete
        if not difference and row.objectives then
            for index,value in ipairs(row.objectives) do
                local prior=old.objectives and old.objectives[index]
                if not prior or prior.numFulfilled~=value.numFulfilled or prior.finished~=value.finished then difference=true; break end
            end
        end
        if difference then
            changed[#changed+1]=id
            if #changed==40 then break end
        end
    end
    if #changed>0 then append({event="observed-progress",questIDs=changed,observedAt=snapshot.observedAt}) end
end
function journal.Dialog() return schema.Clone(dialog) end
function journal.Export() return {entries=schema.Clone(entries),dropped=dropped,scope="session-only"} end
