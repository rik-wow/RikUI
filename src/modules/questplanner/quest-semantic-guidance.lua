-- Match source claims to live objectives; current character observations always win.
local planner,schema=RikUI.QuestPlanner,RikUI.QuestPlanner.Schema
local guidance,bindings,choices={}, {}, {}
planner.SemanticGuidance=guidance
local current,receipts,receiptKeys,advice=nil,{},{},{}
local comparison,comparisonKey,comparisonMesh,compared,provisional,revision=nil,nil,nil,nil,nil,0
local COMPARISON_MS,COMPARISON_BATCHES=1,16
local metrics={matched=0,unknown=0,conflicts=0,areas=0,limited=false}
local MAX_AREAS,MAX_METHODS,MAX_RECEIPTS=8192,2048,128
local sourceRevision
local function sameSnapshot(snapshot)
    return current==snapshot or (current and current.generation and snapshot.generation==current.generation
        and snapshot.identity.product==current.identity.product and snapshot.identity.build==current.identity.build
        and snapshot.identity.locale==current.identity.locale)
end
local function text(value)
    if not schema.Text(value) then return nil end
    return value:gsub("^%s+",""):gsub("%s+$",""):gsub("%s+"," ")
end
local function observedName(value)
    local value=text(planner.Objectives.Text(value))
    if not value then return end
    value=value:gsub("^#/#%s*",""):gsub("%s*[:%-]?%s*#/#$","")
    return text(value)
end
local function matches(observed,expected)
    local label=observedName(observed)
    if not label then return false end
    local kind=expected.type
    if kind~=observed.type and not (kind=="kill-credit" and observed.type=="monster")
        and not (kind=="event" and (observed.type=="event" or observed.type=="log")) then return false end
    if expected.required and expected.required~=observed.numRequired then return false end
    if label==text(expected.text) or label==text(expected.name) then return true end
    return observed.type=="monster" and label==text((expected.name or "").." slain")
end
local function conflict(id,field,reason,reference,observed)
    local key=id..":"..field..":"..reason
    if receiptKeys[key] then return end
    receiptKeys[key]=true;receipts[#receipts+1]={questID=id,field=field,reason=reason,source="runtime-objectives",action="reference-withheld",
        identity=current and schema.Clone(current.identity),generation=current and current.generation,
        reference=reference,observed=observed,corpusRevision=sourceRevision}
    if #receipts>MAX_RECEIPTS then
        local old=table.remove(receipts,1);receiptKeys[old.questID..":"..old.field..":"..old.reason]=nil
    end
end
local function bind(snapshot,id,record)
    local live=snapshot.quests[id]
    if record.title=="" then metrics.unknown=metrics.unknown+#(live.objectives or {});return end
    if live.title~=record.title then metrics.unknown=metrics.unknown+#(live.objectives or {});conflict(id,"title","source/live title mismatch",record.title,live.title);return end
    local result={ids={},navigation={},semantic={},source={product=snapshot.identity.product,build=snapshot.identity.build,
        locale=snapshot.identity.locale,id="questiedb-reference",authority="reference"},revision=sourceRevision}
    local used={}
    for index,observed in ipairs(live.objectives or {}) do
        local found
        for _,expected in ipairs(record.objectives or {}) do
            if matches(observed,expected) then
                if found then found=false;break end
                found=expected
            end
        end
        if found and not used[found.id] then
            result.ids[index]=found.id;result.semantic[index]=found;used[found.id]=true;metrics.matched=metrics.matched+1
        else
            metrics.unknown=metrics.unknown+1
            conflict(id,"objective:"..index,"no unique compatible source target",nil,observed.text)
        end
    end
    return result
end
local function admissible(area,ctx,policy)
    return schema.PlainTable(area) and schema.ID(area.mapID) and schema.Number(area.x,0,1) and schema.Number(area.y,0,1)
        and not policy.avoids[area.mapID] and area.unavailable~=true and area.retiredMap~=true
        and area.phase==nil -- phase membership is not supplied by the character adapter
        and (area.access==nil or area.access=="unknown" or area.access=="outdoor")
        and (area.floor==nil or ctx.floor==area.floor)
end
local function cost(area,ctx,frame)
    if not ctx.position or area.mapID~=ctx.position.mapID then return math.huge end
    local width,height=frame and frame.width,frame and frame.height
    if not schema.Number(width,1,100000) or not schema.Number(height,1,100000) then return math.huge end
    return math.sqrt(((area.x-ctx.position.x)*width)^2+((area.y-ctx.position.y)*height)^2)
end
local function methodAllowed(method,ctx)
    if method.dispositionKnown and (method.kind=="vendor" or method.kind=="talk" or method.kind=="interact" or method.kind=="finish" or method.kind=="start") then
        local faction=ctx.attributes and ctx.attributes.faction
        local required=faction=="Alliance" and "A" or faction=="Horde" and "H"
        if required and method.friendlyToFaction~="AH" and method.friendlyToFaction~=required then return false end
    end
    if method.kind=="vendor" then return method.costKnown==true and method.affordable==true end
    if method.kind=="container" or method.kind=="quest-reward" then return false end
    if method.requiredItem then
        return ctx.inventory and (ctx.inventory[method.requiredItem] or 0)>0
    end
    return true
end
local function candidates(methods,index,ctx,policy,frame,list)
    if metrics.areas>MAX_AREAS or (metrics.methods or 0)>=MAX_METHODS then metrics.limited=true;return end
    for _,method in ipairs(methods or {}) do
        metrics.methods=(metrics.methods or 0)+1
        if metrics.methods>MAX_METHODS then metrics.limited=true;break end
        if methodAllowed(method,ctx) then
            local localAreas=method.areasByMap and ctx.position and method.areasByMap[ctx.position.mapID]
            local areas=localAreas or method.areas
            for _,area in ipairs(areas or {}) do
                metrics.areas=metrics.areas+1
                if metrics.areas>MAX_AREAS then metrics.limited=true;return end
                if admissible(area,ctx,policy) then
                    local distance=cost(area,ctx,frame)
                    list[#list+1]={area=area,method=method,index=index,distance=distance,
                        costBasis=distance==math.huge and "travel distance unknown" or nil}
                end
            end
        end
    end
end
local function pick(list,shared)
    local best
    for _,value in ipairs(list) do
        local count=shared[value.area.id] or 1
        value.shared=count
        value.score=value.distance/math.min(count,4)
        local tied=best and value.score==best.score
        local preferred=tied and value.questZone==true and best.questZone~=true
        local sameZone=tied and value.questZone==best.questZone
        if not best or value.score<best.score or preferred
            or sameZone and tostring(value.area.id)<tostring(best.area.id) then best=value end
    end
    return best
end
local function beginInventory(ctx)
    local inventory,readItems=ctx.inventory or {},{}
    ctx.inventory=inventory
    metrics.inventoryQueries=0
    return function(id)
        if not schema.ID(id) then return end
        if inventory[id]~=nil then return inventory[id] end
        if planner.BagScan then
            if ctx.inventoryExact then inventory[id]=0;return 0 end
            return ctx.inventoryLower and ctx.inventoryLower[id]
        end
        if readItems[id] or metrics.inventoryQueries>=80 then return end
        readItems[id]=true;metrics.inventoryQueries=metrics.inventoryQueries+1
        local value=planner.Context and planner.Context.ItemCount and planner.Context.ItemCount(id)
        if schema.Integer(value,0,2147483647) then inventory[id]=value;return value end
    end
end
local function note(info,value)
    if #info.lines<8 and schema.Text(value) and value~="" then info.lines[#info.lines+1]=value:sub(1,240) end
end
local function itemAdvice(record,live,ctx,policy,frame,list,itemCount)
    local info={lines={},items={}}
    if record.providedItemID then
        local count=itemCount(record.providedItemID)
        info.items[record.providedItemID]=count
        note(info,"Quest item "..record.providedItemID..": "..(count and (count.." carried") or "inventory unknown")..". Follow the quest's use instructions.")
    end
    if live.objectivesComplete==true then return info end
    for _,required in ipairs(record.requiredItems or {}) do
        local count=itemCount(required.itemID)
        info.items[required.itemID]=count
        if count==0 then
            local first=#list+1
            candidates(required.methods,-1,ctx,policy,frame,list)
            for at=first,#list do list[at].prerequisiteItemID=required.itemID end
            note(info,"Required source item "..required.itemID.." is not currently carried.")
        end
    end
    for _,extra in ipairs(record.extraObjectives or {}) do note(info,extra.text or extra.name) end
    return info
end
local function objectiveCandidates(live,binding,ctx,policy,frame,list,itemCount,info)
    for slot,observed in ipairs(live.objectives or {}) do
        local expected=binding.semantic[slot]
        if expected and observed.finished~=true then
            local carried=expected.sourceItemID and itemCount(expected.sourceItemID)
            if carried and carried>0 then
                note(info,"Use carried item "..expected.sourceItemID.." as directed by the live objective; its exact use target is unknown.")
            else candidates(expected.methods,slot,ctx,policy,frame,list) end
        end
    end
end
local function extraCandidates(record,live,binding,ctx,policy,frame,list)
    for _,extra in ipairs(record.extraObjectives or {}) do
        local slot=extra.objectiveIndex
        local expected=slot and binding.semantic[slot]
        if expected and expected.runtimeObjectiveIndex==slot and live.objectives[slot].finished~=true then
            local first=#list+1
            candidates(extra.methods,slot,ctx,policy,frame,list)
            for at=first,#list do list[at].sourceHint=extra.text or extra.name end
        end
    end
    if #list>0 then return end
    for _,extra in ipairs(record.extraObjectives or {}) do
        if not extra.objectiveIndex or extra.objectiveIndex==0 then
            local first=#list+1
            candidates(extra.methods,-2,ctx,policy,frame,list)
            for at=first,#list do list[at].sourceHint=extra.text or extra.name end
        end
    end
end
local function questCandidates(snapshot,id,ctx,policy,frame,itemCount)
    local record=planner.SemanticData.Quest(snapshot.identity,id)
    local live=snapshot.quests[id]
    if not record or not live or live.failed==true or policy.skips[id] then return end
    local binding=bind(snapshot,id,record)
    bindings[id]=binding
    if not binding then return {} end
    local list={}
    advice[id]=itemAdvice(record,live,ctx,policy,frame,list,itemCount)
    if live.objectivesComplete==true then candidates(record.ends,0,ctx,policy,frame,list)
    elseif #list==0 then
        objectiveCandidates(live,binding,ctx,policy,frame,list,itemCount,advice[id])
        extraCandidates(record,live,binding,ctx,policy,frame,list)
    end
    for _,value in ipairs(list) do value.questZone=value.area.areaID==record.zoneOrSort and record.zoneOrSort~=nil end
    return list
end
local function huntBindings(binding)
    for _,expected in pairs(binding and binding.semantic or {}) do
        for _,method in ipairs(expected.methods or {}) do
            if method.kind=="kill" or method.kind=="drop" then
                binding.navigation[expected.id]={kind="hunt",radius=0,source="source-targets",
                    text=(method.kind=="drop" and "Collect " or "Look for ")..(expected.name or "quest objectives"),
                    basis="Source target relation; use live quest progress to identify productive areas."}
                break
            end
        end
    end
end
local function choiceKey(snapshot,selected,ctx,policy,list,shared)
    local live=snapshot.quests[selected]
    local parts={snapshot.identity.build,snapshot.identity.locale,planner.SemanticData.Revision(),selected,tostring(live.objectivesComplete),
        tostring(ctx.position and ctx.position.mapID),tostring(ctx.floor),tostring(ctx.attributes.class),tostring(ctx.attributes.faction)}
    local avoids,inventoryIDs={},{}
    for mapID in pairs(policy.avoids) do avoids[#avoids+1]=mapID end
    table.sort(avoids)
    for _,mapID in ipairs(avoids) do parts[#parts+1]="avoid:"..mapID end
    for _,o in ipairs(live.objectives or {}) do
        parts[#parts+1]=tostring(observedName(o));parts[#parts+1]=tostring(o.type)
        parts[#parts+1]=tostring(o.numRequired);parts[#parts+1]=tostring(o.finished)
    end
    for itemID in pairs(ctx.inventory) do inventoryIDs[#inventoryIDs+1]=itemID end
    table.sort(inventoryIDs)
    for _,itemID in ipairs(inventoryIDs) do parts[#parts+1]="item:"..itemID.."="..tostring(ctx.inventory[itemID]>0) end
    for _,candidate in ipairs(list) do
        parts[#parts+1]=tostring(candidate.area.id).."/"..candidate.index.."/"..candidate.method.kind.."/"..tostring(shared[candidate.area.id]).."/"..tostring(candidate.questZone)
    end
    return table.concat(parts,":")
end
local function compareAreas(snapshot,ctx,policy,previous,pending,shared)
    local selected=previous and choices[previous] and previous
    if not selected then for _,id in ipairs(snapshot.order) do if choices[id] then selected=id;break end end end
    if not selected or not planner.Optimizer or not planner.Optimizer.BeginAreas then
        comparison,comparisonKey,compared=nil,nil,nil;return
    end
    local key=choiceKey(snapshot,selected,ctx,policy,pending[selected],shared)
    local meshRevision=planner.Terrain and planner.Terrain.AreaRevision and planner.Terrain.AreaRevision()
    if comparisonKey~=key or comparisonMesh~=meshRevision then
        if comparisonKey~=key then compared=nil;provisional=choices[selected] end
        comparisonKey,comparisonMesh=key,meshRevision
        comparison=planner.Optimizer.BeginAreas(pending[selected],shared,snapshot.identity,schema.Clone(ctx.position))
        if comparison then comparison.questID=selected end
    end
    choices[selected]=compared or provisional or choices[selected]
end
function guidance.Observe(snapshot,ctx,policy,previous)
    current=snapshot;bindings={};choices={};advice={}
    metrics={matched=0,unknown=0,conflicts=0,areas=0,limited=false}
    local frame=planner.Context and planner.Context.Frame and planner.Context.Frame()
    sourceRevision=planner.SemanticData.Status().revision
    if snapshot.origin=="imported-untrusted" or ctx.origin~="live" then comparison,comparisonKey,compared=nil,nil,nil;return end
    local pending,shared,itemCount={},{},beginInventory(ctx)
    for index,id in ipairs(snapshot.order or {}) do
        if index>40 then metrics.limited=true;break end
        local list=questCandidates(snapshot,id,ctx,policy,frame,itemCount)
        if list then
            pending[id]=list
            local seen={}
            for _,v in ipairs(list) do
                if not seen[v.area.id] then shared[v.area.id]=(shared[v.area.id] or 0)+1;seen[v.area.id]=true end
            end
        end
    end
    for id,list in pairs(pending) do choices[id]=pick(list,shared);huntBindings(bindings[id]) end
    compareAreas(snapshot,ctx,policy,previous,pending,shared)
    metrics.conflicts=#receipts
end
function guidance.Advice(snapshot,id) if sameSnapshot(snapshot) then return advice[id] end end
function guidance.Binding(snapshot,id) if sameSnapshot(snapshot) then return bindings[id] end end
function guidance.Preferred(snapshot,id)
    local value=sameSnapshot(snapshot) and choices[id]
    return value and value.index
end
local VERBS={kill="Kill ",drop="Hunt ",loot="Collect from ",interact="Interact with ",explore="Explore ",vendor="Buy from ",use="Use ",talk="Talk to ",event="Complete the event near ",finish="Turn in to ",start="Speak to ",fish="Fish near ",herb="Gather herbs near ",mine="Mine near ",mount="Mount near ",["pet-battle"]="Battle near "}
function guidance.Apply(snapshot,id,point,step)
    local value=sameSnapshot(snapshot) and choices[id]
    if not value or (point and point.scope=="current-waypoint") then return point end
    local method,area=value.method,value.area
    local action=(VERBS[method.kind] or "Check ")..(method.name or "quest target")
    if value.prerequisiteItemID then action=action.." for required item "..value.prerequisiteItemID end
    local semantic={authority="reference",source="QuestieDB",method=method.kind,targetKind=method.targetKind,targetID=method.targetID,
        objectiveKey=bindings[id] and bindings[id].ids[value.index],
        areaID=area.id,sharedQuests=value.shared,prerequisiteItemID=value.prerequisiteItemID,costBasis=value.costBasis or "map-distance estimate",floorKnown=area.floorKnown==true,
        action=action,instructions=action..". "..(value.sourceHint and ("Source hint: "..value.sourceHint..". ") or "").."Confirm progress in the quest log.",basis=value.distance==math.huge and "Source location; travel between zones, access and floor are unverified."
            or "Forever provider reference; current spawn availability, access and floor are unverified."}
    semantic.comparison=value.comparison and schema.Clone(value.comparison)
    if point and point.mapID==area.mapID and not value.modeledMeters then
        -- A quest-scoped marker establishes no particular mob, objective or turn-in identity.
        -- Cross-zone source coordinates must never be relabeled as a nearby marker.
        return point,nil,{authority="reference",source="client quest marker",locationSource="runtime-quest-marker",
            action="Follow quest marker",instructions="Follow the quest marker and check the quest log for the objective.",
            costBasis="live quest marker; target unverified",comparison=semantic.comparison,
            basis="This marker identifies the quest vicinity, not a confirmed creature or objective location."}
    end
    local target={mapID=area.mapID,x=area.x,y=area.y,scope="semantic-objective-area",api="QuestieDB",areaID=area.id}
    local radius=area.radius
    if area.radiusNormalized and planner.Context and planner.Context.Frame then
        local frame=planner.Context.Frame()
        if frame and frame.position and frame.position.mapID==area.mapID and frame.width and frame.height then
            radius=math.min(150,area.radiusNormalized*math.min(frame.width,frame.height))
        end
    end
    local hunt
    if value.index~=0 and (method.kind=="kill" or method.kind=="drop") and schema.Number(radius,0,150) and radius>0 then
        hunt={kind="hunt",radius=radius,source="source-spawns",text=action,instructions=semantic.instructions,basis=semantic.basis}
    end
    return target,hunt,semantic
end
function guidance.Revision() return revision end
function guidance.Step()
    if not comparison then return end
    local clock=type(debugprofilestop)=="function" and debugprofilestop
    local started=clock and clock()
    for _=1,clock and COMPARISON_BATCHES or 4 do
        local value,done=comparison:Step()
        if done then
            choices[comparison.questID],compared=value,value
            comparison=nil;revision=revision+1
            if planner.Request then planner.Request() end
            return
        end
        if clock and clock()-started>=COMPARISON_MS then return end
    end
end
function guidance.Status() return schema.Clone(metrics) end
function guidance.Receipts() return schema.Clone(receipts) end

