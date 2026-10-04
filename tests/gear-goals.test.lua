-- Data/engine tests use the production model, not a parallel scoring model.
return function(check)
    local env=require("wow_stub")
    local saved={RikUI=RikUI,C_Item=C_Item,GetBuildInfo=GetBuildInfo,UnitLevel=UnitLevel,UnitClass=UnitClass,
        UnitFactionGroup=UnitFactionGroup,UnitRace=UnitRace,GetInventoryItemLink=GetInventoryItemLink,C_QuestLog=C_QuestLog}
    local count,requested,stats,completed=0,{}, {},{}
    RikUI={Secret={IsSecret=function(v)return v=="secret" end,Read=pcall},CharDB={},Changed=function()end}
    RikUI.GearCatalog={version=1,identity={build="1.60.1.70205"},items={
        [100]={name="Sword",inventoryType=13,level=10,itemLevel=12,classID=2,subclassID=7,classes=-1,sources={{kind="quest",id=1,name="Reward"}}},
        [101]={name="Two-hand",inventoryType=17,level=10,itemLevel=15,classID=2,sources={{kind="dungeon",id=4,name="Boss",dungeon="Dungeon"}}},
        [102]={name="Ring",inventoryType=11,level=60,itemLevel=60,classID=4,sources={{kind="quest",id=1,name="Reward"}}}},
        slots={[16]={100,101},[11]={102},[12]={102}},quests={
        [1]={name="Reward quest",requiredLevel=10,preQuestGroup={2},preQuestSingle={3,4}},
        [2]={name="Mandatory",preQuestSingle={1}},[3]={name="Left branch"},[4]={name="Right branch"}},
        variants={}}
    GetBuildInfo=function()return "1.60.1","70205" end
    UnitLevel=function()return 12 end;UnitClass=function()return "Warrior","WARRIOR",1 end
    UnitRace=function()return "Human","Human",1 end;UnitFactionGroup=function()return "Alliance" end
    C_QuestLog={IsQuestFlaggedCompleted=function(id)return completed[id] or false end}
    C_Item={GetItemCount=function()return count end,
        RequestLoadItemDataByID=function(id)requested[#requested+1]=id end,
        GetItemInfo=function(id)
            if id==999 then return end
            return "Item","item:"..id,2,12,10,"Weapon","Sword",1,"INVTYPE_WEAPON",123,0,2,7
        end,GetItemStats=function(link)return stats[link] end}
    GetInventoryItemLink=function(_,slot)return slot==16 and "item:old:enchanted" or slot==17 and "item:shield" or nil end
    assert(loadfile("src/modules/geargoals/gear-model.lua"))()
    local g=RikUI.GearGoals
    check("Gear catalog identity verified",g.CurrentCatalog())
    local rows=g.Query(16,{maxLevel=17})
    check("Gear slot query bounded and level-relevant",#rows==2 and #g.Query(11,{maxLevel=17})==0)
    check("Gear source/name search",#g.Query(16,{search="dungeon",maxLevel=17})==1)
    stats["item:100"]={ITEM_MOD_STAMINA_SHORT=7}
    stats["item:101"]={ITEM_MOD_STAMINA_SHORT=10}
    stats["item:old:enchanted"]={ITEM_MOD_STAMINA_SHORT=3}
    stats["item:shield"]={ITEM_MOD_STAMINA_SHORT=2}
    local comparison=g.Compare(100,16)
    check("Gear full equipped link used",comparison.status=="known" and comparison.deltas[1].delta==4)
    comparison=g.Compare(101,16)
    check("Gear two-hand comparison removes both hands",comparison.status=="known" and comparison.deltas[1].delta==5 and #comparison.replaced==2)
    stats["item:old:enchanted"]=nil
    check("Gear missing stats stay unknown",g.Compare(100,16).status=="unknown")
    stats["item:old:enchanted"]={ITEM_MOD_STAMINA_SHORT="secret"}
    check("Gear secret stat rejected",g.Compare(100,16).status=="unknown")
    check("Gear pin validates selected slot",not g.Pin(11,100,1))
    check("Gear goal pin works",g.Pin(16,100,1))
    check("Gear duplicate pin replaces without growing",g.Pin(16,100,1) and #g.Goals()==1)
    local path=g.Path(1)
    check("Gear cycle terminates with explicit warning",path.issue~=nil and #path.rows<33)
    RikUI.GearCatalog.quests[2].preQuestSingle=nil
    path=g.Path(1)
    check("Gear alternatives require a branch choice",#path.choices==2)
    table.insert(RikUI.GearCatalog.items[100].sources,1,{kind="quest",id=7,name="Other source"})
    check("Gear pinned source survives catalog reordering",g.Goals()[1].source==2 and g.Goals()[1].sourceID==1)
    table.remove(RikUI.GearCatalog.items[100].sources,1)
    check("Gear bounded serialized settings",#RikUI.CharDB.gearGoals<=384)
    local encoded=RikUI.CharDB.gearGoals
    g.Restore()
    check("Gear restore keeps selected goal",#g.Goals()==1 and g.Goals()[1].itemID==100)
    RikUI.CharDB.gearGoals="bad";g.Restore()
    check("Gear malformed restore is rejected",#g.Goals()==0)
    RikUI.CharDB.gearGoals="2|0|0|||";g.Restore()
    check("Gear trailing malformed fields rejected",#g.Goals()==0)
    local catalog=RikUI.GearCatalog;RikUI.GearCatalog=nil;RikUI.CharDB.gearGoals=encoded
    check("Gear saved goals survive absent provider",g.Restore() and #g.Goals()==1 and g.Goals()[1].sourceMissing)
    RikUI.GearCatalog=catalog
    RikUI.CharDB.gearGoals=encoded;g.Restore()
    count="secret";g.Observe()
    check("Gear unknown inventory does not mark acquired",not g.Goals()[1].seen)
    count=1;g.Observe()
    check("Gear actual possession marks acquired",g.Goals()[1].seen)
    g.Pin(16,100,1)
    check("Gear pin observes already-owned item immediately",g.Goals()[1].seen)
    count=0;g.Observe()
    check("Gear acquired memory survives disposal",g.Goals()[1].seen)
    local personal={questGoals={[99]=true},rewardFocus="xp",rewardTarget=888}
    local derived=g.DecoratePolicy(personal)
    check("Gear acquired goal never pursues",derived.rewardTarget==888)
    check("Gear explicit removal",g.Remove(16) and #g.Goals()==0)
    g.Pin(16,100,1);g.Pursue(16)
    derived=g.DecoratePolicy(personal)
    check("Gear pursuit preserves personal flags",personal.questGoals[1]==nil and personal.rewardTarget==888 and derived.questGoals[99])
    check("Gear pursuit adds target and equipment reward",derived.questGoals[1] and derived.rewardTarget==100 and derived.rewardFocus=="equipment")
    g.Stop()
    check("Gear stop restores effective personal policy",g.DecoratePolicy(personal).rewardTarget==888)
    GetBuildInfo=function()return "1.60.1","1" end
    check("Gear stale catalog reported",not g.CurrentCatalog())
    for key,value in pairs(saved)do _G[key]=value end
end
