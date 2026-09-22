-- Selected-quest rewards are read without changing selection. Unknown payouts stay absent.
local planner=RikUI.QuestPlanner
local schema,rewards=planner.Schema,{}
planner.PlanRewards=rewards
local function api(owner,name) return schema.PlainTable(owner) and owner[name] end
local function read(fn,...)
    return planner.Context.Call(fn,...)
end
local function selected()
    local ok,id=read(GetQuestLogSelectedID or api(C_QuestLog,"GetSelectedQuest"))
    if ok and schema.ID(id) then return id end
end
local function items(countFn,itemFn)
    local ok,count=read(countFn)
    if not ok or not schema.Integer(count,0,32) then return end
    local rows={}
    for index=1,count do
        local good,name,_,quantity,quality,usable,id=read(itemFn,index)
        if not good or not schema.ID(id) or not schema.Integer(quantity,1,2147483647) then return end
        local meta,_,_,_,_,_,_,_,stack,equip=read(api(C_Item,"GetItemInfo") or GetItemInfo,id)
        local knownUsable,knownEquipment
        if type(usable)=="boolean" then knownUsable=usable end
        if meta and schema.Text(equip) then knownEquipment=equip~="" end
        rows[#rows+1]={itemID=id,count=quantity,name=schema.Text(name) and name or nil,
            usable=knownUsable,equipment=knownEquipment,
            stackSize=meta and schema.Integer(stack,1,2147483647) and stack or nil}
    end
    return rows
end
function rewards.Read(ctx,snapshot)
    local id=selected()
    if not id or not snapshot.quests[id] then return end
    local show=api(C_QuestLog,"ShouldShowQuestRewards")
    if type(show)=="function" then local ok,allowed=read(show,id);if not ok or allowed~=true then return end end
    local row={authority="observed-offer",questID=id,items=items(GetNumQuestLogRewards,GetQuestLogRewardInfo),
        choices=items(GetNumQuestLogChoices,GetQuestLogChoiceInfo)}
    local ok,money=read(GetQuestLogRewardMoney)
    if ok and schema.Integer(money,0,2147483647) then row.money=money end
    local spellsOK,spells=read(api(C_QuestInfoSystem,"GetQuestRewardSpells"),id)
    if spellsOK and schema.List(spells,32) then
        row.spells={}
        for _,spellID in ipairs(spells) do
            local good,info=read(api(C_QuestInfoSystem,"GetQuestRewardSpellInfo"),id,spellID)
            if good and schema.ID(spellID) and schema.PlainTable(info) and info.isSpellLearned==true then row.spells[#row.spells+1]=spellID end
        end
    end
    if selected()~=id then return end
    ctx.rewards=ctx.rewards or {};local prior=ctx.rewards[id] or {}
    -- Replace this API family's observation atomically. Nil is unknown, not an
    -- invitation to spend an earlier reward. Keep independently observed XP.
    for _,key in ipairs({"authority","questID","items","choices","money","spells"}) do prior[key]=row[key] end
    ctx.rewards[id]=prior
    ctx.stackSizes=ctx.stackSizes or {}
    for _,list in ipairs({row.items or {},row.choices or {}}) do
        for _,item in ipairs(list) do
            if item.stackSize then ctx.stackSizes[item.itemID]=item.stackSize end
        end
    end
end
function rewards.Attach(action,record,state,policy)
    if action.kind~="turnin" then return end
    local live=state.live[action.questID] and state.live[action.questID].reward
    action.typedRewards={items={},reputation={},spells={}}
    local typed=action.typedRewards
    if live then
        typed.money=live.money;typed.spells=schema.Clone(live.spells or {})
        for _,item in ipairs(live.items or {}) do typed.items[#typed.items+1]=schema.Clone(item) end
        local chosen
        for _,item in ipairs(live.choices or {}) do
            if policy.rewardTarget==item.itemID then chosen=item;break end
            if not chosen and item.equipment and item.usable then chosen=item end
        end
        chosen=chosen or (live.choices or {})[1]
        if chosen then typed.items[#typed.items+1]=schema.Clone(chosen);typed.choiceItemID=chosen.itemID end
        typed.authority="observed-offer"
    end
    for _,pair in ipairs(record.reputationReward or {}) do
        if schema.ID(pair[1]) and schema.Integer(pair[2],-42000,42000) then
            typed.reputation[#typed.reputation+1]={factionID=pair[1],value=pair[2],authority="source-estimate"}
        end
    end
    if #typed.items>0 then
        action.gains={}
        for _,item in ipairs(typed.items) do action.gains[#action.gains+1]={itemID=item.itemID,count=item.count} end
    end
end
function rewards.Value(action,policy)
    local row=action.typedRewards
    if not row or action.kind~="turnin" or not policy.rewardFocus or policy.rewardFocus=="xp" then return 0 end
    local value,target=0,policy.rewardTarget
    if policy.rewardFocus=="currency" then value=(row.money or 0)/10000
    elseif policy.rewardFocus=="reputation" then
        for _,rep in ipairs(row.reputation) do if not target or rep.factionID==target then value=value+rep.value/1000 end end
    elseif policy.rewardFocus=="equipment" then
        for _,item in ipairs(row.items) do
            if target and item.itemID==target or not target and item.equipment and item.usable then value=value+1 end
        end
    elseif policy.rewardFocus=="unlocks" then
        for _,id in ipairs(row.spells) do if not target or id==target then value=value+1 end end
    end
    return math.max(-4,math.min(4,value))
end
