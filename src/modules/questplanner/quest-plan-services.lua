-- Optional services are observed only while interacting; never sell, repair or train automatically.
local planner=RikUI.QuestPlanner
local schema,services=planner.Schema,{}
planner.PlanServices=services
local merchant,trainer=false,false
local function call(fn,...) return planner.Context.Call(fn,...) end
local function boolean(v) return type(v)=="boolean" and not RikUI.Secret.IsSecret(v) end
local function falseValue(v) return boolean(v) and v==false end
local function api(owner,name) return schema.PlainTable(owner) and owner[name] end
function services.OnEvent(event)
    if event=="MERCHANT_SHOW" then merchant=true elseif event=="MERCHANT_CLOSED" then merchant=false
    elseif event=="TRAINER_SHOW" then trainer=true elseif event=="TRAINER_CLOSED" then trainer=false
    elseif event=="PLAYER_LEAVING_WORLD" then merchant,trainer=false,false end
end
function services.Read(ctx,records)
    local result={}
    if not ctx.position or not schema.Number(ctx.money,0,2147483647) then return result end
    local function append(kind,cost,slots,instruction,basis,consumes,saleSlots,saleInventory)
        result[#result+1]={id="observed-"..kind,supported=true,optional=true,
            destination=schema.Clone(ctx.position),target={kind="service",name=kind=="training" and "Current trainer" or "Current merchant"},
            instruction=instruction,moneyCost=cost,freesSlots=slots,consumes=consumes,discardStackRoom=consumes,saleSlots=saleSlots,saleInventory=saleInventory,conditionalService=true,basis=basis,observedAt=ctx.observedAt,
            completionEvidence="Observe currency or bag capacity change after your action",
            recovery="Skip this optional service and continue questing."}
    end
    if merchant then
        local ok,can=call(CanMerchantRepair)
        local read,cost,needed=call(GetRepairAllCost)
        if ok and boolean(can) and can and read and boolean(needed) and needed and schema.Number(cost,1,2147483647) and cost<=ctx.money then
            append("repair",cost,nil,"Consider repairing equipment at this merchant","Observed repair quote; benefit is not measured")
        end
        local reserved={}
        for _,record in pairs(records or {}) do
            if record.providedItemID then reserved[record.providedItemID]=true end
            for _,item in ipairs(record.requiredItems or {}) do reserved[item.itemID]=true end
            for _,objective in ipairs(record.objectives or {}) do
                if objective.type=="item" then reserved[objective.targetID]=true end
                if objective.sourceItemID then reserved[objective.sourceItemID]=true end
            end
        end
        local slots,sales,saleSlots,saleInventory=0,{},{},{}
        for index,row in ipairs(ctx.bagItems or {}) do
            if index>128 then break end
            if row.generic and not reserved[row.itemID] and schema.Integer(row.quality,0,0)
                and falseValue(row.isLocked) and falseValue(row.hasNoValue) then
                local qok,quest=call(api(C_Container,"GetContainerItemQuestInfo"),row.bag,row.slot)
                local iok,_,_,_,_,_,_,_,_,_,_,price=call(api(C_Item,"GetItemInfo") or GetItemInfo,row.itemID)
                if qok and schema.PlainTable(quest) and falseValue(quest.isQuestItem) and quest.questID==nil
                    and iok and schema.Number(price,1,2147483647) and schema.Integer(row.count,1,1000000) then
                    if schema.Number((ctx.inventory or {})[row.itemID],row.count,2147483647) then
                        slots=slots+1;sales[#sales+1]={itemID=row.itemID,count=row.count}
                        saleSlots[#saleSlots+1]=row.bag..":"..row.slot;saleInventory[row.itemID]=ctx.inventory[row.itemID]
                    end
                end
            end
        end
        if slots>0 then append("vendor",0,slots,"Review poor-quality items for sale to free bag space",
            "Observed unreserved, non-quest stacks; capacity changes only after you sell",sales,saleSlots,saleInventory) end
    end
    if trainer then
        local ok,count=call(GetNumTrainerServices)
        local best,name
        if ok and schema.Integer(count,0,1000) then
            for index=1,math.min(count,32) do
                local read,title,_,status=call(GetTrainerServiceInfo,index)
                local priced,cost,profession=call(GetTrainerServiceCost,index)
                if read and schema.Text(title) and schema.Text(status) and status=="available"
                    and priced and falseValue(profession) and schema.Number(cost,0,2147483647) and cost<=ctx.money
                    and (not best or cost<best) then best,name=cost,title end
            end
        end
        if best then append("training",best,nil,"Review training: "..name,"Observed affordable offer; no unobserved power increase assumed") end
    end
    return result
end
