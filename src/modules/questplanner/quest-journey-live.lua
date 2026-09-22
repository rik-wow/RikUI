-- A compact live adapter for the first planned journey; no transport facts are invented.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local live={}
planner.JourneyLive=live
local serial=0
local function bindJourney(state,model)
    if not model.selected or model.selected.kind=="travel" then
        if not state.base then return nil end
    else state.base=schema.Clone(model.selected) end
    state.boundModel=model;state.renderDirty=true
    if not state.view then state.view=state.cursor:Snapshot() end
    return state
end
function live.Detach(state)
    if state then state.boundModel=nil;state.renderDirty=true end
end
function live.Attach(model,result,data,context,origin,previous)
    local first=result.actions and result.actions[1]
    local travel=first and first.travel
    if not data or not travel or not travel.path or #travel.path==0 then return nil end
    if not model.selected then return nil end
    local function reject(reason)
        model.selected.destination=nil;model.selected.targetHint=nil;model.selected.suppressSteering=true
        model.selected.detail="Travel instructions need a complete verified route: "..tostring(reason)
        if model.stops and model.stops[1] then model.stops[1]=schema.Clone(model.selected) end
        return nil
    end
    local expected=origin and origin.id
    for _,leg in ipairs(travel.path) do
        if not leg.from or not leg.to or (expected and leg.from~=expected) then return reject("disconnected leg") end
        expected=leg.to
    end
    if not first.node or expected~=first.node then return reject("action endpoint mismatch") end
    local parts={data:Revision(),tostring(first.id),tostring(first.node)}
    for _,leg in ipairs(travel.path) do
        parts[#parts+1]=table.concat({leg.id,leg.from,leg.to,leg.mode,leg.source and leg.source.id or ""},":")
    end
    local key=table.concat(parts,"|")
    if previous and previous.key==key then return bindJourney(previous,model) end
    local nodes={}
    local function node(id)
        if not nodes[id] then
            nodes[id]=data.NavigationNode and data:NavigationNode(id) or data:Node(id)
            if not nodes[id] and origin and id==origin.id then nodes[id]=schema.Clone(origin) end
        end
        return nodes[id]
    end
    serial=serial+1
    local cursor,reason=planner.Journey.New(data:Identity(),serial,travel.path,node)
    if not cursor then return reject(reason) end
    return bindJourney({cursor=cursor,key=key,generation=serial,identity=data:Identity(),nodes=nodes,
        sequence=0,nextAt=0},model)
end
function live.Tick(state,model,paused)
    if not state then return false end
    local frame=planner.Context.Frame and planner.Context.Frame()
    if frame and frame.time and frame.time>=state.nextAt then
        state.nextAt=frame.time+.1;state.sequence=state.sequence+1
        local before=state.cursor:Snapshot()
        local arrivals={}
        if planner.Terrain and planner.Terrain.Arrival then
            for _,id in pairs({before.from,before.to}) do
                local node=state.nodes[id]
                local receipt=node and planner.Terrain.Arrival(node,frame,state.sequence)
                if receipt then arrivals[id]=receipt end
            end
        end
        local value=state.cursor:Observe({identity=state.identity,generation=state.generation,
            sequence=state.sequence,time=frame.time,taxi=frame.taxi,paused=paused,arrivals=arrivals})
        state.view=value
        local mark=table.concat({value.index or 0,value.phase,tostring(value.suppressSteering),tostring(value.complete)},":")
        if mark~=state.mark then state.mark=mark;state.renderDirty=true end
    end
    if paused or not model or state.boundModel~=model or not model.selected
        or model.status=="paused" or model.status=="updating" or model.status=="unavailable"
        or not state.view or not state.renderDirty then return false end
    local value=state.view
    local selected=schema.Clone(state.base)
    if not value.complete then
        selected.actionKind=selected.kind;selected.kind="travel";selected.journey=value
        selected.destination=schema.Clone(value.destination);selected.suppressSteering=value.suppressSteering
        selected.targetHint=nil;selected.stepID="journey:"..state.generation..":"..(value.index or 0)
        selected.stepIdentity="travel-leg"
        local node=value.destination and state.nodes[value.destination.id]
        if selected.destination and node and node.terrain then
            selected.destination.terrainHeight=node.terrain.height
            selected.destination.corpusRevision=node.terrain.revision
        end
        selected.detail=live.Instruction(value).text
    end
    model.selected=selected
    if model.stops and model.stops[1] then model.stops[1]=schema.Clone(selected) end
    state.renderDirty=false
    return true
end
function live.Instruction(value)
    if not value then return nil end
    local mode=value.mode=="flight" and "flight" or value.mode=="hearth" and "hearthstone" or value.mode=="elevator" and "elevator" or "transport"
    local labels={approach="Go to the "..mode.." departure",walking="Follow the walking route",
        waiting="Board the "..mode,riding="Stay on the "..mode,exiting="Leave the "..mode.." at the destination",
        ["riding-unknown"]="Travel in progress; destination unconfirmed",recovery="Travel changed; choose a new route",arrived="Continue the quest action"}
    return {text=labels[value.phase] or "Continue the journey",
        subtext=value.needsReplan and "Refresh guidance from a known location" or value.phase=="waiting" and "Waiting for observed boarding" or "Travel step; quest action remains pending",
        ending=value.suppressSteering}
end
