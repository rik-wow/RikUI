-- Presentation-independent live choices and material-change signatures.
local planner, schema = RikUI.QuestPlanner, RikUI.QuestPlanner.Schema
local guidance={}
planner.Guidance=guidance
local function plain(value,limit)
    if not schema.Text(value) then return "?" end
    return value:gsub("|",""):gsub("[%z\1-\31]"," "):sub(1,limit or 240)
end
guidance.Text=plain
function guidance.Details(model,snapshot,route)
    local selected=model.selected
    if selected and selected.journey and planner.JourneyLive then return planner.JourneyLive.Instruction(selected.journey).text.."\n"..planner.JourneyLive.Instruction(selected.journey).subtext end
    if not selected then return model.detail or "Choose a quest to see its instructions." end
    local quest=snapshot and snapshot.quests and snapshot.quests[selected.questID]
    local lines={plain(quest and quest.title or selected.title,2048),plain(selected.detail,2048)}
    for _,objective in ipairs(quest and quest.objectives or {}) do
        lines[#lines+1]=(objective.finished and "Done: " or "Objective: ")..plain(objective.text,2048)
    end
    if selected.step and selected.step.active then
        local action=selected.step.active
        lines[#lines+1]="Next action: "..plain(action.text or action.kind)
        if selected.step.state=="blocked" then lines[#lines+1]="Waiting for quest prerequisites."
        elseif selected.step.state=="unknown" then lines[#lines+1]="Check the quest log; step evidence is incomplete." end
    end
    if selected.hunt then
        lines[#lines+1]=plain(selected.hunt.instructions or selected.hunt.text,2048)
        lines[#lines+1]=plain(selected.hunt.basis,2048)
    end
    if selected.semantic then
        lines[#lines+1]=plain(selected.semantic.instructions,2048)
        lines[#lines+1]=plain(selected.semantic.basis,2048)
    end
    for _,note in ipairs(selected.referenceAdvice and selected.referenceAdvice.lines or {}) do
        lines[#lines+1]="Source note: "..plain(note,240)
    end
    local hint=selected.targetHint
    if hint and hint.instructions then
        lines[#lines+1]="Reported interaction: "..plain(hint.instructions,2048)
        lines[#lines+1]="Current access, inventory and timing are unverified."
    end
    local floor=route and route.destinationFloor
    if floor then lines[#lines+1]=floor.basis or (floor.label.." chosen by you; target floor is unverified.") end
    if route and route.detail then lines[#lines+1]=route.detail end
    return table.concat(lines,"\n")
end
local TERRAIN_STATUS={hunting="Look for quest targets nearby",loading="Preparing terrain guidance",ready="No walking route selected",["unavailable-position"]="Your position is unavailable",updating="Updating walking route",
    calculating="Calculating walking route",modeled="Terrain route estimate",["modeled-approach"]="Approach estimate; final gap unverified",
    ["outside-coverage"]="Outside terrain map coverage",["no-known-path"]="No connected route in terrain model",
    ["coverage-frontier"]="Route coverage needs a nearer waypoint or retry",["budget-exhausted"]="Walking route search reached its limit",invalid="Terrain guidance is unavailable",
    unavailable="Terrain data is unavailable",disabled="Quest planner is disabled",cancelled="Updating walking route"}
function guidance.RouteStatus(model,terrain)
    if model.status=="paused" then return "Paused" end
    if model.calculated or model.status~="observed" or not model.selected or not model.selected.destination then
        return model.detail or "Quest guidance is unavailable"
    end
    if not terrain or (terrain.status=="unavailable" and terrain.detail=="Terrain datasource is not installed") then
        return "Terrain datasource is not installed"
    end
    if terrain.status=="unknown-location" then
        if (terrain.detail or ""):find("ambiguous",1,true) then return "Your floor is uncertain" end
        if (terrain.detail or ""):find("disagree",1,true) then return "Player location is inconsistent" end
        return "Your position is outside the walking model"
    end
    if terrain.status=="unknown-target" then
        if (terrain.detail or ""):find("ambiguous",1,true) then return "Quest marker floor is uncertain" end
        return "Quest marker is outside the walking model"
    end
    if terrain.status=="modeled-approach" and terrain.detail=="Approach; quest floor is uncertain" then
        return "Follow approach; check quest floor"
    end
    return TERRAIN_STATUS[terrain.status] or "Walking route is unavailable"
end
local COMPASS={"N","NE","E","SE","S","SW","W","NW"}
local function distanceText(yards) return string.format("%d yd",math.max(0,math.floor(yards+.5))) end
local function facingText(bearing,facing)
    if not schema.Number(facing,0,math.pi*2) then
        return "Head "..COMPASS[math.floor((-bearing%(2*math.pi))/(math.pi/4)+.5)%8+1]
    end
    local angle=(bearing-facing+math.pi)%(2*math.pi)-math.pi
    local size=math.abs(angle)
    if size>math.pi*.75 then return "Turn around" end
    if size>math.pi/3 then return angle<0 and "Turn right" or "Turn left" end
    if size>math.pi/9 then return angle<0 and "Bear right" or "Bear left" end
    return "Continue ahead"
end
local function ending(route,distance)
    if route.hunt then return {text=route.hunt.text,subtext=route.hunt.source=="observed-progress"
        and "Continue hunting nearby" or route.hunt.nearby or "Search nearby for targets",distance=distance,ending=true} end
    if route.destinationFloor then
        local inferred=route.destinationFloor.source=="quest-text-model-inference"
        return {text=route.destinationFloor.label..(inferred and " approach reached" or " reached"),
            subtext="Check the quest target",distance=distance,ending=true}
    end
    local floors=route.approach and (route.approach.kind=="observed-marker-common-approach"
        or route.approach.kind=="observed-marker-uncertain-vicinity")
    if floors and route.floorChoiceAvailable then return {text="Choose destination floor",
        subtext="Use the Floor button",distance=distance,ending=true} end
    return {text=floors and "Check the quest floor" or "Route ends nearby",
        subtext=floors and "Marker covers multiple floors" or "Check the quest target",distance=distance,ending=true}
end
-- Distances are to the current steering aim, not invented named turns or interactions.
function guidance.Instruction(route,position,facing,width,height)
    if route and route.searching then return ending(route,0) end
    local point=route and route.next
    if not point or not position or point.mapID~=position.mapID
        or not schema.Number(width,1,100000) or not schema.Number(height,1,100000)
        or not schema.Number(point.x,0,1) or not schema.Number(point.y,0,1)
        or not schema.Number(position.x,0,1) or not schema.Number(position.y,0,1) or not math.atan2 then return nil end
    local dx,dy=(point.x-position.x)*width,(point.y-position.y)*height
    local distance=math.sqrt(dx*dx+dy*dy)
    local remaining=route.meters
    if schema.Number(remaining,0,1000000) and remaining<=2 and distance<=2 then return ending(route,distance) end
    local bearing=math.atan2(-dx,-dy)
    local text=facingText(bearing,facing).." · "..distanceText(distance)
    local subtext=schema.Number(remaining,0,1000000) and ("~"..distanceText(remaining).." remaining") or "Follow the route"
    if route.destinationFloor then subtext=route.destinationFloor.label.." · "..subtext end
    return {text=text,subtext=subtext,distance=distance,bearing=bearing}
end
function guidance.MarkerInstruction(point,position,width,height,state)
    local hint=guidance.Instruction({next=point},position,nil,width,height)
    if not hint then return nil end
    local compass=COMPASS[math.floor((-hint.bearing%(2*math.pi))/(math.pi/4)+.5)%8+1]
    local status=state and state.status
    local detail=status=="loading" and "Route loading"
        or ((status=="calculating" or status=="updating") and "Finding walking route")
        or "No walking route"
    return {text="Marker "..compass.." · "..distanceText(hint.distance),
        subtext=detail,distance=hint.distance,markerOnly=true}
end
local function signatureField(parts,value)
    if parts.limited then return end
    local text=type(value)..":"..tostring(value)
    text=#text..":"..text
    if parts.bytes+#text>131072 then parts.limited=true;return end
    parts.bytes=parts.bytes+#text;parts[#parts+1]=text
end
local function questSignature(parts,id,row,ctx)
    for _,value in ipairs({"quest",id}) do signatureField(parts,value) end
    signatureField(parts,row.objectivesComplete);signatureField(parts,row.failed)
    signatureField(parts,row.level);signatureField(parts,row.title)
    signatureField(parts,row.objectives~=nil)
    for _,objective in ipairs(row.objectives or {}) do
        signatureField(parts,"objective");signatureField(parts,objective.text)
        signatureField(parts,objective.type);signatureField(parts,objective.numFulfilled)
        signatureField(parts,objective.numRequired);signatureField(parts,objective.finished)
    end
    local point,reward=ctx.destinations[id],ctx.rewards[id]
    if point then
        signatureField(parts,string.format("point:%d:%.17g:%.17g",point.mapID,point.x,point.y))
        signatureField(parts,point.api);signatureField(parts,point.scope)
    end
    if reward then
        signatureField(parts,"reward");signatureField(parts,reward.xp);signatureField(parts,reward.level)
    end
    signatureField(parts,ctx.history[id])
end
function guidance.Signature(snapshot,status,ctx,dialog)
    if not snapshot or not ctx then return status.state end
    local parts={bytes=0}
    signatureField(parts,planner.Hunts and planner.Hunts.Revision())
    signatureField(parts,planner.SemanticData and planner.SemanticData.Revision())
    signatureField(parts,planner.SemanticGuidance and planner.SemanticGuidance.Revision())
    for _,value in ipairs({status.state,snapshot.identity.product,snapshot.identity.build,snapshot.identity.locale,
        snapshot.coverage,snapshot.reportedCount}) do signatureField(parts,value) end
    signatureField(parts,ctx.position and ctx.position.mapID)
    local items={}
    for id in pairs(ctx.inventory or {}) do items[#items+1]=id end
    table.sort(items)
    for _,id in ipairs(items) do signatureField(parts,"item:"..id);signatureField(parts,ctx.inventory[id]) end
    for _,key in ipairs({"class","race","faction","level","xp","xpMax","logCapacity"}) do signatureField(parts,ctx.attributes[key]) end
    for _,id in ipairs(snapshot.order) do
        questSignature(parts,id,snapshot.quests[id],ctx)
        if parts.limited then return nil,"Quest observations exceed the planning size limit" end
    end
    if dialog then
        for _,key in ipairs({"event","questID","xp","npcID"}) do signatureField(parts,dialog[key]) end
    end
    if parts.limited then return nil,"Quest observations exceed the planning size limit" end
    return table.concat(parts)
end
function guidance.Observed(snapshot,ctx,policy,previous,includeExcluded)
    local rows={}
    for _,id in ipairs(snapshot.order) do
        local quest,point=snapshot.quests[id],ctx.destinations[id]
        if includeExcluded or (not policy.skips[id] and quest.failed~=true and not (point and policy.avoids[point.mapID])) then
            local detail
            for _,objective in ipairs(quest.objectives or {}) do if not objective.finished then detail=objective.text; break end end
            local hint=planner.Targets and planner.Targets.Match(snapshot,id,point)
            local step=planner.Steps and planner.Steps.ObservedQuest(snapshot,id,ctx)
            local hunt
            local semantic
            if planner.SemanticGuidance and not hint then
                local target,area,claim=planner.SemanticGuidance.Apply(snapshot,id,point,step)
                if claim then point,hunt,semantic=target,area,claim end
            end
            if semantic and step then step.navigation=hunt or step.navigation end
            if planner.Hunts then
                local target,area=planner.Hunts.Destination(snapshot,id,step,point)
                point=target;hunt=area or hunt
            end
            local stage={bytes=0}
            questSignature(stage,id,quest,ctx)
            rows[#rows+1]={questID=id,title=plain(quest.title),kind=quest.objectivesComplete and "turnin" or "objective",
                destinationSignature=not stage.limited and table.concat(stage) or nil,
                detail=plain(hint and hint.detail or detail or (quest.objectivesComplete and "Ready to turn in" or "Check the quest log")),
                step=step,stepID=step and step.stepID,stepIdentity="quest-marker",
                targetHint=hint,hunt=hunt,semantic=semantic,
                referenceAdvice=planner.SemanticGuidance and schema.Clone(planner.SemanticGuidance.Advice(snapshot,id)),destination=schema.Clone(point),pinned=policy.pins[id]==true,
                skipped=policy.skips[id]==true,avoided=point and policy.avoids[point.mapID]==true or false,failed=quest.failed==true}
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
        selected.hunt=nil -- Authored optimizer actions retain their explicit destination semantics.
        selected.detail=first.kind=="turnin" and "Turn in this quest" or first.kind=="pickup" and "Accept this quest" or "Continue this objective"
    else selected=observed[1] and schema.Clone(observed[1]) end
    local calculated=first~=nil
    local detail=calculated and (route.unknownXP>0 and "XP estimate incomplete" or "Calculated from available evidence")
        or "Walking route is not verified"
    if not calculated and selected and not selected.destination then detail="Quest location is unavailable" end
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
    local stops,validUntil={},nil
    for _,action in ipairs(route.actions or {}) do
        for _,leg in ipairs(action.travel and action.travel.path or {}) do
            local lift=leg.elevator
            if lift then
                local deadline=math.min(lift.expiresAt,lift.departAt-lift.board)
                validUntil=validUntil and math.min(validUntil,deadline) or deadline
            end
        end
    end
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
        deferredPins=deferred,position=ctx.position,validUntil=validUntil}
end
