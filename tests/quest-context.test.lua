-- Guarded read-only quest waypoint/POI acquisition and explicit missing-field statuses.
return function(check)
    local names={"RikUI","C_Map","C_QuestLog","SelectQuestLogEntry","QuestPOIUpdateIcons","GetQuestLogRewardXP","GetTime","UnitClass","UnitRace","UnitFactionGroup","UnitLevel","UnitXP","UnitXPMax","UnitPosition","GetUnitSpeed"}
    local saved={}
    for _,name in ipairs(names) do saved[name]=_G[name] end
    local schemaPath="src/modules/questplanner/quest-schema.lua"
    local contextPath="src/modules/questplanner/quest-context.lua"
    local ok,reason=pcall(function()
local function setup()
    local mutations=0
    RikUI={Secret={}}
    RikUI.Secret.IsSecret=function(value) return type(value)=="table" and rawget(value,"secret")==true end
    RikUI.Secret.Read=function(fn,...) return pcall(fn,...) end
    dofile(schemaPath)
    dofile(contextPath)
    local snapshot={identity={product="forever",build="1.60.1.69913",locale="enUS"},order={98319,99158},
        quests={[98319]={id=98319,objectivesComplete=false},[99158]={id=99158,objectivesComplete=true}}}
    local rows={}
    C_Map={GetBestMapForUnit=function() return 1426 end,
        GetPlayerMapPosition=function() return {GetXY=function() return .47,.52 end} end}
    C_QuestLog={GetNextWaypoint=function() end,GetQuestsOnMap=function(mapID)
        check("only current map queried",mapID==1426)
        return rows
    end,IsQuestFlaggedCompleted=function() return false end,GetSelectedQuest=function() return 0 end,
        GetMaxNumQuestsCanAccept=function() return 40 end}
    local function forbidden() mutations=mutations+1; error("forbidden mutation") end
    C_QuestLog.SetSelectedQuest=forbidden
    C_QuestLog.AddQuestWatch=forbidden
    C_QuestLog.SetMapForQuestPOIs=forbidden
    C_Map.SetUserWaypoint=forbidden
    SelectQuestLogEntry=forbidden
    QuestPOIUpdateIcons=forbidden
    GetQuestLogRewardXP=function() return 50 end
    GetTime=function() return 1 end
    UnitClass=function() return "Warrior","WARRIOR",1 end
    UnitRace=function() return "Dwarf","Dwarf",3 end
    UnitFactionGroup=function() return "Alliance" end
    UnitLevel=function() return 7 end
    UnitXP=function() return 1980 end
    UnitXPMax=function() return 4500 end
    UnitPosition=function() return -5500,-800,392,0 end
    GetUnitSpeed=function() return 0,7 end
    return RikUI.QuestPlanner.Context,snapshot,rows,function() return mutations end
end
local function row(id)
    return {questID=id,mapID=1426,x=.4,y=.6,isQuestStart=false,isMapIndicatorQuest=false,inProgress=true,childDepth=0}
end

local context,snapshot,rows,mutations=setup()
rows[1]=row(98319)
rows[2]=row(99158)
rows[2].inProgress=false
local value=context.Read(snapshot)
check("POI fallback for active quest",value.destinations[98319].x==.4)
check("coordinates use queried map",value.destinations[98319].mapID==1426)
check("POI source semantics preserved",value.destinations[98319].scope=="current-map-quest-poi"
    and value.destinations[98319].sourceMapID==1426 and value.destinations[98319].isQuestStart==false)
check("completed active quest POI remains observational",value.destinations[99158].inProgress==false
    and value.destinations[99158].kind==nil)
check("waypoint absence preserved",value.targetStatus[98319].state=="observed"
    and value.targetStatus[98319].waypointState=="no-result")
check("zero historical completion stays false",value.history[99158]==false)
check("world and run diagnostics read only",value.worldPosition.x==-800 and value.worldPosition.z==-5500
    and value.worldPosition.rawReportedZ==392 and value.worldPosition.height==nil
    and value.worldPosition.verticalStatus=="unestablished" and value.worldPosition.mapID==0 and value.runSpeed==7)
check("no selected reward is explicit",value.rewardStatus[98319].state=="no-result"
    and value.rewardStatus[98319].reason=="no-selected-active-quest")
check("no state mutation",mutations()==0)
local originalUnitPosition=UnitPosition
UnitPosition=function() return -5587.2,-526.5,0,0 end
local indoor=context.WorldPosition()
check("zero third return is raw acquisition instead of floor",indoor.rawReportedZ==0
    and indoor.height==nil and indoor.verticalStatus=="unestablished")
UnitPosition=function() return -5587.2,-526.5,nil,0 end
local horizontal=context.WorldPosition()
check("unavailable vertical result preserves readable horizontal position",
    horizontal and horizontal.x==-526.5 and horizontal.rawReportedZ==nil and horizontal.height==nil)
UnitPosition=originalUnitPosition
rows[1].x=.9
check("detached POI copy",value.destinations[98319].x==.4)

context,snapshot,rows=setup()
rows[1]=row(98319)
C_QuestLog.GetNextWaypoint=function() return 1427,.2,.3 end
value=context.Read(snapshot)
check("valid waypoint takes precedence",value.destinations[98319].mapID==1427 and value.destinations[98319].x==.2)
check("valid waypoint status identifies source",value.targetStatus[98319].api=="C_QuestLog.GetNextWaypoint")

context,snapshot,rows=setup()
C_QuestLog.GetNextWaypoint=nil
rows[1]=row(98319)
value=context.Read(snapshot)
check("map fallback works without waypoint API",value.destinations[98319] and value.targetStatus[98319].waypointState=="unavailable")

context,snapshot,rows=setup()
C_QuestLog.GetNextWaypoint=nil
C_QuestLog.GetQuestsOnMap=nil
value=context.Read(snapshot)
check("missing APIs distinguished",value.targetStatus[98319].state=="unavailable"
    and value.targetStatus[98319].reason=="api-missing")

context,snapshot,rows=setup()
value=context.Read(snapshot)
check("known empty map snapshot distinguished",value.mapPOIStatus.state=="no-result"
    and value.mapPOIStatus.reason=="empty-map-list" and value.mapPOIStatus.rows==0)
C_QuestLog.GetQuestsOnMap=function() end
value=context.Read(snapshot)
check("nil result distinct from empty list",value.mapPOIStatus.reason=="no-map-result")
C_QuestLog.GetQuestsOnMap=function() error("not ready") end
value=context.Read(snapshot)
check("read failure distinguished",value.mapPOIStatus.state=="unavailable" and value.mapPOIStatus.reason=="read-failed")

context,snapshot,rows=setup()
rows[1]=row(12345)
value=context.Read(snapshot)
check("inactive POIs not acquired",next(value.destinations)==nil and value.targetStatus[98319].reason=="quest-not-in-map-result")
rows[2]=row(98319)
rows[3]=row(98319)
value=context.Read(snapshot)
check("duplicate points ambiguous even with equal coordinates",value.destinations[98319]==nil and value.targetStatus[98319].state=="ambiguous")

for _,variant in ipairs({"start","indicator","child","othermap","missingflag","invalidflag","secretx","outofrange","missingprogress"}) do
    context,snapshot,rows=setup()
    rows[1]=row(98319)
    if variant=="start" then rows[1].isQuestStart=true
    elseif variant=="indicator" then rows[1].isMapIndicatorQuest=true
    elseif variant=="child" then rows[1].childDepth=1
    elseif variant=="othermap" then rows[1].mapID=1427
    elseif variant=="missingflag" then rows[1].isQuestStart=nil
    elseif variant=="invalidflag" then rows[1].isMapIndicatorQuest=0
    elseif variant=="secretx" then rows[1].x={secret=true}
    elseif variant=="outofrange" then rows[1].y=1.01
    else rows[1].inProgress=nil end
    value=context.Read(snapshot)
    check("unsafe scope/data rejected: "..variant,value.destinations[98319]==nil and value.targetStatus[98319].state=="rejected")
end

context,snapshot,rows=setup()
rows[1]=row(98319)
rows[1].childDepth=nil
value=context.Read(snapshot)
check("documented optional childDepth accepted",value.destinations[98319]~=nil)
rows[2]=false
value=context.Read(snapshot)
check("malformed row invalidates whole map read",value.mapPOIStatus.state=="rejected" and next(value.destinations)==nil)

context,snapshot,rows=setup()
for index=1,257 do rows[index]=row(10000+index) end
value=context.Read(snapshot)
check("map result row budget enforced",value.mapPOIStatus.state=="rejected" and value.mapPOIStatus.reason=="invalid-or-oversized-map-list")
rows[257]=nil
value=context.Read(snapshot)
check("256 rows allowed",value.mapPOIStatus.rows==256)
rows[200]=nil
value=context.Read(snapshot)
check("sparse map result rejected",value.mapPOIStatus.state=="rejected")

context,snapshot,rows=setup()
C_Map.GetBestMapForUnit=function() end
value=context.Read(snapshot)
check("missing player map never uses invented target",value.mapPOIStatus.state=="unavailable"
    and value.mapPOIStatus.reason=="current-map-unavailable" and next(value.destinations)==nil)
C_Map.GetBestMapForUnit=function() return 1426 end
C_QuestLog.GetNextWaypoint=function() return 1426,{secret=true},.5 end
value=context.Read(snapshot)
check("secret waypoint remains diagnostic only",value.targetStatus[98319].waypointState=="rejected")

context,snapshot,rows=setup()
snapshot.order,snapshot.quests={},{}
for id=1,41 do snapshot.order[id]=id;snapshot.quests[id]={id=id} end
value=context.Read(snapshot,{[41]=true})
check("pin ordered first within bounded query budget",value.targetStatus[41].state~="query-limited")
check("over-budget ID explicit",value.targetStatus[40].state=="query-limited" and value.queries==40 and value.queryLimited)

context,snapshot,rows=setup()
C_QuestLog.GetSelectedQuest=function() return 98319 end
GetQuestLogRewardXP=function(...) check("XP read has no assumed explicit-ID overload",select("#",...)==0);return 0 end
value=context.Read(snapshot)
check("observed zero XP preserved",value.rewards[98319].xp==0 and value.rewardStatus[98319].state=="observed")
check("other quest not assigned selected XP",value.rewards[99158]==nil and value.rewardStatus[99158].reason=="quest-not-selected")
GetQuestLogRewardXP=nil
value=context.Read(snapshot)
check("missing XP API explicit",value.rewardStatus[98319].state=="unavailable")
GetQuestLogRewardXP=function() end
value=context.Read(snapshot)
check("nil XP is not zero",value.rewards[98319]==nil and value.rewardStatus[98319].state=="no-result")
GetQuestLogRewardXP=function() return -1 end
value=context.Read(snapshot)
check("invalid XP rejected",value.rewards[98319]==nil and value.rewardStatus[98319].state=="rejected")
GetQuestLogRewardXP=function() return {secret=true} end
value=context.Read(snapshot)
check("secret XP rejected",value.rewards[98319]==nil and value.rewardStatus[98319].state=="rejected")
GetQuestLogRewardXP=function() return 100 end
local selections=0
C_QuestLog.GetSelectedQuest=function() selections=selections+1;return selections==1 and 98319 or 99158 end
value=context.Read(snapshot)
check("selection race discarded",value.rewards[98319]==nil and value.rewardStatus[98319].reason=="selection-changed-or-unavailable")
C_QuestLog.GetSelectedQuest=nil
value=context.Read(snapshot)
check("missing selection API explicit for each reward",value.rewardStatus[98319].state=="unavailable" and value.rewardStatus[99158].state=="unavailable")


    end)
    for _,name in ipairs(names) do _G[name]=saved[name] end
    check("quest context fixture completes",ok,reason)
end
