-- Confirmed combat XP needs localized text plus a unique, participated NPC death.
local planner=RikUI.QuestPlanner
local schema,xp=planner.Schema,{}
planner.PlanXP=xp
local keys={}
for _,stem in ipairs({"FIRSTPERSON","EXHAUSTION1","EXHAUSTION2","EXHAUSTION4","EXHAUSTION5"}) do
    for _,suffix in ipairs({"","_GROUP","_RAID"}) do keys[#keys+1]="COMBATLOG_XPGAIN_"..stem..suffix end
end
xp.TemplateKeys=keys
local function compile(fmt)
    if not schema.Text(fmt) or #fmt==0 or #fmt>512 or fmt:find("|",1,true) or fmt:find("%c") then return end
    local parts,indices,kinds={"^"},{},{}
    local i,nextArg,mode,lastCapture=1,1,nil,false
    while i<=#fmt do
        local c=fmt:sub(i,i)
        if c~="%" then
            parts[#parts+1]=c:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1");i=i+1;lastCapture=false
        elseif fmt:sub(i,i+1)=="%%" then parts[#parts+1]="%%";i=i+2;lastCapture=false
        else
            local number,kind=fmt:sub(i):match("^%%([1-9][0-9]*)%$([sd])")
            local arg,used,nextMode
            if number then arg=tonumber(number);used=#number+3;nextMode="positional"
            else kind=fmt:sub(i):match("^%%([sd])");if not kind then return end
                arg=nextArg;nextArg=nextArg+1;used=2;nextMode="sequential" end
            if arg>5 or #indices>=8 or mode and mode~=nextMode or kinds[arg] and kinds[arg]~=kind or lastCapture then return end
            mode=nextMode;kinds[arg]=kind;indices[#indices+1]=arg
            parts[#parts+1]=kind=="d" and "([0-9]+)" or "(.+)"
            i=i+used;lastCapture=true
        end
    end
    if kinds[1]~="s" or kinds[2]~="d" then return end
    parts[#parts+1]="$";return {pattern=table.concat(parts),indices=indices}
end
function xp.Compile(templates)
    local result,unsupported={},{}
    for _,key in ipairs(keys) do
        local row=compile((templates or {})[key])
        if row then row.key=key;result[#result+1]=row else unsupported[#unsupported+1]=key end
    end
    return result,unsupported
end
function xp.Parse(patterns,message)
    if not schema.Text(message) or #message>1024 or message:find("%c") then return nil,"Invalid XP message" end
    local found
    for _,row in ipairs(patterns or {}) do
        local captures={message:match(row.pattern)}
        if #captures==#row.indices then
            local args,valid={},true
            for i,arg in ipairs(row.indices) do
                if args[arg] and args[arg]~=captures[i] then valid=false;break end
                args[arg]=captures[i]
            end
            local name,amount=args[1],tonumber(args[2])
            if valid and schema.Text(name) and #name>0 and #name<=256 and schema.Integer(amount,1,1200000) then
                if found and (found.name~=name or found.xp~=amount) then return nil,"Ambiguous XP template" end
                found=found or {name=name,xp=amount,template=row.key}
            end
        end
    end
    if found then return found end
    return nil,"Unsupported localized XP message"
end
function xp.NPCID(guid)
    if not schema.Text(guid) then return end
    local kind,id=guid:match("^([%a]+)%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-")
    if kind=="Creature" or kind=="Vehicle" then return tonumber(id) end
end
local context,patterns,deaths,messages,participants=nil,nil,{},{},{}
local seenLines,lineOrder={},{}
local blockedUntil,lastNow,lastUnknown=0,nil,nil
local samples,confirmed=0,0
local function clear() deaths,messages,participants={},{},{} end
local function quarantine(at,why) clear();blockedUntil=at+4;lastUnknown=why end
local function clock(at)
    if not schema.Number(at,0,2147483647) then return false end
    if lastNow and at<lastNow then quarantine(at,"clock reset");lastNow=at;return false end
    lastNow=at;return true
end
local function getter()
    local api=schema.PlainTable(C_CombatLog) and C_CombatLog or {}
    if type(api.IsCombatLogRestricted)=="function" then
        local ok,restricted=planner.Context.Call(api.IsCombatLogRestricted)
        if not ok or restricted~=false then return end
    end
    local fn=api.GetCurrentEventInfo or CombatLogGetCurrentEventInfo
    if type(fn)=="function" then return fn end
end
-- Current clients may expose a restricted callback instead of a frame event.
function xp.CanObserveCombat()
    if not getter() then return false end
    local api=schema.PlainTable(C_EventUtils) and C_EventUtils or {}
    if type(api.IsEventValid)=="function" then
        local ok,valid=planner.Context.Call(api.IsEventValid,"COMBAT_LOG_EVENT_UNFILTERED")
        if not ok or valid~=true then return false end
    end
    if type(api.IsCallbackEvent)=="function" then
        local ok,callback=planner.Context.Call(api.IsCallbackEvent,"COMBAT_LOG_EVENT_UNFILTERED")
        if not ok or callback~=false then return false end
    end
    return true
end
function xp.Reset()
    context,patterns=nil,nil;clear();seenLines,lineOrder={},{};blockedUntil,lastNow,lastUnknown=0,nil,nil;samples,confirmed=0,0
end
function xp.SetContext(value,at)
    if not clock(at) then return end
    if not value or not schema.Text(value.key) or not schema.ID(value.npcID) or not schema.Text(value.playerGUID) then context=nil;clear();return end
    if context and (context.key~=value.key or context.npcID~=value.npcID
        or context.playerGUID~=value.playerGUID or context.petGUID~=value.petGUID) then
        quarantine(at,"actor context changed")
    end
    context={key=value.key,npcID=value.npcID,playerGUID=value.playerGUID,petGUID=value.petGUID,rested=value.rested}
    if not patterns then
        local templates={};for _,key in ipairs(keys) do if schema.Text(_G[key]) then templates[key]=_G[key] end end
        patterns=xp.Compile(templates)
    end
end
local function cohortBoundary(event,...)
    if event=="GROUP_ROSTER_UPDATE" or event=="PLAYER_LEVEL_UP" or event=="PLAYER_EQUIPMENT_CHANGED"
        or event=="ZONE_CHANGED_NEW_AREA" then return true end
    if event=="UNIT_PET" then return select(1,...)=="player" end
    if event=="UPDATE_EXHAUSTION" and context then
        local ok,amount=planner.Context.Call(GetXPExhaustion)
        local rested
        if ok and schema.Number(amount,0,2147483647) then rested=amount>0 end
        -- Pool decrements do not change the cohort while its rested bonus stays active.
        return not ok or rested~=context.rested
    end
end
local damage={SWING_DAMAGE=true,RANGE_DAMAGE=true,SPELL_DAMAGE=true,SPELL_PERIODIC_DAMAGE=true,DAMAGE_SHIELD=true,DAMAGE_SPLIT=true}
function xp.OnEvent(event,at,...)
    if not clock(at) then return end
    if event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT" or cohortBoundary(event,...) then
        context=nil;quarantine(at,"actor context boundary");return true
    end
    if event=="PLAYER_DEAD" then context=nil;quarantine(at,"player death");return end
    if not context or at<blockedUntil then return end
    if event=="CHAT_MSG_COMBAT_XP_GAIN" then
        local message,lineID=select(1,...),select(11,...)
        if schema.ID(lineID) then
            if seenLines[lineID] then return end
            seenLines[lineID]=true;lineOrder[#lineOrder+1]=lineID
            if #lineOrder>128 then seenLines[table.remove(lineOrder,1)]=nil end
        else quarantine(at,"XP line identity unavailable");return end
        if not getter() then quarantine(at,"combat log unavailable");return end
        local parsed,why=xp.Parse(patterns,message)
        if not parsed then quarantine(at,why);return end
        if #messages>=32 then quarantine(at,"XP queue overflow");return end
        messages[#messages+1]={at=at,name=parsed.name,xp=parsed.xp,lineID=lineID,key=context.key}
        return
    end
    if event~="COMBAT_LOG_EVENT_UNFILTERED" then return end
    local fn=getter();if not fn then quarantine(at,"combat log unavailable");return end
    local ok,_,kind,_,source,_,_,_,dest,name,_,_,a,_,_,d=planner.Context.Call(fn)
    if not ok or not schema.Text(kind) then quarantine(at,"invalid combat event");return end
    if not damage[kind] and kind~="UNIT_DIED" and kind~="PARTY_KILL" then return end
    local id=xp.NPCID(dest)
    if not id then
        if schema.Text(dest) and (dest:find("^Creature%-") or dest:find("^Vehicle%-")) then quarantine(at,"NPC identity unavailable") end
        return
    end
    if not schema.Text(name) or #name==0 or #name>256 then quarantine(at,"NPC name unavailable");return end
    local mine=source==context.playerGUID or context.petGUID and source==context.petGUID
    if damage[kind] then
        local amount;if kind=="SWING_DAMAGE" then amount=a else amount=d end
        if mine and schema.Number(amount,.000001,2147483647) then
            local n=0;for _ in pairs(participants) do n=n+1 end
            if n>=32 and not participants[dest] then quarantine(at,"participant overflow");return end
            participants[dest]=at
        end
        return
    end
    local participated=participants[dest]~=nil or kind=="PARTY_KILL" and mine==true
    participants[dest]=nil
    for _,row in ipairs(deaths) do
        if row.guid==dest then row.participated=row.participated or participated;return end
    end
    if #deaths>=32 then quarantine(at,"death queue overflow");return end
    deaths[#deaths+1]={guid=dest,npcID=id,name=name,at=at,key=context.key,participated=participated}
end
function xp.Tick(at)
    if not clock(at) or not context or at<blockedUntil then return end
    if not getter() then quarantine(at,"combat log unavailable");return end
    for _,message in ipairs(messages) do
        if not message.used and at-message.at>2 and at-message.at<=6 then
            local chosen,count=nil,0
            for _,death in ipairs(deaths) do
                if death.name==message.name and math.abs(death.at-message.at)<=2 then chosen=death;count=count+1 end
            end
            if count~=1 then message.used=true;lastUnknown="missing or ambiguous death"
            elseif at-chosen.at>2 then
                local matching=0
                for _,other in ipairs(messages) do if other.name==chosen.name and math.abs(other.at-chosen.at)<=2 then matching=matching+1 end end
                message.used=true
                if matching==1 and not chosen.used and chosen.participated and chosen.npcID==context.npcID
                    and chosen.key==context.key and message.key==context.key then
                    chosen.used=true
                    if planner.PlanLearning.Observe("combatXP",context.key,message.xp,1) then samples=samples+1;confirmed=confirmed+message.xp end
                else lastUnknown="ambiguous or ineligible XP" end
            end
        end
    end
    for _,rows in ipairs({deaths,messages}) do for i=#rows,1,-1 do if at-rows[i].at>6 then table.remove(rows,i) end end end
    for guid,time in pairs(participants) do if at-time>120 then participants[guid]=nil end end
end
function xp.Status()
    local n=0;for _ in pairs(participants) do n=n+1 end
    return {samples=samples,confirmedXP=confirmed,deaths=#deaths,messages=#messages,participants=n,lineIDs=#lineOrder,
        lastUnknown=lastUnknown,templates=patterns and #patterns or 0,basis="localized XP plus unique observed death"}
end
