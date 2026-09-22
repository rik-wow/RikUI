-- Carried resources come from bag contents, never an aggregate that may include equipment.
local planner=RikUI.QuestPlanner
local S,scan=planner.Schema,{}
planner.BagScan=scan
local revision,job=0,nil
local function api(owner,name) return S.PlainTable(owner) and owner[name] end
local function call(fn,...) return planner.Context.Call(fn,...) end
local function current()
    if not job then
        local bags=S.Integer(NUM_BAG_SLOTS,0,16) and NUM_BAG_SLOTS
        job={revision=revision,lastBag=bags or 0,bag=0,equipmentSlot=1,counts={},stacks={},equipped={},maxStacks={},
            queue={},pending={},head=1,genericFree=0,countOK=bags~=false and bags~=nil,freeOK=bags~=false and bags~=nil,equipmentOK=true}
    end
    return job
end
function scan.Invalidate() revision=revision+1;job=nil end
function scan.Need(id)
    local j=current()
    if not S.ID(id) or j.pending[id] or j.maxStacks[id]~=nil or #j.queue>=256 then return end
    j.pending[id]=true;j.queue[#j.queue+1]=id
end
function scan.OnEvent(event,...)
    if event=="GET_ITEM_INFO_RECEIVED" then
        local id,success=...
        if S.ID(id) and type(success)=="boolean" and not RikUI.Secret.IsSecret(success) and success then
            local j=current();if j.maxStacks[id]==false then j.maxStacks[id]=nil;scan.Need(id) end
        end
    elseif event=="BAG_UPDATE" or event=="BAG_UPDATE_DELAYED" or event=="PLAYER_EQUIPMENT_CHANGED"
        or event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_LEAVING_WORLD"
        or event=="UNIT_INVENTORY_CHANGED" and select(1,...)=="player" then scan.Invalidate() end
end
function scan.Step(budget)
    local j=current()
    local wasDone=j.done and j.head>#j.queue
    budget=math.min(budget or 24,32)
    while budget>0 and j.bag<=j.lastBag do
        if not j.active then
            local ok,size=call(api(C_Container,"GetContainerNumSlots") or GetContainerNumSlots,j.bag)
            local read,free,family=call(api(C_Container,"GetContainerNumFreeSlots") or GetContainerNumFreeSlots,j.bag)
            size=ok and S.Integer(size,0,128) and size or nil
            free=read and size and S.Integer(free,0,size) and free or nil
            family=S.Integer(family,0,2147483647) and family or nil
            j.active={size=size or 0,free=free,family=family,slot=1,rows=0,failed=size==nil or free==nil}
            if free and family==0 then j.genericFree=j.genericFree+free end
            if free==nil or family==nil then j.freeOK=false end
            budget=budget-1
        end
        local b=j.active
        if b.slot<=b.size and budget>0 then
            local ok,row=call(api(C_Container,"GetContainerItemInfo"),j.bag,b.slot)
            if ok and S.PlainTable(row) and S.ID(row.itemID) and S.Integer(row.stackCount,1,1000000) then
                local id,count=row.itemID,row.stackCount
                b.rows=b.rows+1;j.counts[id]=(j.counts[id] or 0)+count
                local item={itemID=id,count=count,bag=j.bag,slot=b.slot,generic=b.family==0}
                if S.Integer(row.quality,0,20) then item.quality=row.quality end
                for _,key in ipairs({"isLocked","hasNoValue"}) do
                    if type(row[key])=="boolean" and not RikUI.Secret.IsSecret(row[key]) then item[key]=row[key] end
                end
                j.stacks[#j.stacks+1]=item;scan.Need(id)
            elseif not ok then b.failed=true end
            b.slot=b.slot+1;budget=budget-1
        end
        if b.slot>b.size then
            if b.failed or b.free==nil or b.rows~=b.size-b.free then j.countOK=false end
            j.bag=j.bag+1;j.active=nil
        end
    end
    while budget>0 and j.equipmentSlot<=19 do
        local ok,id=call(GetInventoryItemID,"player",j.equipmentSlot)
        if ok and S.ID(id) then j.equipped[id]=(j.equipped[id] or 0)+1 end
        if not ok then j.equipmentOK=false end
        j.equipmentSlot=j.equipmentSlot+1;budget=budget-1
    end
    for _=1,math.min(4,budget) do
        local id=j.queue[j.head];if not id then break end
        local result={call(api(C_Item,"GetItemInfo") or GetItemInfo,id)}
        j.maxStacks[id]=result[1] and S.Integer(result[9],1,1000000) and result[9] or false
        j.pending[id]=nil;j.head=j.head+1
    end
    j.done=j.bag>j.lastBag and j.equipmentSlot>19
    j.carriedExact=j.done and j.countOK
    j.genericFreeExact=j.done and j.freeOK
    local finished=j.done and j.head>#j.queue
    if finished and not wasDone and planner.Request then planner.Request() end
    if j.head>#j.queue then j.queue,j.head={},1 end
    return j
end
function scan.Read(records)
    for _,record in pairs(records or {}) do
        scan.Need(record.providedItemID)
        for _,item in ipairs(record.requiredItems or {}) do scan.Need(item.itemID) end
        for _,objective in ipairs(record.objectives or {}) do
            if objective.type=="item" then scan.Need(objective.targetID) end
            scan.Need(objective.sourceItemID)
        end
    end
    local j=current()
    local result={inventory={},inventoryLower={},inventoryExact=j.carriedExact==true,stackSizes={},stackRoom={},
        bagItems=S.Clone(j.stacks),equipped=S.Clone(j.equipped),inventoryRevision=j.revision,genericStacks={}}
    for id,count in pairs(j.counts) do
        if j.carriedExact then result.inventory[id]=count else result.inventoryLower[id]=count end
    end
    for id,size in pairs(j.maxStacks) do if size then result.stackSizes[id]=size end end
    for _,item in ipairs(j.stacks) do
        if item.generic then result.genericStacks[item.itemID]=(result.genericStacks[item.itemID] or 0)+1 end
        local size=result.stackSizes[item.itemID]
        if size and item.count<=size then result.stackRoom[item.itemID]=(result.stackRoom[item.itemID] or 0)+size-item.count end
    end
    if j.genericFreeExact then result.bagFree=j.genericFree end
    return result
end
