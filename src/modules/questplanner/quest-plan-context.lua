-- Optional, guarded character capabilities. No quest selection or gameplay actions.
local planner=RikUI.QuestPlanner
local schema,context=planner.Schema,{}
planner.PlanContext=context
local function api(owner,name) return schema.PlainTable(owner) and owner[name] end
local function value(fn,validate,...)
    local ok,result=planner.Context.Call(fn,...)
    if ok and validate(result) then return result end
end
local function number(v) return schema.Number(v,0,2147483647) end
local function boolean(v) return type(v)=="boolean" and not RikUI.Secret.IsSecret(v) end
local function bagFree()
    local total=0
    for bag=0,4 do
        local ok,free,family=planner.Context.Call(api(C_Container,"GetContainerNumFreeSlots") or GetContainerNumFreeSlots,bag)
        if not ok or not schema.Integer(free,0,200) or not schema.Integer(family,0,2147483647) then return end
        if family==0 then total=total+free end
    end
    return total
end
local function requirements(records)
    local result={spells={},reputation={},skills={}}
    local count=0
    local function visit(rule,depth)
        if not rule or depth>10 or count>=128 then return end
        count=count+1
        if rule.op=="spell" and schema.ID(rule.id) then result.spells[rule.id]=true end
        if (rule.op=="reputationMin" or rule.op=="reputationMax") and schema.ID(rule.id) then result.reputation[rule.id]=true end
        if rule.op=="skill" and schema.ID(rule.id) then result.skills[rule.id]=true end
        for _,child in ipairs(rule.args or {}) do visit(child,depth+1) end
        if rule.arg then visit(rule.arg,depth+1) end
    end
    local ids={};for id in pairs(records) do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids) do visit(records[id].planning and records[id].planning.requirements,0) end
    return result
end
function context.Enrich(ctx,snapshot,records)
    ctx.money=value(GetMoney,number)
    local party=value(GetNumGroupMembers,function(v) return schema.Integer(v,0,40) end)
    ctx.partySize=party and math.max(1,party)
    ctx.characterKey=value(UnitGUID,schema.Text,"player")
    ctx.bagFree=bagFree()
    if planner.BagScan then
        local bags=planner.BagScan.Read(records)
        for key,value in pairs(bags) do ctx[key]=value end
        ctx.bagFree=bags.bagFree -- A pending scan cannot retain an older capacity claim.
    end
    ctx.afk=value(UnitIsAFK,boolean,"player")
    ctx.dead=value(UnitIsDeadOrGhost,boolean,"player")
    ctx.inCombat=value(UnitAffectingCombat,boolean,"player")
    ctx.spells,ctx.reputation,ctx.skills,ctx.questTags,ctx.capabilities={},{},{},{},{}
    local health=value(UnitHealthMax,number,"player")
    if health and health>0 then ctx.capabilities.combat={maxHealth=health,level=ctx.attributes.level,group=ctx.partySize} end
    local needed=requirements(records or {})
    local queried=0
    for id in pairs(needed.spells) do
        if queried>=32 then break end
        ctx.spells[id]=value(api(C_SpellBook,"IsSpellKnown") or IsPlayerSpell,boolean,id);queried=queried+1
    end
    for _,id in ipairs(snapshot.order) do
        if #snapshot.order>256 then break end
        local ok,tag=planner.Context.Call(api(C_QuestLog,"GetQuestTagInfo"),id)
        if not ok or not schema.PlainTable(tag) then
            local tagID=value(GetQuestTagInfo,function(v) return schema.Integer(v,0,1000) end,id)
            tag=tagID and {tagID=tagID};ok=tag~=nil
        end
        if ok and schema.PlainTable(tag) and schema.Integer(tag.tagID,0,1000) then
            ctx.questTags[id]={tagID=tag.tagID,dungeon=tag.tagID==81 or tag.tagID==85 or tag.tagID==62 or tag.tagID==88 or tag.tagID==89,
                group=tag.tagID==1 or tag.tagID==62 or tag.tagID==88 or tag.tagID==89}
            local size=value(api(C_QuestLog,"GetSuggestedGroupSize"),function(v) return schema.Integer(v,1,40) end,id)
            if size and size>1 then ctx.questTags[id].requiredParty=size end
        end
    end
    local knownProfessions={planner.Context.Call(GetProfessions)}
    if knownProfessions[1] then
        for index=2,7 do
            local slot=knownProfessions[index]
            if schema.Integer(slot,1,1000) then
                local ok,_,_,rank,_,_,_,skillID=planner.Context.Call(GetProfessionInfo,slot)
                if ok and schema.ID(skillID) and needed.skills[skillID] and schema.Number(rank,0,1000) then ctx.skills[skillID]=rank end
            end
        end
    end
    for id in pairs(needed.reputation) do
        local ok,row=planner.Context.Call(api(C_Reputation,"GetFactionDataByID"),id)
        if ok and schema.PlainTable(row) and schema.Number(row.currentStanding,-42000,100000) then
            ctx.reputation[id]=row.currentStanding
        else
            local read,_,_,_,_,_,standing=planner.Context.Call(GetFactionInfoByID,id)
            if read and schema.Number(standing,-42000,100000) then ctx.reputation[id]=standing end
        end
    end
    ctx.services=planner.PlanServices and planner.PlanServices.Read(ctx,records) or {}
    return ctx
end
function context.Signature(ctx)
    local result={}
    for _,key in ipairs({"money","bagFree","partySize","characterKey","dead","floor","phase","inventoryRevision","inventoryExact"}) do result[#result+1]=key..":"..tostring(ctx[key]) end
    for _,name in ipairs({"spells","reputation","skills","inventory","inventoryLower","stackRoom"}) do
        local ids={};for id in pairs(ctx[name] or {}) do ids[#ids+1]=id end;table.sort(ids)
        for _,id in ipairs(ids) do result[#result+1]=name..":"..id..":"..tostring(ctx[name][id]) end
    end
    for _,service in ipairs(ctx.services or {}) do result[#result+1]=service.id..":"..tostring(service.moneyCost)..":"..tostring(service.freesSlots) end
    return table.concat(result,"|")
end
