-- Reviewed objective definitions bind whole observed lists, never marker target identity.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local bindings,packs={},{}
planner.StepBindings=bindings
local function token(v) return schema.Text(v) and #v>0 and #v<=128 end
function bindings.Install(raw)
    local data=schema.Copy(raw)
    if not data or not schema.Identity(data.identity) or not schema.Source(data.source)
        or data.source.authority~="verified" or not token(data.revision)
        or not schema.Text(data.observationSHA256) or #data.observationSHA256~=64
        or not data.observationSHA256:match("^[a-f0-9]+$") or not schema.List(data.quests,40) then return nil,"invalid-objective-pack" end
    for _,field in ipairs({"product","build","locale"}) do if data.identity[field]~=data.source[field] then return nil,"source-identity" end end
    local seen={}
    for _,quest in ipairs(data.quests) do
        if not schema.ID(quest.questID) or seen[quest.questID] or not schema.Text(quest.title)
            or not schema.List(quest.objectives,32) or #quest.objectives<1 then return nil,"invalid-objective-quest" end
        seen[quest.questID]=true
        local ids={}
        for _,objective in ipairs(quest.objectives) do
            if not token(objective.id) or ids[objective.id] or not schema.Text(objective.text)
                or not schema.Text(objective.type) or not schema.Integer(objective.required,0,1000000) then return nil,"invalid-objective-binding" end
            ids[objective.id]=true
        end
    end
    if #packs>=32 then return nil,"objective-pack-limit" end
    packs[#packs+1]=data
    return true
end
local function matchQuest(quest,observed)
    if not observed or observed.title~=quest.title or not observed.objectives or #observed.objectives~=#quest.objectives then return nil end
    local ids,used={},{}
    for index,objective in ipairs(observed.objectives) do
        local normalized=planner.Objectives.Text(objective)
        for _,expected in ipairs(quest.objectives) do
            if objective.type==expected.type and objective.numRequired==expected.required and normalized==expected.text then
                if ids[index] or used[expected.id] then return nil end
                ids[index],used[expected.id]=expected.id,true
            end
        end
        if not ids[index] then return nil end
    end
    return ids
end
function bindings.Match(snapshot,id)
    local result
    for _,pack in ipairs(packs) do
        local a,b=snapshot.identity,pack.identity
        if a.product==b.product and a.build==b.build and a.locale==b.locale then
            for _,quest in ipairs(pack.quests) do
                if quest.questID==id then
                    local ids=matchQuest(quest,snapshot.quests[id])
                    if ids then
                        if result then return nil end
                        result={ids=ids,source=schema.Clone(pack.source),observationSHA256=pack.observationSHA256,revision=pack.revision}
                    end
                end
            end
        end
    end
    return result
end
