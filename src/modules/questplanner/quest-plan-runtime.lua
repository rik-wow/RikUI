-- Ordinary corpus planning adapter, live reconciliation and bounded durable learning.
local core,planner=RikUI,RikUI.QuestPlanner
local schema,runtime=planner.Schema,{}
planner.PlanRuntime=runtime
local bound,lastSnapshot,lastContext,lastAction,lastSave,lastTrace,currentState
local restored=false
local function save(ctx)
    if not core.CharDB then return end
    if lastSave and ctx.observedAt and ctx.observedAt-lastSave<30 then return end
    core.CharDB.questPlanMemory=planner.PlanLearning.Export(true)
    lastSave=ctx.observedAt
    if core.Changed then core:Changed() end
end
local function distance(a,b,frame)
    if not a or not b or a.mapID~=b.mapID or not frame or not frame.position or frame.position.mapID~=a.mapID or not frame.width or not frame.height then return end
    return math.sqrt(((a.x-b.x)*frame.width)^2+((a.y-b.y)*frame.height)^2)
end
function runtime.Observe(snapshot,ctx,policy)
    local identity=table.concat({snapshot.identity.product,snapshot.identity.build,snapshot.identity.locale,ctx.characterKey or "session"},":")
    if identity~=bound then
        planner.PlanLearning.Bind(snapshot.identity,ctx.characterKey)
        bound=identity;lastSnapshot,lastContext,lastAction,lastSave=nil,nil,nil,nil;restored=false
        if core.CharDB and core.CharDB.questPlanMemory then restored=planner.PlanLearning.Restore(core.CharDB.questPlanMemory) end
    end
    local frame=planner.Context.Frame and planner.Context.Frame()
    local elapsed=lastContext and ctx.observedAt and lastContext.observedAt and ctx.observedAt-lastContext.observedAt
    local moved=lastContext and distance(lastContext.position,ctx.position,frame)
    local usable=elapsed and elapsed>0 and elapsed<=120 and not policy.paused and not ctx.afk and not ctx.dead
    if usable and lastAction and lastSnapshot and moved and moved<80 then
        local before=lastSnapshot.quests[lastAction.questID]
        local after=snapshot.quests[lastAction.questID]
        local index=lastAction.liveIndex
        local a=before and before.objectives and before.objectives[index or 0]
        local b=after and after.objectives and after.objectives[index or 0]
        if a and b and a.type==b.type and a.numRequired==b.numRequired and b.numFulfilled>a.numFulfilled then
            local state={identity=snapshot.identity,class=ctx.attributes.class,level=ctx.attributes.level,partySize=ctx.partySize}
            local kind=lastAction.method=="kill" and "combat" or "collection"
            planner.PlanLearning.Observe(kind,planner.PlanCosts.Context(lastAction,state),elapsed,b.numFulfilled-a.numFulfilled)
            planner.PlanLearning.Activity(lastAction.activity or lastAction.method or "objective")
            planner.PlanLearning.Failure(lastAction.id,false)
        end
    end
    if usable and elapsed<=30 and moved and moved>2 and moved/elapsed>=2 and moved/elapsed<=15 and not ctx.inCombat then
        local key=snapshot.identity.build..":"..ctx.position.mapID..":foot"
        planner.PlanLearning.Observe("travel",key,elapsed,moved)
    end
    if ctx.position then planner.PlanLearning.Visit(ctx.position.mapID) end
    local learned=planner.PlanLearning.State()
    ctx.visited,ctx.recent,ctx.failures,ctx.rememberedCompleted=learned.visited,learned.recent,learned.failures,learned.completed
    lastSnapshot,lastContext=snapshot,ctx
    save(ctx)
end
function runtime.OnEvent(event,...)
    if event=="PLAYER_LOGOUT" and core.CharDB then
        core.CharDB.questPlanMemory=planner.PlanLearning.Export(true)
        if core.Changed then core:Changed() end
    elseif event=="QUEST_TURNED_IN" then planner.PlanLearning.Activity("turnin");planner.PlanLearning.Completion(select(1,...),true);lastSave=nil
    elseif event=="QUEST_ACCEPTED" then planner.PlanLearning.Completion(select(1,...),false);lastSave=nil
    elseif event=="PLAYER_DEAD" and lastAction then planner.PlanLearning.Failure(lastAction.id,true) end
end
function runtime.Feedback(kind,actionID)
    if kind=="unavailable" then
        if not actionID and lastAction then actionID=lastAction.id end
        if not actionID then return nil,"No current action" end
        planner.PlanLearning.Failure(actionID,true)
        return true
    elseif kind=="retry" then
        planner.PlanLearning.Failure(actionID or lastAction and lastAction.id,false);return true
    elseif kind=="reset-learning" then planner.PlanLearning.Reset("estimates");lastSave=nil;return true
    elseif kind=="reset-history" then planner.PlanLearning.Reset("history");lastSave=nil;return true end
    return nil,"Unknown feedback"
end
function runtime.Replay()
    return schema.CopyLimited(lastTrace,32768,524288,16)
end
function runtime.Status()
    return {restored=restored,persistence=core.CharDB and "SavedVariables with configured persistence fallback" or "session-only",
        learning=planner.PlanLearning.Export(true),trace=lastTrace}
end
function runtime.Begin(snapshot,status,ctx,records,observed,policy)
    local state,problem=planner.PlanState.Build(snapshot,status,ctx,records,policy)
    if not state then return nil,problem end
    currentState=state
    local graphJob=planner.PlanGraph.Begin(state,records,observed,policy)
    if not graphJob then return nil,"Future graph unavailable" end
    local searchJob,graph,cancelled,steps,lastPreview
    steps=0
    local frame=planner.Context.Frame and planner.Context.Frame()
    local prior=planner.Controller and planner.Controller.Peek()
    local environment={mapSizes={},previousID=prior and prior.actionID}
    local replayLearning=planner.PlanLearning.Export()
    if frame and frame.position and frame.width and frame.height then
        environment.mapSizes[frame.position.mapID]={frame.width,frame.height}
    end
    -- Strategic costs never publish a walking route. The terrain follower owns continuous navigation.
    local function annotate(result)
        if not result then return end
        result.adaptive=true;result.stateKey=planner.PlanState.Key(state)
        result.replayState=state;result.replayEnvironment=environment;result.replayLearning=replayLearning;result.candidateIDs={}
        for _,action in ipairs(graph and graph.actions or {}) do result.candidateIDs[#result.candidateIDs+1]=action.id end
        return result
    end
    return {state=state,Cancel=function()
        cancelled=true;graphJob:Cancel();if searchJob then searchJob:Cancel() end
    end,Peek=function()
        if searchJob then lastPreview=annotate(searchJob:Peek());return lastPreview end
    end,Step=function()
        if cancelled then return {status="cancelled",adaptive=true} end
        steps=steps+1
        if steps>50000 then
            if searchJob then searchJob:Cancel() end
            local result=lastPreview or {actions={},status="ready",reason="Planning budget exhausted"}
            result.limited=true;return annotate(result)
        end
        if not graph then
            graph=graphJob:Step(1)
            if graph then
                if graph.status~="ready" then return annotate(graph) end
                searchJob,problem=planner.PlanSearch.Begin(graph,state,policy,environment)
                if not searchJob then return annotate({status="error",reason=problem}) end
            end
            return
        end
        return annotate(searchJob:Step(1))
    end}
end
function runtime.Valid(action,policy)
    return currentState and planner.PlanTransitions.Check(action,currentState,policy)==true or false
end
local function actionRow(action,observed,state,prior)
    local row
    for _,candidate in ipairs(observed) do if candidate.questID==action.questID then row=schema.Clone(candidate);break end end
    row=row or {questID=action.questID,title=planner.Guidance.Text(action.title or action.instruction or "Optional service")}
    if prior and prior.actionID==action.id and prior.planAction and prior.planAction.sourceRevision==action.sourceRevision then
        for _,key in ipairs({"destination","hunt","semantic","targetHint","stepID","stepIdentity","destinationSignature"}) do
            row[key]=schema.Clone(prior[key])
        end
    end
    local oldKind=row.kind
    row.kind=action.kind;row.actionID=action.id;row.detail=planner.Guidance.Text(action.instruction)
    row.completionEvidence=action.completionEvidence;row.recovery=action.recovery
    row.sourceSuggestion=action.authority=="reference"
    row.progressText=action.progressText
    if action.kind=="objective" then
        local info=state.objectiveInfo[action.questID] and state.objectiveInfo[action.questID][action.objectiveKey]
        action.liveIndex=info and info.index
        -- Keep the established live route to this objective while counts change.
        local waypoint=row.destination and row.destination.scope=="current-waypoint"
        local sameTarget=row.semantic and row.semantic.objectiveKey==action.objectiveKey
            and row.semantic.targetID==(action.target and action.target.id) and row.semantic.method==action.method
        if not waypoint and (not row.destination or oldKind~=action.kind or not sameTarget) then
            row.destination=schema.Clone(action.destination or row.destination)
            row.hunt,row.semantic,row.targetHint=nil,nil,nil
        end
    else
        local sameTarget=row.semantic and row.semantic.targetID==(action.target and action.target.id)
            and row.semantic.method==action.method
        local waypoint=row.destination and row.destination.scope=="current-waypoint"
        if not row.destination or oldKind~=action.kind or not sameTarget and not waypoint then
            row.destination=schema.Clone(action.destination or row.destination)
            row.hunt,row.semantic,row.targetHint=nil,nil,nil
        end
    end
    row.destinationSignature=row.destinationSignature or action.id
    row.planAction=action
    return row
end
function runtime.Result(result,observed,ctx,policy,prior,state)
    local commitment=result.commitment
    local retained=false
    if prior and commitment and commitment.score and result.score and prior.flavor==policy.flavor
        and result.score-commitment.score<math.max(1,math.abs(commitment.score)*.15)
        and (not result.baselineEfficiency or result.baselineEfficiency==0 or commitment.features.efficiency>=result.baselineEfficiency/(1+policy.detour))
        and not (policy.pins[result.actions and result.actions[1] and result.actions[1].questID]
            and not policy.pins[prior.selected and prior.selected.questID]) then
        local copy={};for key,value in pairs(result) do copy[key]=value end
        for key,value in pairs(commitment) do copy[key]=value end
        copy.reason="Continue the current feasible action";copy.efficiencyCost=nil
        result=copy;retained=true
    end
    local model=planner.Guidance.Result({actions={},status="insufficient-data"},observed,ctx,nil,result.reason,policy)
    model.adaptive=true;model.flavor=policy.flavor;model.sessionMinutes=policy.sessionMinutes
    model.planStatus=result.status;model.refining=result.status=="refining";model.reason=result.reason
    model.coverage=result.coverage;model.metrics=result.metrics;model.limited=result.limited
    model.upNext,model.alternatives,model.stops={},{},{}
    local first
    for _,action in ipairs(result.actions or {}) do
        if action.kind~="complete" then
            local row=actionRow(action,observed,state,not first and prior and prior.selected)
            if not first then first=row
            elseif #model.upNext<3 then
                if not policy.spoilers and not state.active[action.questID] then
                    row.detail="Potential follow-up; confirm after current work"
                    row.title="Future quest"
                end
                model.upNext[#model.upNext+1]=row
            end
            if #model.stops<4 then model.stops[#model.stops+1]=row end
        end
    end
    if first then
        local feasible=planner.PlanTransitions.Check(first.planAction,state,policy)
        if feasible==true then
            model.selected=first;model.actionID=first.actionID
            model.status="observed" -- Terrain accepts this marker; no fabricated calculated walking path.
            model.detail=policy.flavor..": "..(result.reason or "Continue useful quest work")
            lastAction=first.planAction
        end
    end
    for _,alternative in ipairs(result.alternatives or {}) do
        if alternative.action and alternative.action.kind~="complete" then
            local row=actionRow(alternative.action,observed,state)
            row.seconds=alternative.seconds;row.conditional=alternative.conditional
            model.alternatives[#model.alternatives+1]=row
        end
    end
    model.retained=retained
    if prior and prior.actionID and model.actionID~=prior.actionID then
        model.change="Plan updated for "..policy.flavor.." and current quest state"
    end
    model.score=result.score;model.estimate={seconds=result.seconds,upper=result.upperSeconds,xp=result.xp,
        unknownXP=result.unknownXP,conditional=result.conditional,efficiencyCost=result.efficiencyCost,
        stoppingPoint=result.stoppingPoint}
    model.assumptions=result.assumptions;model.excluded=result.excluded
    model.conflicts={}
    for id in pairs(policy.pins) do
        local why=planner.Preferences.Conflict(policy,id,ctx.destinations[id] and ctx.destinations[id].mapID)
        if why then model.conflicts[#model.conflicts+1]=why end
    end
    if not model.selected then model.detail=result.reason or "Follow the live quest instructions while planning" end
    if #model.stops==0 and model.selected then model.stops[1]=model.selected end
    lastTrace={version=1,stateKey=result.stateKey,generation=result.generation,revision=result.revision,flavor=policy.flavor,
        constraints=schema.Clone(policy),state=result.replayState,environment=result.replayEnvironment,learning=result.replayLearning,candidateIDs=result.candidateIDs,actions={},costs=result.costs,excluded=result.excluded,metrics=result.metrics,
        reason=model.reason,score=result.score,conditional=result.conditional}
    for index,action in ipairs(result.actions or {}) do if index<=128 then lastTrace.actions[index]=action.id end end
    return model
end
