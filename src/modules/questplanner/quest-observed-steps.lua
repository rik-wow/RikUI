-- Snapshot objective slots are temporary identities; quest markers stay quest-scoped.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local steps=planner.Steps
local function objectiveStep(id,index,objective,source,boundID)
    local key=boundID or "observed-slot:"..index
    return {id=id..":"..key,kind="objective",questID=id,objectiveID=key,objectiveIdentity=boundID and "bound-objective" or "snapshot-slot",
        text=objective.text or "Check the quest log",targetIdentityKnown=false,source=source,
        prerequisites={{kind="quest-active",questID=id}},
        completion={{kind="objective",questID=id,objectiveID=key,
            count=schema.Integer(objective.numRequired,1,1000000) and objective.numRequired or nil}}},key
end
function steps.ObservedQuest(snapshot,id,ctx)
    local quest=snapshot.quests[id]
    if not quest then return nil end
    local identity=snapshot.identity
    local source={product=identity.product,build=identity.build,locale=identity.locale,id="observed-quest-log",authority="verified"}
    local binding=planner.StepBindings and planner.StepBindings.Match(snapshot,id)
    if binding and binding.source.authority=="verified" then source=binding.source end
    -- Semantic target claims remain reference-only; live log counters own step progress.
    local evidence={identity=identity,activeQuests={[id]=true},questReady={[id]=quest.objectivesComplete},
        turnedIn={[id]=planner.Journal and planner.Journal.TurnedIn and planner.Journal.TurnedIn(id,identity) or false},
        objectives={[id]={}}}
    local definitions={}
    if quest.objectivesComplete~=true then
        for index,objective in ipairs(quest.objectives or {}) do
            local step,key=objectiveStep(id,index,objective,source,binding and binding.ids[index])
            definitions[#definitions+1]=step
            evidence.objectives[id][key]={finished=objective.finished,count=objective.numFulfilled}
        end
        if #definitions==0 then definitions[1]=objectiveStep(id,"unknown",{},source) end
    end
    definitions[#definitions+1]={id=id..":turnin",kind="turnin",questID=id,text="Turn in this quest",
        targetIdentityKnown=false,source=source,prerequisites={{kind="quest-ready",questID=id}},
        completion={{kind="turned-in",questID=id}}}
    local preferred=planner.SemanticGuidance and planner.SemanticGuidance.Preferred(snapshot,id)
    if preferred and preferred>1 and preferred<#definitions then table.insert(definitions,1,table.remove(definitions,preferred)) end
    local handle,reason=steps.New(identity,definitions)
    if not handle then return {state="unknown",reason=reason} end
    local result=handle:Evaluate(evidence)
    result.objectiveBinding=binding and {ids=schema.Clone(binding.ids),source=schema.Clone(binding.source),revision=binding.revision}
    if binding and result.active then result.navigation=schema.Clone(binding.navigation[result.active.objectiveID]) end
    local point=ctx.destinations and ctx.destinations[id]
    if point then
        result.questMarker=schema.Clone(point)
        result.questMarker.coordinateSystem,result.questMarker.association="normalized-map","quest"
        result.questMarker.targetIdentityKnown,result.questMarker.objectiveLocationKnown=false,false
    end
    return result
end
