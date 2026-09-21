-- Conservative definitions for bounded, validated live objective observations.
local planner, schema = RikUI.QuestPlanner, RikUI.QuestPlanner.Schema
local objectives = {}
planner.Objectives = objectives
local MAX_OBJECTIVES, MAX_COUNT = 32, 2147483647

local function valid(value)
    return schema.PlainTable(value) and schema.Text(value.text) and schema.Text(value.type)
        and not RikUI.Secret.IsSecret(value.finished) and type(value.finished)=="boolean"
        and schema.Integer(value.numFulfilled,0,MAX_COUNT) and schema.Integer(value.numRequired,0,MAX_COUNT)
end

local function edge(text, current, required, reversed)
    local before, first, second, after = text:match("^(%s*)(%d+)%s*/%s*(%d+)(.*)$")
    if not first or after~="" and not after:match("^[%s:;,]") then return nil end
    if reversed then first,second=second:reverse(),first:reverse() end
    if tonumber(first)~=current or tonumber(second)~=required then return nil end
    return before.."#/#"..after
end

function objectives.Text(value)
    if not valid(value) then return nil end
    local text=edge(value.text,value.numFulfilled,value.numRequired,false)
    if text then return text,"leading" end
    text=edge(value.text:reverse(),value.numFulfilled,value.numRequired,true)
    if text then return text:reverse(),"trailing" end
    return value.text,"literal"
end

local function comparable(current, previous)
    local text, edgeKind=objectives.Text(current)
    local oldText, oldEdge=objectives.Text(previous)
    return text~=nil and oldText~=nil and current.type==previous.type
        and current.numRequired==previous.numRequired and text==oldText and edgeKind==oldEdge
end

-- Returns changed, increased, reduced, definitionsComparable. No direction is
-- inferred until every objective definition and the list size are comparable.
function objectives.Compare(current, previous)
    if current==nil or previous==nil then return current~=previous,false,false,false end
    local validCurrent,count=schema.List(current,MAX_OBJECTIVES)
    local validPrevious,oldCount=schema.List(previous,MAX_OBJECTIVES)
    if not validCurrent or not validPrevious or count~=oldCount then return true,false,false,false end
    for index=1,count do
        if not comparable(current[index],previous[index]) then return true,false,false,false end
    end
    local changed,increased,reduced=false,false,false
    for index=1,count do
        local value,old=current[index],previous[index]
        changed=changed or value.text~=old.text or value.numFulfilled~=old.numFulfilled or value.finished~=old.finished
        increased=increased or value.numFulfilled>old.numFulfilled or value.finished and not old.finished
        reduced=reduced or value.numFulfilled<old.numFulfilled or old.finished and not value.finished
    end
    return changed,increased,reduced,true
end
