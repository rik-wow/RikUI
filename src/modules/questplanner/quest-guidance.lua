-- Presentation-independent live choices and material-change signatures.
local planner, schema = RikUI.QuestPlanner, RikUI.QuestPlanner.Schema
local guidance={}
planner.Guidance=guidance
local function plain(value)
    if not schema.Text(value) then return "?" end
    return value:gsub("|",""):gsub("[%z\1-\31]"," "):sub(1,240)
end
guidance.Text=plain
function guidance.Signature(snapshot,status,ctx,dialog)
    if not snapshot or not ctx then return status.state end
    local parts={status.state,snapshot.identity.build,snapshot.identity.locale,snapshot.coverage,
        tostring(snapshot.reportedCount),tostring(ctx.position and ctx.position.mapID)}
    for _,key in ipairs({"class","race","faction","level","xp","xpMax","logCapacity"}) do parts[#parts+1]=tostring(ctx.attributes[key]) end
    for _,id in ipairs(snapshot.order) do
        local row=snapshot.quests[id]
        parts[#parts+1]=id..":"..tostring(row.objectivesComplete)..":"..tostring(row.failed)..":"..plain(row.title)
        for _,objective in ipairs(row.objectives or {}) do
            parts[#parts+1]=plain(objective.text)..":"..objective.numFulfilled.."/"..objective.numRequired..":"..tostring(objective.finished)
        end
        local point,reward=ctx.destinations[id],ctx.rewards[id]
        if point then parts[#parts+1]=string.format("%d:%.5f:%.5f",point.mapID,point.x,point.y) end
        if reward then parts[#parts+1]="xp:"..reward.xp..":"..tostring(reward.level) end
        parts[#parts+1]=tostring(ctx.history[id])
    end
    if dialog then parts[#parts+1]=dialog.event..":"..dialog.questID..":"..tostring(dialog.xp)..":"..tostring(dialog.npcID) end
    return table.concat(parts,";")
end
function guidance.Observed(snapshot,ctx,policy,previous)
    local rows={}
    for _,id in ipairs(snapshot.order) do
        local quest,point=snapshot.quests[id],ctx.destinations[id]
        if not policy.skips[id] and quest.failed~=true and not (point and policy.avoids[point.mapID]) then
            local detail
            for _,objective in ipairs(quest.objectives or {}) do if not objective.finished then detail=objective.text; break end end
            rows[#rows+1]={questID=id,title=plain(quest.title),kind=quest.objectivesComplete and "turnin" or "objective",
                detail=plain(detail or (quest.objectivesComplete and "Ready to turn in" or "Check the quest log")),
                destination=schema.Clone(point),pinned=policy.pins[id]==true}
        end
    end
    table.sort(rows,function(a,b)
        if a.pinned~=b.pinned then return a.pinned end
        if a.kind~=b.kind then return a.kind=="turnin" end
        if (a.questID==previous)~=(b.questID==previous) then return a.questID==previous end
        return a.questID<b.questID
    end)
    while #rows>40 do table.remove(rows) end
    return rows
end
function guidance.DialogInput(snapshot,status,ctx,dialog)
    if not dialog or dialog.event~="QUEST_COMPLETE" or not snapshot.quests[dialog.questID] or not ctx.position then return nil end
    local state=planner.Eligibility.FromSnapshot(snapshot,status,ctx.attributes,ctx.history)
    if not state then return nil end
    state.xp,state.xpMax=ctx.attributes.xp,ctx.attributes.xpMax
    state.node="interaction"
    state.travel={identity=schema.Clone(state.identity),departure=ctx.observedAt,flights={},transport={}}
    local source=schema.Clone(state.identity); source.id="live-dialog"; source.authority="verified"
    local row={id="turnin-"..dialog.questID,questID=dialog.questID,kind="turnin",node="interaction",
        zoneID=ctx.position.mapID,title=dialog.title,xp=dialog.xp,xpLevel=dialog.xp and dialog.level or nil,
        source=source,duration={combat=0,looting=0,interaction=3,downtime=0},risk=0,uncertainty=.05}
    local actions=planner.Actions.New(snapshot.identity,{row})
    if not actions then return nil end
    return {state=state,actions=actions}
end
function guidance.Result(route,observed,ctx,data,reason,policy)
    local first=route.actions and route.actions[1]
    local selected
    if first then
        local node=data and data:Node(first.node)
        for _,row in ipairs(observed) do if row.questID==first.questID then selected=schema.Clone(row); break end end
        selected=selected or {questID=first.questID,title=plain(first.title),kind=first.kind}
        selected.destination=node and node.mapID and {mapID=node.mapID,x=node.x,y=node.y} or selected.destination
        selected.detail=first.kind=="turnin" and "Turn in this quest" or first.kind=="pickup" and "Accept this quest" or "Continue this objective"
    else selected=observed[1] and schema.Clone(observed[1]) end
    local calculated=first~=nil
    local detail=calculated and (route.unknownXP>0 and "XP estimate incomplete" or "Calculated from available evidence")
        or "Walking route is not verified"
    if route.limited then detail=detail.."; search limit reached" end
    local deferred,seen={},{}
    for _,id in ipairs(route.deferredPins or {}) do if not seen[id] then deferred[#deferred+1]=id; seen[id]=true end end
    if not calculated then
        for id,pinned in pairs(policy and policy.pins or {}) do
            if pinned then
                if not seen[id] then deferred[#deferred+1]=id; seen[id]=true end
                local point=ctx.destinations[id]
                if policy.skips[id] or (point and policy.avoids[point.mapID]) then route.status="constraint-conflict" end
            end
        end
        table.sort(deferred)
    end
    if route.status=="constraint-conflict" then detail="A pinned quest conflicts with a skip or avoided area"; selected=nil end
    local stops={}
    if calculated and data then
        for _,action in ipairs(route.actions) do
            local node=data:Node(action.node)
            if node and node.mapID then
                stops[#stops+1]={questID=action.questID,title=plain(action.title),destination={mapID=node.mapID,x=node.x,y=node.y}}
            end
        end
    end
    if #stops==0 and selected then stops[1]=schema.Clone(selected) end
    return {status=route.status=="constraint-conflict" and route.status or calculated and route.status or "observed",selected=selected,quests=observed,stops=stops,calculated=calculated,
        detail=detail,reason=reason,limited=route.limited,seconds=calculated and route.seconds or nil,
        xp=calculated and route.gainedXP or nil,unknownXP=route.unknownXP,metrics=route.metrics,
        deferredPins=deferred,position=ctx.position}
end
