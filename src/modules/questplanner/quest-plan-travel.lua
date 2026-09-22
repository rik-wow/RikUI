-- Guarded travel observations. Labels and unlocked nodes never imply a free route.
local planner=RikUI.QuestPlanner
local schema,travel=planner.Schema,{}
planner.PlanTravel=travel
local MAX_ITEMS,MAX_NODES,MAX_OFFERS=32,256,8
local HEARTHSTONE=6948
local bindingRevision,taxiOpen=0,false
local function api(owner,name) return schema.PlainTable(owner) and owner[name] end
local function number(v) return schema.Number(v,0,2147483647) end
local function itemIDs(records)
    local seen,ids={[HEARTHSTONE]=true},{HEARTHSTONE}
    local function add(id)
        if schema.ID(id) and not seen[id] then seen[id]=true;ids[#ids+1]=id end
    end
    for _,record in pairs(records or {}) do
        add(record.providedItemID)
        for _,objective in ipairs(record.objectives or {}) do add(objective.sourceItemID) end
    end
    table.sort(ids)
    return ids
end
local function cooldowns(ctx,records)
    local values,details={},{}
    local read=api(C_Container,"GetItemCooldown") or GetItemCooldown
    for index,id in ipairs(itemIDs(records)) do
        if index>MAX_ITEMS then break end
        local carried=(ctx.inventory or {})[id] or (ctx.inventoryLower or {})[id]
        if carried and carried>0 then
            local ok,start,duration,enabled=planner.Context.Call(read,id)
            if ok and number(start) and number(duration) and schema.Integer(enabled,0,1) and number(ctx.observedAt) then
                local row={enabled=enabled==1,observedAt=ctx.observedAt}
                if row.enabled then
                    row.readyAt=start+duration
                    row.remaining=math.max(0,row.readyAt-ctx.observedAt)
                    values["item:"..id]=row.remaining
                end
                details[id]=row
            end
        end
    end
    return values,details
end
local function point(vector)
    if RikUI.Secret.IsSecret(vector) or vector==nil then return end
    local ok,x,y=pcall(function() return vector:GetXY() end)
    if ok and schema.Number(x,0,1) and schema.Number(y,0,1) then return x,y end
end
local function flightNodes(ctx)
    local mapID=ctx.position and ctx.position.mapID
    if not schema.ID(mapID) then return {} end
    local ok,rows=planner.Context.Call(api(C_TaxiMap,"GetTaxiNodesForMap"),mapID)
    if not ok or not schema.List(rows,MAX_NODES) then return {} end
    local nodes,duplicates={},{}
    local faction=ctx.attributes and ctx.attributes.faction
    local allowed=faction=="Horde" and 1 or faction=="Alliance" and 2
    for _,row in ipairs(rows) do
        if schema.PlainTable(row) and schema.ID(row.nodeID) then
            if nodes[row.nodeID] then duplicates[row.nodeID]=true end
            local x,y=point(row.position)
            if x and schema.Text(row.name) and schema.Integer(row.faction,0,2) and (row.faction==0 or allowed and row.faction==allowed)
                and not RikUI.Secret.IsSecret(row.isUndiscovered) and type(row.isUndiscovered)=="boolean" then
                nodes[row.nodeID]={id=row.nodeID,name=row.name,undiscovered=row.isUndiscovered,
                    destination={mapID=mapID,x=x,y=y,scope="observed-flight-point",api="C_TaxiMap.GetTaxiNodesForMap"},
                    authority="observed-client"}
            end
        end
    end
    for id in pairs(duplicates) do nodes[id]=nil end
    return nodes
end
local function offeredFlights(ctx)
    if not taxiOpen or not ctx.position then return {} end
    local ok,rows=planner.Context.Call(api(C_TaxiMap,"GetAllTaxiNodes"),ctx.position.mapID)
    if not ok or not schema.List(rows,MAX_NODES) then return {} end
    local result={}
    for _,row in ipairs(rows) do
        if #result>=MAX_ITEMS then break end
        if schema.PlainTable(row) and schema.ID(row.nodeID) and schema.Integer(row.state,0,2) and row.state==1 and schema.ID(row.slotIndex) then
            local read,cost=planner.Context.Call(TaxiNodeCost,row.slotIndex)
            if read and number(cost) then
                result[#result+1]={nodeID=row.nodeID,moneyCost=cost,reachableFromCurrentMaster=true,
                    durationStatus="unknown",destinationStatus="unresolved"}
            end
        end
    end
    return result
end
function travel.Read(ctx,records)
    local values,items=cooldowns(ctx,records)
    local ok,label=planner.Context.Call(GetBindLocation)
    local nodes=flightNodes(ctx)
    return values,{items=items,bindLabel=ok and schema.Text(label) and label or nil,
        bindingRevision=bindingRevision,bindDestinationStatus="unknown",
        flightNodes=nodes,offeredFlights=offeredFlights(ctx),observedAt=ctx.observedAt}
end
function travel.Exploration(ctx)
    local rows={}
    for _,node in pairs(ctx.travel and ctx.travel.flightNodes or {}) do
        if node.undiscovered then rows[#rows+1]=node end
    end
    local position=ctx.position
    table.sort(rows,function(a,b)
        local function distance(n) return (n.destination.x-position.x)^2+(n.destination.y-position.y)^2 end
        local da,db=distance(a),distance(b)
        if da~=db then return da<db end
        return a.id<b.id
    end)
    local offers={}
    for i=1,math.min(MAX_OFFERS,#rows) do
        local node=rows[i]
        offers[#offers+1]={id="flight:"..node.destination.mapID..":"..node.id,questID=0,kind="explore",
            title="Discover flight point: "..node.name,instruction="Speak to the flight master at "..node.name.." to learn this flight point",
            destination=schema.Clone(node.destination),zoneID=node.destination.mapID,activity="explore",
            optionalExploration=true,discoveryNode=node.id,visitKey="flight:"..node.destination.mapID..":"..node.id,
            supported=true,authority="observed-client",interaction="talk",
            completionEvidence="The taxi API reports this flight point as discovered",
            recovery="Decline exploration or leave this optional stop if its approach is unavailable"}
    end
    return offers
end
function travel.OnEvent(event)
    if event=="HEARTHSTONE_BOUND" then bindingRevision=bindingRevision+1 end
    if event=="TAXIMAP_OPENED" then taxiOpen=true
    elseif event=="TAXIMAP_CLOSED" or event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_LEAVING_WORLD" then taxiOpen=false end
end
