-- Installed providers never supply executable strings or an unbounded foreground scan.
return function(check)
    local original={RikUI=RikUI,LibQuestieDB=LibQuestieDB,C_Item=C_Item,GetBuildInfo=GetBuildInfo,debugprofilestop=debugprofilestop}
    local clock=0
    RikUI={Secret={Read=pcall,IsSecret=function(v)return v=="secret" end}}
    RikUI.GearGoals={CurrentCatalog=function()return false end,Meta=function()end}
    LibQuestieDB=nil
    assert(loadfile("src/modules/geargoals/gear-provider.lua"))()
    local p=RikUI.GearGoals.Provider
    check("Gear absent provider degrades cleanly",not p.Start() and p.status:find("Install QuestieDB",1,true))
    local all={};for i=1,200 do all[i]=i end
    local items={GetAllIds=function()return all end,Get=function(id,field)
        if field=="class" then return 2 elseif field=="name"then return "Item "..id
        elseif field=="questRewards"then return {500}
        elseif field=="requiredLevel" or field=="itemLevel"then return 10 end
    end}
    local quests={Get=function(id,key)return ({name="Source",requiredLevel=5,requiredClasses=0,requiredRaces=0})[key]end,
        GetAll=function()return {name="wrong shape"}end}
    LibQuestieDB={RequireContract=function()return true end,ModeIndicator={GetStatus=function()return {expansion="Classic"}end},
        Item=items,Quest=quests,Npc={Get=function()end},Enum={raceMaskById={[95]=4294967296}}}
    check("Gear rejects another provider flavor",not p.Start())
    LibQuestieDB.ModeIndicator.GetStatus=function()return {expansion="Forever"}end
    C_Item={GetItemInfoInstant=function(id)return id,"Weapon","Sword","INVTYPE_WEAPON",135274,2,7 end}
    GetBuildInfo=function()return "1.60.1","70205"end
    debugprofilestop=function()clock=clock+.2;return clock end
    check("Gear provider starts supported contract",p.Start())
    p.Step()
    check("Gear provider yields within frame budget",p.scanned>0 and p.scanned<64)
    for _=1,100 do p.Step()end
    check("Gear provider indexed factual source references",p.count==200 and RikUI.GearCatalog.items[1].sources[1].authority=="reference")
    check("Gear provider does not mutate shared inventory",#all==200 and all[1]==1 and all[200]==200)
    local indexed=RikUI.GearCatalog
    check("Gear provider reopening reuses completed index",p.Start() and indexed==RikUI.GearCatalog and p.Progress()==nil)
    quests.GetAll=function()error("missing quest provider")end
    check("Gear selected prerequisite failure stays bounded and explicit",p.Quest(500,true)==nil and p.failed)
    items.GetAllIds=function()return {1}end;items.Get=function()error("provider failed")end
    check("Gear provider refresh starts",p.Start(true))
    p.Step()
    check("Gear provider failure has explicit state",p.status:find("stopped",1,true))
    for key,value in pairs(original)do _G[key]=value end
    if original.LibQuestieDB==nil then LibQuestieDB=nil end
end
