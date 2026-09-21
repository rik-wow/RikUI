-- Reviewed navigation annotations, separate from verified world facts and optimizer actions.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local targets={}
local MARKER_EPSILON=.0000001 -- normalized-coordinate roundoff, not a snapping radius
planner.Targets=targets

-- The quest text establishes "basement"; assigning the reviewed lower model surface is
-- an inference. Neither the POI nor the user's interaction report supplies target altitude.
local entries={
    ["bitter-rivals-basement-v1"]={
        questID=310,identity={product="forever",build="1.60.1.69913",locale="enUS"},
        title="Bitter Rivals",
        objective={text="In the basement of the Thunderbrew Distillery in Kharanos, replace a barrel of Thunder Ale with a Barrel of Barleybrew Scalder.",
            type="log",numRequired=1},
        marker={mapID=1426,x=.47717434167861938,y=.5268782377243042,
            api="C_QuestLog.GetQuestsOnMap",scope="current-map-quest-poi"},
        observationSHA256="042db64be2fffd28595a36e9d727962f77a81b0aa18f926f455ec091e8ebdf4c",
        detail="Basement barrel; check Jarven",
        instructions="If Jarven is guarding the barrel, give him Thunder Ale. Use the barrel after he leaves.",
        instructionsSource="user-reported-sequence",
        floor={revision="d1981b5ac045133c7f2db478e91774432a3eaa82c4e93295478a43bfea5e118e",
            heights={393.09662169989,399.3549},tolerance=.05,index=1,label="Basement",
            basis="Quest text names the basement; the reviewed lower model surface is inferred, not a measured target position."},
    },
}
local function sameIdentity(a,b)
    return a and a.product==b.product and a.build==b.build and a.locale==b.locale
end
local function sameMarker(a,b)
    return a and a.mapID==b.mapID and a.api==b.api and a.scope==b.scope
        and schema.Number(a.x,0,1) and schema.Number(a.y,0,1)
        and math.abs(a.x-b.x)<=MARKER_EPSILON and math.abs(a.y-b.y)<=MARKER_EPSILON
end
local function matches(entry,snapshot,id,point)
    local quest=snapshot.quests[id]
    if id~=entry.questID or not sameIdentity(snapshot.identity,entry.identity) or not sameMarker(point,entry.marker)
        or not quest or quest.title~=entry.title or quest.failed==true or quest.objectivesComplete~=true then return false end
    local objective=quest.objectives and #quest.objectives==1 and quest.objectives[1]
    return objective and objective.text==entry.objective.text and objective.type==entry.objective.type
        and objective.numRequired==entry.objective.numRequired and objective.finished==true
end
function targets.Match(snapshot,id,point)
    for key,entry in pairs(entries) do
        if matches(entry,snapshot,id,point) then
            return {id=key,detail=entry.detail,instructions=entry.instructions,
                instructionsSource=entry.instructionsSource,observationSHA256=entry.observationSHA256}
        end
    end
end
-- Every reviewed surface must still match. A changed mesh or competing floor fails closed.
function targets.Floor(hint,revision,choices,point)
    local entry=hint and entries[hint.id]
    local floor=entry and entry.floor
    if not floor or revision~=floor.revision or not sameMarker(point,entry.marker)
        or #choices~=#floor.heights then return nil end
    for index,height in ipairs(floor.heights) do
        if not schema.Number(choices[index].height,-100000,100000)
            or math.abs(choices[index].height-height)>floor.tolerance then return nil end
    end
    local result=schema.Clone(choices[floor.index])
    result.index,result.label=floor.index,floor.label
    result.source,result.questTargetVerified="quest-text-model-inference",false
    result.basis,result.annotationID=floor.basis,hint.id
    return result
end
