-- Ordinary corpus planning adapter, live reconciliation and bounded durable learning.
local core,planner=RikUI,RikUI.QuestPlanner
local schema,runtime=planner.Schema,{}
planner.PlanRuntime=runtime
local bound,lastSnapshot,lastContext,lastAction,lastSave,lastTrace,lastSearchTrace,currentState
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
        lastTrace,lastSearchTrace=nil,nil
        if core.CharDB and core.CharDB.questPlanMemory then restored=planner.PlanLearning.Restore(core.CharDB.questPlanMemory) end
    end
    local frame=planner.Context.Frame and planner.Context.Frame()
    local elapsed=lastContext and ctx.observedAt and lastContext.observedAt and ctx.observedAt-lastContext.observedAt
    local moved=lastContext and distance(lastContext.position,ctx.position,frame)
    local usable=elapsed and elapsed>0 and elapsed<=120 and not policy.paused and not ctx.afk and not ctx.dead
    if planner.PlanXP then
        local quest=lastAction and snapshot.quests and snapshot.quests[lastAction.questID]
        local eligible=quest and quest.failed~=true and lastAction.kind=="objective"
            and not policy.paused and not ctx.afk and not ctx.dead
            and (lastAction.method=="kill" or lastAction.method=="drop") and lastAction.target
            and ctx.position and ctx.position.mapID==lastAction.zoneID
        local key=eligible and planner.PlanCosts.Context(lastAction,{identity=snapshot.identity,class=ctx.attributes.class,
            level=ctx.attributes.level,partySize=ctx.partySize,equipmentKey=ctx.equipmentKey,xpRested=ctx.xpRested})
        planner.PlanXP.SetContext(eligible and {key=key,npcID=lastAction.target.id,playerGUID=ctx.characterKey,
            petGUID=ctx.petGUID,rested=ctx.xpRested},ctx.observedAt)
        planner.PlanXP.Tick(ctx.observedAt)
    end
    if planner.PlanObserver then planner.PlanObserver.Observe(snapshot,ctx,policy,lastAction) end
    if usable and elapsed<=30 and moved and moved>2 and moved/elapsed>=2 and moved/elapsed<=15 and not ctx.inCombat then
        local key=snapshot.identity.build..":"..ctx.position.mapID..":foot"
        planner.PlanLearning.Observe("travel",key,elapsed,moved)
    end
    if ctx.position then planner.PlanLearning.Visit(ctx.position.mapID) end
    if lastAction and lastAction.visitKey and not ctx.dead and not ctx.afk then
        local near=distance(lastAction.destination,ctx.position,frame)
        local node=lastAction.discoveryNode and ctx.travel and ctx.travel.flightNodes[lastAction.discoveryNode]
        if lastAction.discoveryNode then
            if node and node.undiscovered==false then planner.PlanLearning.VisitPlace(lastAction.visitKey) end
        elseif near and near<=20 then planner.PlanLearning.VisitPlace(lastAction.visitKey) end
    end
    local learned=planner.PlanLearning.State()
    ctx.visited,ctx.recent,ctx.failures,ctx.rememberedCompleted,ctx.places=learned.visited,learned.recent,learned.failures,learned.completed,learned.places
    lastSnapshot,lastContext=snapshot,ctx
    save(ctx)
end
function runtime.OnEvent(event,...)
    local resetEpisode
    if planner.PlanXP then
        local ok,at=planner.Context.Call(GetTime)
        if ok then resetEpisode=planner.PlanXP.OnEvent(event,at,...) end
    end
    if planner.PlanObserver then
        if resetEpisode then planner.PlanObserver.Reset() else planner.PlanObserver.OnEvent(event,...) end
    end
    if event=="PLAYER_LOGOUT" and core.CharDB then
        core.CharDB.questPlanMemory=planner.PlanLearning.Export(true)
        if core.Changed then core:Changed() end
    elseif event=="QUEST_TURNED_IN" then planner.PlanLearning.Activity("turnin");planner.PlanLearning.Completion(select(1,...),true);lastSave=nil
    elseif event=="QUEST_ACCEPTED" then planner.PlanLearning.Completion(select(2,...),false);lastSave=nil
    elseif event=="PLAYER_DEAD" and lastAction then planner.PlanLearning.Failure(lastAction.id,true) end
end
function runtime.Feedback(kind,actionID)
    if (kind=="waiting" or kind=="recovery") and planner.PlanObserver then return planner.PlanObserver.Feedback(kind) end
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
    return schema.CopyDiagnostic(lastTrace)
end
-- The current displayed decision and last completed solver run are distinct evidence.
function runtime.ReplaySearch()
    return schema.CopyDiagnostic(lastSearchTrace)
end
local SWITCH_REASONS={invalid=true,completed=true,better=true,pinned=true,["no-incumbent"]=true}
function runtime.Switches()
    local rows=type(RikUIDB)=="table" and RikUIDB.planSwitches
    local out={}
    if type(rows)=="table" then
        for i=math.max(1,#rows-49),#rows do
            local row=schema.CopyLimited(rows[i],128,4096,5)
            if row then out[#out+1]=row end
        end
    end
    return out
end
local function switchIdentity(model)
    if not model or not model.actionID then return nil end
    local title=model.selected and model.selected.title
    return {actionID=model.actionID,title=schema.Text(title) and title:sub(1,160) or model.actionID}
end
-- Called only by the controller's publication boundary, not speculative Result
-- projections or diagnostic replays.
function runtime.RecordSwitch(prior,model,ctx)
    if (prior and prior.actionID)==model.actionID then return end
    local reason=model.switchReason
    if not SWITCH_REASONS[reason] then reason=prior and prior.actionID and "invalid" or "no-incumbent" end
    local rows=runtime.Switches()
    local position=ctx and ctx.position
    rows[#rows+1]={time=ctx and ctx.observedAt or 0,from=switchIdentity(prior),to=switchIdentity(model),
        fromScore=model.incumbentScore or prior and prior.score,toScore=model.score,reason=reason,
        position=position and {mapID=position.mapID,x=position.x,y=position.y}}
    while #rows>50 do table.remove(rows,1) end
    if type(RikUIDB)~="table" then RikUIDB={} end
    RikUIDB.planSwitches=rows
end
function runtime.ClearReplay() lastTrace=nil end
function runtime.Status()
    return {restored=restored,persistence=core.CharDB and "SavedVariables with configured persistence fallback" or "session-only",
        learning=planner.PlanLearning.Export(true),trace=lastTrace}
end
function runtime.Begin(snapshot,status,ctx,records,observed,policy)
    local state,problem=planner.PlanState.Build(snapshot,status,ctx,records,policy)
    if not state then return nil,problem end
    currentState=state
    local prior=planner.Controller and (planner.Controller.Incumbent or planner.Controller.Peek)()
    local previousID=prior and prior.actionID
    local graphJob=planner.PlanGraph.Begin(state,records,observed,policy,previousID)
    if not graphJob then return nil,"Future graph unavailable" end
    local searchJob,graph,cancelled,steps,lastPreview
    steps=0
    local frame=planner.Context.Frame and planner.Context.Frame()
    local previousAction=prior and prior.selected and prior.selected.planAction
    local environment={mapSizes={},previousID=previousID,incumbent=schema.Clone(prior and prior.actionIDs or {}),
        previousAction=previousAction and {id=previousAction.id,questID=previousAction.questID,
            kind=previousAction.kind,objectiveKey=previousAction.objectiveKey}}
    local replayLearning=planner.PlanLearning.Export()
    if frame and frame.position and frame.width and frame.height then
        environment.mapSizes[frame.position.mapID]={frame.width,frame.height}
    end
    if planner.TravelEstimate then
        environment.travelModel=planner.TravelEstimate.Capture(state,environment.mapSizes)
        environment.travel=assert(planner.TravelEstimate.Open(environment.travelModel))
    end
    local replayEnvironment={mapSizes=environment.mapSizes,previousID=previousID,travelModel=environment.travelModel,
        incumbent=environment.incumbent,previousAction=environment.previousAction}
    -- Strategic costs never publish a walking route. The terrain follower owns continuous navigation.
    local function annotate(result)
        if not result then return end
        result.adaptive=true;result.stateKey=planner.PlanState.Key(state)
        result.replayGraph=graph and {version=graph.version,status=graph.status,identity=graph.identity,revision=graph.revision,coverage=graph.coverage,actions=graph.actions}
        result.replayState=state;result.replayEnvironment=replayEnvironment;result.replayLearning=replayLearning;result.candidateIDs={}
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
    action=schema.Clone(action) -- UI binding must not mutate the captured source graph.
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
local function replayIDs(actions)
    local out={}
    for _,action in ipairs(actions or {}) do out[#out+1]=action.id end
    return out
end
-- Scores are fractions of a level per hour. Require both relative gain and
-- five percentage points of a level/hour, with a stronger arrival commitment.
function runtime.SelectResult(result,policy,prior)
    if not prior or not prior.actionID then return result,false,"no-incumbent" end
    local first
    for _,action in ipairs(result.actions or {}) do if action.kind~="complete" then first=action;break end end
    if first and first.id==prior.actionID then return result,false end
    if result.previousStatus=="completed" or result.previousStatus=="invalid" then
        return result,false,result.previousStatus
    end
    if first and policy.pins[first.questID] and not policy.pins[prior.selected and prior.selected.questID] then
        return result,false,"pinned"
    end
    local commitment=result.commitment
    if not commitment or not commitment.score or not result.score then return result,false,"no-incumbent" end
    local margin=prior.nearDestination and .5 or .25
    local gain=result.score-commitment.score
    if gain>=.05 and gain>=math.abs(commitment.score)*margin then return result,false,"better" end
    local copy={};for key,value in pairs(result) do copy[key]=value end
    for key,value in pairs(commitment) do copy[key]=value end
    copy.reason="Continue the current feasible action";copy.efficiencyCost=nil
    return copy,true
end
local function selectedIdentity(row)
    return row and {questID=row.questID,kind=row.kind,actionID=row.actionID} or nil
end
function runtime.Displayed(model)
    return {status=model.status,actionID=model.actionID,selected=selectedIdentity(model.selected)}
end
local function decisionInputs(observed,ctx,policy,previous)
    local inputs={observed={},destinations={}}
    if observed[1] then inputs.observed[1]=selectedIdentity(observed[1]) end
    for id,pinned in pairs(policy.pins) do
        local point=pinned and ctx.destinations[id]
        if point then inputs.destinations[id]={mapID=point.mapID} end
    end
    if previous then
        inputs.previous={id=previous.id,questID=previous.questID,kind=previous.kind}
        inputs.previousFailures=(ctx.failures or {})[previous.id]
    end
    return schema.CopyLimited(inputs,2048,32768,6)
end
local UNAVAILABLE="This interaction is still unavailable. Choose another quest, or use Retry action when it becomes available."
-- Pure final choice; no publication, attribution, learning or live API reads.
function runtime.ProjectDecision(result,policy,prior,state,inputs)
    local retained,switchReason
    result,retained,switchReason=runtime.SelectResult(result,policy,prior)
    local fallback,conflict=planner.Guidance.Fallback(inputs.observed,inputs,policy)
    local display={status=conflict and "constraint-conflict" or "observed",selected=selectedIdentity(fallback)}
    local decision={mode=fallback and "fallback" or "none",displayed=display,switchReason=switchReason}
    local first
    for index,action in ipairs(result.actions or {}) do
        if action.kind~="complete" then first=action;decision.firstIndex=index;break end
    end
    if first and planner.PlanTransitions.Check(first,state,policy)==true then
        display.status="observed";display.actionID=first.id
        display.selected={questID=first.questID,kind=first.kind,actionID=first.id};decision.mode="planned"
    elseif not first and fallback and inputs.previous and (inputs.previousFailures or 0)>=2
        and fallback.questID==inputs.previous.questID and fallback.kind==inputs.previous.kind then
        display.status="unavailable";display.selected=nil;decision.mode="unavailable"
    end
    return result,retained,decision
end
local function traceResult(raw,result,model,state,policy,prior,inputs,retained)
    local kind=raw.decisionKind
    if kind~="fallback" and kind~="continuity" then
        if raw.replayGraph and raw.replayState and raw.replayEnvironment and raw.replayLearning
            and raw.metrics and schema.Integer(raw.metrics.work,0,48000) then kind="search" else return end
    end
    local sourceState=kind=="search" and raw.replayState or state
    local trace={version=3,kind=kind,source={searchRevision=planner.PlanSearch.REVISION,
        corpusRevision=sourceState.sourceRevision,identity=schema.Clone(sourceState.identity)},
        stateKey=raw.stateKey or planner.PlanState.Key(sourceState),state=sourceState,generation=sourceState.generation,
        revision=sourceState.sourceRevision,flavor=policy.flavor,constraints=schema.Clone(policy),
        replayPrior=prior,displayInputs=inputs,displayed=runtime.Displayed(model),retained=retained,
        actions=replayIDs(result.actions),candidateIDs={},reason=model.reason,score=result.score,conditional=result.conditional}
    if kind=="search" then
        trace.maxSteps=50000;trace.graph=raw.replayGraph;trace.environment=raw.replayEnvironment
        trace.learning=raw.replayLearning;trace.candidateIDs=raw.candidateIDs;trace.searchActions=replayIDs(raw.actions)
        trace.searchReason=raw.reason;trace.searchLimited=raw.limited==true;trace.searchStatus=raw.status
        trace.searchWork=raw.metrics.work;trace.costs=result.costs;trace.excluded=result.excluded;trace.metrics=result.metrics
    else
        trace.proposal={actions=schema.Clone(raw.actions or {}),status=raw.status,reason=raw.reason}
    end
    return trace
end
function runtime.Result(result,observed,ctx,policy,prior,state)
    local raw=result
    local inputs=decisionInputs(observed,ctx,policy,lastAction)
    if not inputs then error("Displayed decision inputs exceed their bounded schema") end
    local replayPrior=prior and {flavor=prior.flavor,actionID=prior.actionID,selected=prior.selected and {questID=prior.selected.questID},
        nearDestination=prior.actionID and planner.RoadGuidance and planner.RoadGuidance.NearDestination
            and planner.RoadGuidance.NearDestination(prior.actionID)==true or false}
    local retained,decision
    result,retained,decision=runtime.ProjectDecision(result,policy,replayPrior,state,inputs)
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
                if not policy.spoilers and action.questID>0 and not state.active[action.questID] then
                    row.detail="Potential follow-up; confirm after current work"
                    row.title="Future quest"
                end
                model.upNext[#model.upNext+1]=row
            end
            if #model.stops<4 then model.stops[#model.stops+1]=row end
        end
    end
    if decision.mode=="planned" then
        model.selected=first;model.actionID=first.actionID
        model.detail=policy.flavor..": "..(result.reason or "Continue useful quest work")
        lastAction=first.planAction
    elseif decision.mode=="none" or decision.mode=="unavailable" then model.selected=nil end
    model.status=decision.displayed.status
    model.actionID=decision.displayed.actionID
    for _,alternative in ipairs(result.alternatives or {}) do
        if alternative.action and alternative.action.kind~="complete" then
            local row=actionRow(alternative.action,observed,state)
            row.seconds=alternative.seconds;row.conditional=alternative.conditional
            model.alternatives[#model.alternatives+1]=row
        end
    end
    model.retained=retained;model.switchReason=decision.switchReason
    model.incumbentScore=raw.commitment and raw.commitment.score
    model.actionIDs=replayIDs(result.actions)
    if raw.decisionKind=="continuity" and prior and prior.actionID==model.actionID then
        model.actionIDs=schema.Clone(prior.actionIDs or model.actionIDs)
    end
    if prior and prior.actionID and model.actionID~=prior.actionID then
        model.change="Plan updated for "..policy.flavor.." and current quest state"
    end
    model.score=result.score or (raw.decisionKind=="continuity" and prior and prior.score);model.estimate={seconds=result.seconds,upper=result.upperSeconds,xp=result.xp,
        unknownXP=result.unknownXP,unknownCombatXP=result.unknownCombatXP,conditional=result.conditional,efficiencyCost=result.efficiencyCost,
        stoppingPoint=result.stoppingPoint}
    model.assumptions=result.assumptions;model.excluded=result.excluded
    model.conflicts={}
    for id in pairs(policy.pins) do
        local why=planner.Preferences.Conflict(policy,id,ctx.destinations[id] and ctx.destinations[id].mapID)
        if why then model.conflicts[#model.conflicts+1]=why end
    end
    if decision.mode=="unavailable" then model.detail=UNAVAILABLE;model.reason=UNAVAILABLE
    elseif not model.selected then model.detail=result.reason or "Follow the live quest instructions while planning" end
    if #model.stops==0 and model.selected then model.stops[1]=model.selected end
    lastTrace=traceResult(raw,result,model,state,policy,replayPrior,inputs,retained)
    if lastTrace and lastTrace.kind=="search" and lastTrace.searchStatus=="ready" then lastSearchTrace=lastTrace end
    return model
end

local function replaySame(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not replaySame(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function replayDiff(a,b)
    for i=1,math.max(#a,#b) do if a[i]~=b[i] then return {index=i,expected=a[i],actual=b[i]} end end
end
local function replayFailure(reason,detail) return {status="rejected",offline=true,reason=reason,detail=detail} end
local function validSelected(row)
    return row==nil or schema.PlainTable(row) and schema.Integer(row.questID,0,2147483647)
        and schema.Text(row.kind) and #row.kind<=32 and (row.actionID==nil or schema.Text(row.actionID) and #row.actionID<=160)
end
local function validDisplay(inputs,expected)
    if not schema.CopyLimited(inputs,2048,32768,6) or not schema.List(inputs.observed,1)
        or not schema.PlainTable(inputs.destinations) or not schema.PlainTable(expected)
        or not schema.Text(expected.status) or #expected.status>64 or not validSelected(expected.selected)
        or (expected.actionID~=nil and (not schema.Text(expected.actionID) or #expected.actionID>160)) then return false end
    if not validSelected(inputs.observed[1]) then return false end
    local count=0
    for id,point in pairs(inputs.destinations) do
        count=count+1
        if count>32 or not schema.ID(id) or not schema.PlainTable(point) or not schema.ID(point.mapID) then return false end
    end
    local p=inputs.previous
    return (p==nil or schema.PlainTable(p) and schema.Text(p.id) and #p.id<=160
        and schema.Integer(p.questID,0,2147483647) and schema.Text(p.kind) and #p.kind<=32)
        and (inputs.previousFailures==nil or p and schema.Integer(inputs.previousFailures,0,2147483647))
end
local function compareDecision(t,result)
    local selected,retained,decision=runtime.ProjectDecision(result,t.constraints,t.replayPrior,t.state,t.displayInputs)
    local ids=replayIDs(selected.actions)
    local difference=replayDiff(t.actions,ids)
    if difference or retained~=t.retained then return {status="mismatch",offline=true,phase="selection",difference=difference} end
    if not replaySame(t.displayed,decision.displayed) then
        return {status="mismatch",offline=true,phase="display",expected=t.displayed,actual=decision.displayed}
    end
    return {status="match",offline=true,replayKind=t.kind,actions=ids,retained=retained,
        displayed=decision.displayed,reason=decision.mode=="unavailable" and UNAVAILABLE or selected.reason,
        limited=selected.limited==true,metrics=schema.Clone(selected.metrics)}
end
local function searchBoundary(t,graph)
    local target=t.searchWork
    if not schema.Integer(target,0,48000) or (t.searchStatus~="ready" and t.searchStatus~="refining")
        or not schema.PlainTable(t.metrics) or t.metrics.work~=target then return nil,"invalid_search_boundary" end
    local environment=schema.Clone(t.environment)
    if environment.travelModel then
        if not planner.TravelEstimate then return nil,"source_mismatch" end
        local why;environment.travel,why=planner.TravelEstimate.Open(environment.travelModel)
        if not environment.travel then return nil,why end
    end
    local job=planner.PlanSearch.Begin(graph,t.state,t.constraints,environment)
    if not job then return nil,"search_construction_failed" end
    local result
    for _=1,target do
        result=job:Step(1)
        if result then job:Cancel();return nil,"search_completed_before_boundary" end
    end
    if t.searchStatus=="refining" then result=job:Peek() else result=job:Step(1) end
    job:Cancel()
    if not result or result.status~=t.searchStatus or not result.metrics or result.metrics.work~=target then
        return nil,"search_boundary_mismatch"
    end
    return result
end
local function replaySearch(t)
    return planner.PlanLearning.WithSnapshot(t.learning,function()
        if not replaySame(planner.PlanLearning.Export(),t.learning) then return replayFailure("learning_restore_mismatch") end
        local result,problem=searchBoundary(t,t.graph)
        if not result then return replayFailure(problem) end
        local searched=replayIDs(result.actions)
        local difference=replayDiff(t.searchActions,searched)
        if difference then return {status="mismatch",offline=true,phase="search",difference=difference} end
        if result.reason~=t.searchReason or (result.limited==true)~=t.searchLimited then
            return {status="mismatch",offline=true,phase="search_terminal",actual={status=result.status,reason=result.reason,limited=result.limited==true}}
        end
        local result=compareDecision(t,result);result.searchActions=searched;return result
    end)
end
local function rebuildGraph(t,source)
    if not schema.PlainTable(t.graph) or not schema.PlainTable(t.environment) or not schema.PlainTable(t.learning)
        or t.graph.status~="ready" or type(t.searchLimited)~="boolean" or t.maxSteps~=50000
        or not schema.List(t.graph.actions,768) or not schema.List(t.candidateIDs,768)
        or #t.graph.actions~=#t.candidateIDs or not schema.List(t.searchActions,128) then return nil,"incomplete_replay" end
    if source.corpusRevision==nil or not replaySame(t.graph.identity,source.identity)
        or t.graph.revision~=source.corpusRevision then return nil,"source_mismatch" end
    local graph=t.graph;graph.byID={};graph.byQuest={}
    for i,a in ipairs(graph.actions) do
        if not schema.PlainTable(a) or not schema.Text(a.id) or graph.byID[a.id] or a.id~=t.candidateIDs[i]
            or not schema.Integer(a.questID,0,2147483647) then return nil,"invalid_graph" end
        graph.byID[a.id]=a;graph.byQuest[a.questID]=graph.byQuest[a.questID] or {}
        table.insert(graph.byQuest[a.questID],a)
    end
    for _,ids in ipairs({t.searchActions,t.actions}) do
        for _,id in ipairs(ids) do if not graph.byID[id] then return nil,"unknown_expected_action" end end
    end
    return graph
end
local function decisionProposal(t)
    local result=t.proposal
    if not schema.PlainTable(result) or not schema.List(result.actions,1) or result.status~="refining"
        or (t.kind=="fallback" and #result.actions~=0) or (t.kind=="continuity" and #result.actions~=1)
        or result.commitment~=nil then return nil,"invalid_decision_proposal" end
    for _,action in ipairs(result.actions) do
        if not schema.PlainTable(action) or not schema.Text(action.id)
            or not schema.Integer(action.questID,0,2147483647) or not schema.Text(action.kind) then
            return nil,"invalid_decision_proposal"
        end
    end
    return result
end
-- Diagnostic-only replay. Imported state stays untrusted; only this private copy is simulated.
-- v1/v2 packets still import, but cannot prove the displayed decision they never captured.
function runtime.RerunReplay(raw,currentSource)
    local t=schema.CopyDiagnostic(raw)
    local source=schema.CopyLimited(currentSource,256,16384,6)
    if t and (t.version==1 or t.version==2) then return replayFailure("display_evidence_unavailable") end
    if not t or t.version~=3 or not source or source.searchRevision~=planner.PlanSearch.REVISION
        or not schema.Identity(source.identity) then return replayFailure("invalid_replay") end
    if not replaySame(t.source,source) then return replayFailure("source_mismatch") end
    if not schema.PlainTable(t.state) or not schema.PlainTable(t.constraints) or type(t.retained)~="boolean"
        or not schema.List(t.actions,128) or not validDisplay(t.displayInputs,t.displayed) then
        return replayFailure("incomplete_replay")
    end
    if not replaySame(t.state.identity,source.identity) or t.state.sourceRevision~=source.corpusRevision then
        return replayFailure("source_mismatch")
    end
    t.state.fresh=true
    if t.kind=="search" then
        local graph,problem=rebuildGraph(t,source)
        if not graph then return replayFailure(problem) end
        local ok,out=replaySearch(t)
        if not ok then return replayFailure("replay_error",tostring(out)) end
        return out
    end
    if t.kind~="fallback" and t.kind~="continuity" then return replayFailure("invalid_replay_kind") end
    local proposal,problem=decisionProposal(t)
    if not proposal then return replayFailure(problem) end
    local ok,out=pcall(compareDecision,t,proposal)
    if not ok then return replayFailure("replay_error",tostring(out)) end
    return out
end
