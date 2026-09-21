-- Explicit action definitions; model durations are separate from observed state.
local planner = RikUI.QuestPlanner
local schema, actions = planner.Schema, {}
planner.Actions = actions
local FIELDS = {id=true,title=true,questID=true,kind=true,node=true,zoneID=true,duration=true,risk=true,uncertainty=true,
    source=true,xp=true,xpLevel=true,category=true,sharedKey=true,requiredObjectives=true,progress=true,
    unlock=true,consumes=true,requirement=true,completeQuest=true}
local DURATIONS = {combat=true,looting=true,interaction=true,downtime=true}
local KINDS = {pickup=true,objective=true,turnin=true,unlock=true}
local CATEGORIES = {normal=true,class=true,travel=true,dungeon=true}

local function only(value,allowed)
    if not schema.PlainTable(value) then return false end
    for key in pairs(value) do if not allowed[key] then return false end end
    return true
end

local function token(value)
    return schema.Text(value) and #value>0 and #value<=128 and value:match("^[%w][%w_.:%-]*$")~=nil
end

local function identity(a,b)
    return schema.Identity(a) and schema.Identity(b) and a.product==b.product and a.build==b.build and a.locale==b.locale
end

local function objectives(row)
    if row.requiredObjectives==nil then return true end
    if row.kind~="pickup" or not schema.List(row.requiredObjectives,32) then return false end
    local seen={}
    for _,item in ipairs(row.requiredObjectives) do
        if not only(item,{key=true,remaining=true}) or not token(item.key) or seen[item.key]
            or not schema.Integer(item.remaining,0,2147483647) then return false end
        seen[item.key]=true
    end
    return true
end

local function costs(row)
    if not only(row.duration,DURATIONS) then return false end
    local total=0
    for key in pairs(DURATIONS) do
        if not schema.Number(row.duration[key],0,3600) then return false end
        total=total+row.duration[key]
    end
    return total<=3600 and schema.Number(row.risk,0,1) and schema.Number(row.uncertainty,0,1)
end

local function rewards(row)
    if row.xp~=nil and not schema.Number(row.xp,0,2147483647) then return false end
    if row.xpLevel~=nil and (not schema.Integer(row.xpLevel,1,1000) or row.xp==nil) then return false end
    if row.kind~="turnin" and (row.xp~=nil or row.xpLevel~=nil or row.consumes~=nil) then return false end
    if row.consumes==nil then return true end
    if not schema.List(row.consumes,16) then return false end
    local seen={}
    for _,item in ipairs(row.consumes) do
        if not only(item,{itemID=true,count=true}) or not schema.ID(item.itemID) or not schema.ID(item.count)
            or seen[item.itemID] then return false end
        seen[item.itemID]=true
    end
    return true
end

local function progress(row)
    if row.kind~="objective" then return row.sharedKey==nil and row.progress==nil and row.completeQuest==nil end
    if row.sharedKey~=nil and not token(row.sharedKey) then return false end
    if row.progress~=nil and not schema.ID(row.progress) then return false end
    if row.completeQuest~=nil and type(row.completeQuest)~="boolean" then return false end
    return not (row.completeQuest and row.sharedKey)
end

local function unlock(row)
    if row.kind~="unlock" then return row.unlock==nil and row.requirement==nil end
    if not only(row.unlock,{kind=true,key=true}) or not token(row.unlock.key)
        or (row.unlock.kind~="flight" and row.unlock.kind~="flag") then return false end
    return schema.Condition(row.requirement)~=nil
end

function actions.Validate(raw,content)
    local row,reason=schema.Copy(raw)
    if not row or not only(row,FIELDS) then return nil,reason or "invalid action fields" end
    if not token(row.id) or not token(row.node) or not schema.ID(row.questID) or not schema.ID(row.zoneID)
        or not KINDS[row.kind] then return nil,"invalid action identity" end
    if not schema.Source(row.source) or not identity(row.source,content) then return nil,"action source mismatch" end
    if row.title~=nil and not schema.Text(row.title) then return nil,"invalid action title" end
    if row.category~=nil and not CATEGORIES[row.category] then return nil,"invalid action category" end
    if not costs(row) or not rewards(row) or not objectives(row) or not progress(row) or not unlock(row) then
        return nil,"invalid action model"
    end
    return row
end

function actions.New(content,rows)
    local copy=schema.Copy(content)
    if not copy or not schema.Identity(copy) or not schema.List(rows,40) then return nil,"invalid action catalogue" end
    local list,byID={},{}
    for _,raw in ipairs(rows) do
        local row,reason=actions.Validate(raw,copy)
        if not row then return nil,reason end
        if byID[row.id] then return nil,"duplicate action ID" end
        list[#list+1],byID[row.id]=row,row
    end
    table.sort(list,function(a,b) return a.id<b.id end)
    return {List=function() return schema.Clone(list) end, Get=function(_,id) return schema.Clone(byID[id]) end,
        Identity=function() return schema.Clone(copy) end}
end
