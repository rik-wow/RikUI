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
-- Focused objective-definition and journal transition regressions.
local function setup()
    RikUI={Secret={IsSecret=function(value) return type(value)=="table" and rawget(value,"secret")==true end}}
    dofile(schemaPath);dofile(objectivesPath);dofile(journalPath)
    return RikUI.QuestPlanner
end
local p=setup()
local function objective(text,current,required,kind,finished)
    return {text=text,numFulfilled=current,numRequired=required,type=kind or "item",finished=finished or false}
end
local function normalized(name,text,current,required,wanted,edge)
    local got,actualEdge=p.Objectives.Text(objective(text,current,required))
    check(name,got==wanted and (not edge or edge==actualEdge))
end
normalized("leading counter","2/5 Boar",2,5,"#/# Boar","leading")
normalized("trailing counter","Boar slain: 2/5",2,5,"Boar slain: #/#","trailing")
normalized("trailing reversed multi-digit values","Collect coins: 12/347",12,347,"Collect coins: #/#","trailing")
normalized("preserve literal numbered goal","2/5 Section 3",2,5,"#/# Section 3")
normalized("preserve other fractions","Clear gate 1/7: 2/5",2,5,"Clear gate 1/7: #/#")
normalized("preserve interior counter","Collect 2/5 Boars today",2,5,"Collect 2/5 Boars today","literal")
normalized("counter spacing only"," \t2 / 5: Section 3 ",2,5," \t#/#: Section 3 ")
normalized("trailing whitespace retained","Section 3: 2 / 5 \t",2,5,"Section 3: #/# \t")
normalized("unmatched current preserved","2/5 Section 3",3,5,"2/5 Section 3","literal")
normalized("unmatched required preserved","2/50 Section 3",2,5,"2/50 Section 3","literal")
normalized("numeric suffix of a name preserved","Section2/5",2,5,"Section2/5","literal")
normalized("ordinal text retained","1/5th fleet",1,5,"1/5th fleet","literal")
normalized("scientific current not a counter","1e2/5 Boar",2,5,"1e2/5 Boar","literal")
normalized("decimal current not a counter","1.2/5 Boar",2,5,"1.2/5 Boar","literal")
normalized("negative current not a counter","-2/5 Boar",2,5,"-2/5 Boar","literal")
normalized("fraction alone","0/0",0,0,"#/#","leading")
normalized("leading zero numeric equality","002/005 Section 3",2,5,"#/# Section 3")
normalized("only one edge counter","2/5 Section 3 2/5",2,5,"#/# Section 3 2/5")
normalized("trailing match does not erase mismatched prefix","7/8 Section 3 2/5",2,5,"7/8 Section 3 #/#")
normalized("literal placeholder stays literal","#/# Section 3",2,5,"#/# Section 3","literal")
normalized("bounded long digit sequence stays unchanged",string.rep("9",2000).."/5",2,5,string.rep("9",2000).."/5")
local invalid=objective("0/5 Boar",0,5);invalid.finished={secret=true}
check("secret field rejected",p.Objectives.Text(invalid)==nil)
invalid=objective("0/5 Boar",.5,5);check("fractional observed count rejected",p.Objectives.Text(invalid)==nil)
invalid=objective(string.rep("x",2049),0,5);check("oversized text rejected",p.Objectives.Text(invalid)==nil)
local function compare(name,current,old,changed,up,down,comparable)
    local a,b,c,d=p.Objectives.Compare(current,old)
    check(name,a==changed and b==up and c==down and d==comparable)
end
local function list(text,n,kind,required,finished) return {objective(text,n,required or 5,kind,finished)} end
compare("matching leading progress",list("2/5 Section 3",2),list("1/5 Section 3",1),true,true,false,true)
compare("matching trailing progress",list("Section 3: 2/5",2),list("Section 3: 1/5",1),true,true,false,true)
compare("remaining goal digit changes definition",list("2/5 Section 3",2),list("1/5 Section 2",1),true,false,false,false)
compare("other fraction changes definition",list("Section 2/3: 2/5",2),list("Section 1/3: 1/5",1),true,false,false,false)
compare("ordinary counter decrease",list("1/5 Boar",1),list("2/5 Boar",2),true,false,true,true)
compare("finished state progress",list("Boar",2,"item",5,true),list("Boar",2),true,true,false,true)
compare("finished state decrease",list("Boar",2),list("Boar",2,"item",5,true),true,false,true,true)
compare("type change overrides count",list("2/5 Boar",2,"monster"),list("1/5 Boar",1),true,false,false,false)
compare("required count change overrides count",list("2/6 Boar",2,"item",6),list("1/5 Boar",1),true,false,false,false)
compare("list addition overrides count",{objective("2/5 Boar",2,5),objective("Wolf",0,3)},list("1/5 Boar",1),true,false,false,false)
compare("list removal is definition change",{},list("1/5 Boar",1),true,false,false,false)
compare("placeholder does not impersonate counter",list("#/# Boar",2),list("1/5 Boar",1),true,false,false,false)
compare("counter moved is definition change",list("Boar 2/5",2),list("1/5 Boar",1),true,false,false,false)
compare("unmatched display count cannot erase change",list("1/5 Boar",2),list("1/5 Boar",1),true,false,false,false)
compare("unavailable remains unknown",nil,nil,false,false,false,false)
compare("unavailable-to-present is not progress",list("2/5 Boar",2),nil,true,false,false,false)
compare("present-to-unavailable is not reduction",nil,list("2/5 Boar",2),true,false,false,false)
compare("known empty list comparable",{},{},false,false,false,true)
local current,prior={},{}
for i=1,32 do current[i]=objective("2/5 Section "..i,2,5);prior[i]=objective("1/5 Section "..i,1,5) end
compare("maximum objective list",current,prior,true,true,false,true)
current[32].text="2/5 New definition"
compare("late definition change suppresses earlier progress",current,prior,true,false,false,false)
current[33]=objective("2/5 Section 33",2,5)
compare("oversized list has no direction",current,prior,true,false,false,false)
compare("sparse list rejected",{[2]=objective("2/5 Boar",2,5)},prior,true,false,false,false)
local function snapshot()
    return {identity={product="forever",build="1.60.1.69913",locale="enUS"},observedAt=2,coverage="log-complete",order={1},
        quests={[1]={id=1,title="Fixture",level=7,failed=false,objectivesComplete=false,objectives=list("1/5 Section 2",1)}}}
end
local function change(name,mutate,wanted)
    p=setup();local old=snapshot();local new=p.Schema.Clone(old);mutate(new,old)
    p.Journal.SnapshotChanged(new,old);local entries=p.Journal.Export().entries
    check(name,wanted and #entries==1 and entries[1].event==wanted or not wanted and #entries==0)
    return entries
end
change("journal unchanged",function() end,nil)
change("journal progress",function(new) new.quests[1].objectives=list("2/5 Section 2",2) end,"observed-progress")
change("journal reduction",function(new) new.quests[1].objectives=list("0/5 Section 2",0) end,"observed-objective-reduction")
for _,field in ipairs({"title","level","failed"}) do
    change("metadata "..field.." overrides progress",function(new)
        new.quests[1].objectives=list("2/5 Section 2",2)
        new.quests[1][field]=field=="title" and "Changed" or field=="level" and 8 or true
    end,"observed-change")
end
change("definition overrides completion",function(new)
    new.quests[1].objectives=list("5/5 Section 3",5);new.quests[1].objectivesComplete=true
end,"observed-change")
change("removed objective overrides completion",function(new)
    new.quests[1].objectives={};new.quests[1].objectivesComplete=true
end,"observed-change")
change("unavailable list cannot direct completion",function(new,old)
    new.quests[1].objectives=nil;old.quests[1].objectives=nil;new.quests[1].objectivesComplete=true
end,"observed-change")
change("comparable explicit completion is progress",function(new) new.quests[1].objectivesComplete=true end,"observed-progress")
change("unknown completion becoming known is change",function(new,old)
    old.quests[1].objectivesComplete=nil;new.quests[1].objectivesComplete=true
end,"observed-change")
change("mixed objective movement is generic change",function(new,old)
    old.quests[1].objectives[2]=objective("2/5 Boar",2,5)
    new.quests[1].objectives={objective("2/5 Section 2",2,5),objective("1/5 Boar",1,5)}
end,"observed-change")
change("partial snapshot cannot establish removal",function(new) new.order={};new.quests={};new.coverage="log-partial" end,nil)
change("complete snapshot establishes absence only",function(new) new.order={};new.quests={} end,"observed-quest-removed")
change("identity change remains initial",function(new) new.identity.locale="frFR" end,"initial-observation")
p=setup();p.Journal.SnapshotChanged(snapshot(),nil);local exported=p.Journal.Export()
check("first log remains initial",exported.entries[1].event=="initial-observation")
exported.entries[1].questIDs[1]=99;check("export detached",p.Journal.Export().entries[1].questIDs[1]==1)
for i=1,60 do local now=snapshot();now.observedAt=i;p.Journal.SnapshotChanged(now,nil) end
local bounded=p.Journal.Export();check("journal remains bounded",#bounded.entries==48 and bounded.dropped==13)

    end)
    for _,name in ipairs(names) do _G[name]=previous[name] end
    check("quest-objectives fixtures complete",ok,reason)
end
