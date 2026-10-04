-- Preindexed source browsing and guarded comparisons. No class weights or automatic equipment.
local core,guard=RikUI,RikUI.Secret
local g={};core.GearGoals=g
local slots={1,2,3,15,5,9,10,6,7,8,11,12,13,14,16,17,18}
g.Slots=slots
g.SlotNames={[1]="Head",[2]="Neck",[3]="Shoulder",[15]="Back",[5]="Chest",[9]="Wrist",
    [10]="Hands",[6]="Waist",[7]="Legs",[8]="Feet",[11]="Ring 1",[12]="Ring 2",
    [13]="Trinket 1",[14]="Trinket 2",[16]="Main hand",[17]="Off hand",[18]="Ranged"}
local goals,focus,tracker={},0,false
local cache,order,queue,queued,requested={},{},{},{},{}
local MAX_GOALS,MAX_CACHE,MAX_QUEUE,MAX_PATH=8,96,32,32
g.Limits={goals=MAX_GOALS,cache=MAX_CACHE,queue=MAX_QUEUE,path=MAX_PATH,savedBytes=384}
local function plain(v)return not guard.IsSecret(v) and type(v)=="table" and getmetatable(v)==nil end
local function number(v,low,high)return not guard.IsSecret(v) and type(v)=="number" and v==v and v>=low and v<=high end
local function integer(v,low,high)return number(v,low,high) and v%1==0 end
local function text(v)return not guard.IsSecret(v) and type(v)=="string" end
local function call(fn,...)if type(fn)=="function" and not guard.IsSecret(fn) then return guard.Read(fn,...) end;return false end
local function api(name)return type(C_Item)=="table" and C_Item[name] end
local function clone(v)if type(v)~="table" then return v end;local r={};for k,x in pairs(v)do r[k]=clone(x)end;return r end
local function catalog()return core.GearCatalog or {items={},slots={},quests={},variants={}} end
local function persona()
    local ok,_,class,classID=call(UnitClass,"player")
    local good,faction=call(UnitFactionGroup,"player")
    local raceOK,_,_,race=call(UnitRace,"player")
    return ok and text(class) and good and text(faction) and faction.."/"..class or "",
        ok and integer(classID,1,64) and classID or nil,raceOK and integer(race,1,256) and race or nil
end
local function maskAllows(mask,id)
    if not number(mask,0,2^53) or mask==0 then return true end
    if not id or id>53 then return nil end
    return math.floor(mask/2^(id-1))%2==1
end
function g.Level()local ok,n=call(UnitLevel,"player");return ok and integer(n,1,1000) and n or nil end
function g.CurrentCatalog()
    local ok,version,build=call(GetBuildInfo)
    return ok and text(version) and (text(build) or integer(build,1,2147483647))
        and version.."."..tostring(build)==(catalog().identity or {}).build or false
end
local function raceAllows(mask,race)
    if not number(mask,0,2^53) or mask==0 then return true end
    local encoded=(catalog().raceMasks or {})[race]
    if not number(encoded,1,2^53) then return nil end
    return math.floor(mask/encoded)%2==1
end
function g.Quest(id,key,full)
    if catalog().installedProvider and g.Provider then return g.Provider.Quest(id,full) end
    key=key or persona();local variant=(catalog().variants or {})[key]
    if variant then
        for _,other in ipairs(variant.removed or {})do if other==id then return end end
        if variant.quests and variant.quests[id] then return variant.quests[id] end
    end
    return catalog().quests[id]
end
function g.Completed(id)
    local ok,v=call(type(C_QuestLog)=="table" and C_QuestLog.IsQuestFlaggedCompleted,id)
    if ok and not guard.IsSecret(v) and type(v)=="boolean" then return v end
end
function g.Active(id)
    local p=core.QuestPlanner
    local snapshot,status
    if p and p.PeekSnapshot then snapshot,status=p.PeekSnapshot() end
    if snapshot and status and (status.state=="current" or status.state=="partial") then
        if snapshot.quests[id] then return true end
        if snapshot.coverage=="log-complete" then return false end
    end
end
function g.Sources(id,key,class,race)
    local item=catalog().items[id];if not item then return {} end
    if not key then key,class,race=persona() end
    local result={}
    for index,src in ipairs(item.sources or {})do
        local q=src.kind=="quest" and g.Quest(src.id,key)
        local allowed=src.kind~="quest" or q and maskAllows(q.requiredClasses,class)~=false and raceAllows(q.requiredRaces,race)~=false
        if allowed then
            local value=clone(src);value.index=index
            if q then value.name=q.name;value.level=q.requiredLevel;value.group=(q.questFlags or 0)%16>=8;value.completed=g.Completed(src.id) end
            result[#result+1]=value
        end
    end
    return result
end
function g.Query(slot,filter)
    filter=filter or {};local result={};local key,class,race=persona();local current=g.CurrentCatalog()
    local search=type(filter.search)=="string" and filter.search:sub(1,80):lower() or ""
    local limit=filter.maxLevel or ((g.Level() or 60)+5)
    for _,id in ipairs(catalog().slots[slot] or {})do
        local item=catalog().items[id]
        if item and (not current or maskAllows(item.classes,class)~=false) then
            local sources=g.Sources(id,key,class,race);local sourceLevel,match=nil,false
            for _,src in ipairs(sources)do
                local level=math.max(item.level or 0,src.level or 0)
                if (not filter.kind or src.kind==filter.kind) and (filter.allSources or src.completed~=true)
                    and (search=="" or item.name:lower():find(search,1,true) or (src.name or ""):lower():find(search,1,true)
                        or (src.dungeon or ""):lower():find(search,1,true)) then match=true;sourceLevel=math.min(sourceLevel or level,level) end
            end
            if match and (filter.allLevels or (sourceLevel or 0)<=limit) then
                result[#result+1]={id=id,item=item,level=sourceLevel or item.level or 0,sources=sources}
            end
        end
    end
    table.sort(result,function(a,b)
        if a.item.itemLevel~=b.item.itemLevel then return (a.item.itemLevel or 0)>(b.item.itemLevel or 0) end
        return a.id<b.id
    end)
    return result
end
function g.Item(id)return catalog().items[id] end
function g.Meta(id,request)
    if not integer(id,1,2147483647) then return end
    if cache[id] then return cache[id] end
    local ok,name,link,quality,level,minLevel,kind,subtype,_,equip,icon,_,classID,subclassID=call(api("GetItemInfo") or GetItemInfo,id)
    if ok and text(name) and text(link) and text(equip) then
        local row={name=name,link=link,equip=equip,quality=integer(quality,0,8) and quality or nil,
            level=integer(level,0,10000) and level or nil,minLevel=integer(minLevel,0,1000) and minLevel or nil,
            kind=text(kind) and kind or nil,subtype=text(subtype) and subtype or nil,
            icon=(text(icon) or integer(icon,1,2147483647)) and icon or nil,
            classID=integer(classID,0,64) and classID or nil,subclassID=integer(subclassID,0,64) and subclassID or nil}
        if #order>=MAX_CACHE then cache[table.remove(order,1)]=nil end
        cache[id]=row;order[#order+1]=id;return row
    end
    if request and not queued[id] and not requested[id] and #queue<MAX_QUEUE then
        queue[#queue+1]=id;queued[id]=true
    end
end
function g.LoadStep()
    for _=1,4 do
        local id=table.remove(queue,1);if not id then break end
        queued[id],requested[id]=nil,true
        call(api("RequestLoadItemDataByID"),id)
    end
end
function g.InvalidateItem(id)
    if integer(id,1,2147483647) then
        cache[id]=nil
        for i=#order,1,-1 do if order[i]==id then table.remove(order,i) end end
        -- Failed requests do not form an event/request loop. Explicit Retry resets them.
    end
end
function g.Retry()
    cache,order,queue,queued,requested={},{},{},{},{}
end
local function stats(link)
    local ok,value=call(api("GetItemStats") or GetItemStats,link)
    if not ok or not plain(value) then return end
    local result,count={},0
    for key,n in pairs(value)do
        count=count+1
        if count>64 or not text(key) or #key>96 or not number(n,-1000000,1000000) then return end
        result[key]=n
    end
    return result
end
function g.Compare(id,slot)
    local item=g.Item(id);local meta=g.Meta(id,true)
    local result={status="unknown",deltas={},replaced={},detail="Waiting for live item statistics"}
    if not item or not meta or not g.SlotNames[slot] then return result end
    local new=stats(meta.link);if not new then return result end
    local replaced={slot}
    if item.inventoryType==17 then replaced={16,17} end
    local old={}
    for _,s in ipairs(replaced)do
        local ok,link=call(GetInventoryItemLink,"player",s)
        if not ok or guard.IsSecret(link) or link~=nil and not text(link) then result.detail="Equipped item unavailable";return result end
        local values={};if link then values=stats(link) end
        if not values then result.detail="Equipped item statistics unavailable";return result end
        result.replaced[#result.replaced+1]={slot=s,link=link}
        for key,n in pairs(values)do old[key]=(old[key] or 0)+n end
    end
    local keys={};for key in pairs(new)do keys[key]=true end;for key in pairs(old)do keys[key]=true end
    for key in pairs(keys)do
        result.deltas[#result.deltas+1]={key=key,label=text(_G[key]) and _G[key] or key:gsub("^ITEM_MOD_",""):gsub("_SHORT$",""):gsub("_"," "),
            before=old[key] or 0,after=new[key] or 0,delta=(new[key] or 0)-(old[key] or 0)}
    end
    table.sort(result.deltas,function(a,b)return a.label<b.label end)
    result.status,result.detail="known","Stat tradeoffs; effects and set bonuses are not scored"
    if slot==17 then
        local ok,link=call(GetInventoryItemLink,"player",16)
        local known,_,_,_,_,_,_,_,_,equip=call(api("GetItemInfo") or GetItemInfo,link)
        if ok and link and known and equip=="INVTYPE_2HWEAPON" then
            result.detail="Requires replacing your two-handed main hand; compare that replacement separately"
            result.handConflict=true
        end
    end
    return result
end
-- A short, bounded tree preserves all-of prerequisites and exposes alternative branches.
function g.Path(id,branch)
    local result={rows={},choices={}};local visiting,seen={},{}
    local function visit(qid,depth,role)
        if depth>12 or #result.rows>=MAX_PATH then result.issue="Prerequisite path exceeds display limit";return end
        if qid<0 then result.issue="Special prerequisite condition requires in-game verification";return end
        if visiting[qid] then result.issue="Source prerequisite cycle; verify the quest in game";return end
        if seen[qid] then return end
        visiting[qid]=true
        local row=g.Quest(qid,nil,true)
        if not row then result.issue="Prerequisite reference missing";visiting[qid]=nil;return end
        if g.Completed(qid)~=true then
            for _,other in ipairs(row.preQuestGroup or {})do visit(other,depth+1,"required") end
            local alternatives=row.preQuestSingle or {}
            if #alternatives==1 then visit(alternatives[1],depth+1,"required")
            elseif #alternatives>1 then
                local chosen
                for _,other in ipairs(alternatives)do if g.Completed(other)==true then chosen=other;break end end
                if not chosen then for _,other in ipairs(alternatives)do if other==branch or g.Active(other)==true then chosen=other;break end end end
                if chosen then visit(chosen,depth+1,"branch")
                else
                    for _,other in ipairs(alternatives)do
                        if #result.choices<MAX_PATH then result.choices[#result.choices+1]={id=other,name=(g.Quest(other) or {}).name or "Unknown prerequisite",parent=qid} end
                    end
                end
            end
        end
        local completed=g.Completed(qid)
        result.rows[#result.rows+1]={id=qid,name=row.name,level=row.requiredLevel,role=role,
            state=completed==true and "complete" or g.Active(qid)==true and "active" or completed==false and "not complete" or "unknown",
            row=row}
        seen[qid],visiting[qid]=true,nil
    end
    visit(id,0,"target");return result
end
local function changed()
    if core.Changed then core:Changed() end
    local p=core.QuestPlanner
    if p and p.enabled and p.Controller then p.Controller.Invalidate();p.Request() end
    if g.View and g.View.Refresh then g.View.Refresh() end
end
local function save()
    local parts={"2",tostring(focus),tracker and "1" or "0"}
    for _,row in ipairs(goals)do parts[#parts+1]=table.concat({row.slot,row.itemID,row.kind=="quest" and "q" or "d",row.sourceID,row.branch or 0,row.seen and 1 or 0},":") end
    local encoded=table.concat(parts,"|");assert(#encoded<=g.Limits.savedBytes)
    if core.CharDB then core.CharDB.gearGoals=encoded end
    changed()
end
local function resolve(row)
    local value=clone(row);value.source=nil
    local item=g.Item(value.itemID)
    for index,src in ipairs(item and item.sources or {})do
        if src.kind==value.kind and src.id==value.sourceID then value.source=index;break end
    end
    value.sourceMissing=value.source==nil
    return value
end
function g.Goals()local result={};for _,row in ipairs(goals)do result[#result+1]=resolve(row)end;return result end
function g.Focused()for _,row in ipairs(goals)do if row.slot==focus then return resolve(row) end end end
function g.Tracking()return tracker end
function g.SetTracker(value)tracker=value==true;save() end
function g.Stop()focus=0;save() end
local function valid(slot,id,source)
    local item=g.Item(id);if not item or not g.SlotNames[slot] or not integer(source,1,#item.sources) then return false end
    for _,other in ipairs(catalog().slots[slot] or {})do if other==id then return true end end
    return false
end
function g.Restore()
    goals,focus,tracker={},0,false
    local encoded=core.CharDB and core.CharDB.gearGoals
    if encoded==nil then return true end
    if not text(encoded) or #encoded>384 then return nil,"Invalid gear goal settings" end
    local version,rawFocus,rawTracker,tail=encoded:match("^(%d+)|(%d+)|([01])(.*)$")
    if version~="2" or tail and tail~="" and tail:sub(1,1)~="|" then return nil,"Invalid gear goal settings" end
    local restored,seen={},{}
    for part in (tail or ""):gmatch("|([^|]+)")do
        local s,id,kind,sourceID,branch,owned=part:match("^(%d+):(%d+):([qd]):(%d+):(%d+):([01])$")
        s,id,sourceID,branch=tonumber(s),tonumber(id),tonumber(sourceID),tonumber(branch)
        if not s or not g.SlotNames[s] or not integer(id,1,2147483647) or not integer(sourceID,1,2147483647) or seen[s] or #restored>=MAX_GOALS or not integer(branch,0,2147483647) then return nil,"Invalid gear goal settings" end
        restored[#restored+1]={slot=s,itemID=id,kind=kind=="q" and "quest" or "dungeon",sourceID=sourceID,branch=branch~=0 and branch or nil,seen=owned=="1"};seen[s]=true
    end
    local canonical=""
    for _,row in ipairs(restored)do canonical=canonical.."|"..table.concat({row.slot,row.itemID,row.kind=="quest" and "q" or "d",row.sourceID,row.branch or 0,row.seen and 1 or 0},":") end
    if canonical~=tail or not integer(tonumber(rawFocus),0,18) then return nil,"Invalid gear goal settings" end
    goals,focus,tracker=restored,tonumber(rawFocus),rawTracker=="1"
    if focus~=0 and not seen[focus] then focus=0 end
    return true
end
local function owned(id)
    local ok,count=call(api("GetItemCount") or GetItemCount,id,false,false,false,false)
    return ok and integer(count,1,2147483647) or false
end
function g.Pin(slot,id,source)
    if not valid(slot,id,source) then return nil,"Choose a source for this equipment slot" end
    for _,row in ipairs(goals)do
        if row.slot==slot then row.itemID,row.kind,row.sourceID,row.branch,row.seen=id,g.Item(id).sources[source].kind,g.Item(id).sources[source].id,nil,owned(id);save();return true end
    end
    if #goals>=MAX_GOALS then return nil,"Eight goal slots are already pinned; remove one first" end
    goals[#goals+1]={slot=slot,itemID=id,kind=g.Item(id).sources[source].kind,sourceID=g.Item(id).sources[source].id,seen=owned(id)};save();return true
end
function g.Remove(slot)
    for i,row in ipairs(goals)do if row.slot==slot then table.remove(goals,i);if focus==slot then focus=0 end;save();return true end end
end
function g.Pursue(slot)
    for _,row in ipairs(goals)do
        if row.slot==slot then
            if row.seen then return nil,"This goal has already been acquired" end
            if resolve(row).sourceMissing then return nil,"Pinned source is unavailable; choose and pin a current source" end
            focus=slot;save();return true
        end
    end
    return nil,"Pin the item first"
end
function g.ChooseBranch(slot,id)
    for _,row in ipairs(goals)do if row.slot==slot then
        local item=g.Item(row.itemID);local source=resolve(row).source
        local src=item and source and item.sources[source]
        if not src then return nil,"Pinned source is unavailable" end
        if src.kind~="quest" then return nil,"Not a quest source" end
        for _,choice in ipairs(g.Path(src.id).choices)do
            if choice.id==id then row.branch=id;save();return true end
        end
    end end
    return nil,"Choose a listed prerequisite branch"
end
function g.Observe()
    local updated=false
    for _,row in ipairs(goals)do
        if not row.seen then
            local ok,count=call(api("GetItemCount") or GetItemCount,row.itemID,false,false,false,false)
            if ok and integer(count,1,2147483647) then row.seen=true;updated=true end
        end
    end
    if updated then save() end
    return updated
end
function g.DecoratePolicy(personal)
    local result=clone(personal)
    if g.Module and not g.Module.enabled then return result end
    local row=g.Focused()
    if not row or row.seen then return result end
    local item=g.Item(row.itemID);local src=item and row.source and item.sources[row.source]
    if not src or src.kind~="quest" then return result end
    result.questGoals=result.questGoals or {}
    local count=0;for _ in pairs(result.questGoals)do count=count+1 end
    local path=g.Path(src.id,row.branch)
    -- Unchosen alternatives stay visible but never become automatic route goals.
    for _,quest in ipairs(path.rows)do
        if quest.state~="complete" and not result.questGoals[quest.id] and count<32 then result.questGoals[quest.id]=true;count=count+1 end
    end
    result.rewardFocus,result.rewardTarget="equipment",row.itemID
    return result
end
