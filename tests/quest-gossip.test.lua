-- Guarded API and conservative observation regression tests.
return function(check)
    local names={"RikUI","GetBuildInfo","GetLocale","GetTime","UnitLevel","UnitGUID","C_GossipInfo",
        "AcceptQuest","CompleteQuest","GetQuestReward"}
    local previous={}
    for _,name in ipairs(names) do previous[name]=_G[name] end
    local ok,reason=pcall(function()
        local schemaPath="src/modules/questplanner/quest-schema.lua"
        local objectivesPath="src/modules/questplanner/quest-objectives.lua"
        local gossipPath="src/modules/questplanner/quest-gossip.lua"
        local journalPath="src/modules/questplanner/quest-journal.lua"
local function setup()
    RikUI={Secret={IsSecret=function(v) return type(v)=="table" and rawget(v,"secret")==true end,
        Read=function(fn,...) return pcall(fn,...) end}}
    dofile(schemaPath)
    local p=RikUI.QuestPlanner
    p.Context={Position=function() return {mapID=1426,x=.47,y=.52} end,
        Dialog=function(event) return {event=event,questID=99158,position={mapID=1426,x=.47,y=.52},npcID=123} end}
    dofile(objectivesPath);dofile(gossipPath);dofile(journalPath)
    local identity={product="forever",build="1.60.1.69913",locale="enUS"}
    GetBuildInfo=function() return "1.60.1","69913","today",16001 end
    GetLocale=function() return "enUS" end
    GetTime=function() return 400 end
    UnitLevel=function() return 7 end
    UnitGUID=function(unit) check("npc token only",unit=="npc");return "Creature-0-1-2-3-456-0000000001" end
    local offered,active={},{}
    local function forbidden() error("unexpected gossip mutation") end
    C_GossipInfo={GetAvailableQuests=function() return offered end,GetActiveQuests=function() return active end,
        SelectAvailableQuest=forbidden,SelectActiveQuest=forbidden,SelectOption=forbidden}
    AcceptQuest=forbidden;CompleteQuest=forbidden;GetQuestReward=forbidden
    return p,identity,offered,active
end
local function row(id) return {questID=id,title="Fixture quest",questLevel=8} end
local p,identity,offered,active=setup()
offered[1]=row(98319);active[1]=row(99158);active[1].isComplete=true
local captured=p.Gossip.Read(identity)
check("capture exact identity",captured.identity.build=="1.60.1.69913" and captured.identity.locale=="enUS")
check("capture context",captured.level==7 and captured.observedAt==400 and captured.npcID==456)
check("position explicitly player interaction",captured.playerInteractionPosition.x==.47 and captured.positionScope=="player-interaction-position" and captured.npcPosition==nil)
check("offered/active separated",captured.offered[1].questID==98319 and captured.active[1].questID==99158)
check("optional nil stays absent",captured.offered[1].repeatable==nil and captured.offered[1].isComplete==nil)
check("active ready is not turn-in",captured.active[1].isComplete==true and captured.active[1].turnedIn==nil)
offered[1].title="Changed";check("capture detached",captured.offered[1].title=="Fixture quest")
check("journal budget respected",p.Schema.CopyLimited(captured,512,8192,8)~=nil)
p.Journal.Record("GOSSIP_SHOW",{identity=identity})
check("gossip integration records observation",p.Journal.Export().entries[1].event=="GOSSIP_SHOW")
p.Journal.Record("QUEST_DETAIL",{identity=identity})
check("dialog interaction position labelled",p.Journal.Dialog().positionScope=="player-interaction-position")

p,identity,offered,active=setup()
identity.build="1.60.1.69999"
check("build mismatch refused",p.Gossip.Read(identity)==nil)
identity.build="1.60.1.69913";GetLocale=function() return "frFR" end
check("locale mismatch refused",p.Gossip.Read(identity)==nil)
GetLocale=function() return "enUS" end;GetBuildInfo=function() return "1.15.8","123","today",11508 end
check("Classic identity refused",p.Gossip.Read(identity)==nil)

p,identity,offered,active=setup()
local guidReads=0;UnitGUID=function() guidReads=guidReads+1;return guidReads==1 and "Creature-0-1-2-3-456-1" or "Creature-0-1-2-3-789-2" end
offered[1]=row(98319)
captured=p.Gossip.Read(identity)
check("NPC race discards lists",captured.status.state=="rejected" and captured.offered==nil and captured.unitGUID==nil)
UnitGUID=function() end;captured=p.Gossip.Read(identity)
check("missing NPC unknown",captured.status.state=="no-result" and captured.offered==nil)
UnitGUID=function() return {secret=true} end;captured=p.Gossip.Read(identity)
check("secret NPC rejected",captured.status.state=="rejected")

p,identity,offered,active=setup()
captured=p.Gossip.Read(identity)
check("empty dialog lists explicit",captured.offeredStatus.reason=="empty-dialog-list" and #captured.offered==0)
C_GossipInfo.GetAvailableQuests=function() end;captured=p.Gossip.Read(identity)
check("nil different from empty",captured.offered==nil and captured.offeredStatus.reason=="no-list-returned")
C_GossipInfo.GetAvailableQuests=nil;captured=p.Gossip.Read(identity)
check("missing getter explicit",captured.status.state=="partial" and captured.offeredStatus.state=="unavailable")
C_GossipInfo.GetAvailableQuests=function() error("failure") end;captured=p.Gossip.Read(identity)
check("getter failure explicit",captured.offeredStatus.reason=="read-failed")
C_GossipInfo.GetAvailableQuests=function() return {secret=true} end;captured=p.Gossip.Read(identity)
check("secret list rejected",captured.offeredStatus.state=="rejected")

for _,variant in ipairs({"duplicate","hole","oversize","badid","badlevel","badtitle","longtitle","secretflag","badflag","badfrequency","badrow"}) do
    p,identity,offered,active=setup();offered[1]=row(98319)
    if variant=="duplicate" then offered[2]=row(98319)
    elseif variant=="hole" then offered[3]=row(99158)
    elseif variant=="oversize" then for i=1,33 do offered[i]=row(i) end
    elseif variant=="badid" then offered[1].questID=0
    elseif variant=="badlevel" then offered[1].questLevel=1.5
    elseif variant=="badtitle" then offered[1].title={secret=true}
    elseif variant=="longtitle" then offered[1].title=string.rep("x",257)
    elseif variant=="secretflag" then offered[1].isComplete={secret=true}
    elseif variant=="badflag" then offered[1].repeatable=0
    elseif variant=="badfrequency" then offered[1].frequency=-1
    else offered[1]=false end
    captured=p.Gossip.Read(identity)
    check("bad offered data rejected: "..variant,captured.offered==nil and captured.status.state=="partial")
end
p,identity,offered,active=setup()
for i=1,32 do offered[i]=row(i);offered[i].title=string.rep("x",256);active[i]=row(i+100);active[i].title=string.rep("x",256) end
captured=p.Gossip.Read(identity)
check("combined journal budget explicit",captured.status.state=="query-limited" and captured.offered==nil and captured.active==nil)
check("budget diagnostic itself fits",p.Schema.CopyLimited(captured,512,8192,8)~=nil)

p,identity,offered,active=setup()
GetTime=function() end;UnitLevel=function() return {secret=true} end
p.Context.Position=function() error("unavailable") end
captured=p.Gossip.Read(identity)
check("context time remains explicitly unavailable",captured.observedAt==nil and captured.contextStatus.time.state=="no-result")
check("secret level not exposed",captured.level==nil and captured.contextStatus.level.state=="rejected")
check("position failure guarded",captured.playerInteractionPosition==nil and captured.contextStatus.playerPosition.state=="unavailable")

local function snapshot(count)
    local value={identity={product="forever",build="1.60.1.69913",locale="enUS"},order={},quests={},coverage="log-complete",observedAt=1}
    for i=1,count do value.order[i]=i;value.quests[i]={id=i,objectivesComplete=false,failed=false,
        objectives={{text="0/5 fixture",type="item",finished=false,numFulfilled=0,numRequired=5}}} end
    return value
end
local function transition(before,after)
    p=setup();p.Journal.SnapshotChanged(after,before);return p.Journal.Export().entries
end
local first=snapshot(2);local entries=transition(nil,first)
check("initial observation distinct",#entries==1 and entries[1].event=="initial-observation")
check("empty initial log still recorded",transition(nil,snapshot(0))[1].event=="initial-observation")
check("unchanged no progress",#transition(first,p.Schema.Clone(first))==0)
local after=p.Schema.Clone(first);after.quests[1].objectives[1].numFulfilled=2;after.quests[1].objectives[1].text="2/5 fixture"
entries=transition(first,after);check("increase recorded",entries[1].event=="observed-progress")
local before=p.Schema.Clone(after);after.quests[1].objectives[1].numFulfilled=1;after.quests[1].objectives[1].text="1/5 fixture"
entries=transition(before,after);check("counter reduction distinct",entries[1].event=="observed-objective-reduction")
after=p.Schema.Clone(first);after.quests[1].objectives={}
entries=transition(first,after);check("shorter objective list is definition change",entries[1].event=="observed-change")
after=p.Schema.Clone(first);after.quests[1].objectives=nil
entries=transition(first,after);check("missing objectives not reduction",entries[1].event=="observed-change")
after=p.Schema.Clone(first);after.quests[1].objectives[1].numRequired=2
entries=transition(first,after);check("changed requirement not fabricated progress",entries[1].event=="observed-change")
after=p.Schema.Clone(first);after.order={1};after.quests[2]=nil
entries=transition(first,after);check("actual complete-log removal recorded",entries[1].event=="observed-quest-removed" and entries[1].questIDs[1]==2)
after.coverage="log-partial"
check("partial log does not prove removal",#transition(first,after)==0)
after=snapshot(3)
entries=transition(first,after);check("newly seen distinct from progress",entries[1].event=="newly-observed" and entries[1].questIDs[1]==3)
after.identity.build="1.60.1.69999"
entries=transition(first,after);check("identity boundary resets comparison",entries[1].event=="initial-observation" and entries[1].reason=="identity-changed")
entries=transition(nil,snapshot(41));check("initial list cap explicit",#entries[1].questIDs==40 and entries[1].total==41 and entries[1].limited)
p=setup();p.Journal.Record("QUEST_TURNED_IN",nil,99158,0,5)
check("existing reward event preserved",p.Journal.Export().entries[1].receivedXP==0)

    end)
    for _,name in ipairs(names) do _G[name]=previous[name] end
    check("quest-gossip fixtures complete",ok,reason)
end
