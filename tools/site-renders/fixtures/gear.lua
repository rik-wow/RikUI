-- Synthetic source/reward observations exercise unchanged RikUI code, not a copied catalog.
-- Item stats here are representative fixture inputs, not claims about these live items.
function RikRenderGear(state)
    local g=RikUI.GearGoals
    local ids={25,35,36,43,44,45,49}
    local names={"Quest sword","Dungeon blade","Group quest weapon","Alternative weapon","Practice sword","Reward option","Quest blade"}
    local items={}
    for index,id in ipairs(ids)do
        items[id]={name=names[index],inventoryType=index==2 and 17 or 13,level=10,itemLevel=20-index,
            icon=135274,classID=2,subclassID=7,classes=-1,sources={{kind=index==2 and "dungeon" or "quest",id=index==2 and 999 or 990,
                name=index==2 and "Sample encounter" or "Sample reward quest",dungeon=index==2 and "Sample dungeon" or nil,authority="reference"}}}
    end
    RikUI.GearCatalog={identity={build=RikRenderClient.version.."."..RikRenderClient.build},
        items=items,slots={[16]=ids,[17]={25,36},[11]={25}},quests={
            [990]={name="Sample reward quest",requiredLevel=10,preQuestGroup={991}},
            [991]={name="A prerequisite to complete",requiredLevel=8,preQuestSingle={992,993}},
            [992]={name="One possible branch",requiredLevel=8},[993]={name="Another possible branch",requiredLevel=8}},
        variants={},counts={items=7,quests=4}}
    GetBuildInfo=function()return RikRenderClient.version,RikRenderClient.build,"",16001 end
    C_Item.GetItemInfo=function(id)
        local numeric=type(id)=="string" and tonumber(id:match("item:(%d+)")) or id
        local item=items[numeric]
        if not item then return end
        return item.name,"item:"..numeric,2,item.itemLevel,item.level,"Weapon","Sword",1,
            item.inventoryType==17 and "INVTYPE_2HWEAPON" or "INVTYPE_WEAPON",item.icon,0,2,7
    end
    C_Item.GetItemStats=function(link)
        if state=="unavailable" then return nil end
        if link=="item:25" then return {ITEM_MOD_STAMINA_SHORT=7,ITEM_MOD_STRENGTH_SHORT=5,ITEM_MOD_AGILITY_SHORT=0} end
        if link=="item:35" then return {ITEM_MOD_STAMINA_SHORT=9,ITEM_MOD_STRENGTH_SHORT=8} end
        return {ITEM_MOD_STAMINA_SHORT=3,ITEM_MOD_STRENGTH_SHORT=2,ITEM_MOD_AGILITY_SHORT=2}
    end
    GetInventoryItemLink=function(_,slot)return slot==16 and "item:43" or slot==17 and "item:44" or nil end
    GetInventoryItemTexture=function(_,slot)return (slot==16 or slot==17) and 135274 or nil end
    C_Item.GetItemCount=function()return state=="acquired" and 1 or 0 end
    C_QuestLog.IsQuestFlaggedCompleted=function()return false end
    UnitLevel=function()return 12 end
    g.Retry();g.Restore()
    g.View.Show(16);g.View.SelectItem(state=="twohand" and 35 or 25,1)
    local w=g.View.Window
    RikRenderCenter(w);RikRenderResize(w)
    if state=="goals" or state=="acquired" or state=="tracker" then
        w.pin:GetScript("OnClick")(w.pin)
        g.Pursue(16)
        if state=="acquired" then g.Observe()end
        if state=="tracker" then
            g.SetTracker(true);w:Hide()
            RikUI.Profile.positions.geargoals={point="CENTER",relativePoint="CENTER",x=0,y=0}
            RikUI.Layout.Apply()
            local holder=CreateFrame("Frame","RikRenderGearTracker",UIParent);holder:SetSize(270,g.Tracker:GetHeight())
            g.Tracker:SetParent(holder);g.Tracker:ClearAllPoints();g.Tracker:SetPoint("TOPLEFT",holder,"TOPLEFT")
            RikRenderCenter(holder);RikRenderResize(holder)
        else w.goals:GetScript("OnClick")(w.goals)end
    end
    if state=="prerequisites" then w.sourceTab:GetScript("OnClick")(w.sourceTab);RikUI.Scroll.SetOffset(w.details,140)end
    g.View.Refresh();RikRenderResize(w)
    assert(g.View.selected and #w.blocks>=3,"Gear workflow did not render")
    if state=="unavailable" then assert(g.Compare(25,16).status=="unknown" and w.blocks[2].click,"Missing item data needs a retry action")end
end
