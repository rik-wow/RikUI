-- Exact installed identity and archived observations; no guide text or target IDs inferred.
local h=dofile("tests/quest-marker-replay.lua")
local p=RikUI.QuestPlanner
for _,id in ipairs({310,313,287}) do
    local quest=assert(h.snapshot.quests[id])
    local step=assert(p.Steps.ObservedQuest(h.snapshot,id,h.snapshot.context))
    assert(step.active and step.active.questID==id)
    assert(step.objectiveBinding and step.objectiveBinding.revision=="dun-morogh-observed-objectives-v1")
    if id==313 then assert(step.active.objectiveID=="q313.wendigo-manes") end
    if id==287 then assert(step.active.objectiveID=="q287.headhunter-kills") end
    assert(step.questMarker.association=="quest" and not step.questMarker.objectiveLocationKnown)
    assert(step.state~="completed","archived objective readiness is not a turn-in event")
    print("OBSERVED STEP",id,quest.title,step.active.kind,step.stepID,step.state)
    for _,objective in ipairs(quest.objectives or {}) do
        print("OBJECTIVE",objective.type,objective.numFulfilled,objective.numRequired,tostring(objective.finished),objective.text)
    end
end
