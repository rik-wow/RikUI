-- Per-objective presentation and explicit location choice; never owns completion.
local planner = RikUI.QuestPlanner
local schema, guide = planner.Schema, {}
planner.ObjectiveGuide = guide
local current, rows, candidates, selected = nil, {}, {}, nil
local VERBS = {kill="Defeat",drop="Defeat and loot",loot="Loot",interact="Interact with",
    talk="Talk to",start="Speak to",use="Use",["use-item"]="Use the quest item at",
    ["pet-battle"]="Battle",explore="Explore",finish="Turn in to",vendor="Buy from",
    fish="Fish at",herb="Gather",mine="Mine",mount="Mount",event="Complete the event at"}
function guide.Reset(snapshot)
    if current and (current.identity.build~=snapshot.identity.build or current.identity.locale~=snapshot.identity.locale
        or current.identity.product~=snapshot.identity.product) then selected=nil end
    if snapshot.origin=="imported-untrusted" or selected and not snapshot.quests[selected.questID] then selected=nil end
    current, rows, candidates = snapshot, {}, {}
end
function guide.Requested(id)
    return selected and selected.questID==id and selected.areaID
end
function guide.Instruction(value, objective)
    local method=value.method
    local result=(VERBS[method.kind] or "Follow the quest instructions at").." "..(method.name or "the target")
    if method.kind=="drop" and objective then result=result.." for "..(objective.name or "the quest item") end
    if method.viaItemID then result=result.."; open the collected container" end
    if value.sourceHint then result=result..". "..value.sourceHint end
    return result
end
local function best(list)
    local result
    for _,value in ipairs(list) do
        if not result or value.distance<result.distance or value.distance==result.distance
            and tostring(value.area.id)<tostring(result.area.id) then result=value end
    end
    return result
end
local function row(id,index,observed,binding,list)
    local expected=binding and binding.semantic[index]
    local value=best(list)
    local count,seen=0,{}
    for _,candidate in ipairs(list) do
        local area=candidate.sourceArea or candidate.area
        if not seen[area.id] then count=count+planner.Waypoints.Count(area);seen[area.id]=true end
    end
    return {questID=id,index=index,objectiveID=expected and expected.id,text=observed.text,
        finished=observed.finished==true,fulfilled=observed.numFulfilled,required=observed.numRequired,
        instruction=value and guide.Instruction(value,expected) or (observed.finished and "Objective complete"
            or expected and expected.sourceItemID and ("Use quest item "..expected.sourceItemID.."; exact use target unknown")
            or expected and "No usable location recorded for this objective" or "Objective location not yet known"),
        destination=value and planner.Waypoints.Destination(value.area),locations=count,
        source=value and (value.method.source or value.area.source or "QuestieDB"),
        authority=value and "reference",objective=expected}
end
function guide.Observe(id,live,binding,list,limited)
    local grouped,result={},{}
    for _,value in ipairs(list) do
        grouped[value.index]=grouped[value.index] or {}
        table.insert(grouped[value.index],value)
    end
    candidates[id]=grouped
    for index,observed in ipairs(live.objectives or {}) do
        result[#result+1]=row(id,index,observed,binding,grouped[index] or {})
    end
    if live.objectivesComplete then
        result[#result+1]=row(id,0,{text="Turn in this quest"},binding,grouped[0] or {})
    end
    for _,entry in ipairs(result) do entry.limited=limited==true end
    rows[id]=result
    if selected and selected.questID==id then
        local found
        for _,entry in ipairs(result) do
            if entry.index==selected.index and entry.objectiveID==selected.objectiveID and not entry.finished then found=true end
        end
        if not found then selected=nil end
    end
end
function guide.Choice(id)
    if not selected or selected.questID~=id then return end
    for _,value in ipairs(candidates[id] and candidates[id][selected.index] or {}) do
        if value.area.id==selected.areaID then return value end
    end
end
function guide.Rows(snapshot,id)
    if not current or snapshot.generation~=current.generation or snapshot.identity.build~=current.identity.build
        or snapshot.identity.locale~=current.identity.locale or snapshot.identity.product~=current.identity.product
        or snapshot.origin=="imported-untrusted" then return {} end
    local result={}
    for _,entry in ipairs(rows[id] or {}) do
        local copy={}
        for key,value in pairs(entry) do if key~="objective" then copy[key]=schema.Clone(value) end end
        local chosen=guide.Choice(id)
        if chosen and chosen.index==entry.index then
            copy.destination=planner.Waypoints.Destination(chosen.area)
            copy.instruction=guide.Instruction(chosen,entry.objective)
        end
        result[#result+1]=copy
    end
    return result
end
local function nextLocation(chosen,list,index)
    local source=chosen.sourceArea or chosen.area
    local nextIndex=(chosen.area.spawnIndex or 1)+1
    if nextIndex<=planner.Waypoints.Count(source) then
        chosen={area=planner.Waypoints.At(source,nextIndex),method=chosen.method,index=index,sourceArea=source,
            sourceHint=chosen.sourceHint,distance=chosen.distance}
    else
        for at,value in ipairs(list) do
            if value.area.id==chosen.area.id or (value.sourceArea or value.area).id==source.id then
                chosen=list[at%#list+1];break
            end
        end
        local original=chosen.sourceArea or chosen.area
        chosen={area=planner.Waypoints.At(original,1),method=chosen.method,index=index,sourceArea=original,
            sourceHint=chosen.sourceHint,distance=chosen.distance}
    end
    return chosen
end
function guide.Select(snapshot,id,index,cycle)
    local entry
    for _,value in ipairs(guide.Rows(snapshot,id)) do if value.index==index then entry=value end end
    if not entry or entry.finished or not entry.destination then return nil,"No known location for this objective" end
    local list=candidates[id][index]
    local chosen=guide.Choice(id)
    if not chosen or chosen.index~=index then chosen=best(list) end
    if cycle then chosen=nextLocation(chosen,list,index) end
    selected={questID=id,index=index,objectiveID=entry.objectiveID,areaID=chosen.area.id}
    -- Replace only this bounded candidate; source tables remain immutable.
    for at,value in ipairs(list) do
        if (value.sourceArea or value.area).id==(chosen.sourceArea or chosen.area).id then list[at]=chosen;break end
    end
    return true
end
function guide.Clear() selected=nil end
